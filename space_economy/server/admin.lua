--============================================================
-- space_economy - server/admin.lua (QBOX Hardened)
-- Admin: permissões, state payload, logs, cofre, dívidas, settings
--============================================================

SE = SE or {}
SE.Admin = SE.Admin or {}

local RES = GetCurrentResourceName()

-- tentativa de usar util/bridge/state existentes, mas com fallback seguro
local U = SE.Util or {}
local B = SE.Bridge or {}
local S = SE.State or {}

--============================================================
-- Fallbacks utilitários (não quebra se SE.Util falhar)
--============================================================
local function toNumber(v, d)
  local n = tonumber(v)
  if n == nil then return d end
  return n
end

local function toInt(v, d)
  local n = tonumber(v)
  if n == nil then return d or 0 end
  n = math.floor(n)
  return n
end

local function clamp(v, a, b)
  v = toNumber(v, a)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function nowTs()
  return os.time()
end

local function safeStr(v, fb)
  if v == nil then return fb or '' end
  local s = tostring(v)
  if s == '' then return fb or '' end
  return s
end

--============================================================
-- Guard obrigatório: GetPlayerDataSafe()
-- (QBOX -> exports.qbx_core:GetPlayer(source))
--============================================================
local function GetPlayerDataSafe(src)
  if src == nil or src == 0 then return nil end

  if U and type(U.GetPlayerDataSafe) == 'function' then
    local ok, pd = pcall(U.GetPlayerDataSafe, src)
    if ok and pd then return pd end
  end

  if GetResourceState('qbx_core') == 'started' and exports.qbx_core and exports.qbx_core.GetPlayer then
    local ok, player = pcall(exports.qbx_core.GetPlayer, exports.qbx_core, src)
    if ok and player then
      if player.PlayerData then return player.PlayerData end
      return player
    end
  end

  if GetResourceState('qb-core') == 'started' and exports['qb-core'] then
    local ok, QBCore = pcall(exports['qb-core'].GetCoreObject, exports['qb-core'])
    if ok and QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
      local ply = QBCore.Functions.GetPlayer(src)
      if ply and ply.PlayerData then return ply.PlayerData end
    end
  end

  return nil
end

--============================================================
-- Permissões (QBOX + ACE + Jobs/Grade + metadata.staff)
--============================================================
function SE.Admin.IsAllowed(src)
  if not src or src == 0 then return true end -- console

  -- 1) ACE (padrão recomendado)
  local ace = Config and Config.Permissions and Config.Permissions.Ace or 'space_economy.admin'
  if ace and IsPlayerAceAllowed(src, ace) then
    return true
  end

  local pd = GetPlayerDataSafe(src)
  if not pd then return false end

  -- 2) metadata staff do QBOX
  if Config and Config.Permissions and Config.Permissions.AllowStaffMeta then
    local md = pd.metadata or pd.Metadata or {}
    local staff = md.staff or md.isstaff or md.isStaff

    -- QBOX comum: staff = "group.admin" / "group.mod"
    if type(staff) == 'string' and staff:find('group%.') then
      return true
    end

    -- legado: boolean
    if staff == true then
      return true
    end
  end

  -- 3) Jobs/Grade
  local jobs = (Config and Config.Permissions and Config.Permissions.Jobs) or {}
  local job = pd.job
  if job and job.name and jobs[job.name] then
    local req = jobs[job.name]
    local grade = 0

    if type(job.grade) == 'table' then
      grade = toInt(job.grade.level or job.grade.grade or 0, 0)
    else
      grade = toInt(job.grade or 0, 0)
    end

    if grade >= toInt(req.minGrade or 0, 0) then
      return true
    end
  end

  return false
end

--============================================================
-- Debug: diagnóstico de permissões (console e in-game)
--============================================================
RegisterCommand('eco_checkperm', function(src)
  print('\n========================================')
  print('[space_economy] DIAGNÓSTICO DE PERMISSÕES')
  print('========================================')
  print(('Source: %d'):format(src or -1))

  if src and src > 0 then
    local ids = GetPlayerIdentifiers(src)
    print('\nIdentifiers:')
    for _, id in ipairs(ids or {}) do
      print(('  - %s'):format(id))
    end
  end

  local ace = Config and Config.Permissions and Config.Permissions.Ace or 'space_economy.admin'
  print(('\nACE esperado: %s | Resultado: %s'):format(ace, tostring(src and src > 0 and IsPlayerAceAllowed(src, ace) or 'console')))

  local pd = (src and src > 0) and GetPlayerDataSafe(src) or nil
  if pd then
    local md = pd.metadata or {}
    print('\nPlayerData:')
    print(('  CitizenID: %s'):format(pd.citizenid or 'N/A'))
    print(('  Job: %s'):format(pd.job and pd.job.name or 'N/A'))
    local grade = 0
    if pd.job then
      if type(pd.job.grade) == 'table' then grade = pd.job.grade.level or pd.job.grade.grade or 0
      else grade = pd.job.grade or 0 end
    end
    print(('  Grade: %s'):format(tostring(grade)))
    print(('  metadata.staff: %s'):format(tostring(md.staff)))
    print(('  metadata.isstaff: %s'):format(tostring(md.isstaff)))
  else
    print('\nPlayerData: NÃO ENCONTRADO')
  end

  local allowed = SE.Admin.IsAllowed(src)
  print(('\nRESULTADO FINAL: %s'):format(allowed and 'PERMITIDO ✓' or 'NEGADO ✗'))
  print('========================================\n')
end, false)

--============================================================
-- State payload (usado pelo painel)
--============================================================
local function ensureSettingsShape(t)
  if type(t) ~= 'table' then t = {} end
  t.mode = type(t.mode) == 'table' and t.mode or {}
  t.manual = type(t.manual) == 'table' and t.manual or {}
  t.ui = type(t.ui) == 'table' and t.ui or {}
  return t
end

local function normalizeMultiplier(v)
  v = toNumber(v, nil)
  if v == nil then return nil end
  if v > 10 then v = v / 100 end
  return clamp(v, 0.10, 5.00)
end

local function normalizeInflation(v)
  v = toNumber(v, nil)
  if v == nil then return nil end
  if v > 10 then v = v / 100 end
  local minR = (Config and Config.Inflation and Config.Inflation.MinRate) or 0.80
  local maxR = (Config and Config.Inflation and Config.Inflation.MaxRate) or 1.50
  return clamp(v, minR, maxR)
end

function SE.Admin.GetStatePayload()
  local vault = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or toInt(S.vaultBalance, 0)
  local settings = ensureSettingsShape(S.settings or {})

  return {
    metrics = {
      vault = vault,
      inflation = toNumber(S.inflationRate, 1.0),
      taxrate = toNumber(S.taxMultiplier, 1.0) * 100.0
    },
    settings = settings,
    taxCatalog = settings.taxCatalog or nil
  }
end

function SE.Admin.ApplySettings(payload)
  payload = payload or {}
  local settings = ensureSettingsShape(S.settings or {})

  -- merge simples
  for k, v in pairs(payload) do
    if type(v) == 'table' and type(settings[k]) == 'table' then
      for kk, vv in pairs(v) do settings[k][kk] = vv end
    else
      settings[k] = v
    end
  end

  local inflMode = tostring(settings.mode and settings.mode.inflation or 'auto'):lower()
  local taxMode  = tostring(settings.mode and settings.mode.taxrate or 'auto'):lower()

  if inflMode == 'manual' then
    local infl = normalizeInflation(settings.manual and settings.manual.inflation)
    if infl then S.inflationRate = infl end
  end

  if taxMode == 'manual' then
    local mult = normalizeMultiplier(settings.manual and settings.manual.taxrate)
    if mult then S.taxMultiplier = mult end
  end

  -- compat legado
  if payload.inflationRate ~= nil then
    local infl = normalizeInflation(payload.inflationRate)
    if infl then S.inflationRate = infl end
  end
  if payload.taxMultiplier ~= nil then
    local mult = normalizeMultiplier(payload.taxMultiplier)
    if mult then S.taxMultiplier = mult end
  end

  S.settings = settings
  S.dirty = true
  return true
end

--============================================================
-- Logs / Cofre / Dívidas (mínimo compatível com events.lua)
--============================================================
function SE.Admin.FetchLogs(limit)
  limit = toInt(limit or 80, 80)
  limit = clamp(limit, 1, 200)

  if not MySQL or not MySQL.query or not MySQL.query.await then return {} end

  local ok, rows = pcall(function()
    return MySQL.query.await([[
      SELECT timestamp, category, message
      FROM space_economy_logs
      ORDER BY id DESC
      LIMIT ?
    ]], { limit })
  end)

  return (ok and type(rows) == 'table') and rows or {}
end

function SE.Admin.ViewVault()
  if SE.Treasury and SE.Treasury.GetBalance then
    return SE.Treasury.GetBalance()
  end
  return toInt(S.vaultBalance, 0)
end

function SE.Admin.AddVault(amount, reason, meta)
  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'Valor inválido.' end
  if not (SE.Treasury and SE.Treasury.Deposit) then return false, 'Tesouro indisponível.' end
  local bal = SE.Treasury.Deposit(amount, reason or 'admin_deposito', meta)
  return true, bal
end

function SE.Admin.WithdrawVault(amount, reason, meta)
  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'Valor inválido.' end
  if not (SE.Treasury and SE.Treasury.Withdraw) then return false, 'Tesouro indisponível.' end
  local bal = SE.Treasury.Withdraw(amount, reason or 'admin_saque', meta)
  return true, bal
end

function SE.Admin.ListDebts(limit)
  if SE.Debts and SE.Debts.ListActive then
    return SE.Debts.ListActive(limit or 150)
  end
  return {}
end

function SE.Admin.GetDebtById(id)
  if SE.Debts and SE.Debts.GetById then
    return SE.Debts.GetById(id)
  end
  return nil
end

function SE.Admin.GetDebtsByCitizen(citizenid, limit)
  if SE.Debts and SE.Debts.GetActiveByCitizen then
    return SE.Debts.GetActiveByCitizen(citizenid, limit or 50)
  end
  return {}
end

function SE.Admin.IssueTaxDebt(src, payload)
  if not (SE.Debts and SE.Debts.Upsert) then
    return false, 'Módulo de dívidas indisponível.'
  end

  payload = payload or {}
  local mode = tostring(payload.targetMode or 'citizenid')
  local citizenid = safeStr(payload.citizenid, '')
  local amount = toInt(payload.amount, 0)
  local reason = safeStr(payload.reason or payload.type, 'Imposto')

  if amount <= 0 then return false, 'Valor inválido.' end

  local dueTs = nowTs()
  local meta = {
    issued_by = tonumber(src) or 0,
    issued_by_name = (src and B and B.GetCharName and B.GetCharName(src)) or 'Console',
    tax_type = safeStr(payload.type, 'OUTRO'),
    base = toInt(payload.base, 0),
    created_ts = dueTs,
    resource = RES
  }

  if mode == 'all_online' then
    local count = 0
    for _, s in ipairs(GetPlayers()) do
      local ss = tonumber(s)
      local pd = GetPlayerDataSafe(ss)
      local cid = pd and pd.citizenid or nil
      if cid then
        SE.Debts.Upsert(cid, amount, reason, dueTs, meta)
        count += 1
      end
    end
    return true, ('Lançado para %d jogadores online.'):format(count)
  end

  if citizenid == '' then return false, 'Informe o CitizenID.' end
  SE.Debts.Upsert(citizenid, amount, reason, dueTs, meta)
  return true, ('Dívida lançada para %s'):format(citizenid)
end
