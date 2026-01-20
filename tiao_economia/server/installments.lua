--============================================================
-- space_economy - server/installments.lua (REESCRITO / QBOX Hardened)
-- Sistema de parcelamento de dívidas (com tabela de parcelas + histórico + avisos)
-- Integra com SE.Debts e SE.Integrations (ps-banking)
--============================================================
SE = SE or {}
SE.Installments = SE.Installments or {}

local Inst = SE.Installments
local U = SE.Util or {}
local B = SE.Bridge or {}
local cfg = Config or {}

local RES = GetCurrentResourceName()

--============================================================
-- Fallback Utils (anti-nil)
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
  ts = _toInt(ts, _nowTs())
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

local function _jsonDecode(str)
  if type(str) ~= 'string' or str == '' then return {} end
  if json and json.decode then
    local ok, out = pcall(function()
      return json.decode(str)
    end)
    if ok and type(out) == 'table' then return out end
  end
  return {}
end

local function dbg(...)
  if type(U.dbg) == 'function' then
    U.dbg(...)
  else
    print('^3[space_economy:installments]^7', ...)
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

local function hasMySQL()
  return MySQL
    and MySQL.query and MySQL.query.await
    and MySQL.single and MySQL.single.await
    and MySQL.scalar and MySQL.scalar.await
    and MySQL.insert and MySQL.insert.await
    and MySQL.update and MySQL.update.await
end

local function tableExists(name)
  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)
  return ok and rows and #rows > 0
end

--============================================================
-- Logs (compat com SE.Log + tabela)
--============================================================
local function logSys(category, message, meta)
  category = _safeStr(category, 'parcelamentos')
  message = _safeStr(message, '')
  if message == '' or not hasMySQL() then return end

  if type(SE.Log) == 'function' then
    pcall(SE.Log, category, message, meta)
  end

  pcall(function()
    MySQL.insert.await([[
      INSERT INTO space_economy_logs (category, message, metadata, created_at)
      VALUES (?, ?, ?, NOW())
    ]], { category, message, meta and _jsonEncode(meta) or nil })
  end)
end

--============================================================
-- Integrações (ps-banking via SE.Integrations)
--============================================================
local function removeMoney(src, amount)
  amount = _toInt(amount, 0)
  if amount <= 0 or not src or src <= 0 then return false end
  if SE.Integrations and type(SE.Integrations.RemoveMoney) == 'function' then
    return SE.Integrations.RemoveMoney(src, amount, 'bank') == true
  end
  return false
end

local function getCitizenId(src)
  if type(B.GetCitizenId) == 'function' then
    return B.GetCitizenId(src)
  end
  return nil
end

local function getSourceByCitizenId(citizenid)
  if type(B.GetSourceByCitizenId) == 'function' then
    return B.GetSourceByCitizenId(citizenid)
  end
  return nil
end

--============================================================
-- Configuração (defaults seguros)
--============================================================
cfg.InstallmentSystem = cfg.InstallmentSystem or {}
local IC = cfg.InstallmentSystem

IC.Enabled = (IC.Enabled ~= false)
IC.MaxInstallments = _toInt(IC.MaxInstallments or (cfg.DebtSystem and cfg.DebtSystem.MaxInstallments) or 12, 12)
IC.MinInstallmentValue = _toInt(IC.MinInstallmentValue or (cfg.DebtSystem and cfg.DebtSystem.MinInstallmentValue) or 100, 100)
IC.FeePercent = _toNumber(IC.FeePercent or (cfg.DebtSystem and cfg.DebtSystem.InstallmentFee) or 0.05, 0.05) -- 5%
IC.DueEveryDays = _toInt(IC.DueEveryDays or 30, 30)
IC.WarnBeforeDays = _toInt(IC.WarnBeforeDays or 3, 3)
IC.MarkOverdue = (IC.MarkOverdue ~= false)

--============================================================
-- Schema (sem information_schema -> evita “acesso negado”)
--============================================================
local schemaReady = false
local cache = { hasCharCache = nil, hasDebtPayments = nil }

local function ensureSchema()
  if schemaReady or not hasMySQL() then return end
  schemaReady = true

  -- plano
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_installment_plans (
      id INT AUTO_INCREMENT PRIMARY KEY,
      debt_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      original_amount BIGINT NOT NULL,
      total_amount BIGINT NOT NULL,
      installments INT NOT NULL,
      installment_value BIGINT NOT NULL,
      paid_installments INT NOT NULL DEFAULT 0,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      fee_percent DECIMAL(10,4) NOT NULL DEFAULT 0.05,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      next_due_at TIMESTAMP NULL,
      completed_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_debt (debt_id),
      INDEX idx_next_due (next_due_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- parcelas
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_installments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      plan_id INT NOT NULL,
      installment_number INT NOT NULL,
      amount BIGINT NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | overdue | paid
      due_at TIMESTAMP NOT NULL,
      paid_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_plan (plan_id),
      INDEX idx_status_due (status, due_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- garante logs (caso não exista)
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

  -- histórico de pagamentos (compat com debts.lua)
  if not tableExists('space_economy_debt_payments') then
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_debt_payments (
        id INT AUTO_INCREMENT PRIMARY KEY,
        debt_id INT NOT NULL,
        citizenid VARCHAR(64) NOT NULL,
        amount BIGINT NOT NULL,
        payment_type VARCHAR(20) NOT NULL DEFAULT 'full', -- full|partial|installment
        installment_number INT NULL,
        paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        meta LONGTEXT NULL,
        INDEX idx_debt (debt_id),
        INDEX idx_citizen (citizenid)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
  end

  cache.hasCharCache = tableExists('space_economy_charcache')
  cache.hasDebtPayments = tableExists('space_economy_debt_payments')

  dbg('Schema de parcelamento garantido.')
  logSys('sistema', ('[%s] Schema installments OK.'):format(RES))
end

CreateThread(function()
  while not hasMySQL() do Wait(250) end
  ensureSchema()
end)

--============================================================
-- CORE: Cálculo do plano
--============================================================
function Inst.Calculate(amount, installments)
  ensureSchema()
  if not IC.Enabled then return nil, 'sistema_desabilitado' end

  amount = _toInt(amount, 0)
  if amount <= 0 then return nil, 'valor_invalido' end

  installments = _toInt(installments, 1)
  if installments < 1 then installments = 1 end
  if installments > IC.MaxInstallments then installments = IC.MaxInstallments end

  local fee = math.floor((amount * IC.FeePercent) + 0.5)
  if fee < 0 then fee = 0 end
  local total = amount + fee

  local instValue = math.ceil(total / installments)
  if instValue < IC.MinInstallmentValue then
    installments = math.floor(total / IC.MinInstallmentValue)
    if installments < 1 then installments = 1 end
    if installments > IC.MaxInstallments then installments = IC.MaxInstallments end
    instValue = math.ceil(total / installments)
  end

  local lastValue = total - (instValue * (installments - 1))
  if lastValue < 0 then lastValue = 0 end

  return {
    original = amount,
    fee = fee,
    feePercent = IC.FeePercent,
    total = total,
    installments = installments,
    installmentValue = instValue,
    lastInstallment = lastValue,
  }
end

--============================================================
-- Helpers internos
--============================================================
local function _updateDebtToInstallment(debtId, planId, totalAmount, metaExtra)
  debtId = _toInt(debtId, 0)
  planId = _toInt(planId, 0)
  totalAmount = _toInt(totalAmount, 0)

  local row = MySQL.single.await([[SELECT id, meta FROM space_economy_debts WHERE id = ? LIMIT 1]], { debtId })
  if not row then return end

  local meta = _jsonDecode(_safeStr(row.meta, ''))
  meta.plan_id = planId
  meta.installment_total = totalAmount
  meta.updated_by = 'installments'
  meta.resource = RES
  if type(metaExtra) == 'table' then
    for k, v in pairs(metaExtra) do meta[k] = v end
  end

  -- status installment + amount = total (saldo a pagar)
  MySQL.update.await([[
    UPDATE space_economy_debts
    SET status = 'installment',
        amount = ?,
        meta = ?
    WHERE id = ?
  ]], { totalAmount, _jsonEncode(meta), debtId })
end

local function _recalcPlanRemaining(planId)
  local row = MySQL.single.await([[
    SELECT COALESCE(SUM(amount),0) as remaining
    FROM space_economy_installments
    WHERE plan_id = ?
      AND status IN ('pending','overdue')
  ]], { planId })
  return _toInt(row and row.remaining, 0)
end

local function _getNextInstallmentRow(planId)
  return MySQL.single.await([[
    SELECT *
    FROM space_economy_installments
    WHERE plan_id = ?
      AND status IN ('pending','overdue')
    ORDER BY installment_number ASC
    LIMIT 1
  ]], { planId })
end

--============================================================
-- CORE: Criar plano
--============================================================
function Inst.CreatePlan(debtId, citizenid, installments, createdBy)
  ensureSchema()
  if not IC.Enabled then return false, 'sistema_desabilitado' end

  debtId = _toInt(debtId, 0)
  if debtId <= 0 then return false, 'debt_id_invalido' end

  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return false, 'citizenid_invalido' end

  installments = _toInt(installments, 1)
  if installments < 1 then installments = 1 end

  -- dívida precisa existir e estar ativa
  local debt = (SE.Debts and type(SE.Debts.GetById) == 'function') and SE.Debts.GetById(debtId) or nil
  if not debt then return false, 'divida_nao_encontrada' end

  if _safeStr(debt.status, '') ~= 'active' then
    return false, 'divida_nao_ativa'
  end

  if _safeStr(debt.citizenid, '') ~= citizenid then
    return false, 'divida_nao_pertence'
  end

  -- evita duplicar plano para mesma dívida
  local exists = MySQL.single.await([[
    SELECT id FROM space_economy_installment_plans
    WHERE debt_id = ? AND status = 'active'
    LIMIT 1
  ]], { debtId })
  if exists and exists.id then
    return false, 'ja_possui_plano_ativo'
  end

  local amount = _toInt(debt.amount, 0)
  if amount <= 0 then return false, 'divida_sem_valor' end

  local plan, err = Inst.Calculate(amount, installments)
  if not plan then return false, err or 'falha_calculo' end

  local firstDueTs = _nowTs() + (IC.DueEveryDays * 24 * 60 * 60)

  local planId = MySQL.insert.await([[
    INSERT INTO space_economy_installment_plans
      (debt_id, citizenid, original_amount, total_amount, installments,
       installment_value, fee_percent, next_due_at, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    debtId,
    citizenid,
    plan.original,
    plan.total,
    plan.installments,
    plan.installmentValue,
    plan.feePercent,
    _tsToIso(firstDueTs),
    _jsonEncode({ created_by = createdBy or 'player', resource = RES })
  })

  if not planId then
    return false, 'falha_criar_plano'
  end

  -- cria parcelas (30/IC.DueEveryDays dias entre elas)
  local baseTs = _nowTs()
  for i = 1, plan.installments do
    local dueTs = baseTs + (i * IC.DueEveryDays * 24 * 60 * 60)
    local value = (i == plan.installments) and plan.lastInstallment or plan.installmentValue

    MySQL.insert.await([[
      INSERT INTO space_economy_installments
        (plan_id, installment_number, amount, due_at, meta)
      VALUES (?, ?, ?, ?, ?)
    ]], {
      planId,
      i,
      _toInt(value, 0),
      _tsToIso(dueTs),
      _jsonEncode({ debt_id = debtId, citizenid = citizenid })
    })
  end

  -- atualiza dívida (installment / amount = total com taxa)
  _updateDebtToInstallment(debtId, planId, plan.total, {
    fee = plan.fee,
    installments = plan.installments
  })

  logSys('parcelamentos', ('Plano criado #%d: %d parcelas | total $%d'):format(
    _toInt(planId, 0), _toInt(plan.installments, 0), _toInt(plan.total, 0)
  ), { plan_id = planId, debt_id = debtId, citizenid = citizenid })

  dbg(('Plano criado: %s | dívida #%d | %d parcelas'):format(citizenid, debtId, plan.installments))
  return true, planId, plan
end

--============================================================
-- CORE: Buscar planos (player)
--============================================================
function Inst.GetActivePlans(citizenid, limit)
  ensureSchema()

  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return {} end

  limit = _toInt(limit or 50, 50)
  if limit < 1 then limit = 1 end
  if limit > 200 then limit = 200 end

  local rows
  if cache.hasCharCache then
    rows = MySQL.query.await([[
      SELECT p.*,
             d.reason as debt_reason,
             COALESCE(c.name,'Desconhecido') as playerName
      FROM space_economy_installment_plans p
      LEFT JOIN space_economy_debts d ON d.id = p.debt_id
      LEFT JOIN space_economy_charcache c ON c.citizenid = p.citizenid
      WHERE p.citizenid = ? AND p.status = 'active'
      ORDER BY p.created_at DESC
      LIMIT ?
    ]], { citizenid, limit }) or {}
  else
    rows = MySQL.query.await([[
      SELECT p.*,
             d.reason as debt_reason,
             'Desconhecido' as playerName
      FROM space_economy_installment_plans p
      LEFT JOIN space_economy_debts d ON d.id = p.debt_id
      WHERE p.citizenid = ? AND p.status = 'active'
      ORDER BY p.created_at DESC
      LIMIT ?
    ]], { citizenid, limit }) or {}
  end

  -- adiciona next installment
  for i = 1, #rows do
    local nextInst = _getNextInstallmentRow(rows[i].id)
    rows[i].next_installment = nextInst
  end

  return rows
end

--============================================================
-- CORE: Buscar detalhes do plano (com parcelas)
--============================================================
function Inst.GetPlanDetails(planId)
  ensureSchema()
  planId = _toInt(planId, 0)
  if planId <= 0 then return nil end

  local plan = MySQL.single.await([[
    SELECT p.*, d.reason as debt_reason
    FROM space_economy_installment_plans p
    LEFT JOIN space_economy_debts d ON d.id = p.debt_id
    WHERE p.id = ?
    LIMIT 1
  ]], { planId })

  if not plan then return nil end

  local insts = MySQL.query.await([[
    SELECT *
    FROM space_economy_installments
    WHERE plan_id = ?
    ORDER BY installment_number ASC
  ]], { planId }) or {}

  plan.installments_list = insts
  plan.remaining_amount = _recalcPlanRemaining(planId)

  return plan
end

--============================================================
-- CORE: Admin Search (por citizenid)
-- (para resolver ações tipo "search_installment" no painel admin)
--============================================================
function Inst.SearchPlansByCitizen(citizenid, limit)
  ensureSchema()

  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return {} end

  limit = _toInt(limit or 50, 50)
  if limit < 1 then limit = 1 end
  if limit > 200 then limit = 200 end

  local rows = MySQL.query.await([[
    SELECT p.*,
           d.reason as debt_reason
    FROM space_economy_installment_plans p
    LEFT JOIN space_economy_debts d ON d.id = p.debt_id
    WHERE p.citizenid = ?
    ORDER BY p.created_at DESC
    LIMIT ?
  ]], { citizenid, limit }) or {}

  for i = 1, #rows do
    rows[i].remaining_amount = _recalcPlanRemaining(rows[i].id)
    rows[i].next_installment = _getNextInstallmentRow(rows[i].id)
  end

  return rows
end

--============================================================
-- CORE: Pagar próxima parcela
--============================================================
function Inst.PayNextInstallment(planId, src)
  ensureSchema()
  if not IC.Enabled then return false, 'sistema_desabilitado' end

  planId = _toInt(planId, 0)
  if planId <= 0 then return false, 'plan_id_invalido' end

  src = tonumber(src) or 0
  if src <= 0 then return false, 'source_invalida' end

  -- lock
  local lockKey = ('installment_plan:%d'):format(planId)
  local owner = ('src_%d'):format(src)

  if SE.Locks and type(SE.Locks.AcquireBlocking) == 'function' then
    local okLock = SE.Locks.AcquireBlocking(lockKey, owner, 30000, 5000, 50)
    if not okLock then return false, 'lock_timeout' end
  end

  local plan = MySQL.single.await([[
    SELECT * FROM space_economy_installment_plans
    WHERE id = ? AND status = 'active'
    LIMIT 1
  ]], { planId })

  if not plan then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'plano_nao_encontrado'
  end

  -- segurança: só o dono paga pelo painel player
  local cid = getCitizenId(src)
  if not cid or _safeStr(plan.citizenid, '') ~= cid then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'nao_autorizado'
  end

  local nextInst = _getNextInstallmentRow(planId)
  if not nextInst then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'sem_parcela_pendente'
  end

  local amount = _toInt(nextInst.amount, 0)
  if amount <= 0 then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'valor_parcela_invalido'
  end

  -- debita do banco (ps-banking)
  if not removeMoney(src, amount) then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'saldo_insuficiente'
  end

  -- marca parcela como paga
  MySQL.update.await([[
    UPDATE space_economy_installments
    SET status='paid', paid_at=NOW()
    WHERE id = ?
  ]], { nextInst.id })

  -- incrementa plano
  local newPaid = _toInt(plan.paid_installments, 0) + 1
  local totalInst = _toInt(plan.installments, 0)

  -- recalcula saldo restante real
  local remaining = _recalcPlanRemaining(planId)

  if newPaid >= totalInst or remaining <= 0 then
    -- finaliza plano
    MySQL.update.await([[
      UPDATE space_economy_installment_plans
      SET paid_installments=?,
          status='completed',
          completed_at=NOW(),
          next_due_at=NULL
      WHERE id=?
    ]], { newPaid, planId })

    -- finaliza dívida
    MySQL.update.await([[
      UPDATE space_economy_debts
      SET status='paid', paid_at=NOW(), amount=0
      WHERE id=?
    ]], { plan.debt_id })
  else
    local nxt = _getNextInstallmentRow(planId)
    MySQL.update.await([[
      UPDATE space_economy_installment_plans
      SET paid_installments=?,
          next_due_at=?
      WHERE id=?
    ]], { newPaid, (nxt and nxt.due_at) or plan.next_due_at, planId })

    -- atualiza dívida com saldo restante
    MySQL.update.await([[
      UPDATE space_economy_debts
      SET amount=?
      WHERE id=?
    ]], { remaining, plan.debt_id })
  end

  -- histórico (debt_payments)
  if cache.hasDebtPayments then
    MySQL.insert.await([[
      INSERT INTO space_economy_debt_payments
        (debt_id, citizenid, amount, payment_type, installment_number, meta)
      VALUES (?, ?, ?, 'installment', ?, ?)
    ]], {
      plan.debt_id,
      plan.citizenid,
      amount,
      _toInt(nextInst.installment_number, newPaid),
      _jsonEncode({ plan_id = planId, installment_id = nextInst.id, src = src, resource = RES })
    })
  end

  -- tesouro (se existir)
  if SE.Treasury and type(SE.Treasury.Deposit) == 'function' then
    pcall(SE.Treasury.Deposit, amount, 'pagamento_parcelamento', {
      plan_id = planId,
      installment_id = nextInst.id,
      debt_id = plan.debt_id,
      citizenid = plan.citizenid
    })
  end

  registerTransaction('pagamento_parcelamento', amount, {
    plan_id = planId,
    installment_id = nextInst.id,
    debt_id = plan.debt_id,
    citizenid = plan.citizenid
  })

  if SE.Locks and type(SE.Locks.Release) == 'function' then
    SE.Locks.Release(lockKey, owner, true)
  end

  logSys('parcelamentos', ('Parcela paga #%d: %d/%d | valor $%d | restante $%d'):format(
    planId, newPaid, totalInst, amount, math.max(remaining, 0)
  ), { plan_id = planId, citizenid = plan.citizenid, debt_id = plan.debt_id })

  return true, {
    planId = planId,
    paid = newPaid,
    total = totalInst,
    remaining = math.max(totalInst - newPaid, 0),
    remaining_amount = math.max(remaining, 0),
    completed = (newPaid >= totalInst or remaining <= 0),
    installment = nextInst
  }
end

--============================================================
-- THREAD: Avisos e overdue
--============================================================
CreateThread(function()
  while not hasMySQL() do Wait(1000) end
  ensureSchema()

  local intervalMs = 60 * 60 * 1000 -- 1h

  while true do
    Wait(intervalMs)

    if not IC.Enabled then
      -- skip
    else
      -- marca pending vencida como overdue
      if IC.MarkOverdue then
        pcall(function()
          MySQL.update.await([[
            UPDATE space_economy_installments
            SET status='overdue'
            WHERE status='pending' AND due_at < NOW()
          ]])
        end)
      end

      -- avisos: vence em até WarnBeforeDays
      local rows = MySQL.query.await([[
        SELECT i.plan_id, i.installment_number, i.amount, i.due_at,
               p.citizenid, p.installments as total_installments
        FROM space_economy_installments i
        INNER JOIN space_economy_installment_plans p ON p.id = i.plan_id
        WHERE p.status='active'
          AND i.status IN ('pending','overdue')
          AND i.due_at BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL ? DAY)
      ]], { IC.WarnBeforeDays }) or {}

      for _, r in ipairs(rows) do
        local src = getSourceByCitizenId(r.citizenid)
        if src then
          notify(src, ('Parcela %d/%d vence em breve. Valor: $%d'):format(
            _toInt(r.installment_number, 0),
            _toInt(r.total_installments, 0),
            _toInt(r.amount, 0)
          ), 'warn')
        end
        Wait(0)
      end
    end
  end
end)

--============================================================
-- EVENTOS DE REDE (player)
--============================================================
RegisterNetEvent('space_economy:server_createInstallmentPlan', function(debtId, installments)
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  local ok, planId, plan = Inst.CreatePlan(debtId, cid, installments, ('src_%d'):format(src))
  if ok then
    notify(src, ('Parcelamento criado: %d x $%d (total $%d)'):format(
      _toInt(plan.installments, 0),
      _toInt(plan.installmentValue, 0),
      _toInt(plan.total, 0)
    ), 'success')
    TriggerClientEvent('space_economy:client_installmentPlanCreated', src, planId, plan)
  else
    notify(src, ('Falha ao criar parcelamento: %s'):format(_safeStr(planId, 'erro')), 'error')
  end
end)

RegisterNetEvent('space_economy:server_payInstallment', function(planId)
  local src = source
  local ok, result = Inst.PayNextInstallment(planId, src)
  if ok then
    if result.completed then
      notify(src, 'Parcelamento quitado com sucesso!', 'success')
    else
      notify(src, ('Parcela paga! Restam %d de %d. Saldo: $%d'):format(
        _toInt(result.remaining, 0),
        _toInt(result.total, 0),
        _toInt(result.remaining_amount, 0)
      ), 'success')
    end
    TriggerClientEvent('space_economy:client_installmentPaid', src, planId, result)
  else
    notify(src, ('Falha ao pagar parcela: %s'):format(_safeStr(result, 'erro')), 'error')
  end
end)

RegisterNetEvent('space_economy:server_getMyInstallments', function()
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end
  local plans = Inst.GetActivePlans(cid, 50)
  TriggerClientEvent('space_economy:client_receiveInstallments', src, plans)
end)

RegisterNetEvent('space_economy:server_getInstallmentPlanDetails', function(planId)
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  local plan = Inst.GetPlanDetails(planId)
  if not plan then
    notify(src, 'Plano de parcelamento não encontrado.', 'error')
    return
  end

  if _safeStr(plan.citizenid, '') ~= cid then
    notify(src, 'Acesso negado.', 'error')
    return
  end

  TriggerClientEvent('space_economy:client_receiveInstallmentPlanDetails', src, plan)
end)

--============================================================
-- ALIASES (para router NUI que chama ações tipo "search_installment")
-- (não atrapalha, só ajuda compat)
--============================================================
RegisterNetEvent('space_economy:server_searchInstallment', function(citizenid)
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  -- player só pode buscar o próprio
  citizenid = _trim(_safeStr(citizenid, cid))
  citizenid = citizenid == '' and cid or citizenid
  if citizenid ~= cid then
    notify(src, 'Acesso negado.', 'error')
    return
  end

  local plans = Inst.SearchPlansByCitizen(citizenid, 50)
  TriggerClientEvent('space_economy:client_receiveInstallments', src, plans)
end)

RegisterNetEvent('space_economy:server_search_installment', function(citizenid)
  TriggerEvent('space_economy:server_searchInstallment', citizenid)
end)

dbg('installments.lua carregado (QBOX Hardened).')
