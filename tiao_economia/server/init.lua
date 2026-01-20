--============================================================
-- space_economy - server/init.lua
-- Bootstrap do servidor (namespace + defaults + guards)
--============================================================
SE = SE or {}

-- Namespaces
SE.Server = SE.Server or {}
SE.State  = SE.State  or {}
SE.Admin  = SE.Admin  or {}
SE.Debts  = SE.Debts  or {}
SE.Tax    = SE.Tax    or {}
SE.Treasury = SE.Treasury or {}
SE.Integrations = SE.Integrations or {}
SE.CharCache = SE.CharCache or {}
SE.Metrics = SE.Metrics or {}

-- Meta
SE.Resource = GetCurrentResourceName()
SE.Version = (GetResourceMetadata(SE.Resource, 'version', 0) or '0.0.0')

-- Guards de runtime
local U = SE.Util

-- Defaults mínimos (não duplicar lógica do state.lua; só garante existência)
SE.State.dirty = SE.State.dirty == true
SE.State.vaultBalance = U and U.toInt and U.toInt(SE.State.vaultBalance, 0) or (SE.State.vaultBalance or 0)
SE.State.inflationRate = U and U.toNumber and U.toNumber(SE.State.inflationRate, 1.0) or (SE.State.inflationRate or 1.0)
SE.State.taxMultiplier = U and U.toNumber and U.toNumber(SE.State.taxMultiplier, 1.0) or (SE.State.taxMultiplier or 1.0)
SE.State.settings = type(SE.State.settings) == 'table' and SE.State.settings or {}

-- Ready flag (útil pra integrações que esperam load state)
SE.Server._ready = false
function SE.Server.IsReady()
  return SE.Server._ready == true
end

function SE.Server.SetReady(v)
  SE.Server._ready = (v == true)
end

-- Helper: log de boot
function SE.Server.BootLog(...)
  if U and U.dbg then
    U.dbg(...)
  else
    print('^3[space_economy]^7', ...)
  end
end

-- Marcar ready assim que o state.lua carregar (state.lua chama LoadState no thread)
CreateThread(function()
  -- aguarda MySQL e o carregamento inicial do state.lua
  local waited = 0
  while not MySQL do Wait(200) waited += 200 if waited > 15000 then break end end

  -- aguarda state load (state.lua define valores e limpa dirty)
  Wait(500)

  SE.Server.SetReady(true)
  SE.Server.BootLog(('Server init pronto | %s v%s'):format(SE.Resource, SE.Version))
end)

--============================================================
-- Exports para desenvolvedores
--============================================================

-- Retorna o multiplicador atual de inflação (ex: 1.05)
exports('GetInflationMultiplier', function()
  if SE.Server and SE.Server.GetInflationRate then
    return SE.Server.GetInflationRate()
  end
  return SE.State and SE.State.inflationRate or 1.0
end)

-- Retorna a taxa configurada para um tipo específico (income, sales, transfer, service)
exports('GetTaxRate', function(taxType)
  taxType = tostring(taxType or ''):lower()
  local external = (Config and Config.ExternalIntegrations) or {}

  if taxType == 'income' then
    return SE.State and SE.State.taxMultiplier or (Config and Config.TaxMultiplierDefault) or 1.0
  end
  if taxType == 'sales' then
    return (external.Inventory and external.Inventory.TaxRate) or 0
  end
  if taxType == 'transfer' then
    return (external.Banking and external.Banking.TransferTaxRate) or 0
  end
  if taxType == 'service' then
    return (external.Management and external.Management.ServiceTaxRate) or 0
  end

  return 0
end)

local function resolveTaxRate(taxType)
  taxType = tostring(taxType or ''):lower()
  local external = (Config and Config.ExternalIntegrations) or {}

  if taxType == 'income' then
    return SE.State and SE.State.taxMultiplier or (Config and Config.TaxMultiplierDefault) or 1.0
  end
  if taxType == 'sales' then
    return (external.Inventory and external.Inventory.TaxRate) or 0
  end
  if taxType == 'transfer' then
    return (external.Banking and external.Banking.TransferTaxRate) or 0
  end
  if taxType == 'service' then
    return (external.Management and external.Management.ServiceTaxRate) or 0
  end

  return 0
end

-- Registra uma atividade econômica manualmente no monitor (PIB)
exports('RegisterEconomicActivity', function(category, amount, metadata)
  if SE.EconomyMonitor and SE.EconomyMonitor.RegisterTransaction then
    SE.EconomyMonitor.RegisterTransaction(category, amount, metadata)
    return true
  end
  return false
end)

-- Calcula imposto, debita o player e deposita no tesouro automaticamente
exports('ApplyTax', function(source, amount, taxType)
  local src = tonumber(source)
  if not src or src <= 0 then return false, 'invalid_source' end

  amount = U and U.toInt and U.toInt(amount, 0) or tonumber(amount) or 0
  if amount <= 0 then return false, 'invalid_amount' end

  taxType = tostring(taxType or 'income')
  local taxAmount = 0

  if taxType:lower() == 'income' and SE.Tax and SE.Tax.Calculate then
    taxAmount = SE.Tax.Calculate(amount)
  else
    local rate = resolveTaxRate(taxType)
    taxAmount = math.floor(amount * (rate / 100))
  end

  if taxAmount <= 0 then return false, 'no_tax' end

  if SE.Integrations and SE.Integrations.RemoveMoney then
    local ok, err = SE.Integrations.RemoveMoney(src, taxAmount, 'bank', ('tax_%s'):format(taxType))
    if not ok then return false, err or 'debit_failed' end
  end

  if SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(taxAmount, ('tax_%s'):format(taxType), { source = src, base = amount })
  end

  return true, taxAmount
end)
