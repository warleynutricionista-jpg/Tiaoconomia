--============================================================
-- space_economy - server/economy_monitor.lua
-- Sistema de Monitoramento Econômico em Tempo Real
-- PIB, Circulação Monetária, Velocidade de Dinheiro
--============================================================
SE = SE or {}
SE.EconomyMonitor = SE.EconomyMonitor or {}

local U = SE.Util
local EM = SE.EconomyMonitor
local GlobalConfig = Config

--============================================================
-- Estado do Monitor
--============================================================
local MonitorState = {
  -- Circulação Monetária
  playerMoney = 0,          -- Dinheiro total dos players
  companyMoney = 0,         -- Dinheiro de empresas/sociedades
  treasuryMoney = 0,        -- Tesouro público
  totalCirculation = 0,     -- Circulação total
  companies = {},           -- Lista de empresas (riqueza corporativa)
  privateDebt = 0,          -- Dívida privada total

  -- PIB (Produto Interno Bruto)
  pib = {
    consumption = 0,        -- Consumo
    investment = 0,         -- Investimento
    government = 0,         -- Gastos governamentais
    exports = 0,            -- Exportações
    imports = 0,            -- Importações
    total = 0,              -- PIB Total
    perCapita = 0,          -- PIB per capita
  },

  -- Indicadores
  velocity = 0,             -- Velocidade de circulação
  bankingRate = 0,          -- Taxa de bancarização (%)
  population = 0,           -- População econômica ativa
  activeMoney = 0,          -- Massa monetária de players ativos (7 dias)
  gini = 0,                 -- Coeficiente de Gini
  populationTotal = 0,     -- População total (base DB quando possível)
  populationActive = 0,    -- População ativa (janela configurável)

  ipcPriceIndex = {},      -- Cache de preços médios por categoria IPC

  -- Rastreamento de transações (últimas 24h)
  transactions = {
    count = 0,
    volume = 0,
    byCategory = {},
  },

  lastTransaction = nil,
  lastGiniUpdate = 0,
  lastUpdate = 0,
}

--============================================================
-- Configuração
--============================================================
local Config = {
  UpdateInterval = 60000,        -- Atualizar a cada 1 minuto
  TransactionHistoryHours = 24,  -- Manter histórico de 24h
  Debug = (GlobalConfig and GlobalConfig.Debug) or false,

  Circulation = {
    UseWealthSnapshot = true,    -- Incluir players offline via snapshot
    ActiveDays = 7,              -- Janela de atividade para população ativa
    SnapshotCacheSeconds = 300,  -- Cache do snapshot (5 min)
  },

  CompanyFundsTables = {
    'management_funds',
    'qb_management_funds',
    'qbx_management_funds',
    { name = 'space_economy_organizations', column = 'balance' },
  },

  -- Categorias de transação para PIB
  Categories = {
    -- Consumo
    'compra_veiculo',
    'compra_imovel',
    'compra_item',
    'servico_mecanico',
    'servico_hospital',
    'alimentacao',
    'combustivel',

    -- Investimento
    'investimento_empresa',
    'compra_acao',
    'aplicacao_financeira',

    -- Governo
    'salario_publico',
    'subsidio',
    'auxilio',

    -- Exportação/Importação (se aplicável)
    'exportacao',
    'importacao',
  },

  IPCSampling = {
    Enabled = true,
    MinSamples = 5,
    MaxChangePerUpdate = 0.05, -- 5% por ciclo
    Map = {
      alimentacao = { 'alimentacao' },
      transporte = { 'combustivel', 'compra_veiculo', 'servico_mecanico' },
      habitacao = { 'compra_imovel' },
      saude = { 'servico_hospital' },
      lazer = { 'compra_item' },
    },
  },
}

local snapshotCache = {
  data = nil,
  ts = 0,
}

local function tableExists(name)
  if not MySQL then return false end
  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)
  return ok and rows and #rows > 0
end

local function getWealthSnapshotCached()
  if not (SE.WealthTax and SE.WealthTax.BuildWealthSnapshot) then return nil end
  local now = os.time()
  local ttl = Config.Circulation.SnapshotCacheSeconds or 300
  if snapshotCache.data and (now - snapshotCache.ts) < ttl then
    return snapshotCache.data
  end
  local data = SE.WealthTax.BuildWealthSnapshot()
  snapshotCache.data = data
  snapshotCache.ts = now
  return data
end

--============================================================
-- Rastrear Transação
--============================================================
function EM.RegisterTransaction(category, amount, metadata)
  if not category or not amount then return end

  amount = U.toInt(amount, 0)
  if amount <= 0 then return end

  -- Adicionar à contagem
  MonitorState.transactions.count = MonitorState.transactions.count + 1
  MonitorState.transactions.volume = MonitorState.transactions.volume + amount

  -- Por categoria
  if not MonitorState.transactions.byCategory[category] then
    MonitorState.transactions.byCategory[category] = {
      count = 0,
      volume = 0,
    }
  end

  MonitorState.transactions.byCategory[category].count = MonitorState.transactions.byCategory[category].count + 1
  MonitorState.transactions.byCategory[category].volume = MonitorState.transactions.byCategory[category].volume + amount

  MonitorState.lastTransaction = {
    category = category,
    amount = amount,
    metadata = metadata,
    timestamp = os.time(),
  }

  -- Salvar no banco de dados para histórico
  if MySQL then
    CreateThread(function()
      pcall(function()
        MySQL.insert.await([[
          INSERT INTO space_economy_transactions (
            category, amount, metadata, created_at
          ) VALUES (?, ?, ?, NOW())
        ]], {
          category,
          amount,
          metadata and json.encode(metadata) or nil
        })
      end)
    end)
  end

  if Config.Debug then
    local sourceInfo = metadata and (metadata.resource or metadata.source or 'unknown') or 'unknown'
    U.dbg(('[EcoMonitor] Transação detectada via Hook: $%d (Fonte: %s)'):format(amount, sourceInfo))
  end

  U.dbg(('[Economy Monitor] Transaction: %s = $%d'):format(category, amount))
end

--============================================================
-- Calcular Circulação Monetária
--============================================================
function EM.CalculateMoneyCirculation()
  local playerMoney = 0
  local bankMoney = 0
  local populationTotal = 0
  local populationActive = 0
  local companies = {}
  local moneySupply = nil

  if SE.DB and SE.DB.GetTotalMoneySupply then
    moneySupply = SE.DB.GetTotalMoneySupply()
    playerMoney = U.toInt(moneySupply.playerMoney, 0)
  end

  local useSnapshot = Config.Circulation.UseWealthSnapshot
  local snapshot = useSnapshot and getWealthSnapshotCached() or nil

  if snapshot and #snapshot > 0 then
    local cutoff = os.time() - ((Config.Circulation.ActiveDays or 7) * 86400)
    local online = {}
    if SE.Bridge and SE.Bridge.GetCitizenId then
      for _, src in ipairs(GetPlayers()) do
        local cid = SE.Bridge.GetCitizenId(tonumber(src))
        if cid then
          online[cid] = true
        end
      end
    end

    local snapshotTotal = 0
    for _, entry in ipairs(snapshot) do
      local cash = U.toInt(entry.cash, 0)
      local bank = U.toInt(entry.bank, 0)
      snapshotTotal = snapshotTotal + cash + bank
      bankMoney = bankMoney + bank
      populationTotal = populationTotal + 1

      local lastSeen = entry.lastSeen
      if (lastSeen and lastSeen >= cutoff) or (not lastSeen and online[entry.citizenid]) then
        populationActive = populationActive + 1
      end
    end

    if not moneySupply then
      playerMoney = snapshotTotal
    end
  else
    -- Somar dinheiro de todos os players online
    for _, src in ipairs(GetPlayers()) do
      local srcNum = tonumber(src)
      if srcNum and SE.Integrations then
        local cash = SE.Integrations.GetMoney(srcNum, 'cash') or 0
        local bank = SE.Integrations.GetMoney(srcNum, 'bank') or 0

        if not moneySupply then
          playerMoney = playerMoney + cash + bank
        end
        bankMoney = bankMoney + bank
      end
    end
    populationTotal = #GetPlayers()
    populationActive = populationTotal
  end

  -- Tesouro
  local treasuryMoney = 0
  if SE.State and SE.State.vaultBalance then
    treasuryMoney = U.toInt(SE.State.vaultBalance, 0)
  end

  -- Empresas/Sociedades (se tiver integração)
  local companyMoney = 0
  if SE.DB and SE.DB.GetAllCompanies then
    companies = SE.DB.GetAllCompanies()
    for _, company in ipairs(companies) do
      companyMoney = companyMoney + U.toInt(company.balance, 0)
    end
  elseif MySQL then
    for _, entry in ipairs(Config.CompanyFundsTables or {}) do
      local tableName = entry
      local columnName = 'amount'

      if type(entry) == 'table' then
        tableName = entry.name
        columnName = entry.column or 'amount'
      end

      if tableName and tableExists(tableName) then
        local ok, result = pcall(function()
          return MySQL.scalar.await(
            ('SELECT COALESCE(SUM(%s), 0) FROM %s'):format(columnName, tableName),
            {}
          )
        end)
        if ok and result then
          companyMoney = companyMoney + U.toInt(result, 0)
        end
      end
    end
  end

  if moneySupply and moneySupply.companyMoney then
    companyMoney = U.toInt(moneySupply.companyMoney, companyMoney)
  end

  -- Total
  local totalCirculation = playerMoney + companyMoney + treasuryMoney

  -- Taxa de bancarização
  local bankingRate = playerMoney > 0 and (bankMoney / playerMoney * 100) or 0

  -- Atualizar estado
  MonitorState.playerMoney = playerMoney
  MonitorState.companyMoney = companyMoney
  MonitorState.treasuryMoney = treasuryMoney
  MonitorState.totalCirculation = totalCirculation
  MonitorState.bankingRate = bankingRate
  MonitorState.population = populationActive > 0 and populationActive or populationTotal
  MonitorState.populationTotal = populationTotal
  MonitorState.populationActive = populationActive
  MonitorState.companies = companies

  local privateDebt = 0
  if SE.DB and SE.DB.GetTotalExternalDebts then
    privateDebt = privateDebt + U.toInt(SE.DB.GetTotalExternalDebts(), 0)
  end
  if SE.DB and SE.DB.GetTotalFinancingDebt then
    privateDebt = privateDebt + U.toInt(SE.DB.GetTotalFinancingDebt(), 0)
  end
  MonitorState.privateDebt = privateDebt

  return {
    playerMoney = playerMoney,
    companyMoney = companyMoney,
    treasuryMoney = treasuryMoney,
    totalCirculation = totalCirculation,
    bankingRate = bankingRate,
    population = MonitorState.population,
    populationTotal = populationTotal,
    populationActive = populationActive,
    privateDebt = privateDebt,
  }
end

--============================================================
-- Massa Monetária de Players Ativos (últimos 7 dias)
--============================================================
function EM.CalculateActiveMoneySupply()
  local activeMoney = 0
  local cutoff = os.time() - ((Config.Circulation.ActiveDays or 7) * 86400)
  local online = {}

  if SE.Bridge and SE.Bridge.GetCitizenId then
    for _, src in ipairs(GetPlayers()) do
      local cid = SE.Bridge.GetCitizenId(tonumber(src))
      if cid then
        online[cid] = true
      end
    end
  end

  local snapshot = getWealthSnapshotCached()
  if snapshot then
    for _, entry in ipairs(snapshot) do
      local lastSeen = entry.lastSeen
      if (lastSeen and lastSeen >= cutoff) or (not lastSeen and online[entry.citizenid]) then
        activeMoney = activeMoney + U.toInt(entry.cash, 0) + U.toInt(entry.bank, 0)
      end
    end
  end

  if activeMoney <= 0 then
    activeMoney = MonitorState.playerMoney or 0
  end

  MonitorState.activeMoney = activeMoney
  return activeMoney
end

--============================================================
-- Coeficiente de Gini (Desigualdade)
--============================================================
function EM.CalculateGini()
  local now = os.time()
  if (now - (MonitorState.lastGiniUpdate or 0)) < 600 then
    return MonitorState.gini or 0
  end

  if not (SE.WealthTax and SE.WealthTax.BuildWealthSnapshot) then
    return MonitorState.gini or 0
  end

  local snapshot = SE.WealthTax.BuildWealthSnapshot()
  if #snapshot == 0 then return MonitorState.gini or 0 end

  local totals = {}
  local sum = 0
  for _, entry in ipairs(snapshot) do
    local total = U.toNumber(entry.total, 0)
    totals[#totals + 1] = total
    sum = sum + total
  end

  if sum <= 0 then
    MonitorState.gini = 0
    MonitorState.lastGiniUpdate = now
    return 0
  end

  table.sort(totals)
  local n = #totals
  local cumulative = 0
  for i, value in ipairs(totals) do
    cumulative = cumulative + (i * value)
  end

  local gini = (2 * cumulative) / (n * sum) - (n + 1) / n
  gini = math.max(0, math.min(gini, 1))

  MonitorState.gini = gini
  MonitorState.lastGiniUpdate = now

  if gini > 0.60 then
    U.dbg('[Economy Monitor] Gini acima de 0.60. Sugestão: aumentar Wealth Tax.')
  end

  return gini
end

function EM.GetTotalCirculation()
  return MonitorState.totalCirculation or 0
end

function EM.GetLastTransaction()
  return MonitorState.lastTransaction
end

--============================================================
-- Calcular PIB
--============================================================
function EM.CalculatePIB()
  local consumption = 0
  local investment = 0
  local government = 0
  local exports = 0
  local imports = 0

  -- Categorizar transações
  for category, data in pairs(MonitorState.transactions.byCategory) do
    local volume = data.volume or 0

    -- Consumo
    if category:find('compra_') or category:find('servico_') or category:find('alimentacao') or category:find('combustivel') then
      consumption = consumption + volume

    -- Investimento
    elseif category:find('investimento_') or category:find('acao') or category:find('aplicacao') then
      investment = investment + volume

    -- Governo
    elseif category:find('salario_publico') or category:find('subsidio') or category:find('auxilio') then
      government = government + volume

    -- Exportação
    elseif category:find('exportacao') then
      exports = exports + volume

    -- Importação
    elseif category:find('importacao') then
      imports = imports + volume
    end
  end

  -- PIB = C + I + G + (X - M)
  local total = consumption + investment + government + (exports - imports)

  -- PIB per capita
  local populationBase = MonitorState.populationActive > 0 and MonitorState.populationActive
    or MonitorState.population
  local perCapita = populationBase > 0 and (total / populationBase) or 0

  -- Atualizar estado
  MonitorState.pib = {
    consumption = consumption,
    investment = investment,
    government = government,
    exports = exports,
    imports = imports,
    total = total,
    perCapita = perCapita,
  }

  return MonitorState.pib
end

--============================================================
-- Calcular Velocidade de Circulação
--============================================================
function EM.CalculateVelocity()
  -- Velocidade = Total de Transações / Massa Monetária
  -- Indica quantas vezes o dinheiro "gira" na economia

  local transactionVolume = MonitorState.transactions.volume or 0
  local activeMoney = EM.CalculateActiveMoneySupply()

  local velocity = activeMoney > 0 and (transactionVolume / activeMoney) or 0

  MonitorState.velocity = velocity

  return velocity
end

--============================================================
-- Atualizar IPC com base em transações reais (proxy de preços)
--============================================================
function EM.UpdateIPCFromTransactions()
  local cfg = Config.IPCSampling
  if not (cfg and cfg.Enabled and SE.MonetaryPolicy) then return end

  for ipcCategory, mapped in pairs(cfg.Map or {}) do
    local totalVolume = 0
    local totalCount = 0

    for _, category in ipairs(mapped) do
      local data = MonitorState.transactions.byCategory[category]
      if data then
        totalVolume = totalVolume + (data.volume or 0)
        totalCount = totalCount + (data.count or 0)
      end
    end

    if totalCount >= (cfg.MinSamples or 1) and totalVolume > 0 then
      local avgPrice = totalVolume / totalCount
      local lastAvg = MonitorState.ipcPriceIndex[ipcCategory]

      if lastAvg and lastAvg > 0 then
        local change = (avgPrice - lastAvg) / lastAvg
        local maxChange = cfg.MaxChangePerUpdate or 0.05
        change = math.max(-maxChange, math.min(maxChange, change))

        exports.tiao_economia:AdjustIPCCategory(ipcCategory, change * 100)
      end

      MonitorState.ipcPriceIndex[ipcCategory] = avgPrice
    end
  end
end

--============================================================
-- Atualizar Todos os Indicadores
--============================================================
function EM.UpdateAll()
  EM.CalculateMoneyCirculation()
  EM.CalculatePIB()
  EM.CalculateVelocity()
  EM.CalculateGini()
  EM.UpdateIPCFromTransactions()

  MonitorState.lastUpdate = os.time()

  U.dbg('[Economy Monitor] Updated: PIB=$' .. U.formatNumber(MonitorState.pib.total))
end

--============================================================
-- Limpar Transações Antigas
--============================================================
function EM.CleanOldTransactions()
  if not MySQL then return end

  local hoursAgo = Config.TransactionHistoryHours

  pcall(function()
    MySQL.execute.await([[
      DELETE FROM space_economy_transactions
      WHERE created_at < DATE_SUB(NOW(), INTERVAL ? HOUR)
    ]], { hoursAgo })
  end)

  U.dbg('[Economy Monitor] Cleaned old transactions')
end

--============================================================
-- Obter Relatório Completo
--============================================================
function EM.GetReport()
  EM.UpdateAll()

  return {
    circulation = {
      playerMoney = MonitorState.playerMoney,
      companyMoney = MonitorState.companyMoney,
      treasuryMoney = MonitorState.treasuryMoney,
      total = MonitorState.totalCirculation,
      bankingRate = MonitorState.bankingRate,
      privateDebt = MonitorState.privateDebt,
    },

    corporateWealth = {
      total = MonitorState.companyMoney,
      companies = MonitorState.companies,
    },

    pib = MonitorState.pib,

    indicators = {
      velocity = MonitorState.velocity,
      population = MonitorState.population,
      populationTotal = MonitorState.populationTotal,
      populationActive = MonitorState.populationActive,
      activeMoney = MonitorState.activeMoney,
      gini = MonitorState.gini,
    },

    transactions = {
      count = MonitorState.transactions.count,
      volume = MonitorState.transactions.volume,
      byCategory = MonitorState.transactions.byCategory,
    },

    lastUpdate = MonitorState.lastUpdate,
  }
end

--============================================================
-- Comando: Relatório Econômico
--============================================================
RegisterCommand('eco_relatorio', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      if src ~= 0 then
        TriggerClientEvent('ox_lib:notify', src, {
          type = 'error',
          description = 'Sem permissão'
        })
      end
      return
    end
  end

  local report = EM.GetReport()
  local companies = report.corporateWealth and report.corporateWealth.companies or {}
  table.sort(companies, function(a, b)
    return U.toInt(a.balance, 0) > U.toInt(b.balance, 0)
  end)

  local topCompanies = {}
  local topLimit = math.min(5, #companies)
  for i = 1, topLimit do
    local company = companies[i]
    topCompanies[#topCompanies + 1] = string.format('  - %s (%s): $%s',
      tostring(company.name),
      tostring(company.source),
      U.formatNumber(U.toInt(company.balance, 0))
    )
  end

  local output = {
    '\n========================================',
    'RELATÓRIO ECONÔMICO DA CIDADE',
    '========================================',
    string.format('População Econômica: %d players', report.indicators.population),
    string.format('População Total (DB): %d', report.indicators.populationTotal or 0),
    string.format('População Ativa: %d', report.indicators.populationActive or 0),
    '',
    'CIRCULAÇÃO MONETÁRIA:',
    string.format('  Total em Circulação: $%s', U.formatNumber(report.circulation.total)),
    string.format('  Players: $%s (%.1f%%)',
      U.formatNumber(report.circulation.playerMoney),
      report.circulation.total > 0 and (report.circulation.playerMoney / report.circulation.total * 100) or 0
    ),
    string.format('  Empresas: $%s (%.1f%%)',
      U.formatNumber(report.circulation.companyMoney),
      report.circulation.total > 0 and (report.circulation.companyMoney / report.circulation.total * 100) or 0
    ),
    string.format('  Empresas registradas: %d', #companies),
    (#topCompanies > 0 and '  Riqueza Corporativa (Top 5):' or '  Riqueza Corporativa: nenhuma'),
    table.unpack(topCompanies),
    string.format('  Tesouro: $%s (%.1f%%)',
      U.formatNumber(report.circulation.treasuryMoney),
      report.circulation.total > 0 and (report.circulation.treasuryMoney / report.circulation.total * 100) or 0
    ),
    string.format('  Bancarização: %.1f%%', report.circulation.bankingRate),
    string.format('  Dívida Privada Total: $%s', U.formatNumber(report.circulation.privateDebt or 0)),
    '',
    'PIB (Produto Interno Bruto):',
    string.format('  PIB Total: $%s', U.formatNumber(report.pib.total)),
    string.format('  PIB per Capita: $%s', U.formatNumber(report.pib.perCapita)),
    string.format('  Consumo: $%s (%.1f%%)',
      U.formatNumber(report.pib.consumption),
      report.pib.total > 0 and (report.pib.consumption / report.pib.total * 100) or 0
    ),
    string.format('  Investimento: $%s (%.1f%%)',
      U.formatNumber(report.pib.investment),
      report.pib.total > 0 and (report.pib.investment / report.pib.total * 100) or 0
    ),
    string.format('  Governo: $%s (%.1f%%)',
      U.formatNumber(report.pib.government),
      report.pib.total > 0 and (report.pib.government / report.pib.total * 100) or 0
    ),
    string.format('  Exportações: $%s', U.formatNumber(report.pib.exports)),
    string.format('  Importações: $%s', U.formatNumber(report.pib.imports)),
    string.format('  Saldo Comercial: $%s (%s)',
      U.formatNumber(report.pib.exports - report.pib.imports),
      report.pib.exports > report.pib.imports and 'Superávit' or 'Déficit'
    ),
    '',
    'INDICADORES:',
    string.format('  Velocidade de Circulação: %.4f', report.indicators.velocity),
    string.format('  Transações (24h): %d (Volume: $%s)',
      report.transactions.count,
      U.formatNumber(report.transactions.volume)
    ),
    '========================================\n',
  }

  for _, line in ipairs(output) do
    print(line)
  end

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Relatório gerado no console do servidor'
    })
  end
end, false)

--============================================================
-- Comando: Diagnóstico de Integrações
--============================================================
RegisterCommand('eco_debug', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      if src ~= 0 then
        TriggerClientEvent('ox_lib:notify', src, {
          type = 'error',
          description = 'Sem permissão'
        })
      end
      return
    end
  end

  local framework = (SE.Framework or (SE.Bridge and SE.Bridge.GetFrameworkName and SE.Bridge.GetFrameworkName()) or 'unknown')
  local dbStatus = (MySQL and 'conectado') or 'indisponível'
  local lastTx = MonitorState.lastTransaction

  local inflation = (SE.MonetaryPolicy and SE.MonetaryPolicy.GetReport and SE.MonetaryPolicy.GetReport().inflation and SE.MonetaryPolicy.GetReport().inflation.annual)
    or (SE.State and SE.State.inflationRate) or 0
  local prevInflation = MonitorState.lastInflationDebug
  local trend = 'estável'
  if prevInflation ~= nil then
    if inflation > prevInflation then trend = 'alta'
    elseif inflation < prevInflation then trend = 'queda' end
  end
  MonitorState.lastInflationDebug = inflation

  local output = {
    '\n========================================',
    'ECONOMIA - DEBUG',
    '========================================',
    ('Framework detectado: %s'):format(framework),
    ('Banco de Dados: %s'):format(dbStatus),
    ('Inflação atual: %.4f (%s)'):format(inflation, trend),
  }

  if lastTx then
    table.insert(output, ('Última transação: %s | $%d | %s'):format(
      tostring(lastTx.category),
      U.toInt(lastTx.amount, 0),
      lastTx.metadata and (lastTx.metadata.resource or lastTx.metadata.source or 'desconhecido') or 'desconhecido'
    ))
  else
    table.insert(output, 'Última transação: nenhuma')
  end

  table.insert(output, '========================================\n')

  for _, line in ipairs(output) do
    print(line)
  end

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Diagnóstico gerado no console do servidor'
    })
  end
end, false)

--============================================================
-- Thread de Atualização Automática
--============================================================
CreateThread(function()
  -- Aguardar inicialização
  Wait(10000)

  while true do
    Wait(Config.UpdateInterval)

    -- Atualizar indicadores
    EM.UpdateAll()

    -- Limpar transações antigas (a cada 1 hora)
    if os.time() % 3600 < 60 then
      EM.CleanOldTransactions()
    end
  end
end)

--============================================================
-- Garantir Tabela de Transações
--============================================================
CreateThread(function()
  if not MySQL then return end

  Wait(2000)

  pcall(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_transactions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        category VARCHAR(64) NOT NULL,
        amount BIGINT NOT NULL,
        metadata TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_category (category),
        INDEX idx_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
  end)

  U.dbg('[Economy Monitor] Transactions table ensured')
end)

--============================================================
-- Exports
--============================================================
exports('RegisterTransaction', EM.RegisterTransaction)
exports('GetEconomyReport', EM.GetReport)
exports('GetPIB', function() return MonitorState.pib.total end)
exports('GetPIBPerCapita', function() return MonitorState.pib.perCapita end)
exports('GetMoneyCirculation', function() return MonitorState.totalCirculation end)
exports('GetTotalCirculation', function() return MonitorState.totalCirculation end)
exports('GetVelocity', function() return MonitorState.velocity end)

print('^2[space_economy]^7 Economy Monitor loaded - Update interval: ' .. Config.UpdateInterval .. 'ms')
