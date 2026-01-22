--============================================================
-- space_economy - server/new_panels.lua
-- Backend logic for new Player & Staff panels
--============================================================

SE = SE or {}
SE.Panels = SE.Panels or {}

local U = SE.Util or {}
local B = SE.Bridge or {}

local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^3[new_panels]^7', ...) end
end

local function notify(src, ntype, msg)
  if not src or src == 0 then return end
  TriggerClientEvent('ox_lib:notify', src, {
    type = ntype or 'info',
    description = msg
  })
end

--============================================================
-- PLAYER PANEL CALLBACKS
--============================================================

-- Get player financial data
lib.callback.register('space_economy:getFinancialData', function(source)
  local src = source
  if not src or src == 0 then return nil end

  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  if not citizenid then return nil end

  local data = {
    creditScore = 750,
    totalDebts = 0,
    debtsCount = 0,
    installmentsCount = 0,
    nextInstallment = 'Próx: --',
    debts = {},
    installments = {}
  }

  -- Get credit score
  if SE.CreditScore and SE.CreditScore.GetScore then
    data.creditScore = SE.CreditScore.GetScore(citizenid)
  end

  -- Get debts
  if SE.Debts and SE.Debts.GetPlayerDebts then
    local debts = SE.Debts.GetPlayerDebts(citizenid) or {}
    data.debts = debts
    data.debtsCount = #debts

    for _, debt in ipairs(debts) do
      data.totalDebts = data.totalDebts + (debt.amount or 0)
    end
  end

  -- Get installments
  if SE.Installments and SE.Installments.GetActive then
    local installments = SE.Installments.GetActive(citizenid) or {}
    data.installments = installments
    data.installmentsCount = #installments

    if #installments > 0 and installments[1].nextDue then
      data.nextInstallment = installments[1].nextDue
    end
  end

  return data
end)

-- Get player organizations
lib.callback.register('space_economy:getMyOrganizations', function(source)
  local src = source
  if not src or src == 0 then return {} end

  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  if not citizenid then return {} end

  if not MySQL then return {} end

  local orgs = MySQL.query.await([[
    SELECT o.*, COUNT(DISTINCT m.id) as members
    FROM space_economy_organizations o
    LEFT JOIN space_economy_org_members m ON m.org_id = o.id
    WHERE o.owner_citizenid = ? OR o.id IN (
      SELECT org_id FROM space_economy_org_members WHERE citizenid = ?
    )
    GROUP BY o.id
  ]], { citizenid, citizenid })

  return orgs or {}
end)

-- Get stock quotes
lib.callback.register('space_economy:getStockQuotes', function(source)
  if SE.StockMarket and SE.StockMarket.GetQuotes then
    return SE.StockMarket.GetQuotes()
  end
  return {}
end)

-- Get player portfolio
lib.callback.register('space_economy:getMyPortfolio', function(source)
  local src = source
  if not src or src == 0 then return { invested = 0, current = 0, stocks = {} } end

  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  if not citizenid then return { invested = 0, current = 0, stocks = {} } end

  if SE.StockMarket and SE.StockMarket.GetPortfolio then
    return SE.StockMarket.GetPortfolio(citizenid)
  end

  return { invested = 0, current = 0, stocks = {} }
end)

-- Get banking products
lib.callback.register('space_economy:getBankingProducts', function(source)
  if SE.BankingSystem and SE.BankingSystem.GetProducts then
    return SE.BankingSystem.GetProducts()
  end
  return {}
end)

-- Get player investments
lib.callback.register('space_economy:getMyInvestments', function(source)
  local src = source
  if not src or src == 0 then return {} end

  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  if not citizenid then return {} end

  if SE.BankingSystem and SE.BankingSystem.GetInvestments then
    return SE.BankingSystem.GetInvestments(citizenid)
  end

  return {}
end)

-- Get player shops
lib.callback.register('space_economy:getMyShops', function(source)
  local src = source
  if not src or src == 0 then return {} end

  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  if not citizenid then return {} end

  if SE.Shops and SE.Shops.GetPlayerShops then
    return SE.Shops.GetPlayerShops(citizenid)
  end

  return {}
end)

--============================================================
-- STAFF PANEL CALLBACKS
--============================================================

-- Open staff panel (permission check)
RegisterNetEvent('space_economy:server_openStaffPanel', function()
  local src = source
  if not src or src == 0 then return end

  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão para acessar o painel administrativo')
    return
  end

  TriggerClientEvent('space_economy:client_open_staff', src)
end)

-- Get economy overview
lib.callback.register('space_economy:getEconomyOverview', function(source)
  local data = {
    treasury = 0,
    pib = 0,
    pibPerCapita = 0,
    circulation = 0,
    velocity = 0,
    selic = 0,
    inflation = 1.0,
    unemployment = 0,
    minWage = 0,
    totalOrgs = 0,
    activeOrgs = 0
  }

  -- Treasury
  if SE.Treasury and SE.Treasury.GetBalance then
    data.treasury = SE.Treasury.GetBalance()
  end

  -- PIB
  if SE.EconomyMonitor then
    if SE.EconomyMonitor.GetPIB then
      data.pib = SE.EconomyMonitor.GetPIB()
    end
    if SE.EconomyMonitor.GetPIBPerCapita then
      data.pibPerCapita = SE.EconomyMonitor.GetPIBPerCapita()
    end
    if SE.EconomyMonitor.GetMoneyCirculation then
      data.circulation = SE.EconomyMonitor.GetMoneyCirculation()
    end
    if SE.EconomyMonitor.GetVelocity then
      data.velocity = SE.EconomyMonitor.GetVelocity()
    end
  end

  -- Monetary Policy
  if SE.MonetaryPolicy then
    if SE.MonetaryPolicy.GetSELIC then
      data.selic = SE.MonetaryPolicy.GetSELIC()
    end
    if SE.MonetaryPolicy.GetInflation then
      data.inflation = SE.MonetaryPolicy.GetInflation()
    end
  end

  -- Labor Market
  if SE.LaborMarket then
    if SE.LaborMarket.GetUnemploymentRate then
      data.unemployment = SE.LaborMarket.GetUnemploymentRate()
    end
    if SE.LaborMarket.GetMinimumWage then
      data.minWage = SE.LaborMarket.GetMinimumWage()
    end
  end

  -- Organizations
  if MySQL then
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM space_economy_organizations')
    data.totalOrgs = count or 0
    data.activeOrgs = count or 0
  end

  return data
end)

-- Get economy data
lib.callback.register('space_economy:getEconomyData', function(source)
  local data = {
    selic = 0,
    inflationTarget = 4.5,
    inflation = 0
  }

  if SE.MonetaryPolicy then
    if SE.MonetaryPolicy.GetSELIC then
      data.selic = SE.MonetaryPolicy.GetSELIC()
    end
    if SE.MonetaryPolicy.GetInflation then
      data.inflation = SE.MonetaryPolicy.GetInflation()
    end
  end

  return data
end)

-- Get all organizations
lib.callback.register('space_economy:getAllOrganizations', function(source)
  if not MySQL then return {} end

  local orgs = MySQL.query.await([[
    SELECT o.*, COUNT(DISTINCT m.id) as members
    FROM space_economy_organizations o
    LEFT JOIN space_economy_org_members m ON m.org_id = o.id
    GROUP BY o.id
    ORDER BY o.id DESC
  ]])

  return orgs or {}
end)

-- Get stock market admin data
lib.callback.register('space_economy:getStockMarketAdmin', function(source)
  local data = {
    companies = {},
    index = 1000,
    volume = 0,
    companiesCount = 0,
    transactionsToday = 0
  }

  if SE.StockMarket then
    if SE.StockMarket.GetListedCompanies then
      data.companies = SE.StockMarket.GetListedCompanies()
      data.companiesCount = #data.companies
    end
    if SE.StockMarket.GetMarketIndex then
      data.index = SE.StockMarket.GetMarketIndex()
    end
    if SE.StockMarket.GetTotalVolume then
      data.volume = SE.StockMarket.GetTotalVolume()
    end
  end

  return data
end)

-- Get active event
lib.callback.register('space_economy:getActiveEvent', function(source)
  if SE.EconomicEvents and SE.EconomicEvents.GetCurrentEvent then
    return SE.EconomicEvents.GetCurrentEvent()
  end
  return nil
end)

-- Get event history
lib.callback.register('space_economy:getEventHistory', function(source)
  if SE.EconomicEvents and SE.EconomicEvents.GetHistory then
    return SE.EconomicEvents.GetHistory()
  end
  return {}
end)

-- Get cache stats
lib.callback.register('space_economy:getCacheStats', function(source)
  if SE.Cache and SE.Cache.GetStats then
    return SE.Cache.GetStats()
  end
  return {}
end)

--============================================================
-- PLAYER PANEL ACTIONS
--============================================================

RegisterNetEvent('space_economy:server_createOrg', function(name, tag)
  local src = source
  if not src or src == 0 then return end

  if SE.Organizations and SE.Organizations.CreateOrganization then
    local ok, result = SE.Organizations.CreateOrganization(src, name, tag)
    if ok then
      notify(src, 'success', ('Organização criada! ID: %s'):format(result))
    else
      notify(src, 'error', ('Erro ao criar organização: %s'):format(result or 'erro'))
    end
  else
    notify(src, 'error', 'Sistema de organizações não disponível')
  end
end)

RegisterNetEvent('space_economy:server_buyStock', function(symbol, quantity)
  local src = source
  if not src or src == 0 then return end

  if SE.StockMarket and SE.StockMarket.BuyStock then
    local ok, msg = SE.StockMarket.BuyStock(src, symbol, quantity)
    if ok then
      notify(src, 'success', 'Ações compradas com sucesso!')
    else
      notify(src, 'error', msg or 'Erro ao comprar ações')
    end
  else
    notify(src, 'error', 'Bolsa de valores não disponível')
  end
end)

RegisterNetEvent('space_economy:server_sellStock', function(symbol, quantity)
  local src = source
  if not src or src == 0 then return end

  if SE.StockMarket and SE.StockMarket.SellStock then
    local ok, msg = SE.StockMarket.SellStock(src, symbol, quantity)
    if ok then
      notify(src, 'success', 'Ações vendidas com sucesso!')
    else
      notify(src, 'error', msg or 'Erro ao vender ações')
    end
  else
    notify(src, 'error', 'Bolsa de valores não disponível')
  end
end)

RegisterNetEvent('space_economy:server_invest', function(productId, amount)
  local src = source
  if not src or src == 0 then return end

  if SE.BankingSystem and SE.BankingSystem.Invest then
    local ok, msg = SE.BankingSystem.Invest(src, productId, amount)
    if ok then
      notify(src, 'success', 'Investimento realizado com sucesso!')
    else
      notify(src, 'error', msg or 'Erro ao investir')
    end
  else
    notify(src, 'error', 'Sistema bancário não disponível')
  end
end)

RegisterNetEvent('space_economy:server_redeemInvestment', function(investmentId)
  local src = source
  if not src or src == 0 then return end

  if SE.BankingSystem and SE.BankingSystem.RedeemInvestment then
    local ok, msg = SE.BankingSystem.RedeemInvestment(src, investmentId)
    if ok then
      notify(src, 'success', 'Investimento resgatado com sucesso!')
    else
      notify(src, 'error', msg or 'Erro ao resgatar')
    end
  else
    notify(src, 'error', 'Sistema bancário não disponível')
  end
end)

RegisterNetEvent('space_economy:server_createShop', function(name)
  local src = source
  if not src or src == 0 then return end

  if SE.Shops and SE.Shops.CreateShop then
    local ok, msg = SE.Shops.CreateShop(src, name)
    if ok then
      notify(src, 'success', 'Loja criada com sucesso!')
    else
      notify(src, 'error', msg or 'Erro ao criar loja')
    end
  else
    notify(src, 'error', 'Sistema de lojas não disponível')
  end
end)

--============================================================
-- STAFF PANEL ACTIONS
--============================================================

RegisterNetEvent('space_economy:server_treasuryDeposit', function(amount)
  local src = source
  if not src or src == 0 then return end

  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(amount, 'admin_deposit', { admin_src = src })
    notify(src, 'success', 'Depósito realizado')
  end
end)

RegisterNetEvent('space_economy:server_treasuryWithdraw', function(amount)
  local src = source
  if not src or src == 0 then return end

  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.Treasury and SE.Treasury.Withdraw then
    SE.Treasury.Withdraw(amount, 'admin_withdraw', { admin_src = src })
    notify(src, 'success', 'Saque realizado')
  end
end)

RegisterNetEvent('space_economy:server_forceWageAdjustment', function()
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.LaborMarket and SE.LaborMarket.ForceWageAdjustment then
    SE.LaborMarket.ForceWageAdjustment()
    notify(src, 'success', 'Salário mínimo ajustado')
  end
end)

RegisterNetEvent('space_economy:server_forceCOPOM', function()
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.MonetaryPolicy and SE.MonetaryPolicy.ForceCOPOMMeeting then
    SE.MonetaryPolicy.ForceCOPOMMeeting()
    notify(src, 'success', 'Reunião COPOM executada')
  end
end)

RegisterNetEvent('space_economy:server_adjustSELIC', function(action)
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.MonetaryPolicy and SE.MonetaryPolicy.AdjustSELIC then
    SE.MonetaryPolicy.AdjustSELIC(action)
    notify(src, 'success', 'SELIC ajustada')
  end
end)

RegisterNetEvent('space_economy:server_adjustIPC', function(category, value)
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.MonetaryPolicy and SE.MonetaryPolicy.AdjustIPCCategory then
    SE.MonetaryPolicy.AdjustIPCCategory(category, value)
    notify(src, 'success', ('IPC de %s ajustado'):format(category))
  end
end)

RegisterNetEvent('space_economy:server_listCompanyOnStock', function(orgId, symbol, initialPrice)
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.StockMarket and SE.StockMarket.ListCompany then
    local ok, msg = SE.StockMarket.ListCompany(orgId, symbol, initialPrice)
    if ok then
      notify(src, 'success', 'Empresa listada na bolsa')
    else
      notify(src, 'error', msg or 'Erro ao listar empresa')
    end
  end
end)

RegisterNetEvent('space_economy:server_adjustStockPrice', function(companyId, adjustment)
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.StockMarket and SE.StockMarket.AdjustPrice then
    SE.StockMarket.AdjustPrice(companyId, adjustment)
    notify(src, 'success', 'Cotação ajustada')
  end
end)

RegisterNetEvent('space_economy:server_triggerEvent', function(eventId)
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.EconomicEvents and SE.EconomicEvents.TriggerEvent then
    SE.EconomicEvents.TriggerEvent(eventId)
    notify(src, 'success', 'Evento disparado')
  end
end)

RegisterNetEvent('space_economy:server_setEventOutcome', function(outcome)
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.EconomicEvents and SE.EconomicEvents.SetOutcome then
    SE.EconomicEvents.SetOutcome(outcome)
    notify(src, 'success', 'Desfecho definido')
  end
end)

RegisterNetEvent('space_economy:server_warmupCache', function()
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.Cache and SE.Cache.Warmup then
    SE.Cache.Warmup()
    notify(src, 'success', 'Cache pré-aquecido')
  end
end)

RegisterNetEvent('space_economy:server_clearCache', function()
  local src = source
  if SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  if SE.Cache and SE.Cache.Clear then
    SE.Cache.Clear()
    notify(src, 'success', 'Cache limpo')
  end
end)

dbg('new_panels.lua loaded')
