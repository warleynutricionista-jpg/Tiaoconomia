--============================================================
-- space_economy - server/alerts.lua
-- Monitoramento e alertas automatizados
--============================================================
SE = SE or {}
SE.Alerts = SE.Alerts or {}

local Alerts = SE.Alerts
local U = SE.Util or {}
local B = SE.Bridge or {}

local cfg = (Config and Config.Alerts) or {}

local AlertState = {
  last = {},
}

local function toNumber(value, fallback)
  if U and U.toNumber then return U.toNumber(value, fallback) end
  local num = tonumber(value)
  if not num then return fallback end
  return num
end

local function toInt(value, fallback)
  if U and U.toInt then return U.toInt(value, fallback) end
  local num = tonumber(value)
  if not num then return fallback end
  return math.floor(num)
end

local function shouldAlert(kind, cooldownMinutes)
  local now = os.time()
  local last = AlertState.last[kind]
  local cooldown = tonumber(cooldownMinutes) or tonumber(cfg.CooldownMinutes) or 30
  if last and (now - last) < (cooldown * 60) then
    return false
  end
  AlertState.last[kind] = now
  return true
end

local function notifyStaff(message)
  if not (cfg.NotifyStaff == true) then return end
  for _, src in ipairs(GetPlayers()) do
    local s = tonumber(src)
    if s and B.CanAdmin and B.CanAdmin(s) then
      if B.Notify then
        B.Notify(s, message, 'warning', 'Economia')
      else
        TriggerClientEvent('chat:addMessage', s, { args = { 'Economia', message } })
      end
    end
  end
end

function Alerts.Notify(kind, message, payload, options)
  if not (cfg and cfg.Enabled) then return false end

  kind = tostring(kind or 'alert')
  message = tostring(message or '')

  local cooldown = options and options.cooldownMinutes
  if not shouldAlert(kind, cooldown) then
    return false
  end

  if type(SE.Log) == 'function' then
    SE.Log('alert', message, payload or {})
  end

  if SE.Discord and SE.Discord.Alert then
    SE.Discord.Alert(message, options and options.description or nil, options and options.color or nil)
  end

  notifyStaff(message)
  return true
end

local function checkInflation()
  local maxInflation = toNumber(cfg.MaxInflation, 0)
  if maxInflation <= 0 then return end

  local current = toNumber(SE.State and SE.State.inflationRate, 1.0)
  if current >= maxInflation then
    Alerts.Notify(
      'inflation_spike',
      ('Inflação acima do limite: %.2f (limite %.2f)'):format(current, maxInflation),
      { inflation = current, limit = maxInflation },
      { description = 'A inflação ultrapassou o limite configurado.' }
    )
  end
end

local function checkVault()
  local minBalance = toInt(cfg.MinVaultBalance, 0)
  if minBalance <= 0 then return end

  local vault = toInt(SE.State and SE.State.vaultBalance, 0)
  if vault <= minBalance then
    Alerts.Notify(
      'low_vault',
      ('Tesouro abaixo do limite: $%d (mínimo $%d)'):format(vault, minBalance),
      { vault = vault, limit = minBalance },
      { description = 'O saldo do tesouro está abaixo do mínimo configurado.' }
    )
  end
end

local function checkAll()
  checkInflation()
  checkVault()
end

CreateThread(function()
  local interval = tonumber(cfg.IntervalMinutes) or 5
  if interval < 1 then interval = 1 end

  while true do
    if cfg.Enabled and SE.Server and SE.Server.IsReady and SE.Server.IsReady() then
      checkAll()
    end
    Wait(interval * 60000)
  end
end)

exports('AlertNotify', Alerts.Notify)
exports('AlertCheckAll', checkAll)
