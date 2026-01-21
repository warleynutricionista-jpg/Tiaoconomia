--============================================================
-- space_economy - server/stock_market.lua
-- Sistema de Bolsa de Valores Completo
-- Ações, Ibovespa, Circuit Breaker, Portfólio
--============================================================
SE = SE or {}
SE.StockMarket = SE.StockMarket or {}

local U = SE.Util
local SM = SE.StockMarket

-- Inicializar seed do random para evitar sequências previsíveis
math.randomseed(os.time() + GetGameTimer())

--============================================================
-- Empresas Listadas
--============================================================
local Companies = {
  {
    ticker = 'BENN',
    name = "Benny's Mechanics",
    sector = 'Serviços',
    sharesOutstanding = 120000,
    basePrice = 150,
    currentPrice = 150.0,  -- Garantir que seja número
    openPrice = 150.0,
    dayChange = 0.0,
    volume = 0,
    marketCap = 18000000,  -- Inicializar market cap
    beta = 1.2,  -- Volatilidade (>1 = mais volátil)
  },
  {
    ticker = 'AMMU',
    name = 'Ammunation Corp',
    sector = 'Comércio',
    sharesOutstanding = 180000,
    basePrice = 320,
    currentPrice = 320,
    openPrice = 320,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 0.9,
  },
  {
    ticker = 'PDLS',
    name = 'Paradise Stores',
    sector = 'Comércio',
    sharesOutstanding = 220000,
    basePrice = 85,
    currentPrice = 85,
    openPrice = 85,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 1.1,
  },
  {
    ticker = 'CLUC',
    name = 'Cluckin Bell',
    sector = 'Alimentação',
    sharesOutstanding = 260000,
    basePrice = 45,
    currentPrice = 45,
    openPrice = 45,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 0.7,
  },
  {
    ticker = 'MAZE',
    name = 'Maze Bank',
    sector = 'Financeiro',
    sharesOutstanding = 90000,
    basePrice = 580,
    currentPrice = 580,
    openPrice = 580,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 1.5,
  },
  {
    ticker = 'PHMC',
    name = 'Pillbox Medical',
    sector = 'Saúde',
    sharesOutstanding = 140000,
    basePrice = 210,
    currentPrice = 210,
    openPrice = 210,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 0.6,
  },
  {
    ticker = 'LSPD',
    name = 'Property Developers',
    sector = 'Imóveis',
    sharesOutstanding = 160000,
    basePrice = 125,
    currentPrice = 125,
    openPrice = 125,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 1.3,
  },
  {
    ticker = 'VPCR',
    name = 'Vapid Rentals',
    sector = 'Transporte',
    sharesOutstanding = 190000,
    basePrice = 95,
    currentPrice = 95,
    openPrice = 95,
    dayChange = 0.0,
    volume = 0,
    marketCap = 0,
    beta = 1.0,
  },
}

--============================================================
-- Estado do Mercado
--============================================================
local MarketState = {
  ibovespa = 10000,
  ibovespaOpen = 10000,
  ibovespaChange = 0.0,
  isOpen = true,
  circuitBreaker = false,
  circuitBreakerReason = '',
}

--============================================================
-- Configuração
--============================================================
local Config = {
  UpdateInterval = 30000,        -- Atualizar preços a cada 30 segundos
  CircuitBreakerThreshold = 0.10, -- -10% fecha mercado
  TradingFee = 0.005,            -- 0.5% de corretagem
  CapitalGainsTax = 0.15,        -- 15% IR sobre ganho de capital
  MaxShares = 10000,             -- Máximo de ações por empresa
}

--============================================================
-- Obter Empresa por Ticker
--============================================================
local function getCompany(ticker)
  for _, company in ipairs(Companies) do
    if company.ticker == ticker then
      return company
    end
  end
  return nil
end

--============================================================
-- Calcular Ibovespa
--============================================================
function SM.CalculateIbovespa()
  local totalWeight = 0
  local weightedSum = 0

  for _, company in ipairs(Companies) do
    -- Garantir que currentPrice nunca seja nil
    local price = company.currentPrice or company.basePrice or 100
    company.currentPrice = price

    local marketCap = price * (company.sharesOutstanding or 1)
    local weight = marketCap > 0 and marketCap or price
    local change = (price - company.openPrice) / company.openPrice

    weightedSum = weightedSum + (change * weight)
    totalWeight = totalWeight + weight
  end

  local avgChange = totalWeight > 0 and (weightedSum / totalWeight) or 0
  MarketState.ibovespa = MarketState.ibovespaOpen * (1 + avgChange)
  MarketState.ibovespaChange = avgChange

  -- Circuit Breaker?
  if avgChange <= -Config.CircuitBreakerThreshold and not MarketState.circuitBreaker then
    MarketState.circuitBreaker = true
    MarketState.isOpen = false
    MarketState.circuitBreakerReason = 'Queda de ' .. string.format('%.1f%%', avgChange * 100)

    U.dbg('[Stock Market] CIRCUIT BREAKER! Market closed due to ' .. MarketState.circuitBreakerReason)

    -- Notificar todos
    for _, src in ipairs(GetPlayers()) do
      local srcNum = tonumber(src)
      if srcNum then
        TriggerClientEvent('ox_lib:notify', srcNum, {
          type = 'error',
          title = '⚠️ CIRCUIT BREAKER',
          description = 'Bolsa fechada: ' .. MarketState.circuitBreakerReason,
          duration = 15000,
        })
      end
    end
  end

  return MarketState.ibovespa
end

--============================================================
-- Atualizar Preços (Simulação de Mercado)
--============================================================
function SM.UpdatePrices()
  if not MarketState.isOpen then return end

  -- Fatores externos
  local pibGrowth = 0
  local inflation = 0
  local selic = 0

  if SE.EconomyMonitor then
    local report = SE.EconomyMonitor.GetReport()
    pibGrowth = report.pib.total > 0 and 0.05 or -0.02  -- Simplificado
  end

  if SE.MonetaryPolicy then
    inflation = SE.MonetaryPolicy.GetMonthlyInflation() or 0
    selic = SE.MonetaryPolicy.GetSELIC() or 0
  end

  -- Atualizar cada empresa
  for _, company in ipairs(Companies) do
    -- Variação aleatória baseada em volatilidade (beta)
    local randomChange = (math.random() - 0.5) * 0.04 * company.beta  -- ±2% * beta

    -- Influência de fatores externos
    local pibEffect = pibGrowth * 0.3
    local inflationEffect = -inflation * 0.2
    local selicEffect = -selic * 0.5  -- SELIC alta = ações caem

    -- Variação total
    local totalChange = randomChange + pibEffect + inflationEffect + selicEffect

    -- Aplicar
    company.currentPrice = company.currentPrice * (1 + totalChange)

    -- Garantir preço mínimo
    if company.currentPrice < company.basePrice * 0.1 then
      company.currentPrice = company.basePrice * 0.1
    end

    -- Calcular variação do dia
    company.dayChange = (company.currentPrice - company.openPrice) / company.openPrice
    company.marketCap = company.currentPrice * (company.sharesOutstanding or 1)
  end

  -- Recalcular Ibovespa
  SM.CalculateIbovespa()

  U.dbg(('[Stock Market] Prices updated | Ibovespa: %.2f (%+.2f%%)'):format(
    MarketState.ibovespa,
    MarketState.ibovespaChange * 100
  ))
end

--============================================================
-- Comprar Ações
--============================================================
function SM.BuyStock(src, ticker, quantity)
  src = tonumber(src)
  quantity = U.toInt(quantity, 0)

  if not src or quantity <= 0 then return false end

  -- Mercado aberto?
  if not MarketState.isOpen then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Mercado fechado'
    })
    return false
  end

  -- Empresa existe?
  local company = getCompany(ticker)
  if not company then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Empresa não encontrada'
    })
    return false
  end

  -- Calcular custo
  local pricePerShare = company.currentPrice
  local subtotal = pricePerShare * quantity
  local fee = subtotal * Config.TradingFee
  local total = subtotal + fee

  -- Player tem dinheiro?
  local citizenid = SE.Integrations.GetCitizenId(src)
  if not citizenid then return false end

  local hasMoney = SE.Integrations.GetMoney(src, 'bank') >= total

  if not hasMoney then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Saldo insuficiente'
    })
    return false
  end

  -- Remover dinheiro
  SE.Integrations.RemoveMoney(src, 'bank', total, 'Compra de ações ' .. ticker)

  -- Adicionar ações ao portfólio
  if not MySQL then return false end

  MySQL.insert.await([[
    INSERT INTO space_economy_stocks (citizenid, ticker, quantity, purchase_price, purchased_at)
    VALUES (?, ?, ?, ?, NOW())
    ON DUPLICATE KEY UPDATE
      quantity = quantity + VALUES(quantity)
  ]], {
    citizenid,
    ticker,
    quantity,
    pricePerShare
  })

  -- Atualizar volume
  company.volume = company.volume + quantity

  -- Registrar transação
  if SE.EconomyMonitor then
    SE.EconomyMonitor.RegisterTransaction('compra_acao', total, {
      ticker = ticker,
      quantity = quantity,
      price = pricePerShare,
    })
  end

  TriggerClientEvent('ox_lib:notify', src, {
    type = 'success',
    title = 'Ações Compradas',
    description = string.format('%d x %s por $%s (+ $%s taxa)',
      quantity,
      ticker,
      U.formatNumber(subtotal),
      U.formatNumber(fee)
    ),
    duration = 8000,
  })

  U.dbg(('[Stock Market] %s bought %d x %s @ $%.2f'):format(
    citizenid,
    quantity,
    ticker,
    pricePerShare
  ))

  return true
end

--============================================================
-- Vender Ações
--============================================================
function SM.SellStock(src, ticker, quantity)
  src = tonumber(src)
  quantity = U.toInt(quantity, 0)

  if not src or quantity <= 0 then return false end

  -- Mercado aberto?
  if not MarketState.isOpen then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Mercado fechado'
    })
    return false
  end

  -- Empresa existe?
  local company = getCompany(ticker)
  if not company then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Empresa não encontrada'
    })
    return false
  end

  local citizenid = SE.Integrations.GetCitizenId(src)
  if not citizenid or not MySQL then return false end

  -- Player tem essas ações?
  local stock = MySQL.single.await([[
    SELECT quantity, purchase_price FROM space_economy_stocks
    WHERE citizenid = ? AND ticker = ? LIMIT 1
  ]], { citizenid, ticker })

  if not stock or stock.quantity < quantity then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Você não possui ações suficientes'
    })
    return false
  end

  -- Calcular venda
  local currentPrice = company.currentPrice
  local purchasePrice = stock.purchase_price
  local subtotal = currentPrice * quantity
  local fee = subtotal * Config.TradingFee

  -- Calcular ganho de capital e IR
  local capitalGain = (currentPrice - purchasePrice) * quantity
  local tax = capitalGain > 0 and (capitalGain * Config.CapitalGainsTax) or 0

  local netAmount = subtotal - fee - tax

  -- Atualizar quantidade
  MySQL.execute.await([[
    UPDATE space_economy_stocks
    SET quantity = quantity - ?
    WHERE citizenid = ? AND ticker = ?
  ]], { quantity, citizenid, ticker })

  -- Remover registro se quantidade = 0
  MySQL.execute.await([[
    DELETE FROM space_economy_stocks
    WHERE citizenid = ? AND ticker = ? AND quantity <= 0
  ]], { citizenid, ticker })

  -- Dar dinheiro ao player
  SE.Integrations.AddMoney(src, netAmount, 'bank', 'venda_acoes_' .. ticker)

  -- Atualizar volume
  company.volume = company.volume + quantity

  -- Registrar transação
  if SE.EconomyMonitor then
    SE.EconomyMonitor.RegisterTransaction('compra_acao', netAmount, {
      ticker = ticker,
      quantity = quantity,
      price = currentPrice,
      type = 'sell',
    })
  end

  TriggerClientEvent('ox_lib:notify', src, {
    type = 'success',
    title = 'Ações Vendidas',
    description = string.format('%d x %s por $%s\nLucro: $%s (IR: $%s)',
      quantity,
      ticker,
      U.formatNumber(netAmount),
      U.formatNumber(capitalGain),
      U.formatNumber(tax)
    ),
    duration = 10000,
  })

  U.dbg(('[Stock Market] %s sold %d x %s @ $%.2f (gain: $%.2f)'):format(
    citizenid,
    quantity,
    ticker,
    currentPrice,
    capitalGain
  ))

  return true
end

--============================================================
-- Obter Portfólio do Player
--============================================================
function SM.GetPortfolio(citizenid)
  if not MySQL or not citizenid then return {} end

  local stocks = MySQL.query.await([[
    SELECT ticker, quantity, purchase_price, purchased_at
    FROM space_economy_stocks
    WHERE citizenid = ?
  ]], { citizenid })

  if not stocks then return {} end

  local portfolio = {}
  local totalInvested = 0
  local totalCurrent = 0

  for _, stock in ipairs(stocks) do
    local company = getCompany(stock.ticker)
    if company then
      local invested = stock.purchase_price * stock.quantity
      local current = company.currentPrice * stock.quantity
      local gain = current - invested
      local gainPercent = invested > 0 and (gain / invested) or 0

      totalInvested = totalInvested + invested
      totalCurrent = totalCurrent + current

      table.insert(portfolio, {
        ticker = stock.ticker,
        name = company.name,
        quantity = stock.quantity,
        purchasePrice = stock.purchase_price,
        currentPrice = company.currentPrice,
        invested = invested,
        current = current,
        gain = gain,
        gainPercent = gainPercent,
        purchasedAt = stock.purchased_at,
      })
    end
  end

  return {
    stocks = portfolio,
    totalInvested = totalInvested,
    totalCurrent = totalCurrent,
    totalGain = totalCurrent - totalInvested,
    totalGainPercent = totalInvested > 0 and ((totalCurrent - totalInvested) / totalInvested) or 0,
  }
end

--============================================================
-- Obter Cotações
--============================================================
function SM.GetQuotes()
  local quotes = {}

  for _, company in ipairs(Companies) do
    table.insert(quotes, {
      ticker = company.ticker,
      name = company.name,
      sector = company.sector,
      price = company.currentPrice,
      dayChange = company.dayChange,
      volume = company.volume,
      beta = company.beta,
    })
  end

  return {
    companies = quotes,
    ibovespa = MarketState.ibovespa,
    ibovespaChange = MarketState.ibovespaChange,
    isOpen = MarketState.isOpen,
    circuitBreaker = MarketState.circuitBreaker,
  }
end

--============================================================
-- Comando: Ver Cotações
--============================================================
RegisterCommand('bolsa', function(source, args)
  local src = tonumber(source)

  local quotes = SM.GetQuotes()

  print('\n========================================')
  print('BOLSA DE VALORES - COTAÇÕES')
  print('========================================')
  print(string.format('Ibovespa: %.2f (%+.2f%%)',
    quotes.ibovespa,
    quotes.ibovespaChange * 100
  ))
  print(string.format('Status: %s', quotes.isOpen and 'ABERTO' or 'FECHADO'))
  if quotes.circuitBreaker then
    print('⚠️ CIRCUIT BREAKER ATIVO')
  end
  print('')

  for _, company in ipairs(quotes.companies) do
    local arrow = company.dayChange > 0 and '↑' or (company.dayChange < 0 and '↓' or '→')
    print(string.format('%-4s | %-25s | $%-7.2f | %s %.2f%%',
      company.ticker,
      company.name,
      company.price,
      arrow,
      company.dayChange * 100
    ))
  end

  print('========================================\n')

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Cotações geradas no console'
    })
  end
end, false)

--============================================================
-- Thread de Atualização de Preços
--============================================================
CreateThread(function()
  -- Aguardar inicialização
  Wait(20000)

  while true do
    Wait(Config.UpdateInterval)

    SM.UpdatePrices()
  end
end)

--============================================================
-- Thread de Abertura/Fechamento do Mercado
--============================================================
CreateThread(function()
  Wait(20000)

  while true do
    Wait(3600000)  -- A cada 1 hora

    -- Reabrir mercado se circuit breaker estiver ativo há mais de 1h
    if MarketState.circuitBreaker then
      MarketState.circuitBreaker = false
      MarketState.isOpen = true

      -- Reset preços de abertura
      for _, company in ipairs(Companies) do
        company.openPrice = company.currentPrice
      end

      MarketState.ibovespaOpen = MarketState.ibovespa

      U.dbg('[Stock Market] Market reopened after circuit breaker')
    end
  end
end)

--============================================================
-- Garantir Tabelas
--============================================================
CreateThread(function()
  if not MySQL then return end

  Wait(2000)

  pcall(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_stocks (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(50) NOT NULL,
        ticker VARCHAR(8) NOT NULL,
        quantity INT NOT NULL DEFAULT 0,
        purchase_price DOUBLE NOT NULL,
        purchased_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_holding (citizenid, ticker),
        INDEX idx_citizenid (citizenid),
        INDEX idx_ticker (ticker)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
  end)

  U.dbg('[Stock Market] Tables ensured')
end)

--============================================================
-- Exports
--============================================================
exports('BuyStock', SM.BuyStock)
exports('SellStock', SM.SellStock)
exports('GetPortfolio', SM.GetPortfolio)
exports('GetStockQuotes', SM.GetQuotes)

print('^2[space_economy]^7 Stock Market loaded - ' .. #Companies .. ' companies listed | Ibovespa: ' .. MarketState.ibovespa)
