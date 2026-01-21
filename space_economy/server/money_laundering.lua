--============================================================
-- space_economy - server/money_laundering.lua
-- Sistema de lavagem oficial (empresas de fachada)
--============================================================
SE = SE or {}
SE.MoneyLaundering = SE.MoneyLaundering or {}

local ML = SE.MoneyLaundering
local U = SE.Util or {}
local B = SE.Bridge or {}

local cfg = (Config and Config.MoneyLaundering) or {}

local function toInt(v, d)
  if U and U.toInt then return U.toInt(v, d or 0) end
  v = tonumber(v)
  if not v then return d or 0 end
  return math.floor(v)
end

local function toNumber(v, d)
  if U and U.toNumber then return U.toNumber(v, d or 0) end
  v = tonumber(v)
  if not v then return d or 0 end
  return v
end

local function logLaunder(src, amount, cleaned, fee)
  if SE.Audit and SE.Audit.Log then
    SE.Audit.Log(src, 'money_launder', {
      amount = amount,
      cleaned = cleaned,
      fee = fee,
    })
  end

  if type(SE.Log) == 'function' then
    SE.Log('system', ('Lavagem oficial: $%d (limpo=%d, taxa=%d)'):format(amount, cleaned, fee), {
      amount = amount,
      cleaned = cleaned,
      fee = fee,
    })
  end
end

function ML.Process(src, amount, reason)
  if not (cfg and cfg.Enabled) then return false, 'disabled' end
  if not (SE.Integrations and SE.Integrations.AddMoney) then return false, 'no_integration' end

  src = tonumber(src)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = toInt(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  local minAmount = toInt(cfg.MinAmount, 0)
  local maxAmount = toInt(cfg.MaxAmount, 0)
  if minAmount > 0 and amount < minAmount then return false, 'below_min' end
  if maxAmount > 0 and amount > maxAmount then return false, 'above_max' end

  local feePercent = toNumber(cfg.FeePercent, 0.0)
  local fee = math.floor(amount * feePercent)
  local cleaned = amount - fee

  if cleaned <= 0 then return false, 'fee_exceeds' end

  local ok = SE.Integrations.AddMoney(src, cleaned, 'bank', reason or cfg.Reason or 'lavagem_oficial')
  if ok ~= true then return false, 'credit_failed' end

  if fee > 0 and SE.Treasury and type(SE.Treasury.Deposit) == 'function' then
    local treasuryShare = toNumber(cfg.TreasuryShare, 1.0)
    local toTreasury = math.floor(fee * treasuryShare)
    if toTreasury > 0 then
      pcall(SE.Treasury.Deposit, toTreasury, 'lavagem_oficial', { source = src })
    end
  end

  logLaunder(src, amount, cleaned, fee)
  return true
end

RegisterNetEvent('space_economy:server_launderMoney', function(amount)
  local src = source
  ML.Process(src, amount)
end)

exports('ProcessMoneyLaundering', ML.Process)

print('^2[space_economy]^7 Money laundering loaded')
