--============================================================
-- space_economy - server/monetary_policy.lua
-- Sistema de Política Monetária Automática
-- SELIC, Inflação Dinâmica, IPC, COPOM Virtual
--============================================================
SE = SE or {}
SE.MonetaryPolicy = SE.MonetaryPolicy or {}

local U = SE.Util
local MP = SE.MonetaryPolicy

--============================================================
-- Estado da Política Monetária
--============================================================
local PolicyState = {
  -- Taxa SELIC
  selic = 0.0050,              -- 0.50% ao mês (inicial)
  selicHistory = {},

  -- Inflação
  inflation = {
    monthly = 0.0,             -- Inflação mensal
    annual = 0.0,              -- Inflação anual
    accumulated = 0.0,         -- Inflação acumulada
    target = 0.04,             -- Meta: 4% ao ano
    tolerance = 0.02,          -- Tolerância: ±2%
  },

  -- IPC (Índice de Preços ao Consumidor)
  ipc = {
    current = 100.0,           -- Índice atual (base 100)
    previous = 100.0,          -- Índice anterior
    variation = 0.0,           -- Variação percentual

    -- Por categoria (peso = %)
    categories = {
      { name = 'alimentacao',  weight = 0.25, index = 100.0, variation = 0.0 },
      { name = 'transporte',   weight = 0.20, index = 100.0, variation = 0.0 },
      { name = 'habitacao',    weight = 0.35, index = 100.0, variation = 0.0 },
      { name = 'saude',        weight = 0.10, index = 100.0, variation = 0.0 },
      { name = 'lazer',        weight = 0.10, index = 100.0, variation = 0.0 },
    },
  },

  -- COPOM (Comitê de Política Monetária)
  copom = {
    lastMeeting = 0,
    nextMeeting = 0,
    lastDecision = 'MANTER',   -- SUBIR, MANTER, BAIXAR
    justification = 'Início do sistema',
  },

  -- Rastreamento de massa monetária
  moneySupply = {
    current = 0,
    previous = 0,
    growth = 0.0,              -- % de crescimento
  },

  lastUpdate = 0,
}

--============================================================
-- Configuração
--============================================================
local Config = {
  UpdateInterval = 120000,      -- Atualizar a cada 2 minutos
  COPOMMeetingInterval = 3600,  -- Reunião COPOM a cada 1 hora (em segundos)

  SELIC = {
    Min = 0.0025,               -- 0.25% ao mês
    Max = 0.0200,               -- 2.00% ao mês
    AdjustStep = 0.0025,        -- Ajuste de 0.25%
  },

  Inflation = {
    Target = 0.04,              -- 4% ao ano
    Tolerance = 0.02,           -- ±2%
  },

  -- Pesos para cálculo de inflação
  InflationWeights = {
    moneySupply = 0.60,         -- 60% baseado em massa monetária
    ipc = 0.40,                 -- 40% baseado em IPC
  },
}

local function ensurePolicySettings()
  if not SE.State then return nil end
  SE.State.settings = type(SE.State.settings) == 'table' and SE.State.settings or {}
  SE.State.settings.monetaryPolicy = type(SE.State.settings.monetaryPolicy) == 'table'
    and SE.State.settings.monetaryPolicy or {}
  return SE.State.settings.monetaryPolicy
end

--============================================================
-- Calcular Inflação por Massa Monetária
--============================================================
function MP.CalculateMoneySupplyInflation()
  -- Pegar circulação monetária do Economy Monitor
  local currentSupply = 0
  if SE.EconomyMonitor and SE.EconomyMonitor.GetReport then
    local report = SE.EconomyMonitor.GetReport()
    currentSupply = report.circulation.total or 0
  end

  -- Crescimento da massa monetária
  local growth = 0.0
  if PolicyState.moneySupply.previous > 0 then
    growth = (currentSupply - PolicyState.moneySupply.previous) / PolicyState.moneySupply.previous
  end

  -- Atualizar
  PolicyState.moneySupply.previous = PolicyState.moneySupply.current
  PolicyState.moneySupply.current = currentSupply
  PolicyState.moneySupply.growth = growth

  -- Inflação baseada em massa monetária
  -- Se massa aumenta 10%, inflação tende a 10%
  local inflationFromMoney = growth

  return inflationFromMoney
end

--============================================================
-- Calcular IPC (Índice de Preços ao Consumidor)
--============================================================
function MP.CalculateIPC()
  -- Somar variações ponderadas
  local weightedSum = 0.0

  for _, category in ipairs(PolicyState.ipc.categories) do
    weightedSum = weightedSum + (category.variation * category.weight)
  end

  -- Atualizar índice
  PolicyState.ipc.previous = PolicyState.ipc.current
  PolicyState.ipc.current = PolicyState.ipc.current * (1 + weightedSum)
  PolicyState.ipc.variation = weightedSum

  return weightedSum
end

--============================================================
-- Ajustar IPC de Categoria
--============================================================
function MP.AdjustIPCCategory(categoryName, percentChange)
  for _, category in ipairs(PolicyState.ipc.categories) do
    if category.name == categoryName then
      category.variation = category.variation + (percentChange / 100)
      category.index = category.index * (1 + percentChange / 100)

      U.dbg(('[Monetary Policy] IPC %s adjusted by %.2f%%'):format(categoryName, percentChange))
      return true
    end
  end

  return false
end

--============================================================
-- Calcular Inflação Total
--============================================================
function MP.CalculateInflation()
  -- Inflação por massa monetária
  local moneyInflation = MP.CalculateMoneySupplyInflation()

  -- Inflação por IPC
  local ipcInflation = MP.CalculateIPC()

  -- Inflação final ponderada
  local monthlyInflation = (
    (moneyInflation * Config.InflationWeights.moneySupply) +
    (ipcInflation * Config.InflationWeights.ipc)
  )

  -- Atualizar inflação mensal
  PolicyState.inflation.monthly = monthlyInflation

  -- Inflação anual (composta)
  PolicyState.inflation.annual = math.pow(1 + monthlyInflation, 12) - 1

  -- Inflação acumulada
  PolicyState.inflation.accumulated = PolicyState.inflation.accumulated + monthlyInflation

  U.dbg(('[Monetary Policy] Inflation: Monthly=%.2f%% | Annual=%.2f%%'):format(
    monthlyInflation * 100,
    PolicyState.inflation.annual * 100
  ))

  return monthlyInflation
end

--============================================================
-- Revisão Autônoma (Velocidade + PIB + Tesouro)
--============================================================
function MP.ReviewAutonomy()
  if not (Config and Config.Inflation and Config.Inflation.AutoAdjust) then return end

  if not (SE.EconomyMonitor and SE.EconomyMonitor.GetReport) then return end

  local report = SE.EconomyMonitor.GetReport()
  local velocity = (report.indicators and report.indicators.velocity) or 0
  local pib = (report.pib and report.pib.total) or 0
  local vault = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or
    (SE.State and SE.State.vaultBalance) or 0

  local settings = ensurePolicySettings() or {}
  local taxStep = Config.Inflation.TaxStep or 0.05
  local inflStep = Config.Inflation.InflationStep or 0.05

  local curInflation = (SE.Server and SE.Server.GetInflationRate and SE.Server.GetInflationRate())
    or (SE.State and SE.State.inflationRate) or 1.0
  local curTax = (SE.Server and SE.Server.GetTaxMultiplier and SE.Server.GetTaxMultiplier())
    or (SE.State and SE.State.taxMultiplier) or 1.0

  -- Velocidade do dinheiro: economia aquecida
  if velocity >= (Config.Inflation.VelocityHigh or 1.2) then
    curInflation = curInflation + inflStep
    curTax = curTax + taxStep
    U.dbg('[Monetary Policy] Autonomia: economia aquecida, ajustando inflação/impostos')

  elseif velocity <= (Config.Inflation.VelocityLow or 0.6) then
    curInflation = curInflation - inflStep
    curTax = curTax - taxStep
    U.dbg('[Monetary Policy] Autonomia: economia fria, reduzindo inflação/impostos')
  end

  -- Cenário de superávit
  if Config.Treasury and vault > (Config.Treasury.MaxReserves or 0) then
    curTax = math.min(curTax, 0.8)
    U.dbg('[Monetary Policy] Autonomia: superávit detectado, impostos reduzidos')
  end

  -- PIB em queda: estímulo
  local lastPib = tonumber(settings.lastPIB or 0) or 0
  if lastPib > 0 and pib < lastPib then
    curInflation = curInflation - inflStep
    curTax = curTax - taxStep
    U.dbg('[Monetary Policy] Autonomia: PIB em queda, estímulo aplicado')
  end

  -- Laffer básico: receita semanal
  if SE.Metrics and SE.Metrics.GetWeeklyRevenue then
    local weekly = SE.Metrics.GetWeeklyRevenue() or {}
    local totalWeekly = 0
    for _, row in ipairs(weekly) do
      totalWeekly = totalWeekly + U.toInt(row.total, 0)
    end

    local lastWeekly = tonumber(settings.lastWeeklyRevenue or 0) or 0
    if lastWeekly > 0 and totalWeekly < lastWeekly then
      curTax = curTax - taxStep
      U.dbg('[Monetary Policy] Autonomia: receita caiu, impostos suavizados')
    end

    settings.lastWeeklyRevenue = totalWeekly
  end

  settings.lastPIB = pib
  if SE.Server and SE.Server.MarkDirty then
    SE.Server.MarkDirty()
  end

  if SE.Server and SE.Server.SetInflationRate then
    SE.Server.SetInflationRate(curInflation)
  end

  if SE.Server and SE.Server.SetTaxMultiplier then
    SE.Server.SetTaxMultiplier(curTax)
  end
end

--============================================================
-- COPOM: Tomar Decisão sobre SELIC
--============================================================
function MP.COPOMMeeting()
  local now = os.time()

  -- Verificar se já passou tempo suficiente
  if PolicyState.copom.nextMeeting > now then
    return
  end

  U.dbg('[Monetary Policy] COPOM Meeting started')

  -- Calcular inflação atual
  local currentInflation = PolicyState.inflation.annual
  local target = PolicyState.inflation.target
  local tolerance = PolicyState.inflation.tolerance

  local currentSELIC = PolicyState.selic
  local newSELIC = currentSELIC
  local decision = 'MANTER'
  local justification = ''

  -- Lógica de decisão
  if currentInflation > (target + tolerance) then
    -- Inflação ACIMA da meta → SUBIR SELIC
    newSELIC = math.min(currentSELIC + Config.SELIC.AdjustStep, Config.SELIC.Max)
    decision = 'SUBIR'
    justification = string.format(
      'Inflação em %.1f%% (meta: %.1f%%). Ajuste preventivo.',
      currentInflation * 100,
      target * 100
    )

  elseif currentInflation < (target - tolerance) then
    -- Inflação ABAIXO da meta → BAIXAR SELIC
    newSELIC = math.max(currentSELIC - Config.SELIC.AdjustStep, Config.SELIC.Min)
    decision = 'BAIXAR'
    justification = string.format(
      'Inflação em %.1f%% (meta: %.1f%%). Estímulo necessário.',
      currentInflation * 100,
      target * 100
    )

  else
    -- Inflação DENTRO da meta → MANTER
    decision = 'MANTER'
    justification = string.format(
      'Inflação em %.1f%% dentro da meta (%.1f%% ±%.1f%%). Manter estabilidade.',
      currentInflation * 100,
      target * 100,
      tolerance * 100
    )
  end

  -- Aplicar decisão
  PolicyState.selic = newSELIC
  PolicyState.copom.lastMeeting = now
  PolicyState.copom.nextMeeting = now + Config.COPOMMeetingInterval
  PolicyState.copom.lastDecision = decision
  PolicyState.copom.justification = justification

  -- Salvar no histórico
  table.insert(PolicyState.selicHistory, {
    timestamp = now,
    selic = newSELIC,
    decision = decision,
    inflation = currentInflation,
  })

  -- Limitar histórico a 100 entradas
  if #PolicyState.selicHistory > 100 then
    table.remove(PolicyState.selicHistory, 1)
  end

  U.dbg(('[Monetary Policy] COPOM Decision: %s SELIC to %.2f%% (was %.2f%%)'):format(
    decision,
    newSELIC * 100,
    currentSELIC * 100
  ))

  -- Notificar admins
  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum and SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(srcNum) then
      TriggerClientEvent('ox_lib:notify', srcNum, {
        type = 'info',
        title = 'COPOM - Decisão',
        description = string.format('SELIC: %s para %.2f%%', decision, newSELIC * 100),
        duration = 10000,
      })
    end
  end

  return {
    decision = decision,
    selic = newSELIC,
    justification = justification,
  }
end

--============================================================
-- Ajustar Preço pela Inflação
--============================================================
function MP.AdjustPriceForInflation(basePrice)
  basePrice = U.toInt(basePrice, 0)

  local inflationFactor = 1 + PolicyState.inflation.accumulated
  local adjustedPrice = math.floor(basePrice * inflationFactor)

  return adjustedPrice
end

--============================================================
-- Obter Relatório de Política Monetária
--============================================================
function MP.GetReport()
  return {
    selic = {
      current = PolicyState.selic,
      monthly = PolicyState.selic,
      annual = math.pow(1 + PolicyState.selic, 12) - 1,
    },

    inflation = PolicyState.inflation,

    ipc = {
      current = PolicyState.ipc.current,
      variation = PolicyState.ipc.variation,
      categories = PolicyState.ipc.categories,
    },

    copom = {
      lastMeeting = PolicyState.copom.lastMeeting,
      nextMeeting = PolicyState.copom.nextMeeting,
      lastDecision = PolicyState.copom.lastDecision,
      justification = PolicyState.copom.justification,
    },

    moneySupply = PolicyState.moneySupply,
  }
end

--============================================================
-- Comando: Relatório de Política Monetária
--============================================================
RegisterCommand('eco_politica', function(source, args)
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

  local report = MP.GetReport()

  local output = {
    '\n========================================',
    'POLÍTICA MONETÁRIA',
    '========================================',
    'TAXA SELIC:',
    string.format('  Atual: %.2f%% ao mês', report.selic.current * 100),
    string.format('  Anualizada: %.2f%% ao ano', report.selic.annual * 100),
    '',
    'INFLAÇÃO:',
    string.format('  Mensal: %.2f%%', report.inflation.monthly * 100),
    string.format('  Anual: %.2f%%', report.inflation.annual * 100),
    string.format('  Acumulada: %.2f%%', report.inflation.accumulated * 100),
    string.format('  Meta: %.2f%% (±%.2f%%)',
      report.inflation.target * 100,
      report.inflation.tolerance * 100
    ),
    string.format('  Status: %s',
      (report.inflation.annual >= (report.inflation.target - report.inflation.tolerance) and
       report.inflation.annual <= (report.inflation.target + report.inflation.tolerance))
      and '✅ DENTRO DA META' or '⚠️ FORA DA META'
    ),
    '',
    'IPC (Índice de Preços):',
    string.format('  Atual: %.2f', report.ipc.current),
    string.format('  Variação: %+.2f%%', report.ipc.variation * 100),
    '  Por Categoria:',
  }

  for _, cat in ipairs(report.ipc.categories) do
    table.insert(output, string.format('    %s: Índice %.2f | Variação %+.2f%% | Peso %.0f%%',
      cat.name:upper(),
      cat.index,
      cat.variation * 100,
      cat.weight * 100
    ))
  end

  table.insert(output, '')
  table.insert(output, 'ÚLTIMA DECISÃO COPOM:')
  table.insert(output, string.format('  Decisão: %s', report.copom.lastDecision))
  table.insert(output, string.format('  SELIC: %.2f%%', report.selic.current * 100))
  table.insert(output, string.format('  Justificativa: %s', report.copom.justification))
  table.insert(output, string.format('  Próxima reunião em: %d minutos',
    math.max(0, math.floor((report.copom.nextMeeting - os.time()) / 60))
  ))
  table.insert(output, '========================================\n')

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
-- Comando: Forçar Reunião COPOM
--============================================================
RegisterCommand('eco_copom', function(source, args)
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

  -- Forçar reunião
  PolicyState.copom.nextMeeting = 0
  local result = MP.COPOMMeeting()

  print(string.format('[COPOM] Decisão: %s | SELIC: %.2f%% | %s',
    result.decision,
    result.selic * 100,
    result.justification
  ))

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      title = 'COPOM',
      description = string.format('%s SELIC para %.2f%%', result.decision, result.selic * 100)
    })
  end
end, false)

--============================================================
-- Comando: Ajustar IPC
--============================================================
RegisterCommand('eco_ipc', function(source, args)
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

  local category = args[1]
  local percent = tonumber(args[2]) or 0

  if not category or percent == 0 then
    print('Uso: /eco_ipc <categoria> <percentual>')
    print('Categorias: alimentacao, transporte, habitacao, saude, lazer')
    return
  end

  local success = MP.AdjustIPCCategory(category, percent)

  if success then
    print(string.format('[IPC] %s ajustado em %+.2f%%', category, percent))

    if src ~= 0 then
      TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        description = string.format('IPC %s: %+.2f%%', category, percent)
      })
    end
  else
    print('[IPC] Categoria inválida')
  end
end, false)

--============================================================
-- Thread de Atualização Automática
--============================================================
CreateThread(function()
  -- Aguardar inicialização
  Wait(15000)

  -- Definir próxima reunião COPOM
  PolicyState.copom.nextMeeting = os.time() + Config.COPOMMeetingInterval

  while true do
    Wait(Config.UpdateInterval)

    -- Calcular inflação
    MP.CalculateInflation()

    -- Verificar se é hora de reunião COPOM
    MP.COPOMMeeting()

    PolicyState.lastUpdate = os.time()
  end
end)

--============================================================
-- Thread de Autonomia Econômica
--============================================================
CreateThread(function()
  Wait(20000)

  while true do
    local interval = (Config.Inflation and Config.Inflation.AdjustIntervalHours or 6)
    MP.ReviewAutonomy()
    Wait(interval * 60 * 60 * 1000)
  end
end)

--============================================================
-- Garantir Tabela de Histórico
--============================================================
CreateThread(function()
  if not MySQL then return end

  Wait(2000)

  pcall(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_selic_history (
        id INT AUTO_INCREMENT PRIMARY KEY,
        selic DOUBLE NOT NULL,
        decision VARCHAR(16),
        inflation DOUBLE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
  end)

  U.dbg('[Monetary Policy] SELIC history table ensured')
end)

--============================================================
-- Exports
--============================================================
exports('GetSELIC', function() return PolicyState.selic end)
exports('GetInflation', function() return PolicyState.inflation.annual end)
exports('GetMonthlyInflation', function() return PolicyState.inflation.monthly end)
exports('AdjustPriceForInflation', MP.AdjustPriceForInflation)
exports('GetMonetaryPolicyReport', MP.GetReport)
exports('AdjustIPCCategory', MP.AdjustIPCCategory)
exports('ForceCOPOMMeeting', MP.COPOMMeeting)

print('^2[space_economy]^7 Monetary Policy loaded - SELIC: ' .. string.format('%.2f%%', PolicyState.selic * 100))
