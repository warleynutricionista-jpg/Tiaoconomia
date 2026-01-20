--============================================================
-- space_economy - server/economy_monitor.lua
-- Sistema de Monitoramento Econômico Ultra-Realista
-- MELHORIA CRÍTICA #2 - Economia Auto-Regulada
--============================================================
SE = SE or {}
SE.EconomyMonitor = SE.EconomyMonitor or {}

local U = SE.Util
local EM = SE.EconomyMonitor

--============================================================
-- Estado Econômico Global
--============================================================
EM.State = {
  -- Circulação Monetária
  total_circulacao = 0,
  dinheiro_players = 0,
  dinheiro_empresas = 0,
  tesouro_publico = 0,
  dinheiro_cash = 0,
  dinheiro_banco = 0,

  -- PIB (Produto Interno Bruto)
  pib_total = 0,
  pib_consumo = 0,        -- Compras em lojas
  pib_investimento = 0,   -- Veículos, propriedades
  pib_governo = 0,        -- Gastos públicos
  pib_exportacoes = 0,    -- Vendas para NPCs
  pib_importacoes = 0,    -- Compras de NPCs

  -- Indicadores
  pib_per_capita = 0,
  velocidade_circulacao = 0,
  populacao_economica = 0,  -- Players ativos

  -- Histórico (últimas 24h)
  historico_pib = {},
  historico_circulacao = {},
  historico_velocidade = {},

  -- Transações (período atual)
  transacoes_periodo = {
    total = 0,
    compras = 0,
    vendas = 0,
    transferencias = 0,
    impostos = 0,
    salarios = 0,
  },

  -- Setores Econômicos
  setores = {
    comercio = { participacao = 0.30, crescimento = 0 },
    servicos = { participacao = 0.45, crescimento = 0 },
    industria = { participacao = 0.25, crescimento = 0 },
  },

  -- Timestamp última atualização
  ultima_atualizacao = 0,
}

--============================================================
-- Configuração
--============================================================
local Config = {
  UpdateIntervalMs = 60000,      -- Atualizar a cada 1 minuto
  HistoryMaxEntries = 1440,      -- 24h (1440 minutos)
  SaveIntervalMs = 300000,       -- Salvar a cada 5 minutos
  EnableRealTimeTracking = true,
  EnableSectorAnalysis = true,
}

--============================================================
-- Schema
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Tabela de snapshots econômicos
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      timestamp BIGINT NOT NULL,
      total_circulacao BIGINT NOT NULL DEFAULT 0,
      dinheiro_players BIGINT NOT NULL DEFAULT 0,
      dinheiro_empresas BIGINT NOT NULL DEFAULT 0,
      tesouro_publico BIGINT NOT NULL DEFAULT 0,
      pib_total BIGINT NOT NULL DEFAULT 0,
      pib_consumo BIGINT NOT NULL DEFAULT 0,
      pib_investimento BIGINT NOT NULL DEFAULT 0,
      pib_governo BIGINT NOT NULL DEFAULT 0,
      pib_exportacoes BIGINT NOT NULL DEFAULT 0,
      pib_importacoes BIGINT NOT NULL DEFAULT 0,
      velocidade_circulacao DECIMAL(10,4) NOT NULL DEFAULT 0,
      populacao_economica INT NOT NULL DEFAULT 0,
      metadata LONGTEXT NULL,
      INDEX idx_timestamp (timestamp),
      INDEX idx_created (id DESC)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Tabela de transações econômicas (agregadas)
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_transactions (
      id INT AUTO_INCREMENT PRIMARY KEY,
      periodo VARCHAR(20) NOT NULL,
      tipo VARCHAR(50) NOT NULL,
      valor BIGINT NOT NULL DEFAULT 0,
      quantidade INT NOT NULL DEFAULT 0,
      metadata LONGTEXT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_periodo_tipo (periodo, tipo),
      INDEX idx_created (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Tabela de indicadores setoriais
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_sectors (
      id INT AUTO_INCREMENT PRIMARY KEY,
      timestamp BIGINT NOT NULL,
      setor VARCHAR(50) NOT NULL,
      participacao_pib DECIMAL(10,4) NOT NULL DEFAULT 0,
      crescimento DECIMAL(10,4) NOT NULL DEFAULT 0,
      volume_negocios BIGINT NOT NULL DEFAULT 0,
      metadata LONGTEXT NULL,
      INDEX idx_timestamp_setor (timestamp, setor)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  U.dbg('[EconomyMonitor] Schema garantido')
end

CreateThread(function()
  while not MySQL do Wait(250) end
  ensureSchema()
end)

--============================================================
-- Calcular Circulação Monetária Total
--============================================================
function EM.CalcularCirculacao()
  if not MySQL then return 0 end

  local total = 0
  local players = 0
  local empresas = 0
  local cash = 0
  local banco = 0

  -- 1. Dinheiro dos players
  local ok, playerMoney = pcall(function()
    return MySQL.query.await([[
      SELECT
        COALESCE(SUM(JSON_EXTRACT(money, '$.cash')), 0) as total_cash,
        COALESCE(SUM(JSON_EXTRACT(money, '$.bank')), 0) as total_bank
      FROM players
      WHERE JSON_VALID(money)
    ]])
  end)

  if ok and playerMoney and playerMoney[1] then
    cash = U.toInt(playerMoney[1].total_cash, 0)
    banco = U.toInt(playerMoney[1].total_bank, 0)
    players = cash + banco
  end

  -- 2. Dinheiro de empresas/sociedades
  local ok2, sociedades = pcall(function()
    return MySQL.query.await([[
      SELECT COALESCE(SUM(amount), 0) as total
      FROM management_funds
    ]])
  end)

  if ok2 and sociedades and sociedades[1] then
    empresas = U.toInt(sociedades[1].total, 0)
  end

  -- 3. Tesouro público
  local tesouro = 0
  if SE.State and SE.State.vaultBalance then
    tesouro = U.toInt(SE.State.vaultBalance, 0)
  end

  total = players + empresas + tesouro

  -- Atualizar estado
  EM.State.total_circulacao = total
  EM.State.dinheiro_players = players
  EM.State.dinheiro_empresas = empresas
  EM.State.tesouro_publico = tesouro
  EM.State.dinheiro_cash = cash
  EM.State.dinheiro_banco = banco

  return total
end

--============================================================
-- Calcular PIB (Produto Interno Bruto)
--============================================================
function EM.CalcularPIB()
  local periodo = os.date('%Y-%m-%d')

  if not MySQL then return 0 end

  -- Buscar transações do período
  local ok, transacoes = pcall(function()
    return MySQL.query.await([[
      SELECT
        tipo,
        COALESCE(SUM(valor), 0) as total,
        COUNT(*) as quantidade
      FROM space_economy_transactions
      WHERE periodo = ?
      GROUP BY tipo
    ]], { periodo })
  end)

  local consumo = 0
  local investimento = 0
  local governo = 0
  local exportacoes = 0
  local importacoes = 0

  if ok and transacoes then
    for _, t in ipairs(transacoes) do
      local tipo = t.tipo or ''
      local valor = U.toInt(t.total, 0)

      if tipo:find('compra_') or tipo:find('shop_') then
        consumo = consumo + valor
      elseif tipo:find('veiculo_') or tipo:find('propriedade_') then
        investimento = investimento + valor
      elseif tipo:find('salario_') or tipo:find('governo_') then
        governo = governo + valor
      elseif tipo:find('venda_npc_') then
        exportacoes = exportacoes + valor
      elseif tipo:find('compra_npc_') then
        importacoes = importacoes + valor
      end
    end
  end

  -- PIB = C + I + G + (X - M)
  local pib = consumo + investimento + governo + (exportacoes - importacoes)

  -- Atualizar estado
  EM.State.pib_total = pib
  EM.State.pib_consumo = consumo
  EM.State.pib_investimento = investimento
  EM.State.pib_governo = governo
  EM.State.pib_exportacoes = exportacoes
  EM.State.pib_importacoes = importacoes

  return pib
end

--============================================================
-- Calcular Velocidade de Circulação
--============================================================
function EM.CalcularVelocidade()
  local circulacao = EM.State.total_circulacao
  local transacoes = EM.State.transacoes_periodo.total

  if circulacao <= 0 then return 0 end

  -- V = T / M (Transações / Massa monetária)
  local velocidade = transacoes / circulacao

  EM.State.velocidade_circulacao = velocidade

  return velocidade
end

--============================================================
-- Calcular PIB per Capita
--============================================================
function EM.CalcularPIBPerCapita()
  local pib = EM.State.pib_total
  local populacao = #GetPlayers()

  EM.State.populacao_economica = populacao

  if populacao <= 0 then return 0 end

  local pib_per_capita = pib / populacao
  EM.State.pib_per_capita = pib_per_capita

  return pib_per_capita
end

--============================================================
-- Registrar Transação Econômica
--============================================================
function EM.RegistrarTransacao(tipo, valor, metadata)
  if not MySQL or not Config.EnableRealTimeTracking then return end

  tipo = U.safeStr(tipo, 'desconhecido')
  valor = U.toInt(valor, 0)

  if valor <= 0 then return end

  local periodo = os.date('%Y-%m-%d')

  -- Atualizar contador em memória
  EM.State.transacoes_periodo.total = EM.State.transacoes_periodo.total + valor

  if tipo:find('compra') or tipo:find('shop') then
    EM.State.transacoes_periodo.compras = EM.State.transacoes_periodo.compras + valor
  elseif tipo:find('venda') then
    EM.State.transacoes_periodo.vendas = EM.State.transacoes_periodo.vendas + valor
  elseif tipo:find('imposto') or tipo:find('taxa') then
    EM.State.transacoes_periodo.impostos = EM.State.transacoes_periodo.impostos + valor
  elseif tipo:find('salario') or tipo:find('pagamento') then
    EM.State.transacoes_periodo.salarios = EM.State.transacoes_periodo.salarios + valor
  else
    EM.State.transacoes_periodo.transferencias = EM.State.transacoes_periodo.transferencias + valor
  end

  -- Salvar no banco (batch a cada minuto)
  CreateThread(function()
    pcall(function()
      MySQL.insert.await([[
        INSERT INTO space_economy_transactions (periodo, tipo, valor, quantidade, metadata)
        VALUES (?, ?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE
          valor = valor + VALUES(valor),
          quantidade = quantidade + 1
      ]], { periodo, tipo, valor, metadata and U.safeJsonEncode(metadata) or nil })
    end)
  end)
end

--============================================================
-- Salvar Snapshot Econômico
--============================================================
function EM.SalvarSnapshot()
  if not MySQL then return end

  local now = os.time()

  pcall(function()
    MySQL.insert.await([[
      INSERT INTO space_economy_snapshots (
        timestamp, total_circulacao, dinheiro_players, dinheiro_empresas,
        tesouro_publico, pib_total, pib_consumo, pib_investimento,
        pib_governo, pib_exportacoes, pib_importacoes,
        velocidade_circulacao, populacao_economica, metadata
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      now,
      EM.State.total_circulacao,
      EM.State.dinheiro_players,
      EM.State.dinheiro_empresas,
      EM.State.tesouro_publico,
      EM.State.pib_total,
      EM.State.pib_consumo,
      EM.State.pib_investimento,
      EM.State.pib_governo,
      EM.State.pib_exportacoes,
      EM.State.pib_importacoes,
      EM.State.velocidade_circulacao,
      EM.State.populacao_economica,
      U.safeJsonEncode({
        setores = EM.State.setores,
        transacoes = EM.State.transacoes_periodo,
      })
    })
  end)

  -- Adicionar ao histórico em memória
  table.insert(EM.State.historico_pib, {
    timestamp = now,
    valor = EM.State.pib_total,
  })

  table.insert(EM.State.historico_circulacao, {
    timestamp = now,
    valor = EM.State.total_circulacao,
  })

  table.insert(EM.State.historico_velocidade, {
    timestamp = now,
    valor = EM.State.velocidade_circulacao,
  })

  -- Limitar histórico
  if #EM.State.historico_pib > Config.HistoryMaxEntries then
    table.remove(EM.State.historico_pib, 1)
  end
  if #EM.State.historico_circulacao > Config.HistoryMaxEntries then
    table.remove(EM.State.historico_circulacao, 1)
  end
  if #EM.State.historico_velocidade > Config.HistoryMaxEntries then
    table.remove(EM.State.historico_velocidade, 1)
  end

  U.dbg(('[EconomyMonitor] Snapshot salvo - PIB: $%d | Circulação: $%d | Velocidade: %.4f'):format(
    EM.State.pib_total,
    EM.State.total_circulacao,
    EM.State.velocidade_circulacao
  ))
end

--============================================================
-- Atualização Completa
--============================================================
function EM.AtualizarCompleto()
  EM.CalcularCirculacao()
  EM.CalcularPIB()
  EM.CalcularVelocidade()
  EM.CalcularPIBPerCapita()
  EM.State.ultima_atualizacao = os.time()
end

--============================================================
-- Obter Relatório Econômico
--============================================================
function EM.GetRelatorio()
  return {
    circulacao = {
      total = EM.State.total_circulacao,
      players = EM.State.dinheiro_players,
      empresas = EM.State.dinheiro_empresas,
      tesouro = EM.State.tesouro_publico,
      cash = EM.State.dinheiro_cash,
      banco = EM.State.dinheiro_banco,
      porcentagem_bancarizado = EM.State.total_circulacao > 0 and
        (EM.State.dinheiro_banco / EM.State.total_circulacao * 100) or 0,
    },

    pib = {
      total = EM.State.pib_total,
      per_capita = EM.State.pib_per_capita,
      consumo = EM.State.pib_consumo,
      investimento = EM.State.pib_investimento,
      governo = EM.State.pib_governo,
      exportacoes = EM.State.pib_exportacoes,
      importacoes = EM.State.pib_importacoes,
      saldo_comercial = EM.State.pib_exportacoes - EM.State.pib_importacoes,
    },

    indicadores = {
      velocidade_circulacao = EM.State.velocidade_circulacao,
      populacao_economica = EM.State.populacao_economica,
    },

    transacoes = EM.State.transacoes_periodo,

    setores = EM.State.setores,

    ultima_atualizacao = EM.State.ultima_atualizacao,
  }
end

--============================================================
-- Thread de Atualização Periódica
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()

  while true do
    Wait(Config.UpdateIntervalMs)
    EM.AtualizarCompleto()
  end
end)

--============================================================
-- Thread de Salvamento de Snapshots
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end

  while true do
    Wait(Config.SaveIntervalMs)
    EM.SalvarSnapshot()
  end
end)

--============================================================
-- Comando Admin - Relatório Econômico
--============================================================
RegisterCommand('eco_relatorio', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      print('[EconomyMonitor] Acesso negado')
      return
    end
  end

  EM.AtualizarCompleto()
  local relatorio = EM.GetRelatorio()

  print('\n========================================')
  print('RELATÓRIO ECONÔMICO DA CIDADE')
  print('========================================')
  print(string.format('População Econômica: %d players', relatorio.indicadores.populacao_economica))
  print('')
  print('CIRCULAÇÃO MONETÁRIA:')
  print(string.format('  Total em Circulação: $%d', relatorio.circulacao.total))
  print(string.format('  Players: $%d (%.1f%%)', relatorio.circulacao.players,
    relatorio.circulacao.total > 0 and (relatorio.circulacao.players / relatorio.circulacao.total * 100) or 0))
  print(string.format('  Empresas: $%d (%.1f%%)', relatorio.circulacao.empresas,
    relatorio.circulacao.total > 0 and (relatorio.circulacao.empresas / relatorio.circulacao.total * 100) or 0))
  print(string.format('  Tesouro: $%d (%.1f%%)', relatorio.circulacao.tesouro,
    relatorio.circulacao.total > 0 and (relatorio.circulacao.tesouro / relatorio.circulacao.total * 100) or 0))
  print(string.format('  Bancarização: %.1f%%', relatorio.circulacao.porcentagem_bancarizado))
  print('')
  print('PIB (Produto Interno Bruto):')
  print(string.format('  PIB Total: $%d', relatorio.pib.total))
  print(string.format('  PIB per Capita: $%d', relatorio.pib.per_capita))
  print(string.format('  Consumo: $%d (%.1f%%)', relatorio.pib.consumo,
    relatorio.pib.total > 0 and (relatorio.pib.consumo / relatorio.pib.total * 100) or 0))
  print(string.format('  Investimento: $%d (%.1f%%)', relatorio.pib.investimento,
    relatorio.pib.total > 0 and (relatorio.pib.investimento / relatorio.pib.total * 100) or 0))
  print(string.format('  Governo: $%d (%.1f%%)', relatorio.pib.governo,
    relatorio.pib.total > 0 and (relatorio.pib.governo / relatorio.pib.total * 100) or 0))
  print(string.format('  Exportações: $%d', relatorio.pib.exportacoes))
  print(string.format('  Importações: $%d', relatorio.pib.importacoes))
  print(string.format('  Saldo Comercial: $%d %s',
    math.abs(relatorio.pib.saldo_comercial),
    relatorio.pib.saldo_comercial >= 0 and '(Superávit)' or '(Déficit)'))
  print('')
  print('INDICADORES:')
  print(string.format('  Velocidade de Circulação: %.4f', relatorio.indicadores.velocidade_circulacao))
  print('')
  print('TRANSAÇÕES DO PERÍODO:')
  print(string.format('  Total: $%d', relatorio.transacoes.total))
  print(string.format('  Compras: $%d', relatorio.transacoes.compras))
  print(string.format('  Vendas: $%d', relatorio.transacoes.vendas))
  print(string.format('  Impostos: $%d', relatorio.transacoes.impostos))
  print(string.format('  Salários: $%d', relatorio.transacoes.salarios))
  print('========================================\n')
end, false)

--============================================================
-- Exports
--============================================================
exports('RegistrarTransacao', EM.RegistrarTransacao)
exports('GetRelatorioEconomico', EM.GetRelatorio)
exports('GetCirculacaoMonetaria', function() return EM.State.total_circulacao end)
exports('GetPIB', function() return EM.State.pib_total end)
exports('GetPIBPerCapita', function() return EM.State.pib_per_capita end)
exports('GetVelocidadeCirculacao', function() return EM.State.velocidade_circulacao end)

print('^2[space_economy]^7 Economy Monitor loaded - Tracking real-time GDP and monetary circulation')
