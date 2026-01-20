--============================================================
-- space_economy - server/labor_market.lua
-- Sistema de Mercado de Trabalho Ultra-Realista
-- FASE 3.3 - Salário Mínimo Dinâmico e Taxa de Desemprego
--============================================================
SE = SE or {}
SE.LaborMarket = SE.LaborMarket or {}

local U = SE.Util
local LM = SE.LaborMarket

--============================================================
-- Estado do Mercado de Trabalho
--============================================================
LM.State = {
  salario_minimo = 2000,
  salario_minimo_anterior = 2000,
  salario_medio = 5000,

  taxa_desemprego = 0.05,  -- 5%
  populacao_economica_ativa = 0,
  empregados = 0,
  desempregados = 0,

  -- Salários por setor
  setores = {
    policia = {
      nome = 'Polícia',
      piso = 3000,
      teto = 16000,
      multiplicador = 1.5,
      empregados = 0,
      vagas = 50,
    },
    paramedico = {
      nome = 'Paramédico',
      piso = 4000,
      teto = 20000,
      multiplicador = 2.0,
      empregados = 0,
      vagas = 30,
    },
    mecanico = {
      nome = 'Mecânico',
      piso = 2400,
      teto = 10000,
      multiplicador = 1.2,
      empregados = 0,
      vagas = 40,
    },
    taxista = {
      nome = 'Taxista',
      piso = 2200,
      teto = 8000,
      multiplicador = 1.1,
      empregados = 0,
      vagas = 60,
    },
    caminhoneiro = {
      nome = 'Caminhoneiro',
      piso = 2800,
      teto = 12000,
      multiplicador = 1.4,
      empregados = 0,
      vagas = 40,
    },
    advogado = {
      nome = 'Advogado',
      piso = 5000,
      teto = 25000,
      multiplicador = 2.5,
      empregados = 0,
      vagas = 20,
    },
    jornalista = {
      nome = 'Jornalista',
      piso = 3500,
      teto = 15000,
      multiplicador = 1.75,
      empregados = 0,
      vagas = 15,
    },
    lixeiro = {
      nome = 'Lixeiro',
      piso = 2100,
      teto = 6000,
      multiplicador = 1.05,
      empregados = 0,
      vagas = 30,
    },
  },

  -- Ajustes históricos
  historico_salario_minimo = {},
  historico_desemprego = {},
  ultima_atualizacao = 0,
}

--============================================================
-- Configuração
--============================================================
local Config = {
  UpdateIntervalMs = 1800000,  -- Atualizar a cada 30 minutos
  AjusteSalarioIntervalMs = 7200000,  -- Ajustar salário a cada 2h (em prod seria anual)

  -- Critérios de ajuste
  InflacaoAlvo = 0.04,
  CrescimentoPIBAlvo = 0.03,

  -- Desemprego
  MetaDesemprego = 0.06,  -- 6%
  DesempregoNaturalMin = 0.03,  -- 3% (friccional)
  DesempregoNaturalMax = 0.08,  -- 8%
}

--============================================================
-- Schema
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Histórico de salário mínimo
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_minimum_wage (
      id INT AUTO_INCREMENT PRIMARY KEY,
      timestamp BIGINT NOT NULL,
      valor BIGINT NOT NULL,
      variacao DECIMAL(10,4) NOT NULL DEFAULT 0,
      inflacao_periodo DECIMAL(10,4) NOT NULL DEFAULT 0,
      pib_crescimento DECIMAL(10,4) NOT NULL DEFAULT 0,
      justificativa TEXT NULL,
      INDEX idx_timestamp (timestamp)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Estatísticas de emprego
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_employment_stats (
      id INT AUTO_INCREMENT PRIMARY KEY,
      timestamp BIGINT NOT NULL,
      populacao_ativa INT NOT NULL DEFAULT 0,
      empregados INT NOT NULL DEFAULT 0,
      desempregados INT NOT NULL DEFAULT 0,
      taxa_desemprego DECIMAL(10,4) NOT NULL DEFAULT 0,
      salario_medio BIGINT NOT NULL DEFAULT 0,
      metadata LONGTEXT NULL,
      INDEX idx_timestamp (timestamp)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  U.dbg('[LaborMarket] Schema garantido')
end

CreateThread(function()
  while not MySQL do Wait(250) end
  ensureSchema()
end)

--============================================================
-- Calcular Taxa de Desemprego
--============================================================
function LM.CalculateUnemploymentRate()
  -- Obter total de players online
  local totalPlayers = #GetPlayers()
  LM.State.populacao_economica_ativa = totalPlayers

  if totalPlayers == 0 then
    LM.State.taxa_desemprego = 0
    return 0
  end

  -- Contar empregados por job
  local empregados = 0
  for setor, dados in pairs(LM.State.setores) do
    dados.empregados = 0
  end

  -- Integração com QBCore/QBox para contar jobs
  if GetResourceState('qbx_core') == 'started' or GetResourceState('qb-core') == 'started' then
    for _, playerId in ipairs(GetPlayers()) do
      local Player = exports.qbx_core:GetPlayer(tonumber(playerId))
      if not Player and exports['qb-core'] then
        Player = exports['qb-core']:GetPlayer(tonumber(playerId))
      end

      if Player and Player.PlayerData and Player.PlayerData.job then
        local jobName = Player.PlayerData.job.name

        -- Contar se tem job válido (não "unemployed")
        if jobName and jobName ~= 'unemployed' and jobName ~= 'none' then
          empregados = empregados + 1

          -- Contar por setor
          if LM.State.setores[jobName] then
            LM.State.setores[jobName].empregados = LM.State.setores[jobName].empregados + 1
          end
        end
      end
    end
  end

  LM.State.empregados = empregados
  LM.State.desempregados = totalPlayers - empregados
  LM.State.taxa_desemprego = totalPlayers > 0 and (LM.State.desempregados / totalPlayers) or 0

  return LM.State.taxa_desemprego
end

--============================================================
-- Calcular Salário Médio
--============================================================
function LM.CalculateAverageWage()
  local soma_salarios = 0
  local total_empregados = 0

  for setor, dados in pairs(LM.State.setores) do
    if dados.empregados > 0 then
      -- Média entre piso e teto ponderada por empregados
      local salario_medio_setor = (dados.piso + dados.teto) / 2
      soma_salarios = soma_salarios + (salario_medio_setor * dados.empregados)
      total_empregados = total_empregados + dados.empregados
    end
  end

  LM.State.salario_medio = total_empregados > 0 and
    math.floor(soma_salarios / total_empregados) or LM.State.salario_minimo

  return LM.State.salario_medio
end

--============================================================
-- Ajustar Salário Mínimo Automaticamente
--============================================================
function LM.AdjustMinimumWage()
  local salario_atual = LM.State.salario_minimo

  -- Obter inflação
  local inflacao = 0
  if SE.MonetaryPolicy and SE.MonetaryPolicy.State then
    inflacao = SE.MonetaryPolicy.State.inflacao_anual or 0
  end

  -- Obter crescimento PIB
  local crescimento_pib = 0
  if SE.EconomyMonitor and SE.EconomyMonitor.State then
    -- Aproximação: comparar PIB atual com histórico
    local historico = SE.EconomyMonitor.State.historico_pib
    if #historico >= 2 then
      local pib_atual = historico[#historico].valor
      local pib_anterior = historico[#historico - 1].valor
      if pib_anterior > 0 then
        crescimento_pib = (pib_atual / pib_anterior) - 1
      end
    end
  end

  -- Fórmula de ajuste:
  -- Novo Salário = Atual × (1 + Inflação + 50% do Crescimento PIB)
  local ajuste_inflacao = inflacao
  local ajuste_produtividade = crescimento_pib * 0.5

  local variacao_total = ajuste_inflacao + ajuste_produtividade

  -- Limitar ajuste: -5% a +15% ao ano
  variacao_total = U.clamp(variacao_total, -0.05, 0.15)

  local novo_salario = math.floor(salario_atual * (1 + variacao_total))

  -- Mínimo absoluto: $1500
  novo_salario = math.max(1500, novo_salario)

  -- Justificativa
  local justificativa = string.format(
    'Ajuste por inflação (%.2f%%) + produtividade (%.2f%%) = %.2f%%',
    ajuste_inflacao * 100,
    ajuste_produtividade * 100,
    variacao_total * 100
  )

  -- Atualizar
  LM.State.salario_minimo_anterior = LM.State.salario_minimo
  LM.State.salario_minimo = novo_salario

  -- Ajustar pisos/tetos de todos os setores
  for setor, dados in pairs(LM.State.setores) do
    dados.piso = math.floor(LM.State.salario_minimo * dados.multiplicador)
    dados.teto = math.floor(dados.piso * (dados.teto / dados.piso))  -- Manter proporção
  end

  -- Salvar histórico
  table.insert(LM.State.historico_salario_minimo, {
    timestamp = os.time(),
    valor = novo_salario,
    variacao = variacao_total,
  })

  if #LM.State.historico_salario_minimo > 100 then
    table.remove(LM.State.historico_salario_minimo, 1)
  end

  MySQL.insert.await([[
    INSERT INTO space_economy_minimum_wage
      (timestamp, valor, variacao, inflacao_periodo, pib_crescimento, justificativa)
    VALUES (?, ?, ?, ?, ?, ?)
  ]], { os.time(), novo_salario, variacao_total, inflacao, crescimento_pib, justificativa })

  U.dbg(('[LaborMarket] Salário mínimo ajustado: $%d → $%d (%+.2f%%) | %s'):format(
    salario_atual,
    novo_salario,
    variacao_total * 100,
    justificativa
  ))

  -- Notificar players
  TriggerClientEvent('chat:addMessage', -1, {
    args = { '[TRABALHO]', string.format('💰 Salário mínimo ajustado: $%d → $%d (%+.2f%%)',
      salario_atual, novo_salario, variacao_total * 100) }
  })

  return novo_salario
end

--============================================================
-- Salvar Estatísticas
--============================================================
function LM.SaveStats()
  MySQL.insert.await([[
    INSERT INTO space_economy_employment_stats
      (timestamp, populacao_ativa, empregados, desempregados, taxa_desemprego, salario_medio, metadata)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], {
    os.time(),
    LM.State.populacao_economica_ativa,
    LM.State.empregados,
    LM.State.desempregados,
    LM.State.taxa_desemprego,
    LM.State.salario_medio,
    U.safeJsonEncode({ setores = LM.State.setores })
  })
end

--============================================================
-- Atualização Completa
--============================================================
function LM.Update()
  LM.CalculateUnemploymentRate()
  LM.CalculateAverageWage()
  LM.SaveStats()
  LM.State.ultima_atualizacao = os.time()
end

--============================================================
-- Obter Relatório
--============================================================
function LM.GetReport()
  return {
    salario_minimo = {
      atual = LM.State.salario_minimo,
      anterior = LM.State.salario_minimo_anterior,
      variacao = LM.State.salario_minimo_anterior > 0 and
        ((LM.State.salario_minimo / LM.State.salario_minimo_anterior) - 1) or 0,
    },

    salario_medio = LM.State.salario_medio,

    emprego = {
      populacao_ativa = LM.State.populacao_economica_ativa,
      empregados = LM.State.empregados,
      desempregados = LM.State.desempregados,
      taxa_desemprego = LM.State.taxa_desemprego,
      meta_desemprego = Config.MetaDesemprego,
      status = LM.State.taxa_desemprego <= Config.MetaDesemprego and 'BOM' or 'ALTO',
    },

    setores = LM.State.setores,

    ultima_atualizacao = LM.State.ultima_atualizacao,
  }
end

--============================================================
-- Thread de Atualização Periódica
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()

  Wait(10000)  -- Aguardar outros sistemas

  while true do
    Wait(Config.UpdateIntervalMs)
    LM.Update()
  end
end)

--============================================================
-- Thread de Ajuste de Salário Mínimo
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end

  Wait(Config.AjusteSalarioIntervalMs)

  while true do
    Wait(Config.AjusteSalarioIntervalMs)
    LM.AdjustMinimumWage()
  end
end)

--============================================================
-- Comando - Relatório do Mercado de Trabalho
--============================================================
RegisterCommand('eco_trabalho', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  LM.Update()
  local report = LM.GetReport()

  print('\n========================================')
  print('MERCADO DE TRABALHO')
  print('========================================')
  print('SALÁRIO MÍNIMO:')
  print(string.format('  Atual: $%d', report.salario_minimo.atual))
  print(string.format('  Anterior: $%d', report.salario_minimo.anterior))
  print(string.format('  Variação: %+.2f%%', report.salario_minimo.variacao * 100))
  print('')
  print('SALÁRIO MÉDIO:')
  print(string.format('  $%d', report.salario_medio))
  print('')
  print('EMPREGO:')
  print(string.format('  População Economicamente Ativa: %d', report.emprego.populacao_ativa))
  print(string.format('  Empregados: %d (%.1f%%)',
    report.emprego.empregados,
    report.emprego.populacao_ativa > 0 and (report.emprego.empregados / report.emprego.populacao_ativa * 100) or 0
  ))
  print(string.format('  Desempregados: %d', report.emprego.desempregados))
  print(string.format('  Taxa de Desemprego: %.2f%% (meta: %.2f%%)',
    report.emprego.taxa_desemprego * 100,
    report.emprego.meta_desemprego * 100
  ))
  print(string.format('  Status: %s', report.emprego.status))
  print('')
  print('SETORES (Emprego):')
  for setor, dados in pairs(report.setores) do
    print(string.format('  %s: %d/%d vagas | Piso: $%d | Teto: $%d',
      dados.nome,
      dados.empregados,
      dados.vagas,
      dados.piso,
      dados.teto
    ))
  end
  print('========================================\n')
end, false)

--============================================================
-- Comando - Forçar Ajuste de Salário
--============================================================
RegisterCommand('eco_ajustar_salario', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  print('[LaborMarket] Ajuste de salário forçado por admin')
  LM.AdjustMinimumWage()
end, false)

--============================================================
-- Exports
--============================================================
exports('GetMinimumWage', function() return LM.State.salario_minimo end)
exports('GetAverageWage', function() return LM.State.salario_medio end)
exports('GetUnemploymentRate', function() return LM.State.taxa_desemprego end)
exports('GetLaborReport', LM.GetReport)
exports('GetSectorWages', function(setor)
  return LM.State.setores[setor]
end)

print('^2[space_economy]^7 Labor Market loaded - Dynamic minimum wage and unemployment tracking active')
