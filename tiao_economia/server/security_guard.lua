--============================================================
-- space_economy - server/security_guard.lua
-- Economy Guard: validação de ganhos, quarentena e disjuntor
--============================================================
SE = SE or {}
SE.SecurityGuard = SE.SecurityGuard or {}

local SG = SE.SecurityGuard
local U = SE.Util or {}
local B = SE.Bridge or {}

local cfg = (Config and Config.Security) or {}

local GuardState = {
  gainWindow = {},
  quarantine = {},
  emergency = false,
  circulationHistory = {},
}

local function toInt(v, d)
  if U and U.toInt then return U.toInt(v, d or 0) end
  v = tonumber(v)
  if not v then return d or 0 end
  return math.floor(v)
end

local function safeStr(v, fallback)
  if U and U.safeStr then return U.safeStr(v, fallback) end
  if v == nil then return fallback or '' end
  return tostring(v)
end

local function inList(val, list)
  if type(list) ~= 'table' then return false end
  for _, v in ipairs(list) do
    if tostring(v):lower() == tostring(val):lower() then
      return true
    end
  end
  return false
end

local function alertStaff(msg)
  if not msg then return end
  for _, src in ipairs(GetPlayers()) do
    local s = tonumber(src)
    if s and (B.CanAdmin and B.CanAdmin(s)) then
      if B.Notify then
        B.Notify(s, msg, 'error', 'Economy Guard')
      else
        TriggerClientEvent('chat:addMessage', s, { args = { 'GUARD', msg } })
      end
    end
  end
end

local function logSecurity(src, flagType, amount, reason, action, meta)
  local payload = {
    type = flagType,
    amount = amount,
    reason = reason,
    action = action,
  }
  if type(meta) == 'table' then
    for k, v in pairs(meta) do
      payload[k] = v
    end
  end

  if SE.Audit and SE.Audit.Log then
    SE.Audit.Log(src, 'security_flag', payload)
  end

  if type(SE.Log) == 'function' then
    SE.Log('security', ('Security flag: %s'):format(flagType), payload)
  end
end

local function addQuarantine(citizenid, amount, reason, meta)
  if not citizenid then return end
  local entry = GuardState.quarantine[citizenid]
  if not entry then
    entry = { total = 0, items = {} }
    GuardState.quarantine[citizenid] = entry
  end

  entry.total = entry.total + amount
  entry.items[#entry.items + 1] = {
    amount = amount,
    reason = reason,
    at = os.time(),
    meta = meta,
  }
end

function SG.IsEmergency()
  return GuardState.emergency == true
end

function SG.SetEmergency(state, reason)
  state = state == true
  if GuardState.emergency == state then return end

  GuardState.emergency = state

  if SE.State then
    SE.State.settings = type(SE.State.settings) == 'table' and SE.State.settings or {}
    SE.State.settings.security = type(SE.State.settings.security) == 'table' and SE.State.settings.security or {}
    SE.State.settings.security.emergency = state
    SE.State.settings.security.emergencyReason = reason
    if SE.Server and SE.Server.MarkDirty then
      SE.Server.MarkDirty()
    end
  end

  if state then
    alertStaff(('Modo de emergência econômico ATIVADO: %s'):format(reason or 'circuit_breaker'))
  else
    alertStaff('Modo de emergência econômico DESATIVADO')
  end

  if type(SE.Log) == 'function' then
    SE.Log('security', ('Emergency=%s'):format(tostring(state)), { reason = reason })
  end
end

function SG.ValidateCredit(src, amount, account, reason)
  if not (cfg and cfg.Enabled) then return true end

  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  account = safeStr(account, 'bank')
  reason = safeStr(reason, '')

  if SG.IsEmergency() and cfg.Emergency and cfg.Emergency.Enabled and account == 'bank' then
    logSecurity(src, 'emergency_lock', amount, reason, 'blocked', { account = account })
    return false, 'emergency_lock'
  end

  local reasonLower = reason:lower()

  if reason == '' then
    logSecurity(src, 'missing_reason', amount, reason, 'blocked')
    return false, 'missing_reason'
  end

  if cfg.EnforceReasonCatalog and type(cfg.AllowedReasons) == 'table' and #cfg.AllowedReasons > 0 then
    if not inList(reasonLower, cfg.AllowedReasons) then
      logSecurity(src, 'unknown_reason', amount, reason, 'blocked')
      return false, 'unknown_reason'
    end
  end

  if inList(reasonLower, cfg.GenericReasons) and amount >= toInt(cfg.MaxGenericAmount, 0) then
    local cid = B.GetCitizenId and B.GetCitizenId(src) or nil
    addQuarantine(cid, amount, reason, { flag = 'generic_reason' })
    logSecurity(src, 'generic_reason', amount, reason, 'quarantined', { citizenid = cid })
    alertStaff(('Transação bloqueada (motivo genérico): $%d para %s'):format(amount, tostring(cid or src)))
    return false, 'generic_reason'
  end

  if amount >= toInt(cfg.SuspiciousThreshold, 0) then
    local cid = B.GetCitizenId and B.GetCitizenId(src) or nil
    addQuarantine(cid, amount, reason, { flag = 'high_value' })
    logSecurity(src, 'high_value', amount, reason, 'quarantined', { citizenid = cid })
    alertStaff(('Transação suspeita bloqueada: $%d para %s'):format(amount, tostring(cid or src)))
    return false, 'high_value'
  end

  local now = os.time()
  local entry = GuardState.gainWindow[src]
  if not entry or (now - entry.start) >= 60 then
    entry = { start = now, total = 0 }
    GuardState.gainWindow[src] = entry
  end

  entry.total = entry.total + amount
  if entry.total > toInt(cfg.MaxGainPerMinute, 0) then
    local cid = B.GetCitizenId and B.GetCitizenId(src) or nil
    addQuarantine(cid, amount, reason, { flag = 'rate_limit', window_total = entry.total })
    logSecurity(src, 'rate_limit', amount, reason, 'quarantined', { citizenid = cid, window_total = entry.total })
    alertStaff(('Rate limit atingido: $%d/min para %s'):format(entry.total, tostring(cid or src)))
    return false, 'rate_limit'
  end

  return true
end

function SG.ValidateDebit(src, amount, account, reason)
  if not (cfg and cfg.Enabled) then return true end

  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  account = safeStr(account, 'bank')
  reason = safeStr(reason, '')

  if SG.IsEmergency() and cfg.Emergency and cfg.Emergency.Enabled then
    local highValue = toInt(cfg.Emergency.HighValueBlock, 0)
    if account == 'bank' or (highValue > 0 and amount >= highValue) then
      logSecurity(src, 'emergency_lock', amount, reason, 'blocked', { account = account })
      return false, 'emergency_lock'
    end
  end

  return true
end

function SG.GetQuarantine(citizenid)
  return GuardState.quarantine[citizenid] or { total = 0, items = {} }
end

function SG.ReleaseQuarantine(citizenid, amount, reason)
  if not citizenid or citizenid == '' then return false, 'invalid_citizenid' end

  local entry = GuardState.quarantine[citizenid]
  if not entry or entry.total <= 0 then return false, 'empty' end

  amount = toInt(amount or entry.total, entry.total)
  if amount <= 0 then return false, 'invalid_amount' end

  if amount > entry.total then amount = entry.total end

  if not (SE.Integrations and SE.Integrations.AddMoney) then return false, 'no_integration' end

  local src = B.GetSourceByCitizenId and B.GetSourceByCitizenId(citizenid) or nil
  if not src then return false, 'player_offline' end

  local ok = SE.Integrations.AddMoney(src, amount, 'bank', reason or 'liberacao_quarentena')
  if ok == true then
    entry.total = entry.total - amount
    logSecurity(src, 'quarantine_release', amount, reason or 'liberacao_quarentena', 'released', { citizenid = citizenid })
    return true
  end

  return false, 'release_failed'
end

--============================================================
-- Circuit Breaker: monitora circulação
--============================================================
CreateThread(function()
  Wait(15000)

  if SE.State and SE.State.settings and SE.State.settings.security then
    GuardState.emergency = SE.State.settings.security.emergency == true
  end

  while true do
    local interval = (cfg.Emergency and cfg.Emergency.CheckIntervalSeconds or 300)
    Wait(interval * 1000)

    if not (cfg.Emergency and cfg.Emergency.Enabled) then
      goto continue
    end

    if not (SE.EconomyMonitor and SE.EconomyMonitor.GetReport) then
      goto continue
    end

    local report = SE.EconomyMonitor.GetReport()
    local total = toInt(report.circulation and report.circulation.total or 0, 0)
    local now = os.time()

    GuardState.circulationHistory[#GuardState.circulationHistory + 1] = {
      time = now,
      total = total,
    }

    local window = toInt(cfg.Emergency.WindowSeconds, 3600)
    while GuardState.circulationHistory[1]
      and (now - GuardState.circulationHistory[1].time) > window do
      table.remove(GuardState.circulationHistory, 1)
    end

    local oldest = GuardState.circulationHistory[1]
    if oldest and oldest.total > 0 then
      local spike = toInt(cfg.Emergency.CirculationSpikePercent * 10000, 0) / 10000
      if total >= (oldest.total * (1 + spike)) then
        if not SG.IsEmergency() then
          SG.SetEmergency(true, 'circulation_spike')
        end
      end
    end

    ::continue::
  end
end)

RegisterCommand('eco_guard_release', function(source)
  local src = tonumber(source)
  if src and src > 0 then
    if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then return end
  end

  SG.SetEmergency(false, 'manual_release')
end)

print('^2[space_economy]^7 Economy Guard loaded')
