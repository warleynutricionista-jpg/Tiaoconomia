--============================================================
-- space_economy - server/debts.lua (MELHORADO)
-- Sistema completo de dívidas com juros, carência, cobranças e sync ps-banking
--============================================================
SE = SE or {}
SE.Debts = SE.Debts or {}

local Debts = SE.Debts
local U = SE.Util or {}
local B = SE.Bridge or {}
local cfg = Config or {}

local RES = GetCurrentResourceName()

--============================================================
-- Fallback Utils (anti-nil / base QBOX)
--============================================================
local function _safeStr(v, fb)
  if v == nil then return fb or '' end
  local s = tostring(v)
  if s == '' then return fb or '' end
  return s
end

local function _trim(s)
  s = _safeStr(s, '')
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function _toInt(v, d)
  local n = tonumber(v)
  if not n then return d or 0 end
  if n >= 0 then return math.floor(n + 0.0) end
  return math.ceil(n - 0.0)
end

local function _toNumber(v, d)
  local n = tonumber(v)
  if not n then return d end
  return n
end

local function _nowTs()
  return os.time()
end

local function _tsToIso(ts)
  ts = tonumber(ts)
  if not ts then return nil end
  return os.date('%Y-%m-%d %H:%M:%S', ts)
end

local function _jsonEncode(tbl)
  if type(U.safeJsonEncode) == 'function' then
    return U.safeJsonEncode(tbl)
  end
  if json and json.encode then
    local ok, out = pcall(function()
      return json.encode(tbl or {})
    end)
    return ok and out or '{}'
  end
  return '{}'
end

local function dbg(...)
  if type(U.dbg) == 'function' then
    U.dbg(...)
  else
    print('^3[space_economy:debts]^7', ...)
  end
end

local function notify(src, msg, typ)
  if src and src > 0 and type(B.Notify) == 'function' then
    B.Notify(src, msg, typ or 'inform')
  end
end

local function registerTransaction(category, amount, meta)
  if SE
    and SE.EconomyMonitor
    and type(SE.EconomyMonitor.RegisterTransaction) == 'function' then
    SE.EconomyMonitor.RegisterTransaction(category, amount, meta)
  end
end

local function getSourceByCitizen(citizenid)
  if type(B.GetSourceByCitizenId) == 'function' then
    return B.GetSourceByCitizenId(citizenid)
  end
  return nil
end

local function getCitizenId(src)
  if type(B.GetCitizenId) == 'function' then
    return B.GetCitizenId(src)
  end
  return nil
end

local function hasMySQL()
  return MySQL
    and MySQL.query and MySQL.query.await
    and MySQL.single and MySQL.single.await
    and MySQL.scalar and MySQL.scalar.await
    and MySQL.insert and MySQL.insert.await
    and MySQL.update and MySQL.update.await
end

--============================================================
-- Config Defaults
--============================================================
cfg.DebtSystem = cfg.DebtSystem or {}
local DS = cfg.DebtSystem

if DS.Enabled == nil then DS.Enabled = true end
DS.DefaultDueDays = _toInt(DS.DefaultDueDays or 7, 7)
DS.GraceHours = _toInt(DS.GraceHours or 24, 24)
DS.InterestDailyRate = _toNumber(DS.InterestDailyRate or 0.01, 0.01) -- 1% ao dia (exemplo)
DS.WarnEveryHours = _toInt(DS.WarnEveryHours or 12, 12)

-- ps-banking
DS.PSBanking = DS.PSBanking or {}
if DS.PSBanking.Enabled == nil then DS.PSBanking.Enabled = true end
DS.PSBanking.ScanIntervalMs = _toInt(DS.PSBanking.ScanIntervalMs or 60000, 60000)
DS.PSBanking.CreateBillOnUpsert = (DS.PSBanking.CreateBillOnUpsert ~= false) -- default true
DS.PSBanking.BillPrefix = _safeStr(DS.PSBanking.BillPrefix or '[SE#%d] ', '[SE#%d] ')

--============================================================
-- Logs (usa tabela space_economy_logs se existir)
--============================================================
local function logSys(category, message, meta)
  category = _safeStr(category, 'sistema')
  message = _safeStr(message, '')
  if message == '' or not hasMySQL() then return end

  -- Se existir SE.Log (módulo do seu core), usa também
  if type(SE.Log) == 'function' then
    pcall(SE.Log, category, message, meta)
  end

  -- Fallback SQL (idempotente: tabela criada no schema)
  pcall(function()
    MySQL.insert.await([[
      INSERT INTO space_economy_logs (category, message, metadata, created_at)
      VALUES (?, ?, ?, NOW())
    ]], { category, message, meta and _jsonEncode(meta) or nil })
  end)
end

--============================================================
-- SCHEMA: Sem information_schema (evita erro de permissão)
--============================================================
local schemaReady = false
local cache = {
  hasCharCache = nil,
  hasLogsTable = nil,
}

local function tableExists(name)
  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)
  return ok and rows and #rows > 0
end

local function columnsMap(tbl)
  local map = {}
  local ok, cols = pcall(function()
    return MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tbl))
  end)
  if not ok or not cols then return map end
  for _, c in ipairs(cols) do
    if c and c.Field then map[c.Field] = true end
  end
  return map
end

local function ensureSchema()
  if schemaReady or not hasMySQL() then return end
  schemaReady = true

  -- Debts
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_debts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL DEFAULT 0,
      original_amount BIGINT NOT NULL DEFAULT 0,
      reason VARCHAR(200) NOT NULL DEFAULT 'Imposto',
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      interest_rate DECIMAL(10,4) NOT NULL DEFAULT 0.0100,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      due_at TIMESTAMP NULL,
      grace_until TIMESTAMP NULL,
      paid_at TIMESTAMP NULL,
      last_interest_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_status_due (status, due_at),
      INDEX idx_grace (grace_until)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- Backfill colunas em instalações antigas (sem information_schema)
  local cols = columnsMap('space_economy_debts')

  if not cols.original_amount then
    pcall(function()
      MySQL.query.await('ALTER TABLE space_economy_debts ADD COLUMN original_amount BIGINT NOT NULL DEFAULT 0 AFTER amount')
    end)
  end
  if not cols.grace_until then
    pcall(function()
      MySQL.query.await('ALTER TABLE space_economy_debts ADD COLUMN grace_until TIMESTAMP NULL AFTER due_at')
    end)
  end
  if not cols.last_interest_at then
    pcall(function()
      MySQL.query.await('ALTER TABLE space_economy_debts ADD COLUMN last_interest_at TIMESTAMP NULL')
    end)
  end

  -- Payments history
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_debt_payments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      debt_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL,
      payment_type VARCHAR(20) NOT NULL DEFAULT 'full',
      installment_number INT NULL,
      paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      meta LONGTEXT NULL,
      INDEX idx_debt (debt_id),
      INDEX idx_citizen (citizenid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- External payments idempotency (ps-banking tx_id)
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_external_payments (
      provider VARCHAR(32) NOT NULL,
      external_tx_id BIGINT NOT NULL,
      debt_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (provider, external_tx_id),
      INDEX idx_debt (debt_id),
      INDEX idx_citizen (citizenid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- ps-banking scan cursor
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_psbanking_cursor (
      id INT NOT NULL PRIMARY KEY DEFAULT 1,
      last_tx_id BIGINT NOT NULL DEFAULT 0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  MySQL.insert.await([[
    INSERT IGNORE INTO space_economy_psbanking_cursor (id, last_tx_id)
    VALUES (1, 0)
  ]])

  -- logs table (caso não exista no seu schema antigo)
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_logs (
      id INT AUTO_INCREMENT PRIMARY KEY,
      category VARCHAR(64) NOT NULL DEFAULT 'sistema',
      message VARCHAR(255) NOT NULL,
      metadata LONGTEXT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_created (created_at),
      INDEX idx_cat (category)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  cache.hasCharCache = tableExists('space_economy_charcache')
  cache.hasLogsTable = true

  dbg('Schema de dívidas garantido (sem information_schema).')
  logSys('sistema', ('[%s] Schema debts/payments OK.'):format(RES))
end

CreateThread(function()
  while not hasMySQL() do Wait(250) end
  ensureSchema()
end)

--============================================================
-- ps-banking integration
--============================================================
local function psBankingAvailable()
  return DS.PSBanking.Enabled
    and GetResourceState('ps-banking') == 'started'
    and exports['ps-banking']
    and exports['ps-banking'].createBill
end

local function buildBillDesc(debtId, reason)
  reason = _safeStr(reason, 'Dívida')
  return (DS.PSBanking.BillPrefix):format(debtId) .. reason
end

local function createPSBankingBill(citizenid, amount, description)
  if not psBankingAvailable() then return false end
  citizenid = _safeStr(citizenid, '')
  amount = _toInt(amount, 0)
  description = _safeStr(description, '')
  if citizenid == '' or amount <= 0 or description == '' then return false end

  local ok = pcall(function()
    exports['ps-banking']:createBill({
      identifier = citizenid,
      description = description,
      type = "Expense",
      amount = amount,
    })
  end)

  return ok == true
end

local function getCursor()
  local row = MySQL.single.await('SELECT last_tx_id FROM space_economy_psbanking_cursor WHERE id=1 LIMIT 1')
  return row and tonumber(row.last_tx_id) or 0
end

local function setCursor(lastId)
  lastId = tonumber(lastId) or 0
  MySQL.update.await('UPDATE space_economy_psbanking_cursor SET last_tx_id = ? WHERE id=1', { lastId })
end

-- Aplica pagamento externo (ps-banking) idempotente
local function applyExternalPayment(provider, txId, debtId, citizenid, amount, meta)
  provider = _safeStr(provider, 'unknown')
  txId = tonumber(txId) or 0
  debtId = _toInt(debtId, 0)
  citizenid = _safeStr(citizenid, '')
  amount = _toInt(amount, 0)

  if txId <= 0 or debtId <= 0 or citizenid == '' or amount <= 0 then
    return false
  end

  -- INSERT IGNORE na tabela de idempotência
  local inserted = MySQL.insert.await([[
    INSERT IGNORE INTO space_economy_external_payments
      (provider, external_tx_id, debt_id, citizenid, amount)
    VALUES (?, ?, ?, ?, ?)
  ]], { provider, txId, debtId, citizenid, amount })

  if not inserted then
    return false -- já processado
  end

  -- Faz a baixa como "pagamento parcial/total" sem remover dinheiro (já pagou no banco)
  Debts.ApplyPayment(debtId, citizenid, amount, 'bank_bill', meta or { provider = provider, tx_id = txId })
  return true
end

--============================================================
-- CORE API
--============================================================

-- Atualiza meta com merge simples
local function mergeMeta(oldJson, newTbl)
  newTbl = type(newTbl) == 'table' and newTbl or {}
  if oldJson and json and json.decode then
    local ok, decoded = pcall(function() return json.decode(oldJson) end)
    if ok and type(decoded) == 'table' then
      for k, v in pairs(newTbl) do decoded[k] = v end
      return _jsonEncode(decoded)
    end
  end
  return _jsonEncode(newTbl)
end

-- Cria/Atualiza dívida (UPSERT idempotente por citizenid+reason se meta.forceNew ~= true)
function Debts.Upsert(citizenid, amount, reason, dueTs, meta)
  ensureSchema()

  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return false, 'citizenid_invalid' end

  amount = _toInt(amount, 0)
  if amount <= 0 then return false, 'amount_invalid' end

  reason = _trim(_safeStr(reason or 'Imposto', 'Imposto'))
  meta = type(meta) == 'table' and meta or {}

  local now = _nowTs()
  local dueAt = dueTs and _tsToIso(dueTs) or _tsToIso(now + (DS.DefaultDueDays * 24 * 60 * 60))
  local graceUntil = _tsToIso(now + (DS.GraceHours * 60 * 60))
  local interestRate = _toNumber(DS.InterestDailyRate, 0.01)

  local forceNew = meta.forceNew == true

  local existing
  if not forceNew then
    existing = MySQL.single.await([[
      SELECT id, amount, meta
      FROM space_economy_debts
      WHERE citizenid = ? AND status = 'active' AND reason = ?
      LIMIT 1
    ]], { citizenid, reason })
  end

  if existing then
    local newAmount = _toInt(existing.amount, 0) + amount
    local merged = mergeMeta(existing.meta, meta)

    MySQL.update.await([[
      UPDATE space_economy_debts
      SET amount = ?,
          due_at = ?,
          grace_until = ?,
          interest_rate = ?,
          meta = ?
      WHERE id = ?
    ]], { newAmount, dueAt, graceUntil, interestRate, merged, existing.id })

    dbg(('Dívida atualizada: %s | %d -> %d | %s'):format(citizenid, _toInt(existing.amount, 0), newAmount, reason))
    logSys('dividas', ('Dívida atualizada: %s +%d = %d'):format(reason, amount, newAmount), { citizenid = citizenid, debt_id = existing.id })

    -- (opcional) gerar nova bill em atualização (geralmente NÃO recomendado para evitar duplicar)
    -- Se você quiser, habilite DS.PSBanking.CreateBillOnUpsertUpdate (não definido por padrão)
    if DS.PSBanking.CreateBillOnUpsert == true and meta.billOnUpdate == true then
      local desc = buildBillDesc(existing.id, reason)
      createPSBankingBill(citizenid, amount, desc) -- cria somente para o incremento
    end

    return true, existing.id
  end

  local insertId = MySQL.insert.await([[
    INSERT INTO space_economy_debts
      (citizenid, amount, original_amount, reason, status, interest_rate, due_at, grace_until, meta)
    VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?)
  ]], { citizenid, amount, amount, reason, interestRate, dueAt, graceUntil, _jsonEncode(meta) })

  if not insertId then
    logSys('erro', 'Falha ao criar dívida', { citizenid = citizenid, amount = amount, reason = reason })
    return false, 'db_insert_failed'
  end

  dbg(('Nova dívida: %s | %d | %s (#%d)'):format(citizenid, amount, reason, insertId))
  logSys('dividas', ('Nova dívida: %s = %d'):format(reason, amount), { citizenid = citizenid, debt_id = insertId })

  local src = getSourceByCitizen(citizenid)
  if src then
    notify(src, ('Nova dívida lançada: $%d - %s'):format(amount, reason), 'inform')
  end

  -- cria BILL no ps-banking
  if DS.PSBanking.CreateBillOnUpsert and psBankingAvailable() then
    local desc = buildBillDesc(insertId, reason)
    local ok = createPSBankingBill(citizenid, amount, desc)
    if ok then
      logSys('integracao', ('ps-banking: Bill criada para dívida #%d'):format(insertId), { citizenid = citizenid, amount = amount })
    else
      logSys('erro', ('ps-banking: Falha ao criar bill da dívida #%d'):format(insertId), { citizenid = citizenid, amount = amount })
    end
  end

  return true, insertId
end

function Debts.ListActive(limit, offset)
  ensureSchema()
  limit = _toInt(limit or 150, 150)
  offset = _toInt(offset or 0, 0)
  if limit < 1 then limit = 1 end
  if limit > 200 then limit = 200 end
  if offset < 0 then offset = 0 end

  local rows = {}

  if cache.hasCharCache == nil then
    cache.hasCharCache = tableExists('space_economy_charcache')
  end

  if cache.hasCharCache then
    local ok, out = pcall(function()
      return MySQL.query.await([[
        SELECT d.*,
               COALESCE(c.name, 'Desconhecido') as playerName
        FROM space_economy_debts d
        LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
        WHERE d.status = 'active'
        ORDER BY d.amount DESC
        LIMIT ? OFFSET ?
      ]], { limit, offset })
    end)
    rows = (ok and out) or {}
  else
    rows = MySQL.query.await([[
      SELECT d.*, 'Desconhecido' as playerName
      FROM space_economy_debts d
      WHERE d.status = 'active'
      ORDER BY d.amount DESC
      LIMIT ? OFFSET ?
    ]], { limit, offset }) or {}
  end

  for _, row in ipairs(rows) do
    row.isOnline = (getSourceByCitizen(row.citizenid) ~= nil)
    row.amount = _toInt(row.amount, 0)
    row.original_amount = _toInt(row.original_amount, 0)
  end

  return rows
end

function Debts.GetById(id)
  ensureSchema()
  id = _toInt(id, 0)
  if id <= 0 then return nil end

  local row

  if cache.hasCharCache == nil then
    cache.hasCharCache = tableExists('space_economy_charcache')
  end

  if cache.hasCharCache then
    row = MySQL.single.await([[
      SELECT d.*,
             COALESCE(c.name, 'Desconhecido') as playerName
      FROM space_economy_debts d
      LEFT JOIN space_economy_charcache c ON c.citizenid = d.citizenid
      WHERE d.id = ?
      LIMIT 1
    ]], { id })
  else
    row = MySQL.single.await([[
      SELECT d.*, 'Desconhecido' as playerName
      FROM space_economy_debts d
      WHERE d.id = ?
      LIMIT 1
    ]], { id })
  end

  if row then
    row.isOnline = (getSourceByCitizen(row.citizenid) ~= nil)
    row.amount = _toInt(row.amount, 0)
    row.original_amount = _toInt(row.original_amount, 0)
  end

  return row
end

function Debts.GetActiveByCitizen(citizenid, limit)
  ensureSchema()
  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return {} end

  limit = _toInt(limit or 50, 50)
  if limit < 1 then limit = 1 end
  if limit > 200 then limit = 200 end

  local rows = MySQL.query.await([[
    SELECT d.*, 'Desconhecido' as playerName
    FROM space_economy_debts d
    WHERE d.citizenid = ? AND d.status = 'active'
    ORDER BY d.created_at DESC
    LIMIT ?
  ]], { citizenid, limit }) or {}

  for _, row in ipairs(rows) do
    row.amount = _toInt(row.amount, 0)
    row.original_amount = _toInt(row.original_amount, 0)
    row.isOnline = (getSourceByCitizen(row.citizenid) ~= nil)
  end

  return rows
end

function Debts.GetTotalByCitizen(citizenid)
  ensureSchema()
  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return 0 end

  local row = MySQL.single.await([[
    SELECT COALESCE(SUM(amount), 0) as total
    FROM space_economy_debts
    WHERE citizenid = ? AND status = 'active'
  ]], { citizenid })

  return row and _toInt(row.total, 0) or 0
end

function Debts.Stats()
  ensureSchema()
  local row = MySQL.single.await([[
    SELECT
      COALESCE(COUNT(*),0) AS activeCount,
      COALESCE(SUM(amount),0) AS activeTotal
    FROM space_economy_debts
    WHERE status = 'active'
  ]])
  return {
    activeCount = _toInt(row and row.activeCount, 0),
    activeTotal = _toInt(row and row.activeTotal, 0),
  }
end

--============================================================
-- ApplyPayment: baixa dívida sem remover dinheiro (ex.: ps-banking já cobrou)
--============================================================
function Debts.ApplyPayment(debtId, citizenid, amountPaid, paymentType, meta)
  ensureSchema()

  debtId = _toInt(debtId, 0)
  citizenid = _trim(_safeStr(citizenid, ''))
  amountPaid = _toInt(amountPaid, 0)
  paymentType = _safeStr(paymentType, 'external')

  if debtId <= 0 or citizenid == '' or amountPaid <= 0 then
    return false, 'invalid_args'
  end

  -- lock opcional
  local lockKey = ('debt:%d'):format(debtId)
  local owner = 'external'
  if SE.Locks and type(SE.Locks.AcquireBlocking) == 'function' then
    SE.Locks.AcquireBlocking(lockKey, owner, 15000, 2500, 50)
  end

  local debt = Debts.GetById(debtId)
  if not debt or debt.status ~= 'active' then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'debt_not_found'
  end

  local owed = _toInt(debt.amount, 0)
  local pay = amountPaid
  if pay > owed then pay = owed end

  local remaining = owed - pay

  if remaining <= 0 then
    MySQL.update.await([[
      UPDATE space_economy_debts
      SET status = 'paid', paid_at = NOW(), amount = 0
      WHERE id = ?
    ]], { debtId })
  else
    MySQL.update.await([[
      UPDATE space_economy_debts
      SET amount = ?
      WHERE id = ?
    ]], { remaining, debtId })
  end

  MySQL.insert.await([[
    INSERT INTO space_economy_debt_payments
      (debt_id, citizenid, amount, payment_type, meta)
    VALUES (?, ?, ?, ?, ?)
  ]], { debtId, citizenid, pay, paymentType, meta and _jsonEncode(meta) or nil })

  -- tesouro (opcional)
  if SE.Treasury and type(SE.Treasury.Deposit) == 'function' then
    pcall(SE.Treasury.Deposit, pay, 'pagamento_divida', {
      debt_id = debtId,
      citizenid = citizenid,
      source = paymentType
    })
  end

  registerTransaction('pagamento_divida', pay, {
    debt_id = debtId,
    citizenid = citizenid,
    source = paymentType
  })

  if SE.Locks and type(SE.Locks.Release) == 'function' then
    SE.Locks.Release(lockKey, owner, true)
  end

  logSys('dividas', ('Pagamento aplicado (%s): #%d | %d | restante: %d'):format(paymentType, debtId, pay, remaining), {
    debt_id = debtId, citizenid = citizenid, paid = pay, remaining = remaining
  })

  return true, remaining
end

--============================================================
-- Pay: pagamento in-game (remove dinheiro via integrações)
--============================================================
function Debts.Pay(debtId, src, amountToPay)
  ensureSchema()

  debtId = _toInt(debtId, 0)
  if debtId <= 0 then return false, 'invalid_debt_id' end

  src = tonumber(src) or 0

  -- lock opcional
  local lockKey = ('debt:%d'):format(debtId)
  local owner = ('src_%d'):format(src)
  if SE.Locks and type(SE.Locks.AcquireBlocking) == 'function' then
    local okLock = SE.Locks.AcquireBlocking(lockKey, owner, 30000, 5000, 50)
    if not okLock then return false, 'lock_timeout' end
  end

  local debt = Debts.GetById(debtId)
  if not debt or debt.status ~= 'active' then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'debt_not_found'
  end

  local owed = _toInt(debt.amount, 0)
  local pay = amountToPay and _toInt(amountToPay, 0) or owed
  if pay <= 0 then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'invalid_amount'
  end
  if pay > owed then pay = owed end

  local removed = false
  if SE.Integrations and type(SE.Integrations.RemoveMoney) == 'function' and src > 0 then
    removed = SE.Integrations.RemoveMoney(src, pay, 'bank')
  end

  if not removed then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'insufficient_funds'
  end

  -- aplica como pagamento normal (já removeu a grana)
  local okApply, remaining = Debts.ApplyPayment(debtId, debt.citizenid, pay, 'manual', {
    src = src,
    reason = 'pagamento_in_game'
  })

  if SE.Locks and type(SE.Locks.Release) == 'function' then
    SE.Locks.Release(lockKey, owner, true)
  end

  return okApply, remaining
end

--============================================================
-- JUROS AUTOMÁTICOS (Thread)
--============================================================
CreateThread(function()
  while not hasMySQL() do Wait(1000) end
  ensureSchema()

  local intervalMs = 60 * 60 * 1000 -- 1h
  while true do
    Wait(intervalMs)

    if not DS.Enabled then
      -- sem goto (evita bugs)
    else
      local debts = MySQL.query.await([[
        SELECT id, amount, interest_rate
        FROM space_economy_debts
        WHERE status = 'active'
          AND (grace_until IS NULL OR grace_until < NOW())
          AND (last_interest_at IS NULL OR last_interest_at < DATE_SUB(NOW(), INTERVAL 24 HOUR))
      ]]) or {}

      for _, d in ipairs(debts) do
        local amount = _toInt(d.amount, 0)
        local rate = _toNumber(d.interest_rate, DS.InterestDailyRate)
        local interest = math.floor((amount * rate) + 0.5)

        if interest > 0 then
          local newAmount = amount + interest
          MySQL.update.await([[
            UPDATE space_economy_debts
            SET amount = ?, last_interest_at = NOW()
            WHERE id = ?
          ]], { newAmount, d.id })

          dbg(('Juros aplicados: dívida %d | +%d = %d'):format(d.id, interest, newAmount))
          logSys('juros', ('Juros aplicados: #%d +%d = %d'):format(d.id, interest, newAmount), { debt_id = d.id })
        else
          -- marca para não recalcular toda hora
          MySQL.update.await([[UPDATE space_economy_debts SET last_interest_at = NOW() WHERE id = ?]], { d.id })
        end

        Wait(0)
      end
    end
  end
end)

--============================================================
-- AVISOS PERIÓDICOS (Thread)
--============================================================
CreateThread(function()
  while not hasMySQL() do Wait(1000) end
  ensureSchema()

  local warnIntervalMs = DS.WarnEveryHours * 60 * 60 * 1000
  while true do
    Wait(warnIntervalMs)

    if not DS.Enabled then
      -- skip
    else
      local debts = MySQL.query.await([[
        SELECT citizenid, SUM(amount) as total
        FROM space_economy_debts
        WHERE status = 'active'
          AND due_at IS NOT NULL
          AND due_at < NOW()
        GROUP BY citizenid
      ]]) or {}

      for _, d in ipairs(debts) do
        local src = getSourceByCitizen(d.citizenid)
        if src then
          notify(src, ('Você possui $%d em dívidas vencidas. Regularize sua situação.'):format(_toInt(d.total, 0)), 'error')
        end
        Wait(0)
      end
    end
  end
end)

--============================================================
-- PS-BANKING SYNC: baixa dívida quando bill for paga
--============================================================
CreateThread(function()
  while not hasMySQL() do Wait(1000) end
  ensureSchema()

  while true do
    Wait(DS.PSBanking.ScanIntervalMs)

    if not (DS.Enabled and psBankingAvailable() and tableExists('ps_banking_transactions')) then
      -- sem ps-banking ou tabela, ignora
    else
      local lastId = getCursor()

      -- pega transações novas com prefixo [SE#ID]
      local rows = MySQL.query.await([[
        SELECT id, identifier, description, amount, date, isIncome, type
        FROM ps_banking_transactions
        WHERE id > ?
          AND description LIKE '[SE#%]%'
          AND amount > 0
        ORDER BY id ASC
        LIMIT 250
      ]], { lastId }) or {}

      local newLast = lastId

      for _, tx in ipairs(rows) do
        local txId = tonumber(tx.id) or 0
        if txId > newLast then newLast = txId end

        local cid = _trim(_safeStr(tx.identifier, ''))
        local desc = _safeStr(tx.description, '')
        local amount = _toInt(tx.amount, 0)

        -- parse: [SE#123]
        local debtId = desc:match('%[SE#(%d+)%]')
        debtId = _toInt(debtId, 0)

        if debtId > 0 and cid ~= '' and amount > 0 then
          -- idempotente: provider + tx_id
          local okApplied = applyExternalPayment('ps-banking', txId, debtId, cid, amount, {
            tx_id = txId,
            description = desc,
            type = tx.type,
            isIncome = tx.isIncome,
            date = tx.date
          })

          if okApplied then
            dbg(('ps-banking sync: pagamento detectado tx=%d debt=%d cid=%s amt=%d'):format(txId, debtId, cid, amount))
          end
        end

        Wait(0)
      end

      if newLast > lastId then
        setCursor(newLast)
      end
    end
  end
end)

--============================================================
-- EVENTOS DE REDE
--============================================================
RegisterNetEvent('space_economy:server_payDebt', function(debtId, amount)
  local src = source
  local ok, remaining = Debts.Pay(debtId, src, amount)

  if ok then
    if remaining and remaining > 0 then
      notify(src, ('Pagamento parcial realizado. Restante: $%d'):format(_toInt(remaining, 0)), 'success')
    else
      notify(src, 'Dívida quitada com sucesso!', 'success')
    end
  else
    notify(src, ('Falha ao pagar dívida: %s'):format(_safeStr(remaining, 'erro')), 'error')
  end
end)

RegisterNetEvent('space_economy:server_listMyDebts', function()
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  local debts = Debts.GetActiveByCitizen(cid, 50)
  TriggerClientEvent('space_economy:client_receiveMyDebts', src, debts)
end)

dbg('debts.lua (MELHORADO) carregado - ps-banking sync ativo.')
