--============================================================
-- space_economy - server/integrations.lua (REESCRITO)
-- Wrapper multi-framework + integrações (ps-banking / housing / garage / jobs / inventory)
-- Foco: fallbacks robustos + logs/statement no ps-banking para ações feitas por outros resources
--============================================================
SE = SE or {}
SE.Integrations = SE.Integrations or {}

local U = SE.Util
local B = SE.Bridge
local cfg = (Config and Config.Integrations) or {}

--============================================================
-- Helpers base (fallback caso U não exista)
--============================================================
local function toInt(v, d)
  if U and U.toInt then return U.toInt(v, d or 0) end
  v = tonumber(v)
  if not v then return d or 0 end
  v = math.floor(v)
  if d ~= nil and v == 0 then return d end
  return v
end

local function safeStr(v, d)
  if U and U.safeStr then return U.safeStr(v, d or '') end
  v = tostring(v or d or '')
  return v
end

local function trim(s)
  if U and U.trim then return U.trim(s) end
  s = tostring(s or '')
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function dbg(...)
  if U and U.dbg then
    U.dbg(...)
  else
    print('^3[space_economy:integrations]^7', ...)
  end
end

local function isStarted(res)
  return GetResourceState(res) == 'started'
end

local function getResourceState(res)
  local state = GetResourceState(res)
  if not state or state == '' then return 'missing' end
  return state
end

local function listResourceStates(resources)
  local out = {}
  for _, res in ipairs(resources or {}) do
    out[res] = getResourceState(res)
  end
  return out
end

--============================================================
-- Cache simples (dados estáticos como nome do personagem)
--============================================================
local PlayerCache = {
  ttl = 60,
  names = {},
}

local function cacheGet(container, key)
  local entry = container[key]
  if not entry then return nil end
  if (os.time() - entry.ts) > PlayerCache.ttl then
    container[key] = nil
    return nil
  end
  return entry.value
end

local function cacheSet(container, key, value)
  container[key] = { value = value, ts = os.time() }
end

function SE.Integrations.GetCharacterName(srcOrCid)
  local cid = nil
  local src = nil

  if type(srcOrCid) == 'number' then
    src = tonumber(srcOrCid)
  elseif type(srcOrCid) == 'string' then
    cid = trim(srcOrCid)
    if cid:match('^%d+$') then
      src = tonumber(cid)
      cid = nil
    end
  end

  if src then
    local cached = cacheGet(PlayerCache.names, src)
    if cached then return cached end

    local name = (B and B.GetCharName and B.GetCharName(src)) or 'Desconhecido'
    cacheSet(PlayerCache.names, src, name)
    return name
  end

  if cid then
    local cached = cacheGet(PlayerCache.names, cid)
    if cached then return cached end

    local name = (SE.CharCache and SE.CharCache.ResolveName and SE.CharCache.ResolveName(cid)) or 'Desconhecido'
    cacheSet(PlayerCache.names, cid, name)
    return name
  end

  return 'Desconhecido'
end

--============================================================
-- MySQL wrapper (oxmysql / mysql-async / MySQL.*)
--============================================================
local function dbQuery(sql, params)
  params = params or {}

  if MySQL and MySQL.query and MySQL.query.await then
    local ok, res = pcall(function() return MySQL.query.await(sql, params) end)
    if ok then return res end
  end

  if exports and exports.oxmysql and exports.oxmysql.query_async then
    local ok, res = pcall(function() return exports.oxmysql:query_async(sql, params) end)
    if ok then return res end
  end

  if MySQL and MySQL.Async and MySQL.Async.fetchAll then
    local p = promise.new()
    MySQL.Async.fetchAll(sql, params, function(res) p:resolve(res or {}) end)
    return Citizen.Await(p) or {}
  end

  return nil
end

local function dbSingle(sql, params)
  params = params or {}
  if MySQL and MySQL.single and MySQL.single.await then
    local ok, res = pcall(function() return MySQL.single.await(sql, params) end)
    if ok then return res end
  end
  local rows = dbQuery(sql, params) or {}
  return rows[1]
end

local function dbScalar(sql, params)
  params = params or {}
  if MySQL and MySQL.scalar and MySQL.scalar.await then
    local ok, res = pcall(function() return MySQL.scalar.await(sql, params) end)
    if ok then return res end
  end
  local row = dbSingle(sql, params)
  if not row then return nil end
  for _, v in pairs(row) do return v end
  return nil
end

local function dbExec(sql, params)
  params = params or {}

  if MySQL and MySQL.update and MySQL.update.await then
    local ok, res = pcall(function() return MySQL.update.await(sql, params) end)
    if ok then return res end
  end

  if exports and exports.oxmysql and exports.oxmysql.update_async then
    local ok, res = pcall(function() return exports.oxmysql:update_async(sql, params) end)
    if ok then return res end
  end

  if MySQL and MySQL.Async and MySQL.Async.execute then
    local p = promise.new()
    MySQL.Async.execute(sql, params, function(affected) p:resolve(affected or 0) end)
    return Citizen.Await(p) or 0
  end

  return 0
end

--============================================================
-- Cache de schema/tabelas (evita SHOW TABLES repetido)
--============================================================
local _schemaCache = {
  tables = {},
  cols = {},
}

local function tableExists(t)
  t = tostring(t or '')
  if t == '' then return false end
  if _schemaCache.tables[t] ~= nil then return _schemaCache.tables[t] end

  local rows = dbQuery('SHOW TABLES LIKE ?', { t })
  local ok = rows and #rows > 0
  _schemaCache.tables[t] = ok
  return ok
end

local function colsOf(t)
  t = tostring(t or '')
  if t == '' then return {} end
  if _schemaCache.cols[t] then return _schemaCache.cols[t] end

  local out = {}
  local rows = dbQuery(('SHOW COLUMNS FROM `%s`'):format(t)) or {}
  for _, c in ipairs(rows) do
    if c and c.Field then out[c.Field] = true end
  end
  _schemaCache.cols[t] = out
  return out
end

local function pickCol(cols, candidates)
  for _, c in ipairs(candidates) do
    if cols[c] then return c end
  end
  return nil
end

--============================================================
-- DETECÇÃO DE FRAMEWORKS
--============================================================
local FrameworkDetected = nil
local QBCoreCached = nil

local function DetectFramework()
  if FrameworkDetected then return FrameworkDetected end

  if isStarted('qbx_core') and exports.qbx_core then
    FrameworkDetected = 'qbx'
    dbg('Framework detectado: qbx_core')
    return FrameworkDetected
  end

  if isStarted('qb-core') and exports['qb-core'] then
    FrameworkDetected = 'qbcore'
    dbg('Framework detectado: qb-core')
    return FrameworkDetected
  end

  if isStarted('es_extended') then
    FrameworkDetected = 'esx'
    dbg('Framework detectado: es_extended')
    return FrameworkDetected
  end

  FrameworkDetected = 'unknown'
  dbg('AVISO: framework não detectado')
  return FrameworkDetected
end

local function GetQBCore()
  if QBCoreCached then return QBCoreCached end
  if exports and exports['qb-core'] and exports['qb-core'].GetCoreObject then
    local ok, core = pcall(exports['qb-core'].GetCoreObject)
    if ok and core then QBCoreCached = core end
  end
  return QBCoreCached
end

local function GetPlayer(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end

  local fw = DetectFramework()

  if fw == 'qbx' and exports.qbx_core and exports.qbx_core.GetPlayer then
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok then return p end
  end

  if fw == 'qbcore' then
    local core = GetQBCore()
    if core and core.Functions and core.Functions.GetPlayer then
      return core.Functions.GetPlayer(src)
    end
  end

  return nil
end

local function GetPlayerByCitizenId(citizenid)
  citizenid = trim(safeStr(citizenid, ''))
  if citizenid == '' then return nil end

  if B and B.GetPlayerByCitizenId then
    local ok, p = pcall(B.GetPlayerByCitizenId, citizenid)
    if ok and p then return p end
  end

  local core = GetQBCore()
  if core and core.Functions and core.Functions.GetPlayerByCitizenId then
    return core.Functions.GetPlayerByCitizenId(citizenid)
  end

  -- qbx_core às vezes tem export de lookup; tentamos de forma best-effort
  if exports.qbx_core and exports.qbx_core.GetPlayerByCitizenId then
    local ok, p = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(citizenid) end)
    if ok then return p end
  end

  return nil
end

--============================================================
-- CITIZENID
--============================================================
function SE.Integrations.GetCitizenId(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end

  if B and B.GetCitizenId then
    local ok, cid = pcall(B.GetCitizenId, src)
    if ok and cid and cid ~= '' then return cid end
  end

  local p = GetPlayer(src)
  if p and p.PlayerData then
    return p.PlayerData.citizenid
  end

  return nil
end

local function normalizeCitizenId(cidOrSrc)
  if cidOrSrc == nil then return nil end
  if type(cidOrSrc) == 'number' then return SE.Integrations.GetCitizenId(cidOrSrc) end
  if type(cidOrSrc) == 'string' then
    local s = trim(cidOrSrc)
    if s:match('^%d+$') then return SE.Integrations.GetCitizenId(tonumber(s)) end
    return s
  end
  return nil
end

--============================================================
-- PS-BANKING: statement para transações feitas por outros resources
-- (ps-banking normalmente só grava histórico quando a ação vem do próprio app)
--============================================================
local psbCfg = cfg.PsBanking or {}
psbCfg.EnableStatements = (psbCfg.EnableStatements ~= false) -- default true
psbCfg.StatementTable = psbCfg.StatementTable or 'ps_banking_transactions'

local function PsBankingAddStatementByCitizenId(citizenid, amount, description, isIncome)
  if not psbCfg.EnableStatements then return false, 'disabled' end
  if not isStarted('ps-banking') then return false, 'ps_banking_not_started' end

  citizenid = trim(safeStr(citizenid, ''))
  if citizenid == '' then return false, 'invalid_citizenid' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  local t = tostring(psbCfg.StatementTable or 'ps_banking_transactions')
  if not tableExists(t) then return false, 'table_not_found' end

  local cols = colsOf(t)
  local colId   = pickCol(cols, { 'id' })
  local colCid  = pickCol(cols, { 'identifier', 'citizenid', 'citizen_id' })
  local colDesc = pickCol(cols, { 'description', 'title', 'label', 'reason', 'message' })
  local colType = pickCol(cols, { 'type', 'account', 'category' })
  local colAmt  = pickCol(cols, { 'amount', 'value', 'total' })
  local colDate = pickCol(cols, { 'date', 'created_at', 'createdAt', 'timestamp' })
  local colIn   = pickCol(cols, { 'isIncome', 'income', 'is_income' })

  if not colCid or not colDesc or not colAmt then
    return false, 'schema_incompatible'
  end

  local fields, marks, params = {}, {}, {}

  fields[#fields+1] = ('`%s`'):format(colCid);  marks[#marks+1] = '?'; params[#params+1] = citizenid
  fields[#fields+1] = ('`%s`'):format(colDesc); marks[#marks+1] = '?'; params[#params+1] = safeStr(description, 'Transação')

  if colType then
    fields[#fields+1] = ('`%s`'):format(colType); marks[#marks+1] = '?'; params[#params+1] = 'bank'
  end

  fields[#fields+1] = ('`%s`'):format(colAmt); marks[#marks+1] = '?'; params[#params+1] = amount

  if colDate then
    fields[#fields+1] = ('`%s`'):format(colDate); marks[#marks+1] = 'NOW()'
  end

  if colIn then
    fields[#fields+1] = ('`%s`'):format(colIn); marks[#marks+1] = '?'; params[#params+1] = (isIncome and 1 or 0)
  end

  local sql = ('INSERT INTO `%s` (%s) VALUES (%s)'):format(t, table.concat(fields, ', '), table.concat(marks, ', '))

  local ok, err = pcall(function()
    dbExec(sql, params)
  end)

  if not ok then
    local errorMsg = tostring(err)
    dbg('[Integrations] Erro ao adicionar statement ps-banking: ' .. errorMsg)

    -- Log no sistema se disponível
    if SE.Log and type(SE.Log) == 'function' then
      pcall(SE.Log, 'erro', 'Falha ao criar statement ps-banking', {
        citizenid = citizenid,
        amount = amount,
        error = errorMsg
      })
    end

    return false, errorMsg
  end

  return true
end

--============================================================
-- MONEY OPERATIONS (robustas + retorno correto)
--============================================================
local function _bridgeRemove(src, account, amount, reason)
  if not (B and B.RemoveMoney) then return nil end
  -- tenta assinaturas comuns sem quebrar
  local ok, res = pcall(function() return B.RemoveMoney(src, account, amount, reason) end)
  if ok and (res == true or res == 1) then return true end
  return false
end

local function _bridgeAdd(src, account, amount, reason)
  if not (B and B.AddMoney) then return nil end
  local ok, res = pcall(function() return B.AddMoney(src, account, amount, reason) end)
  if ok and (res == true or res == 1) then return true end
  return false
end

local function _playerRemove(p, account, amount, reason)
  if not (p and p.Functions and p.Functions.RemoveMoney) then return nil end
  local ok, res = pcall(function()
    return p.Functions.RemoveMoney(account, amount, reason)
  end)
  if not ok then return false end
  -- IMPORTANTÍSSIMO: respeitar retorno da função do framework
  if res == nil then return true end -- alguns forks não retornam, mas executam
  return res == true
end

local function _playerAdd(p, account, amount, reason)
  if not (p and p.Functions and p.Functions.AddMoney) then return nil end
  local ok, res = pcall(function()
    return p.Functions.AddMoney(account, amount, reason)
  end)
  if not ok then return false end
  if res == nil then return true end
  return res == true
end

local function GetIntegrationStatus()
  local status = {
    generatedAt = os.date('!%Y-%m-%d %H:%M:%S'),
    framework = {
      detected = DetectFramework(),
      resources = listResourceStates({ 'qbx_core', 'qb-core', 'es_extended' }),
    },
    dependencies = listResourceStates({ 'ox_lib', 'oxmysql' }),
    integrations = {
      banking = {
        enabled = cfg.Banking and cfg.Banking.Enabled ~= false,
        resource = cfg.Banking and cfg.Banking.Resource or 'auto',
        resources = listResourceStates({ 'ps-banking', 'qb-banking', 'qbx-banking' }),
      },
      dispatch = {
        enabled = cfg.Dispatch and cfg.Dispatch.Enabled == true,
        resource = cfg.Dispatch and cfg.Dispatch.Resource or 'ps-dispatch',
        resources = listResourceStates({ 'ps-dispatch' }),
      },
      mdt = {
        enabled = cfg.MDT and cfg.MDT.Enabled == true,
        resource = cfg.MDT and cfg.MDT.Resource or 'ps-mdt',
        resources = listResourceStates({ 'ps-mdt' }),
      },
      housing = {
        enabled = cfg.RealEstate and cfg.RealEstate.Enabled == true,
        resources = listResourceStates({ 'ps-housing', 'qb-houses', 'qbx-houses' }),
      },
      garages = {
        enabled = cfg.Garages and cfg.Garages.Enabled == true,
        resources = listResourceStates({ 'rhd_garage', 'qb-garage', 'qb-garages', 'qbx-garages' }),
      },
      dealership = {
        enabled = true,
        resources = listResourceStates({ 'rm-dealership', 'qb-vehicleshop', 'qbx-vehicleshop' }),
      },
      inventory = {
        enabled = true,
        resources = listResourceStates({ 'ox_inventory', 'ps-inventory', 'qb-inventory' }),
      },
    },
    externalIntegrations = {
      configured = (Config and (Config.ExternalIntegrations or (Config.Integrations and Config.Integrations.ExternalIntegrations))) ~= nil,
    },
    dbIntegrations = {
      configured = (Config and (Config.DBIntegrations or (Config.Integrations and Config.Integrations.DBIntegrations))) ~= nil,
      initialized = SE.DBIntegrations and SE.DBIntegrations.State and SE.DBIntegrations.State.initialized or false,
      systems = SE.DBIntegrations and SE.DBIntegrations.Config and SE.DBIntegrations.Config.Systems or {},
    },
  }

  return status
end

SE.Integrations.GetStatus = GetIntegrationStatus

local function logTrailDebit(src, amount, account, reason, meta)
  if not (SE.MoneyTrail and SE.MoneyTrail.LogDebit) then return end
  SE.MoneyTrail.LogDebit(src, amount, account, reason, meta)
end

local function logTrailCredit(src, amount, account, reason, meta)
  if not (SE.MoneyTrail and SE.MoneyTrail.LogCredit) then return end
  SE.MoneyTrail.LogCredit(src, amount, account, reason, meta)
end

function SE.Integrations.GetBalance(src, account)
  src = tonumber(src)
  if not src or src <= 0 then return 0 end
  account = account or 'bank'

  if B and B.GetBalance then
    local ok, bal = pcall(B.GetBalance, src, account)
    if ok and type(bal) == 'number' then return toInt(bal, 0) end
  end

  if B and account == 'bank' and B.GetBankBalance then
    local ok, bal = pcall(B.GetBankBalance, src)
    if ok and type(bal) == 'number' then return toInt(bal, 0) end
  end

  local p = GetPlayer(src)
  if p and p.PlayerData and p.PlayerData.money then
    return toInt(p.PlayerData.money[account], 0)
  end

  return 0
end

function SE.Integrations.RemoveMoney(src, amount, account, reason)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  account = account or 'bank'
  reason = safeStr(reason, 'space_economy')

  if SE.SecurityGuard and SE.SecurityGuard.ValidateDebit then
    local okGuard, errGuard = SE.SecurityGuard.ValidateDebit(src, amount, account, reason)
    if not okGuard then
      return false, errGuard or 'blocked_by_guard'
    end
  end

  -- saldo (evita remover e dar true por bug)
  local bal = SE.Integrations.GetBalance(src, account)
  if bal < amount then
    return false, 'insufficient_funds'
  end

  -- Bridge primeiro
  local r = _bridgeRemove(src, account, amount, reason)
  if r == true then
    if account == 'bank' then
      local cid = SE.Integrations.GetCitizenId(src)
      if cid then PsBankingAddStatementByCitizenId(cid, amount, ('-%s'):format(reason), false) end
    end
    logTrailDebit(src, amount, account, reason, { account = account, reason = reason, source = 'bridge' })
    return true
  elseif r == false then
    -- continua nos fallbacks
  end

  local p = GetPlayer(src)
  local rr = _playerRemove(p, account, amount, reason)
  if rr == true then
    if account == 'bank' then
      local cid = SE.Integrations.GetCitizenId(src)
      if cid then PsBankingAddStatementByCitizenId(cid, amount, ('-%s'):format(reason), false) end
    end
    logTrailDebit(src, amount, account, reason, { account = account, reason = reason, source = 'player' })
    return true
  elseif rr == false then
    return false, 'remove_failed'
  end

  -- fallback qb-core direto (caso GetPlayer acima seja qbx e não exponha Functions)
  if DetectFramework() == 'qbcore' then
    local core = GetQBCore()
    if core and core.Functions and core.Functions.GetPlayer then
      local ply = core.Functions.GetPlayer(src)
      local rr2 = _playerRemove(ply, account, amount, reason)
      if rr2 == true then
        if account == 'bank' then
          local cid = SE.Integrations.GetCitizenId(src)
          if cid then PsBankingAddStatementByCitizenId(cid, amount, ('-%s'):format(reason), false) end
        end
        logTrailDebit(src, amount, account, reason, { account = account, reason = reason, source = 'qbcore' })
        return true
      elseif rr2 == false then
        return false, 'remove_failed'
      end
    end
  end

  return false, 'no_integration'
end

function SE.Integrations.AddMoney(src, amount, account, reason)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  account = account or 'bank'
  reason = safeStr(reason, 'space_economy')

  if SE.SecurityGuard and SE.SecurityGuard.ValidateCredit then
    local okGuard, errGuard = SE.SecurityGuard.ValidateCredit(src, amount, account, reason)
    if not okGuard then
      return false, errGuard or 'blocked_by_guard'
    end
  end

  local r = _bridgeAdd(src, account, amount, reason)
  if r == true then
    if account == 'bank' then
      local cid = SE.Integrations.GetCitizenId(src)
      if cid then PsBankingAddStatementByCitizenId(cid, amount, ('+%s'):format(reason), true) end
    end
    logTrailCredit(src, amount, account, reason, { account = account, reason = reason, source = 'bridge' })
    return true
  elseif r == false then
    -- continua
  end

  local p = GetPlayer(src)
  local rr = _playerAdd(p, account, amount, reason)
  if rr == true then
    if account == 'bank' then
      local cid = SE.Integrations.GetCitizenId(src)
      if cid then PsBankingAddStatementByCitizenId(cid, amount, ('+%s'):format(reason), true) end
    end
    logTrailCredit(src, amount, account, reason, { account = account, reason = reason, source = 'player' })
    return true
  elseif rr == false then
    return false, 'add_failed'
  end

  if DetectFramework() == 'qbcore' then
    local core = GetQBCore()
    if core and core.Functions and core.Functions.GetPlayer then
      local ply = core.Functions.GetPlayer(src)
      local rr2 = _playerAdd(ply, account, amount, reason)
      if rr2 == true then
        if account == 'bank' then
          local cid = SE.Integrations.GetCitizenId(src)
          if cid then PsBankingAddStatementByCitizenId(cid, amount, ('+%s'):format(reason), true) end
        end
        logTrailCredit(src, amount, account, reason, { account = account, reason = reason, source = 'qbcore' })
        return true
      elseif rr2 == false then
        return false, 'add_failed'
      end
    end
  end

  return false, 'no_integration'
end

--============================================================
-- BANKING TRANSFER (player -> conta society / holder)
-- ps-banking: debita via framework e credita via AddMoney(holder)
--============================================================
function SE.Integrations.BankingTransfer(fromSrc, toAccount, amount, reason)
  fromSrc = tonumber(fromSrc)
  if not fromSrc or fromSrc <= 0 then return false, 'invalid_source' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  reason = safeStr(reason, 'Transferência')

  -- ps-banking (flow recomendado)
  if isStarted('ps-banking') and exports['ps-banking'] then
    local holder = toAccount
    local toId = tonumber(toAccount)

    if toId and exports['ps-banking'].GetAccountById then
      local okAcc, acc = pcall(function() return exports['ps-banking']:GetAccountById(toId) end)
      if okAcc and acc and acc.holder then
        holder = acc.holder
      else
        return false, 'invalid_target_account'
      end
    else
      holder = trim(safeStr(holder, ''))
      if holder == '' then return false, 'invalid_target_account' end
    end

    local okRemove, errRemove = SE.Integrations.RemoveMoney(fromSrc, amount, 'bank', reason)
    if not okRemove then
      return false, errRemove or 'could_not_debit_player'
    end

    local okAdd, addRes = pcall(function()
      if exports['ps-banking'].AddMoney then
        return exports['ps-banking']:AddMoney(holder, amount, reason)
      end
      return false
    end)

    if not (okAdd and addRes == true) then
      -- rollback
      SE.Integrations.AddMoney(fromSrc, amount, 'bank', ('rollback:%s'):format(reason))
      return false, 'ps_banking_add_failed'
    end

    -- statement extra (society): se quiser, também loga em tabela do ps-banking
    -- (normalmente ps-banking já registra do lado da conta society)
    dbg(('ps-banking transfer OK: src=%d -> holder=%s amount=%d'):format(fromSrc, holder, amount))
    if SE.MoneyTrail and SE.MoneyTrail.LogTransfer then
      local fromCid = SE.Integrations.GetCitizenId(fromSrc)
      SE.MoneyTrail.LogTransfer(fromCid or tostring(fromSrc), holder, amount, reason, {
        from_src = fromSrc,
        to_account = holder,
        reason = reason,
        source = 'ps-banking',
      })
    end
    return true
  end

  -- qb-banking / qbx-banking (fallback genérico)
  local bankingRes =
    (isStarted('qb-banking') and 'qb-banking')
    or (isStarted('qbx-banking') and 'qbx-banking')
    or nil

  if bankingRes and exports[bankingRes] then
    local ok, res = pcall(function()
      local ex = exports[bankingRes]
      if ex and ex.Transfer then
        return ex.Transfer(ex, fromSrc, toAccount, amount, reason)
      end
      return false
    end)
    if ok and res then
      if SE.MoneyTrail and SE.MoneyTrail.LogTransfer then
        local fromCid = SE.Integrations.GetCitizenId(fromSrc)
        SE.MoneyTrail.LogTransfer(fromCid or tostring(fromSrc), tostring(toAccount), amount, reason, {
          from_src = fromSrc,
          to_account = tostring(toAccount),
          reason = reason,
          source = bankingRes,
        })
      end
      return true
    end
  end

  return false, 'no_banking_integration'
end

--============================================================
-- MANDADOS / DISPATCH (ps-dispatch / ps-mdt)
--============================================================
local function vec3FromCfg(v)
  if type(v) == 'vector3' then return v end
  if type(v) == 'table' then
    local x = tonumber(v.x or v[1]) or 0.0
    local y = tonumber(v.y or v[2]) or 0.0
    local z = tonumber(v.z or v[3]) or 0.0
    return vector3(x, y, z)
  end
  return vector3(0.0, 0.0, 0.0)
end

local function FindOnlineSrcByCitizenId(citizenid)
  citizenid = trim(safeStr(citizenid, ''))
  if citizenid == '' then return nil end
  for _, s in ipairs(GetPlayers()) do
    local src = tonumber(s)
    if src then
      local cid = SE.Integrations.GetCitizenId(src)
      if cid == citizenid then
        return src
      end
    end
  end
  return nil
end

local function GetPlayerCoordsSafe(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  local ok, coords = pcall(function() return GetEntityCoords(ped) end)
  if ok and coords then
    return vector3(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0)
  end
  return nil
end

local function SendPsDispatchAlert(data)
  if not isStarted('ps-dispatch') then
    return false, 'ps_dispatch_not_started'
  end

  local ok = pcall(function()
    -- caminho mais comum em forks
    TriggerEvent('dispatch:server:notify', data)
  end)
  if ok then return true end

  if exports['ps-dispatch'] and type(exports['ps-dispatch'].CustomAlert) == 'function' then
    local ok2 = pcall(function()
      exports['ps-dispatch']:CustomAlert({
        coords       = data._coords or vector3(data.origin.x, data.origin.y, data.origin.z),
        message      = data.dispatchMessage,
        dispatchCode = data.dispatchCode,
        description  = data.description or data.firstStreet,
        radius       = 0,
        sprite       = data.blipSprite,
        color        = data.blipColour,
        scale        = data.blipScale,
        length       = data.blipLength,
        recipientList= data.job,
      })
    end)
    if ok2 then return true end
  end

  return false, 'ps_dispatch_failed'
end

local function parseDueToUnix(due)
  if not due then return 0 end
  if type(due) == 'number' then
    if due > 1000000000 then return math.floor(due) end
    return 0
  end
  if type(due) ~= 'string' then return 0 end

  local s = trim(due)
  -- YYYY-MM-DD
  do
    local y, m, d = s:match('^(%d+)%-(%d+)%-(%d+)$')
    if y then
      return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
    end
  end

  -- YYYY-MM-DD HH:MM:SS (MySQL)
  do
    local y, m, d, hh, mm, ss = s:match('^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)$')
    if y then
      return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) })
    end
  end

  return 0
end

function SE.Integrations.EmitWarrantIfNeeded(debt)
  if not debt then return false end

  local wcfg = (Config and Config.WarrantAlert) or {}
  if not wcfg.Enabled then return false end

  local days = ((Config and Config.DebtSystem) and Config.DebtSystem.WarrantAfterDaysOverdue) or 7
  local dueTs = parseDueToUnix(debt.due_at)
  if dueTs <= 0 then return false end

  local overdueDays = math.floor((os.time() - dueTs) / (24 * 60 * 60))
  if overdueDays < days then return false end

  -- ps-dispatch
  if wcfg.UsePsDispatch and isStarted('ps-dispatch') then
    local jobs = wcfg.Jobs or wcfg.RecipientList or { 'police' }
    local onlineSrc = FindOnlineSrcByCitizenId(debt.citizenid)
    local coords = onlineSrc and GetPlayerCoordsSafe(onlineSrc) or nil
    if not coords then
      coords = vec3FromCfg(wcfg.DefaultCoords or wcfg.DefaultDispatchCoords or { x = 0.0, y = 0.0, z = 0.0 })
    end

    local amount = toInt(debt.amount, 0)
    local reason = safeStr(debt.reason, '')
    local title  = wcfg.Title or 'Dívida Ativa'
    local msg    = wcfg.Message or 'Cidadão com dívida ativa'

    local payload = {
      dispatchcodename = wcfg.DispatchCodeName or 'spaceeconomy_warrant',
      dispatchCode     = wcfg.DispatchCode or '10-90',
      firstStreet      = title,
      priority         = wcfg.Priority or 2,
      origin           = { x = coords.x, y = coords.y, z = coords.z },
      dispatchMessage  = msg,
      description      = ('%s | Dívida: $%d | CID: %s | %s'):format(title, amount, safeStr(debt.citizenid, ''), reason),
      name             = safeStr(debt.citizenid, ''),
      callsign         = 'Fiscal',
      job              = jobs,
      blipSprite       = wcfg.Sprite or 457,
      blipColour       = wcfg.Color or 1,
      blipScale        = wcfg.Scale or 1.0,
      blipLength       = wcfg.Length or 3,
      _coords          = coords,
    }

    local okSend, errSend = SendPsDispatchAlert(payload)
    if okSend then
      dbg('Mandado emitido (ps-dispatch):', debt.citizenid)
      return true
    end

    dbg('Falha ao emitir mandado (ps-dispatch):', errSend or 'unknown')
  end

  -- ps-mdt
  if wcfg.UsePsMdt and isStarted('ps-mdt') then
    pcall(function()
      exports['ps-mdt']:NewReport({
        author = 'Sistema Fiscal',
        title = wcfg.Title or 'Dívida Ativa',
        description = ('%s\nValor: $%d\nCitizenID: %s\nMotivo: %s'):format(
          wcfg.Message or '',
          toInt(debt.amount, 0),
          safeStr(debt.citizenid, ''),
          safeStr(debt.reason, '')
        ),
        tags = { 'fiscal', 'divida' },
        officers = {},
      })
    end)
    dbg('Report criado (ps-mdt):', debt.citizenid)
    return true
  end

  return false
end

--============================================================
-- LAVAGEM (stub)
--============================================================
function SE.Integrations.WashMoney(src, businessId, amount, feePercent)
  if B and B.Notify then
    B.Notify(src, 'Sistema de lavagem não configurado', 'error', 'Economia')
  else
    TriggerClientEvent('space_economy:client_notify', src, 'Sistema de lavagem não configurado', 'error')
  end
  return false
end

--============================================================
-- RESIDÊNCIAS / HOUSING (ps-housing / qb-houses / qbx-houses)
--============================================================
local HousingDetected = nil
local function DetectHousing()
  if HousingDetected then return HousingDetected end

  if isStarted('ps-housing') then HousingDetected = 'ps-housing'
  elseif isStarted('qb-houses') then HousingDetected = 'qb-houses'
  elseif isStarted('qbx-houses') then HousingDetected = 'qbx-houses'
  else HousingDetected = 'none' end

  dbg('Housing detectado:', HousingDetected)
  return HousingDetected
end

function SE.Integrations.GetResidences(cidOrSrc)
  local citizenid = normalizeCitizenId(cidOrSrc)
  if not citizenid or citizenid == '' then return {} end

  local housing = DetectHousing()

  if housing == 'ps-housing' and exports['ps-housing'] then
    if exports['ps-housing'].GetProperties then
      local ok, props = pcall(function() return exports['ps-housing']:GetProperties() end)
      if ok and type(props) == 'table' then
        local out = {}
        for _, v in pairs(props) do
          local pd = (type(v) == 'table' and v.propertyData) or v
          if pd and pd.owner == citizenid then
            out[#out+1] = {
              id = safeStr(pd.property_id, ''),
              street = safeStr(pd.street, ''),
              region = safeStr(pd.region, ''),
              price = toInt(pd.price, 0),
              apartment = pd.apartment,
            }
          end
        end
        return out
      end
    end

    -- fallback DB
    local rows = dbQuery(
      'SELECT property_id, street, region, price, apartment FROM properties WHERE owner_citizenid = ?',
      { citizenid }
    ) or {}

    local out = {}
    for _, r in ipairs(rows) do
      out[#out+1] = {
        id = safeStr(r.property_id, ''),
        street = safeStr(r.street, ''),
        region = safeStr(r.region, ''),
        price = toInt(r.price, 0),
        apartment = r.apartment,
      }
    end
    return out
  end

  if housing == 'qb-houses' or housing == 'qbx-houses' then
    local rows = dbQuery([[
      SELECT
        ph.house as house,
        hl.label as label,
        hl.price as price
      FROM player_houses ph
      LEFT JOIN houselocations hl ON hl.name = ph.house
      WHERE ph.citizenid = ?
    ]], { citizenid })

    if rows and type(rows) == 'table' then
      local out = {}
      for _, r in ipairs(rows) do
        out[#out+1] = {
          id = safeStr(r.house, ''),
          street = safeStr(r.label, ''),
          region = '',
          price = toInt(r.price, 0),
          apartment = false,
        }
      end
      return out
    end

    local rows2 = dbQuery('SELECT house FROM player_houses WHERE citizenid = ?', { citizenid }) or {}
    local out2 = {}
    for _, r in ipairs(rows2) do
      out2[#out2+1] = { id = safeStr(r.house, ''), street = '', region = '', price = 0, apartment = false }
    end
    return out2
  end

  return {}
end

function SE.Integrations.GetResidenceSummary(cidOrSrc)
  local props = SE.Integrations.GetResidences(cidOrSrc)
  local aptBase = ((Config and Config.Residences) and Config.Residences.ApartmentBaseValue) or 50000

  local total = 0
  for _, p in ipairs(props) do
    local v = toInt(p.price, 0)
    if v <= 0 and p.apartment then v = aptBase end
    total = total + v
  end

  return { count = #props, totalValue = total, properties = props }
end

function SE.Integrations.GetResidenceTaxBase(cidOrSrc)
  local s = SE.Integrations.GetResidenceSummary(cidOrSrc)
  return toInt(s.totalValue, 0), toInt(s.count, 0)
end

--============================================================
-- GARAGENS / VEÍCULOS (DB fallback)
--============================================================
local function normPlate(plate)
  plate = trim(safeStr(plate, ''))
  if plate == '' then return nil end
  return plate:upper()
end

function SE.Integrations.GetVehicleOwnerByPlate(plate)
  plate = normPlate(plate)
  if not plate then return nil end

  local fw = DetectFramework()

  if fw == 'qbcore' or fw == 'qbx' then
    local row = dbSingle('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    return row and row.citizenid and tostring(row.citizenid) or nil
  end

  if fw == 'esx' then
    local row = dbSingle('SELECT owner FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    return row and row.owner and tostring(row.owner) or nil
  end

  return nil
end

function SE.Integrations.GetOwnedVehicles(cidOrSrc)
  local fw = DetectFramework()
  local out = {}

  if fw == 'qbcore' or fw == 'qbx' then
    local citizenid = normalizeCitizenId(cidOrSrc)
    if not citizenid or citizenid == '' then return {} end

    local rows = dbQuery('SELECT plate, state, garage, vehicle FROM player_vehicles WHERE citizenid = ?', { citizenid })
      or dbQuery('SELECT plate, state, garage FROM player_vehicles WHERE citizenid = ?', { citizenid })
      or {}

    for _, r in ipairs(rows) do
      out[#out+1] = {
        plate = normPlate(r.plate),
        state = toInt(r.state, 0),
        garage = safeStr(r.garage, ''),
        model = r.vehicle and tostring(r.vehicle) or nil,
        raw = r,
      }
    end
    return out
  end

  if fw == 'esx' then
    local identifier = (type(cidOrSrc) == 'string' and cidOrSrc) or nil
    if not identifier or identifier == '' then return {} end

    local rows = dbQuery('SELECT plate, stored, vehicle FROM owned_vehicles WHERE owner = ?', { identifier }) or {}
    for _, r in ipairs(rows) do
      out[#out+1] = {
        plate = normPlate(r.plate),
        state = (toInt(r.stored, 0) == 1) and 1 or 0,
        garage = '',
        model = nil,
        raw = r,
      }
    end
    return out
  end

  return {}
end

function SE.Integrations.SetVehicleStateByPlate(plate, state, garage)
  plate = normPlate(plate)
  if not plate then return false, 'invalid_plate' end

  state = toInt(state, -1)
  if state < 0 then return false, 'invalid_state' end

  garage = safeStr(garage, '')

  local fw = DetectFramework()
  if fw == 'qbcore' or fw == 'qbx' then
    local affected = 0
    if garage ~= '' then
      affected = dbExec('UPDATE player_vehicles SET state = ?, garage = ? WHERE plate = ?', { state, garage, plate })
      if (tonumber(affected) or 0) > 0 then return true end
    end
    affected = dbExec('UPDATE player_vehicles SET state = ? WHERE plate = ?', { state, plate })
    if (tonumber(affected) or 0) > 0 then return true end
    return false, 'vehicle_not_found'
  end

  if fw == 'esx' then
    local stored = (state == 1) and 1 or 0
    local affected = dbExec('UPDATE owned_vehicles SET stored = ? WHERE plate = ?', { stored, plate })
    if (tonumber(affected) or 0) > 0 then return true end
    return false, 'vehicle_not_found'
  end

  return false, 'no_garage_integration'
end

function SE.Integrations.ImpoundVehicleByPlate(plate, impoundGarage)
  return SE.Integrations.SetVehicleStateByPlate(plate, 2, impoundGarage or 'impound')
end

function SE.Integrations.ReleaseVehicleByPlate(plate, targetGarage)
  return SE.Integrations.SetVehicleStateByPlate(plate, 1, targetGarage or 'pillbox')
end

--============================================================
-- CONCESSIONÁRIA / VEHICLESHOP (rm-dealership / qb-vehicleshop / qbx-vehicleshop)
--============================================================
local DealershipDetected = nil
local function DetectDealership()
  if DealershipDetected then return DealershipDetected end

  if isStarted('rm-dealership') then DealershipDetected = 'rm-dealership'
  elseif isStarted('qb-vehicleshop') then DealershipDetected = 'qb-vehicleshop'
  elseif isStarted('qbx-vehicleshop') then DealershipDetected = 'qbx-vehicleshop'
  else DealershipDetected = 'none' end

  dbg('Concessionária detectada:', DealershipDetected)
  return DealershipDetected
end

function SE.Integrations.GetVehiclePriceByModel(model)
  model = trim(safeStr(model, ''))
  if model == '' then return 0, nil, 'invalid_model' end

  local dealership = DetectDealership()

  if dealership == 'rm-dealership' and tableExists('dealership_vehicles') then
    local row = dbSingle('SELECT price, name FROM dealership_vehicles WHERE model = ? LIMIT 1', { model })
    if row then return toInt(row.price, 0), row.name, 'rm-dealership:dealership_vehicles' end
  end

  local fw = DetectFramework()

  if fw == 'qbcore' then
    local core = GetQBCore()
    if core and core.Shared and core.Shared.Vehicles then
      local v = core.Shared.Vehicles[model]
      if v then return toInt(v.price, 0), (v.name or v.label), 'qbcore:shared_vehicles' end
    end
  end

  if fw == 'qbx' and exports.qbx_core then
    local ok, data = pcall(function()
      if exports.qbx_core.GetVehicleData then return exports.qbx_core:GetVehicleData(model) end
      if exports.qbx_core.GetVehiclesByName then return exports.qbx_core:GetVehiclesByName(model) end
      return nil
    end)
    if ok and type(data) == 'table' then
      return toInt(data.price, 0), (data.name or data.label), 'qbx:vehicle_data'
    end
  end

  local tryTables = {
    { sql = 'SELECT price, name FROM vehicles WHERE model = ? LIMIT 1', tag = 'db:vehicles' },
    { sql = 'SELECT price, name FROM vehicle_shop WHERE model = ? LIMIT 1', tag = 'db:vehicle_shop' },
    { sql = 'SELECT price, name FROM dealership_vehicles WHERE model = ? LIMIT 1', tag = 'db:dealership_vehicles' },
  }

  for _, t in ipairs(tryTables) do
    local row = dbSingle(t.sql, { model })
    if row then return toInt(row.price, 0), row.name, t.tag end
  end

  return 0, nil, 'not_found'
end

function SE.Integrations.GetVehicles(cidOrSrc)
  local citizenid = normalizeCitizenId(cidOrSrc)
  if not citizenid or citizenid == '' then return {} end

  local dealership = DetectDealership()
  local out = {}

  if dealership == 'rm-dealership' and tableExists('player_vehicles') then
    local rows = dbQuery([[
      SELECT
        pv.plate,
        pv.vehicle as model,
        pv.garage,
        pv.state,
        dv.price,
        dv.name
      FROM player_vehicles pv
      LEFT JOIN dealership_vehicles dv ON dv.model COLLATE utf8mb4_unicode_ci = pv.vehicle COLLATE utf8mb4_unicode_ci
      WHERE pv.citizenid = ?
    ]], { citizenid }) or {}

    for _, r in ipairs(rows) do
      out[#out+1] = {
        plate = safeStr(r.plate, ''),
        model = safeStr(r.model, ''),
        name = r.name,
        price = toInt(r.price, 0),
        garage = safeStr(r.garage, ''),
        state = toInt(r.state, 0),
      }
    end
    return out
  end

  local rows = dbQuery('SELECT plate, vehicle as model, garage, state FROM player_vehicles WHERE citizenid = ?', { citizenid }) or {}
  for _, r in ipairs(rows) do
    local model = safeStr(r.model, '')
    local price, name = SE.Integrations.GetVehiclePriceByModel(model)
    out[#out+1] = {
      plate = safeStr(r.plate, ''),
      model = model,
      name = name,
      price = toInt(price, 0),
      garage = safeStr(r.garage, ''),
      state = toInt(r.state, 0),
    }
  end

  return out
end

function SE.Integrations.GetVehicleSummary(cidOrSrc)
  local vehicles = SE.Integrations.GetVehicles(cidOrSrc)
  local baseMin = ((Config and Config.Vehicles) and Config.Vehicles.BaseValueIfUnknown) or 25000

  local total = 0
  for _, v in ipairs(vehicles) do
    local p = toInt(v.price, 0)
    if p <= 0 then p = baseMin end
    total = total + p
  end

  return { count = #vehicles, totalValue = total, vehicles = vehicles }
end

function SE.Integrations.GetVehicleTaxBase(cidOrSrc)
  local s = SE.Integrations.GetVehicleSummary(cidOrSrc)
  return toInt(s.totalValue, 0), toInt(s.count, 0)
end

--============================================================
-- JOBS / GANGS (online + offline)
--============================================================
local function formatName(charinfo)
  if type(charinfo) == 'string' then
    local ok, decoded = pcall(json.decode, charinfo)
    if ok and decoded then charinfo = decoded end
  end
  charinfo = charinfo or {}
  local fn = trim(safeStr(charinfo.firstname or charinfo.firstName, ''))
  local ln = trim(safeStr(charinfo.lastname or charinfo.lastName, ''))
  local full = trim((fn .. ' ' .. ln):gsub('%s+', ' '))
  if full == '' then full = 'Desconhecido' end
  return full
end

local function buildJobObject(jobName, gradeLevel)
  local core = GetQBCore()
  if not (core and core.Shared and core.Shared.Jobs) then return nil, 'no_job_defs' end

  jobName = trim(safeStr(jobName, ''))
  gradeLevel = tonumber(gradeLevel) or 0

  local def = core.Shared.Jobs[jobName]
  if not def or not def.grades then return nil, 'invalid_job' end

  local gkey = tostring(gradeLevel)
  local gdef = def.grades[gkey]
  if not gdef then return nil, 'invalid_grade' end

  local payment = tonumber(gdef.payment or def.payment or 0) or 0
  local isboss = (gdef.isboss == true)

  return {
    name = jobName,
    label = def.label or jobName,
    type = def.type or 'job',
    onduty = true,
    isboss = isboss,
    payment = payment,
    grade = {
      name = gdef.name or gkey,
      level = gradeLevel,
      payment = payment,
      isboss = isboss,
    }
  }
end

local function buildGangObject(gangName, gradeLevel)
  local core = GetQBCore()
  if not (core and core.Shared and core.Shared.Gangs) then return nil, 'no_gang_defs' end

  gangName = trim(safeStr(gangName, ''))
  gradeLevel = tonumber(gradeLevel) or 0

  local def = core.Shared.Gangs[gangName]
  if not def or not def.grades then return nil, 'invalid_gang' end

  local gkey = tostring(gradeLevel)
  local gdef = def.grades[gkey]
  if not gdef then return nil, 'invalid_grade' end

  local isboss = (gdef.isboss == true)

  return {
    name = gangName,
    label = def.label or gangName,
    isboss = isboss,
    grade = {
      level = gradeLevel,
      name = gdef.name or gkey,
      payment = tonumber(gdef.payment or 0) or 0,
    }
  }
end

local function upsertPlayerGroup(citizenid, groupType, groupName, grade)
  citizenid = trim(safeStr(citizenid, ''))
  groupType = trim(safeStr(groupType, ''))
  groupName = trim(safeStr(groupName, ''))
  grade = tonumber(grade) or 0
  if citizenid == '' or groupType == '' or groupName == '' then return false end
  if not tableExists('player_groups') then return false end

  pcall(function()
    dbExec('DELETE FROM player_groups WHERE citizenid = ? AND type = ?', { citizenid, groupType })
  end)
  dbExec('INSERT INTO player_groups (citizenid, `group`, type, grade) VALUES (?, ?, ?, ?)', { citizenid, groupName, groupType, grade })
  return true
end

local function setJobOffline(citizenid, jobName, gradeLevel)
  local job, err = buildJobObject(jobName, gradeLevel)
  if not job then return false, err end
  if not tableExists('players') then return false, 'players_table_missing' end

  local ok = pcall(function()
    dbExec('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(job), citizenid })
  end)
  pcall(function() upsertPlayerGroup(citizenid, 'job', jobName, gradeLevel) end)
  return ok
end

local function setGangOffline(citizenid, gangName, gradeLevel)
  local gang, err = buildGangObject(gangName, gradeLevel)
  if not gang then return false, err end
  if not tableExists('players') then return false, 'players_table_missing' end

  local ok = pcall(function()
    dbExec('UPDATE players SET gang = ? WHERE citizenid = ?', { json.encode(gang), citizenid })
  end)
  pcall(function() upsertPlayerGroup(citizenid, 'gang', gangName, gradeLevel) end)
  return ok
end

local function isBoss(src, kind, expectedName)
  local p = GetPlayer(src)
  if not (p and p.PlayerData) then return false end

  kind = kind or 'job'
  if kind == 'gang' then
    local g = p.PlayerData.gang
    if not (g and g.name) then return false end
    if expectedName and g.name ~= expectedName then return false end
    return g.isboss == true or (g.grade and g.grade.isboss == true)
  end

  local j = p.PlayerData.job
  if not (j and j.name) then return false end
  if expectedName and j.name ~= expectedName then return false end
  return j.isboss == true or (j.grade and j.grade.isboss == true)
end

function SE.Integrations.SetJob(targetCidOrSrc, jobName, gradeLevel)
  local citizenid = normalizeCitizenId(targetCidOrSrc)
  if not citizenid then return false, 'invalid_target' end

  jobName = trim(safeStr(jobName, ''))
  gradeLevel = tonumber(gradeLevel) or 0
  if jobName == '' then return false, 'invalid_job' end

  local online = GetPlayerByCitizenId(citizenid)
  if online and online.Functions and online.Functions.SetJob then
    local ok = pcall(function() online.Functions.SetJob(jobName, gradeLevel) end)
    if ok then
      pcall(function() upsertPlayerGroup(citizenid, 'job', jobName, gradeLevel) end)
      return true
    end
  end

  local ok2, err2 = setJobOffline(citizenid, jobName, gradeLevel)
  if ok2 then return true end
  return false, err2 or 'set_job_failed'
end

function SE.Integrations.HireEmployee(bossSrc, targetSrc, jobName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  targetSrc = tonumber(targetSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end
  if not targetSrc or targetSrc <= 0 then return false, 'invalid_target' end

  jobName = trim(safeStr(jobName, ''))
  gradeLevel = tonumber(gradeLevel) or 0
  if jobName == '' then return false, 'invalid_job' end

  if not isBoss(bossSrc, 'job', jobName) then return false, 'not_boss' end
  local targetCid = SE.Integrations.GetCitizenId(targetSrc)
  if not targetCid then return false, 'target_no_citizenid' end

  return SE.Integrations.SetJob(targetCid, jobName, gradeLevel)
end

function SE.Integrations.SetEmployeeGrade(bossSrc, targetCidOrSrc, jobName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  jobName = trim(safeStr(jobName, ''))
  gradeLevel = tonumber(gradeLevel) or 0
  if jobName == '' then return false, 'invalid_job' end

  if not isBoss(bossSrc, 'job', jobName) then return false, 'not_boss' end
  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  return SE.Integrations.SetJob(cid, jobName, gradeLevel)
end

function SE.Integrations.FireEmployee(bossSrc, targetCidOrSrc, unemployedJob, unemployedGrade)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  local bossP = GetPlayer(bossSrc)
  local jobName = bossP and bossP.PlayerData and bossP.PlayerData.job and bossP.PlayerData.job.name or nil
  if not jobName then return false, 'boss_no_job' end
  if not isBoss(bossSrc, 'job', jobName) then return false, 'not_boss' end

  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  unemployedJob = unemployedJob or 'unemployed'
  unemployedGrade = tonumber(unemployedGrade) or 0
  return SE.Integrations.SetJob(cid, unemployedJob, unemployedGrade)
end

function SE.Integrations.GetJobEmployees(jobName, viewerCidOrSrc)
  jobName = trim(safeStr(jobName, ''))
  if jobName == '' then return {} end

  local viewerCid = normalizeCitizenId(viewerCidOrSrc)
  local out = {}

  -- Qbox: player_groups
  if tableExists('player_groups') and tableExists('players') then
    local rows = dbQuery([[
      SELECT pg.citizenid, pg.grade, p.charinfo
      FROM player_groups pg
      LEFT JOIN players p ON p.citizenid = pg.citizenid
      WHERE pg.type = 'job' AND pg.`group` = ?
    ]], { jobName }) or {}

    local core = GetQBCore()
    local grades = core and core.Shared and core.Shared.Jobs and core.Shared.Jobs[jobName] and core.Shared.Jobs[jobName].grades or {}

    if #rows > 0 then
      for _, r in ipairs(rows) do
        local cid = r.citizenid
        local online = GetPlayerByCitizenId(cid)
        local gradeLevel = tonumber(r.grade) or 0
        local gdef = grades[tostring(gradeLevel)] or {}
        out[#out+1] = {
          citizenid = cid,
          name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
          grade = { level = gradeLevel, name = gdef.name or tostring(gradeLevel), isboss = gdef.isboss == true },
          isboss = (gdef.isboss == true),
          online = online ~= nil,
          source = online and online.PlayerData and online.PlayerData.source or nil,
          isSelf = (viewerCid ~= nil and cid == viewerCid)
        }
      end
      table.sort(out, function(a,b) return (a.grade.level or 0) > (b.grade.level or 0) end)
      return out
    end
  end

  -- fallback QB: players.job JSON
  if tableExists('players') then
    local rows = dbQuery("SELECT citizenid, charinfo, job FROM players WHERE job LIKE ?", { '%' .. jobName .. '%' }) or {}
    for _, r in ipairs(rows) do
      local jobObj = {}
      if r.job then
        local ok, decoded = pcall(json.decode, r.job)
        if ok and decoded then jobObj = decoded end
      end
      if jobObj and jobObj.name == jobName then
        local cid = r.citizenid
        local online = GetPlayerByCitizenId(cid)
        out[#out+1] = {
          citizenid = cid,
          name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
          grade = jobObj.grade or {},
          isboss = jobObj.isboss == true,
          online = online ~= nil,
          source = online and online.PlayerData and online.PlayerData.source or nil,
          isSelf = (viewerCid ~= nil and cid == viewerCid)
        }
      end
    end
    table.sort(out, function(a,b)
      local ga = (a.grade and (a.grade.level or a.grade.grade or 0)) or 0
      local gb = (b.grade and (b.grade.level or b.grade.grade or 0)) or 0
      return ga > gb
    end)
  end

  return out
end

function SE.Integrations.SetGang(targetCidOrSrc, gangName, gradeLevel)
  local citizenid = normalizeCitizenId(targetCidOrSrc)
  if not citizenid then return false, 'invalid_target' end

  gangName = trim(safeStr(gangName, ''))
  gradeLevel = tonumber(gradeLevel) or 0
  if gangName == '' then return false, 'invalid_gang' end

  local online = GetPlayerByCitizenId(citizenid)
  if online and online.Functions and online.Functions.SetGang then
    local ok = pcall(function() online.Functions.SetGang(gangName, gradeLevel) end)
    if ok then
      pcall(function() upsertPlayerGroup(citizenid, 'gang', gangName, gradeLevel) end)
      return true
    end
  end

  local ok2, err2 = setGangOffline(citizenid, gangName, gradeLevel)
  if ok2 then return true end
  return false, err2 or 'set_gang_failed'
end

function SE.Integrations.HireGangMember(bossSrc, targetSrc, gangName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  targetSrc = tonumber(targetSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end
  if not targetSrc or targetSrc <= 0 then return false, 'invalid_target' end

  gangName = trim(safeStr(gangName, ''))
  gradeLevel = tonumber(gradeLevel) or 0
  if gangName == '' then return false, 'invalid_gang' end

  if not isBoss(bossSrc, 'gang', gangName) then return false, 'not_boss' end
  local targetCid = SE.Integrations.GetCitizenId(targetSrc)
  if not targetCid then return false, 'target_no_citizenid' end

  return SE.Integrations.SetGang(targetCid, gangName, gradeLevel)
end

function SE.Integrations.SetGangGrade(bossSrc, targetCidOrSrc, gangName, gradeLevel)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  gangName = trim(safeStr(gangName, ''))
  gradeLevel = tonumber(gradeLevel) or 0
  if gangName == '' then return false, 'invalid_gang' end

  if not isBoss(bossSrc, 'gang', gangName) then return false, 'not_boss' end
  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  return SE.Integrations.SetGang(cid, gangName, gradeLevel)
end

function SE.Integrations.FireGangMember(bossSrc, targetCidOrSrc, defaultGang, defaultGrade)
  bossSrc = tonumber(bossSrc)
  if not bossSrc or bossSrc <= 0 then return false, 'invalid_boss' end

  local bossP = GetPlayer(bossSrc)
  local gangName = bossP and bossP.PlayerData and bossP.PlayerData.gang and bossP.PlayerData.gang.name or nil
  if not gangName then return false, 'boss_no_gang' end
  if not isBoss(bossSrc, 'gang', gangName) then return false, 'not_boss' end

  local cid = normalizeCitizenId(targetCidOrSrc)
  if not cid then return false, 'invalid_target' end

  defaultGang = defaultGang or 'none'
  defaultGrade = tonumber(defaultGrade) or 0
  return SE.Integrations.SetGang(cid, defaultGang, defaultGrade)
end

function SE.Integrations.GetGangMembers(gangName, viewerCidOrSrc)
  gangName = trim(safeStr(gangName, ''))
  if gangName == '' then return {} end

  local viewerCid = normalizeCitizenId(viewerCidOrSrc)
  local out = {}

  if tableExists('player_groups') and tableExists('players') then
    local rows = dbQuery([[
      SELECT pg.citizenid, pg.grade, p.charinfo
      FROM player_groups pg
      LEFT JOIN players p ON p.citizenid = pg.citizenid
      WHERE pg.type = 'gang' AND pg.`group` = ?
    ]], { gangName }) or {}

    local core = GetQBCore()
    local grades = core and core.Shared and core.Shared.Gangs and core.Shared.Gangs[gangName] and core.Shared.Gangs[gangName].grades or {}

    if #rows > 0 then
      for _, r in ipairs(rows) do
        local cid = r.citizenid
        local online = GetPlayerByCitizenId(cid)
        local gradeLevel = tonumber(r.grade) or 0
        local gdef = grades[tostring(gradeLevel)] or {}
        out[#out+1] = {
          citizenid = cid,
          name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
          grade = { level = gradeLevel, name = gdef.name or tostring(gradeLevel), isboss = gdef.isboss == true },
          isboss = (gdef.isboss == true),
          online = online ~= nil,
          source = online and online.PlayerData and online.PlayerData.source or nil,
          isSelf = (viewerCid ~= nil and cid == viewerCid)
        }
      end
      table.sort(out, function(a,b) return (a.grade.level or 0) > (b.grade.level or 0) end)
      return out
    end
  end

  if tableExists('players') then
    local rows2 = dbQuery("SELECT citizenid, charinfo, gang FROM players WHERE gang LIKE ?", { '%' .. gangName .. '%' }) or {}
    for _, r in ipairs(rows2) do
      local gangObj = {}
      if r.gang then
        local ok, decoded = pcall(json.decode, r.gang)
        if ok and decoded then gangObj = decoded end
      end
      if gangObj and gangObj.name == gangName then
        local cid = r.citizenid
        local online = GetPlayerByCitizenId(cid)
        out[#out+1] = {
          citizenid = cid,
          name = online and formatName(online.PlayerData.charinfo) or formatName(r.charinfo),
          grade = gangObj.grade or {},
          isboss = gangObj.isboss == true,
          online = online ~= nil,
          source = online and online.PlayerData and online.PlayerData.source or nil,
          isSelf = (viewerCid ~= nil and cid == viewerCid)
        }
      end
    end
    table.sort(out, function(a,b)
      local ga = (a.grade and (a.grade.level or a.grade.grade or 0)) or 0
      local gb = (b.grade and (b.grade.level or b.grade.grade or 0)) or 0
      return ga > gb
    end)
  end

  return out
end

--============================================================
-- INVENTÁRIO / INVENTORY (ox_inventory / qb-inventory / ps-inventory)
--============================================================
local InventoryDetected = nil
local function DetectInventory()
  if InventoryDetected then return InventoryDetected end

  if isStarted('ox_inventory') then InventoryDetected = 'ox'
  elseif isStarted('ps-inventory') then InventoryDetected = 'ps'
  elseif isStarted('qb-inventory') then InventoryDetected = 'qb'
  else InventoryDetected = 'none' end

  dbg('Inventário detectado:', InventoryDetected)
  return InventoryDetected
end

function SE.Integrations.InventoryAddItem(src, item, amount, metadata, slot)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  item = trim(safeStr(item, ''))
  if item == '' then return false, 'invalid_item' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  local inv = DetectInventory()

  if B and B.InventoryAddItem then
    local ok, res = pcall(B.InventoryAddItem, src, item, amount, metadata, slot)
    if ok and res then return true end
  end

  if inv == 'ox' and exports.ox_inventory then
    local ok, res = pcall(function() return exports.ox_inventory:AddItem(src, item, amount, metadata, slot) end)
    if ok and res then return true end
    return false, 'ox_add_failed'
  end

  if (inv == 'qb' or inv == 'ps') and DetectFramework() == 'qbcore' then
    local core = GetQBCore()
    if core and core.Functions and core.Functions.GetPlayer then
      local ply = core.Functions.GetPlayer(src)
      if ply and ply.Functions and ply.Functions.AddItem then
        local ok, res = pcall(function() return ply.Functions.AddItem(item, amount, slot, metadata) end)
        if ok and res then return true end
        return false, 'qb_add_failed'
      end
    end
  end

  return false, 'no_inventory_integration'
end

function SE.Integrations.InventoryRemoveItem(src, item, amount, metadata, slot)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  item = trim(safeStr(item, ''))
  if item == '' then return false, 'invalid_item' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  local inv = DetectInventory()

  if B and B.InventoryRemoveItem then
    local ok, res = pcall(B.InventoryRemoveItem, src, item, amount, metadata, slot)
    if ok and res then return true end
  end

  if inv == 'ox' and exports.ox_inventory then
    local ok, res = pcall(function() return exports.ox_inventory:RemoveItem(src, item, amount, metadata, slot) end)
    if ok and res then return true end
    return false, 'ox_remove_failed'
  end

  if (inv == 'qb' or inv == 'ps') and DetectFramework() == 'qbcore' then
    local core = GetQBCore()
    if core and core.Functions and core.Functions.GetPlayer then
      local ply = core.Functions.GetPlayer(src)
      if ply and ply.Functions and ply.Functions.RemoveItem then
        local ok, res = pcall(function() return ply.Functions.RemoveItem(item, amount, slot) end)
        if ok and res then return true end
        return false, 'qb_remove_failed'
      end
    end
  end

  return false, 'no_inventory_integration'
end

function SE.Integrations.InventoryGetItemCount(src, item, metadata)
  src = tonumber(src)
  if not src or src <= 0 then return 0 end

  item = trim(safeStr(item, ''))
  if item == '' then return 0 end

  local inv = DetectInventory()

  if B and B.InventoryGetItemCount then
    local ok, res = pcall(B.InventoryGetItemCount, src, item, metadata)
    if ok and type(res) == 'number' then return toInt(res, 0) end
  end

  if inv == 'ox' and exports.ox_inventory then
    local ok, res = pcall(function() return exports.ox_inventory:GetItemCount(src, item, metadata, true) end)
    if ok and type(res) == 'number' then return toInt(res, 0) end
    return 0
  end

  if (inv == 'qb' or inv == 'ps') and DetectFramework() == 'qbcore' then
    local core = GetQBCore()
    if core and core.Functions and core.Functions.GetPlayer then
      local ply = core.Functions.GetPlayer(src)
      if ply and ply.Functions and ply.Functions.GetItemByName then
        local data = ply.Functions.GetItemByName(item)
        return toInt(data and data.amount or 0, 0)
      end
    end
  end

  return 0
end

function SE.Integrations.InventoryHasItem(src, item, amount, metadata)
  amount = toInt(amount, 1)
  return SE.Integrations.InventoryGetItemCount(src, item, metadata) >= amount
end

function SE.Integrations.InventoryCanCarryItem(src, item, amount, metadata)
  src = tonumber(src)
  if not src or src <= 0 then return false end

  item = trim(safeStr(item, ''))
  if item == '' then return false end

  amount = toInt(amount, 0)
  if amount <= 0 then return false end

  local inv = DetectInventory()

  if inv == 'ox' and exports.ox_inventory and exports.ox_inventory.CanCarryItem then
    local ok, res = pcall(function() return exports.ox_inventory:CanCarryItem(src, item, amount, metadata) end)
    if ok then return res == true end
  end

  return true
end

function SE.Integrations.OpenStash(src, name, label, slots, weight, groups, coords)
  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  name = trim(safeStr(name, ''))
  if name == '' then return false, 'invalid_stash' end

  label = safeStr(label, name)
  slots = toInt(slots, 20)
  weight = toInt(weight, 100000)

  local inv = DetectInventory()

  if inv == 'ox' and exports.ox_inventory then
    pcall(function() exports.ox_inventory:RegisterStash(name, label, slots, weight, false, groups, coords) end)
    TriggerClientEvent('ox_inventory:openInventory', src, 'stash', name)
    return true
  end

  if inv == 'qb' or inv == 'ps' then
    TriggerClientEvent('inventory:client:SetCurrentStash', src, name)
    TriggerClientEvent('inventory:client:OpenInventory', src, 'stash', { id = name, slots = slots, weight = weight })
    return true
  end

  return false, 'no_inventory_integration'
end

--============================================================
-- EXPORTS
--============================================================
exports('RemoveMoney', SE.Integrations.RemoveMoney)
exports('AddMoney', SE.Integrations.AddMoney)
exports('GetBalance', SE.Integrations.GetBalance)

exports('EmitWarrant', SE.Integrations.EmitWarrantIfNeeded)
exports('BankingTransfer', SE.Integrations.BankingTransfer)

exports('GetCitizenId', SE.Integrations.GetCitizenId)

exports('GetResidences', SE.Integrations.GetResidences)
exports('GetResidenceSummary', SE.Integrations.GetResidenceSummary)
exports('GetResidenceTaxBase', SE.Integrations.GetResidenceTaxBase)

exports('GetVehicleOwnerByPlate', SE.Integrations.GetVehicleOwnerByPlate)
exports('GetOwnedVehicles', SE.Integrations.GetOwnedVehicles)
exports('SetVehicleStateByPlate', SE.Integrations.SetVehicleStateByPlate)
exports('ImpoundVehicleByPlate', SE.Integrations.ImpoundVehicleByPlate)
exports('ReleaseVehicleByPlate', SE.Integrations.ReleaseVehicleByPlate)

exports('GetVehiclePriceByModel', SE.Integrations.GetVehiclePriceByModel)
exports('GetVehicles', SE.Integrations.GetVehicles)
exports('GetVehicleSummary', SE.Integrations.GetVehicleSummary)
exports('GetVehicleTaxBase', SE.Integrations.GetVehicleTaxBase)

exports('SetJob', SE.Integrations.SetJob)
exports('HireEmployee', SE.Integrations.HireEmployee)
exports('FireEmployee', SE.Integrations.FireEmployee)
exports('SetEmployeeGrade', SE.Integrations.SetEmployeeGrade)
exports('GetJobEmployees', SE.Integrations.GetJobEmployees)

exports('SetGang', SE.Integrations.SetGang)
exports('HireGangMember', SE.Integrations.HireGangMember)
exports('FireGangMember', SE.Integrations.FireGangMember)
exports('SetGangGrade', SE.Integrations.SetGangGrade)
exports('GetGangMembers', SE.Integrations.GetGangMembers)

exports('InventoryAddItem', SE.Integrations.InventoryAddItem)
exports('InventoryRemoveItem', SE.Integrations.InventoryRemoveItem)
exports('InventoryGetItemCount', SE.Integrations.InventoryGetItemCount)
exports('InventoryHasItem', SE.Integrations.InventoryHasItem)
exports('InventoryCanCarryItem', SE.Integrations.InventoryCanCarryItem)
exports('OpenStash', SE.Integrations.OpenStash)
exports('GetIntegrationStatus', SE.Integrations.GetStatus)

RegisterCommand('se:integrationstatus', function(source)
  if source ~= 0 then return end
  local payload = GetIntegrationStatus()
  local encoded = (U and U.safeJsonEncode and U.safeJsonEncode(payload)) or (json and json.encode and json.encode(payload)) or tostring(payload)
  print('^2[space_economy]^7 Integrações detectadas:')
  print(encoded)
end, true)

-- extra: statement direto (se você quiser usar em outros módulos)
exports('PsBankingAddStatementByCitizenId', PsBankingAddStatementByCitizenId)
