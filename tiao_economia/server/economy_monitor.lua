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
}

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

  -- Somar dinheiro de todos os players online
  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum and SE.Integrations then
      local cash = SE.Integrations.GetMoney(srcNum, 'cash') or 0
      local bank = SE.Integrations.GetMoney(srcNum, 'bank') or 0

      playerMoney = playerMoney + cash + bank
      bankMoney = bankMoney + bank
    end
  end

  -- Tesouro
  local treasuryMoney = 0
  if SE.State and SE.State.vaultBalance then
    treasuryMoney = U.toInt(SE.State.vaultBalance, 0)
  end

  -- Empresas/Sociedades (se tiver integração)
  local companyMoney = 0
  if MySQL then
    local ok, result = pcall(function()
      -- Tentar buscar de qb-management ou similar
      return MySQL.scalar.await(
        'SELECT COALESCE(SUM(amount), 0) FROM management_funds',
        {}
      )
    end)
    if ok and result then
      companyMoney = U.toInt(result, 0)
    end
  end

  -- Total
  local totalCirculation = playerMoney + companyMoney + treasuryMoney

  -- Taxa de bancarização
  local bankingRate = playerMoney > 0 and (bankMoney / playerMoney * 100) or 0

  -- População
  local population = #GetPlayers()

  -- Atualizar estado
  MonitorState.playerMoney = playerMoney
  MonitorState.companyMoney = companyMoney
  MonitorState.treasuryMoney = treasuryMoney
  MonitorState.totalCirculation = totalCirculation
  MonitorState.bankingRate = bankingRate
  MonitorState.population = population

  return {
    playerMoney = playerMoney,
    companyMoney = companyMoney,
    treasuryMoney = treasuryMoney,
    totalCirculation = totalCirculation,
    bankingRate = bankingRate,
    population = population,
  }
end

--============================================================
-- Massa Monetária de Players Ativos (últimos 7 dias)
--============================================================
function EM.CalculateActiveMoneySupply()
  local activeMoney = 0
  local cutoff = os.time() - (7 * 24 * 60 * 60)
  local online = {}

  if SE.Bridge and SE.Bridge.GetCitizenId then
    for _, src in ipairs(GetPlayers()) do
      local cid = SE.Bridge.GetCitizenId(tonumber(src))
      if cid then
        online[cid] = true
      end
    end
  end

  if SE.WealthTax and SE.WealthTax.BuildWealthSnapshot then
    local snapshot = SE.WealthTax.BuildWealthSnapshot()
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
  local perCapita = MonitorState.population > 0 and (total / MonitorState.population) or 0

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
-- Atualizar Todos os Indicadores
--============================================================
function EM.UpdateAll()
  EM.CalculateMoneyCirculation()
  EM.CalculatePIB()
  EM.CalculateVelocity()
  EM.CalculateGini()

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
    },

    pib = MonitorState.pib,

    indicators = {
      velocity = MonitorState.velocity,
      population = MonitorState.population,
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

  local output = {
    '\n========================================',
    'RELATÓRIO ECONÔMICO DA CIDADE',
    '========================================',
    string.format('População Econômica: %d players', report.indicators.population),
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
    string.format('  Tesouro: $%s (%.1f%%)',
      U.formatNumber(report.circulation.treasuryMoney),
      report.circulation.total > 0 and (report.circulation.treasuryMoney / report.circulation.total * 100) or 0
    ),
    string.format('  Bancarização: %.1f%%', report.circulation.bankingRate),
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
