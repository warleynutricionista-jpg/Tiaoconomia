--============================================================
-- space_economy - server/stock_market.lua
-- Sistema de Bolsa de Valores Ultra-Realista
-- FASE 3.3 - Trading, Ações e Índice Ibovespa
--============================================================
SE = SE or {}
SE.StockMarket = SE.StockMarket or {}

local U = SE.Util
local SM = SE.StockMarket

--============================================================
-- Catálogo de Empresas e Ações
--============================================================
SM.Companies = {
  {
    ticker = 'BENN',
    nome = "Benny's Mechanics",
    setor = 'servicos',
    preco_inicial = 150,
    acoes_totais = 10000,
    acoes_disponiveis = 7000,
    volatilidade = 0.15,  -- 15% de variação
    dividendos_trimestre = 0.03,  -- 3% de dividendos
    pe_ratio = 12,  -- Preço/Lucro
    descricao = 'Rede de mecânicas premium da cidade',
  },
  {
    ticker = 'AMMU',
    nome = 'Ammunation Corp',
    setor = 'comercio',
    preco_inicial = 320,
    acoes_totais = 5000,
    acoes_disponiveis = 3500,
    volatilidade = 0.20,
    dividendos_trimestre = 0.05,
    pe_ratio = 15,
    descricao = 'Maior rede de armamentos',
  },
  {
    ticker = 'PDLS',
    nome = 'Paradise LS Stores',
    setor = 'comercio',
    preco_inicial = 85,
    acoes_totais = 15000,
    acoes_disponiveis = 10000,
    volatilidade = 0.10,
    dividendos_trimestre = 0.02,
    pe_ratio = 10,
    descricao = 'Rede de lojas de conveniência',
  },
  {
    ticker = 'CLUC',
    nome = 'Cluckin Bell Foods',
    setor = 'alimentacao',
    preco_inicial = 45,
    acoes_totais = 20000,
    acoes_disponiveis = 15000,
    volatilidade = 0.12,
    dividendos_trimestre = 0.025,
    pe_ratio = 8,
    descricao = 'Fast food mais popular',
  },
  {
    ticker = 'MAZE',
    nome = 'Maze Bank',
    setor = 'financeiro',
    preco_inicial = 580,
    acoes_totais = 8000,
    acoes_disponiveis = 5000,
    volatilidade = 0.18,
    dividendos_trimestre = 0.04,
    pe_ratio = 18,
    descricao = 'Principal banco da cidade',
  },
  {
    ticker = 'PHMC',
    nome = 'Pillbox Medical Center',
    setor = 'saude',
    preco_inicial = 210,
    acoes_totais = 6000,
    acoes_disponiveis = 4000,
    volatilidade = 0.08,
    dividendos_trimestre = 0.035,
    pe_ratio = 14,
    descricao = 'Sistema de saúde da cidade',
  },
  {
    ticker = 'LSPD',
    nome = 'LS Property Developers',
    setor = 'imoveis',
    preco_inicial = 125,
    acoes_totais = 12000,
    acoes_disponiveis = 8000,
    volatilidade = 0.25,
    dividendos_trimestre = 0.02,
    pe_ratio = 20,
    descricao = 'Construtora e incorporadora',
  },
  {
    ticker = 'VPCR',
    nome = 'Vapid Car Rentals',
    setor = 'transporte',
    preco_inicial = 95,
    acoes_totais = 10000,
    acoes_disponiveis = 7500,
    volatilidade = 0.16,
    dividendos_trimestre = 0.03,
    pe_ratio = 11,
    descricao = 'Aluguel de veículos',
  },
}

--============================================================
-- Estado do Mercado
--============================================================
SM.State = {
  empresas = {},
  indice_ibovespa = 10000,
  ibovespa_anterior = 10000,
  ibovespa_historico = {},

  volume_negociado_dia = 0,
  transacoes_dia = 0,

  status_mercado = 'aberto',  -- aberto, fechado, pregao
  ultimo_update = 0,

  -- Circuit breaker (parar mercado em quedas bruscas)
  circuit_breaker_ativo = false,
  circuit_breaker_percentual = -0.10,  -- -10% dispara
}

--============================================================
-- Carteiras dos Players
--============================================================
SM.Portfolios = {}  -- [citizenid] = { [ticker] = quantidade }

--============================================================
-- Configuração
--============================================================
local Config = {
  UpdateIntervalMs = 120000,  -- Atualizar preços a cada 2 minutos
  CircuitBreakerThreshold = -0.10,  -- -10%
  CircuitBreakerDuration = 1800000,  -- 30 minutos fechado

  TaxaCorretagem = 0.005,  -- 0.5% de corretagem
  ImpostoGanhoCapital = 0.15,  -- 15% sobre lucro

  DividendosIntervalMs = 7200000,  -- Pagar a cada 2h (em prod seria trimestral)

  EnablePreMarket = true,
  EnableAfterMarket = true,
}

--============================================================
-- Schema
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Empresas e ações
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_stocks (
      ticker VARCHAR(10) PRIMARY KEY,
      nome VARCHAR(100) NOT NULL,
      setor VARCHAR(50) NOT NULL,
      preco_atual DECIMAL(15,2) NOT NULL,
      preco_abertura DECIMAL(15,2) NOT NULL,
      preco_minimo DECIMAL(15,2) NOT NULL,
      preco_maximo DECIMAL(15,2) NOT NULL,
      variacao_dia DECIMAL(10,4) NOT NULL DEFAULT 0,
      volume_dia BIGINT NOT NULL DEFAULT 0,
      market_cap BIGINT NOT NULL DEFAULT 0,
      pe_ratio DECIMAL(10,2) NOT NULL DEFAULT 0,
      dividendos_trimestre DECIMAL(10,4) NOT NULL DEFAULT 0,
      metadata LONGTEXT NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_setor (setor)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Portfólio dos players
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_portfolios (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      ticker VARCHAR(10) NOT NULL,
      quantidade INT NOT NULL DEFAULT 0,
      preco_medio_compra DECIMAL(15,2) NOT NULL DEFAULT 0,
      valor_investido BIGINT NOT NULL DEFAULT 0,
      metadata LONGTEXT NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY unique_portfolio (citizenid, ticker),
      INDEX idx_citizen (citizenid),
      INDEX idx_ticker (ticker)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Histórico de transações
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_stock_transactions (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      ticker VARCHAR(10) NOT NULL,
      tipo VARCHAR(10) NOT NULL,
      quantidade INT NOT NULL,
      preco DECIMAL(15,2) NOT NULL,
      total BIGINT NOT NULL,
      taxa_corretagem BIGINT NOT NULL DEFAULT 0,
      lucro_prejuizo BIGINT NULL,
      imposto BIGINT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_citizen_ticker (citizenid, ticker),
      INDEX idx_created (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Histórico de preços
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_stock_history (
      id INT AUTO_INCREMENT PRIMARY KEY,
      ticker VARCHAR(10) NOT NULL,
      timestamp BIGINT NOT NULL,
      preco DECIMAL(15,2) NOT NULL,
      volume BIGINT NOT NULL DEFAULT 0,
      INDEX idx_ticker_timestamp (ticker, timestamp)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Índice Ibovespa
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_ibovespa (
      id INT AUTO_INCREMENT PRIMARY KEY,
      timestamp BIGINT NOT NULL,
      valor DECIMAL(15,2) NOT NULL,
      variacao DECIMAL(10,4) NOT NULL DEFAULT 0,
      INDEX idx_timestamp (timestamp)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  U.dbg('[StockMarket] Schema garantido')
end

CreateThread(function()
  while not MySQL do Wait(250) end
  ensureSchema()
end)

--============================================================
-- Inicializar Empresas
--============================================================
function SM.InitializeCompanies()
  for _, company in ipairs(SM.Companies) do
    local ticker = company.ticker

    -- Verificar se já existe
    local exists = MySQL.scalar.await('SELECT ticker FROM space_economy_stocks WHERE ticker = ?', { ticker })

    if not exists then
      -- Criar empresa
      MySQL.insert.await([[
        INSERT INTO space_economy_stocks (
          ticker, nome, setor, preco_atual, preco_abertura,
          preco_minimo, preco_maximo, market_cap, pe_ratio,
          dividendos_trimestre, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ]], {
        ticker,
        company.nome,
        company.setor,
        company.preco_inicial,
        company.preco_inicial,
        company.preco_inicial,
        company.preco_inicial,
        company.preco_inicial * company.acoes_totais,
        company.pe_ratio,
        company.dividendos_trimestre,
        U.safeJsonEncode({
          acoes_totais = company.acoes_totais,
          acoes_disponiveis = company.acoes_disponiveis,
          volatilidade = company.volatilidade,
          descricao = company.descricao,
        })
      })

      U.dbg(('[StockMarket] Empresa criada: %s (%s) - $%d'):format(
        company.nome,
        ticker,
        company.preco_inicial
      ))
    end

    -- Carregar para memória
    SM.LoadCompany(ticker)
  end
end

--============================================================
-- Carregar Empresa
--============================================================
function SM.LoadCompany(ticker)
  local row = MySQL.single.await('SELECT * FROM space_economy_stocks WHERE ticker = ?', { ticker })

  if row then
    local metadata = U.safeJsonDecode(row.metadata) or {}

    SM.State.empresas[ticker] = {
      ticker = row.ticker,
      nome = row.nome,
      setor = row.setor,
      preco_atual = U.toNumber(row.preco_atual, 0),
      preco_abertura = U.toNumber(row.preco_abertura, 0),
      preco_minimo = U.toNumber(row.preco_minimo, 0),
      preco_maximo = U.toNumber(row.preco_maximo, 0),
      variacao_dia = U.toNumber(row.variacao_dia, 0),
      volume_dia = U.toInt(row.volume_dia, 0),
      market_cap = U.toInt(row.market_cap, 0),
      pe_ratio = U.toNumber(row.pe_ratio, 0),
      dividendos_trimestre = U.toNumber(row.dividendos_trimestre, 0),
      acoes_totais = U.toInt(metadata.acoes_totais, 10000),
      acoes_disponiveis = U.toInt(metadata.acoes_disponiveis, 7000),
      volatilidade = U.toNumber(metadata.volatilidade, 0.15),
      descricao = U.safeStr(metadata.descricao, ''),
    }
  end
end

--============================================================
-- Atualizar Preços das Ações
--============================================================
function SM.UpdatePrices()
  if SM.State.status_mercado ~= 'aberto' then return end

  for ticker, empresa in pairs(SM.State.empresas) do
    local preco_anterior = empresa.preco_atual

    -- Variação aleatória baseada em volatilidade
    local variacao_base = (math.random() - 0.5) * 2 * empresa.volatilidade

    -- Influências econômicas
    local influencia_pib = 0
    local influencia_inflacao = 0
    local influencia_setor = 0

    if SE.EconomyMonitor then
      local pib = SE.EconomyMonitor.State.pib_total or 0
      influencia_pib = (pib > 0) and 0.01 or -0.01
    end

    if SE.MonetaryPolicy then
      local inflacao = SE.MonetaryPolicy.State.inflacao_anual or 0
      influencia_inflacao = -inflacao * 0.5  -- Inflação alta = ações caem
    end

    -- Eventos econômicos
    if SE.EconomicEvents and SE.EconomicEvents.State.evento_ativo then
      local evento = SE.EconomicEvents.State.evento_ativo
      if evento.tipo == 'crise' then
        variacao_base = variacao_base - 0.05
      elseif evento.tipo == 'boom' then
        variacao_base = variacao_base + 0.05
      end
    end

    -- Variação total
    local variacao_total = variacao_base + influencia_pib + influencia_inflacao + influencia_setor
    variacao_total = U.clamp(variacao_total, -0.15, 0.15)  -- Máximo ±15%

    -- Novo preço
    local novo_preco = preco_anterior * (1 + variacao_total)
    novo_preco = math.max(1, math.floor(novo_preco + 0.5))  -- Mínimo $1

    empresa.preco_atual = novo_preco

    -- Atualizar min/max do dia
    if novo_preco < empresa.preco_minimo then
      empresa.preco_minimo = novo_preco
    end
    if novo_preco > empresa.preco_maximo then
      empresa.preco_maximo = novo_preco
    end

    -- Variação do dia
    if empresa.preco_abertura > 0 then
      empresa.variacao_dia = (novo_preco / empresa.preco_abertura) - 1
    end

    -- Salvar no banco
    MySQL.update.await([[
      UPDATE space_economy_stocks
      SET preco_atual = ?, preco_minimo = ?, preco_maximo = ?,
          variacao_dia = ?, market_cap = ?
      WHERE ticker = ?
    ]], {
      novo_preco,
      empresa.preco_minimo,
      empresa.preco_maximo,
      empresa.variacao_dia,
      novo_preco * empresa.acoes_totais,
      ticker
    })

    -- Salvar histórico
    MySQL.insert.await([[
      INSERT INTO space_economy_stock_history (ticker, timestamp, preco, volume)
      VALUES (?, ?, ?, ?)
    ]], { ticker, os.time(), novo_preco, empresa.volume_dia })
  end

  -- Atualizar Ibovespa
  SM.UpdateIbovespa()

  SM.State.ultimo_update = os.time()
end

--============================================================
-- Atualizar Índice Ibovespa
--============================================================
function SM.UpdateIbovespa()
  -- Média ponderada das ações
  local soma_ponderada = 0
  local soma_pesos = 0

  for ticker, empresa in pairs(SM.State.empresas) do
    local peso = empresa.market_cap
    soma_ponderada = soma_ponderada + (empresa.preco_atual * peso)
    soma_pesos = soma_pesos + peso
  end

  local novo_ibovespa = soma_pesos > 0 and (soma_ponderada / soma_pesos) or 10000
  novo_ibovespa = math.floor(novo_ibovespa + 0.5)

  SM.State.ibovespa_anterior = SM.State.indice_ibovespa
  SM.State.indice_ibovespa = novo_ibovespa

  local variacao = SM.State.ibovespa_anterior > 0 and
    ((novo_ibovespa / SM.State.ibovespa_anterior) - 1) or 0

  -- Circuit breaker
  if variacao <= Config.CircuitBreakerThreshold and not SM.State.circuit_breaker_ativo then
    SM.TriggerCircuitBreaker()
  end

  -- Salvar histórico
  table.insert(SM.State.ibovespa_historico, {
    timestamp = os.time(),
    valor = novo_ibovespa,
    variacao = variacao,
  })

  if #SM.State.ibovespa_historico > 288 then
    table.remove(SM.State.ibovespa_historico, 1)
  end

  MySQL.insert.await([[
    INSERT INTO space_economy_ibovespa (timestamp, valor, variacao)
    VALUES (?, ?, ?)
  ]], { os.time(), novo_ibovespa, variacao })
end

--============================================================
-- Circuit Breaker (Parar mercado em queda brusca)
--============================================================
function SM.TriggerCircuitBreaker()
  SM.State.circuit_breaker_ativo = true
  SM.State.status_mercado = 'fechado'

  U.dbg('[StockMarket] ⚠️ CIRCUIT BREAKER ATIVADO! Mercado fechado por 30 minutos.')

  TriggerClientEvent('chat:addMessage', -1, {
    args = { '[BOLSA]', '⚠️ CIRCUIT BREAKER! Mercado fechado devido queda brusca.' }
  })

  -- Reabrir após duração
  SetTimeout(Config.CircuitBreakerDuration, function()
    SM.State.circuit_breaker_ativo = false
    SM.State.status_mercado = 'aberto'

    TriggerClientEvent('chat:addMessage', -1, {
      args = { '[BOLSA]', '✅ Mercado reaberto após circuit breaker.' }
    })
  end)
end

--============================================================
-- Comprar Ações
--============================================================
function SM.BuyStock(src, ticker, quantidade)
  ticker = U.safeStr(ticker, ''):upper()
  quantidade = U.toInt(quantidade, 0)

  if quantidade <= 0 then
    return false, 'Quantidade inválida'
  end

  local empresa = SM.State.empresas[ticker]
  if not empresa then
    return false, 'Empresa não encontrada'
  end

  if SM.State.status_mercado ~= 'aberto' then
    return false, 'Mercado fechado'
  end

  if quantidade > empresa.acoes_disponiveis then
    return false, 'Ações insuficientes disponíveis'
  end

  local custo_total = empresa.preco_atual * quantidade
  local corretagem = math.floor(custo_total * Config.TaxaCorretagem)
  local total_pagar = custo_total + corretagem

  -- Verificar dinheiro
  local citizenid = SE.Bridge.GetCitizenId(src)
  if not citizenid then return false, 'Cidadão não encontrado' end

  local removed = false
  if SE.Integrations and SE.Integrations.RemoveMoney then
    removed = SE.Integrations.RemoveMoney(src, total_pagar, 'bank')
  end

  if not removed then
    return false, 'Saldo insuficiente'
  end

  -- Atualizar portfólio
  local portfolio = MySQL.single.await([[
    SELECT * FROM space_economy_portfolios
    WHERE citizenid = ? AND ticker = ?
  ]], { citizenid, ticker })

  if portfolio then
    -- Já possui ações, atualizar
    local qtd_atual = U.toInt(portfolio.quantidade, 0)
    local investido_atual = U.toInt(portfolio.valor_investido, 0)

    local nova_qtd = qtd_atual + quantidade
    local novo_investido = investido_atual + custo_total
    local novo_preco_medio = novo_investido / nova_qtd

    MySQL.update.await([[
      UPDATE space_economy_portfolios
      SET quantidade = ?, valor_investido = ?, preco_medio_compra = ?
      WHERE id = ?
    ]], { nova_qtd, novo_investido, novo_preco_medio, portfolio.id })
  else
    -- Nova posição
    MySQL.insert.await([[
      INSERT INTO space_economy_portfolios
        (citizenid, ticker, quantidade, preco_medio_compra, valor_investido)
      VALUES (?, ?, ?, ?, ?)
    ]], { citizenid, ticker, quantidade, empresa.preco_atual, custo_total })
  end

  -- Registrar transação
  MySQL.insert.await([[
    INSERT INTO space_economy_stock_transactions
      (citizenid, ticker, tipo, quantidade, preco, total, taxa_corretagem)
    VALUES (?, ?, 'COMPRA', ?, ?, ?, ?)
  ]], { citizenid, ticker, quantidade, empresa.preco_atual, custo_total, corretagem })

  -- Atualizar empresa
  empresa.acoes_disponiveis = empresa.acoes_disponiveis - quantidade
  empresa.volume_dia = empresa.volume_dia + quantidade

  MySQL.update.await([[
    UPDATE space_economy_stocks
    SET volume_dia = volume_dia + ?,
        metadata = JSON_SET(metadata, '$.acoes_disponiveis', ?)
    WHERE ticker = ?
  ]], { quantidade, empresa.acoes_disponiveis, ticker })

  -- Registrar transação econômica
  if SE.EconomyMonitor then
    SE.EconomyMonitor.RegistrarTransacao('compra_acoes', total_pagar, {
      ticker = ticker,
      quantidade = quantidade,
      citizenid = citizenid,
    })
  end

  U.dbg(('[StockMarket] %s comprou %d ações de %s por $%d'):format(
    citizenid, quantidade, ticker, total_pagar
  ))

  return true, {
    quantidade = quantidade,
    preco_unitario = empresa.preco_atual,
    total = custo_total,
    corretagem = corretagem,
    total_pago = total_pagar,
  }
end

--============================================================
-- Vender Ações
--============================================================
function SM.SellStock(src, ticker, quantidade)
  ticker = U.safeStr(ticker, ''):upper()
  quantidade = U.toInt(quantidade, 0)

  if quantidade <= 0 then
    return false, 'Quantidade inválida'
  end

  local empresa = SM.State.empresas[ticker]
  if not empresa then
    return false, 'Empresa não encontrada'
  end

  if SM.State.status_mercado ~= 'aberto' then
    return false, 'Mercado fechado'
  end

  local citizenid = SE.Bridge.GetCitizenId(src)
  if not citizenid then return false, 'Cidadão não encontrado' end

  -- Verificar portfólio
  local portfolio = MySQL.single.await([[
    SELECT * FROM space_economy_portfolios
    WHERE citizenid = ? AND ticker = ?
  ]], { citizenid, ticker })

  if not portfolio or U.toInt(portfolio.quantidade, 0) < quantidade then
    return false, 'Ações insuficientes'
  end

  local receita_bruta = empresa.preco_atual * quantidade
  local corretagem = math.floor(receita_bruta * Config.TaxaCorretagem)

  -- Calcular lucro/prejuízo e imposto
  local preco_medio_compra = U.toNumber(portfolio.preco_medio_compra, 0)
  local custo_compra = preco_medio_compra * quantidade
  local lucro = receita_bruta - custo_compra
  local imposto = 0

  if lucro > 0 then
    imposto = math.floor(lucro * Config.ImpostoGanhoCapital)
  end

  local receita_liquida = receita_bruta - corretagem - imposto

  -- Adicionar dinheiro
  if SE.Integrations and SE.Integrations.AddMoney then
    SE.Integrations.AddMoney(src, receita_liquida, 'bank')
  end

  -- Imposto vai para tesouro
  if imposto > 0 and SE.Treasury then
    SE.Treasury.Deposit(imposto, 'imposto_ganho_capital', {
      citizenid = citizenid,
      ticker = ticker,
    })
  end

  -- Atualizar portfólio
  local qtd_atual = U.toInt(portfolio.quantidade, 0)
  local nova_qtd = qtd_atual - quantidade

  if nova_qtd <= 0 then
    -- Vender tudo, remover
    MySQL.query.await('DELETE FROM space_economy_portfolios WHERE id = ?', { portfolio.id })
  else
    local investido_atual = U.toInt(portfolio.valor_investido, 0)
    local novo_investido = investido_atual - custo_compra

    MySQL.update.await([[
      UPDATE space_economy_portfolios
      SET quantidade = ?, valor_investido = ?
      WHERE id = ?
    ]], { nova_qtd, novo_investido, portfolio.id })
  end

  -- Registrar transação
  MySQL.insert.await([[
    INSERT INTO space_economy_stock_transactions
      (citizenid, ticker, tipo, quantidade, preco, total, taxa_corretagem, lucro_prejuizo, imposto)
    VALUES (?, ?, 'VENDA', ?, ?, ?, ?, ?, ?)
  ]], { citizenid, ticker, quantidade, empresa.preco_atual, receita_bruta, corretagem, lucro, imposto })

  -- Atualizar empresa
  empresa.acoes_disponiveis = empresa.acoes_disponiveis + quantidade
  empresa.volume_dia = empresa.volume_dia + quantidade

  MySQL.update.await([[
    UPDATE space_economy_stocks
    SET volume_dia = volume_dia + ?,
        metadata = JSON_SET(metadata, '$.acoes_disponiveis', ?)
    WHERE ticker = ?
  ]], { quantidade, empresa.acoes_disponiveis, ticker })

  U.dbg(('[StockMarket] %s vendeu %d ações de %s por $%d (lucro: $%d)'):format(
    citizenid, quantidade, ticker, receita_liquida, lucro
  ))

  return true, {
    quantidade = quantidade,
    preco_unitario = empresa.preco_atual,
    receita_bruta = receita_bruta,
    corretagem = corretagem,
    imposto = imposto,
    receita_liquida = receita_liquida,
    lucro_prejuizo = lucro,
  }
end

--============================================================
-- Obter Cotações
--============================================================
function SM.GetQuotes(ticker)
  if ticker then
    return SM.State.empresas[ticker:upper()]
  end
  return SM.State.empresas
end

--============================================================
-- Obter Portfólio do Player
--============================================================
function SM.GetPortfolio(citizenid)
  local rows = MySQL.query.await([[
    SELECT p.*, s.nome, s.preco_atual, s.variacao_dia
    FROM space_economy_portfolios p
    JOIN space_economy_stocks s ON s.ticker = p.ticker
    WHERE p.citizenid = ?
  ]], { citizenid })

  local portfolio = {}
  local valor_total_investido = 0
  local valor_total_atual = 0

  for _, row in ipairs(rows or {}) do
    local quantidade = U.toInt(row.quantidade, 0)
    local preco_atual = U.toNumber(row.preco_atual, 0)
    local preco_medio = U.toNumber(row.preco_medio_compra, 0)
    local investido = U.toInt(row.valor_investido, 0)

    local valor_atual = preco_atual * quantidade
    local lucro_prejuizo = valor_atual - investido
    local rentabilidade = investido > 0 and ((valor_atual / investido) - 1) or 0

    table.insert(portfolio, {
      ticker = row.ticker,
      nome = row.nome,
      quantidade = quantidade,
      preco_medio_compra = preco_medio,
      preco_atual = preco_atual,
      valor_investido = investido,
      valor_atual = valor_atual,
      lucro_prejuizo = lucro_prejuizo,
      rentabilidade = rentabilidade,
      variacao_dia = U.toNumber(row.variacao_dia, 0),
    })

    valor_total_investido = valor_total_investido + investido
    valor_total_atual = valor_total_atual + valor_atual
  end

  return {
    posicoes = portfolio,
    total_investido = valor_total_investido,
    total_atual = valor_total_atual,
    lucro_prejuizo_total = valor_total_atual - valor_total_investido,
    rentabilidade_total = valor_total_investido > 0 and
      ((valor_total_atual / valor_total_investido) - 1) or 0,
  }
end

--============================================================
-- Thread de Atualização de Preços
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()
  SM.InitializeCompanies()

  Wait(5000)

  while true do
    Wait(Config.UpdateIntervalMs)
    SM.UpdatePrices()
  end
end)

--============================================================
-- Comando - Ver Cotações
--============================================================
RegisterCommand('bolsa', function(source, args)
  local quotes = SM.GetQuotes()

  print('\n========================================')
  print('BOLSA DE VALORES - COTAÇÕES')
  print('========================================')
  print(string.format('Ibovespa: %.2f (%+.2f%%)',
    SM.State.indice_ibovespa,
    ((SM.State.indice_ibovespa / SM.State.ibovespa_anterior) - 1) * 100
  ))
  print(string.format('Status: %s', SM.State.status_mercado:upper()))
  print('')

  for ticker, empresa in pairs(quotes) do
    print(string.format('%s - %s', ticker, empresa.nome))
    print(string.format('  Preço: $%.2f | Variação: %+.2f%%',
      empresa.preco_atual,
      empresa.variacao_dia * 100
    ))
    print(string.format('  Min/Max Dia: $%.2f / $%.2f | Volume: %d',
      empresa.preco_minimo,
      empresa.preco_maximo,
      empresa.volume_dia
    ))
    print('')
  end

  print('========================================\n')
end, false)

--============================================================
-- Exports
--============================================================
exports('BuyStock', SM.BuyStock)
exports('SellStock', SM.SellStock)
exports('GetQuotes', SM.GetQuotes)
exports('GetPortfolio', SM.GetPortfolio)
exports('GetIbovespa', function() return SM.State.indice_ibovespa end)

print('^2[space_economy]^7 Stock Market loaded - Trading system active with Ibovespa index')
