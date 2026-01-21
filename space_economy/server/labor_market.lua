--============================================================
-- space_economy - server/labor_market.lua
-- Sistema de Mercado de Trabalho
-- Salário Mínimo Dinâmico, Taxa de Desemprego
--============================================================
SE = SE or {}
SE.LaborMarket = SE.LaborMarket or {}

local U = SE.Util
local LM = SE.LaborMarket

--============================================================
-- Estado do Mercado de Trabalho
--============================================================
local LaborState = {
  minimumWage = 2000,           -- Salário mínimo inicial
  lastAdjustment = 0,
  adjustmentHistory = {},

  unemployment = {
    rate = 0.05,                -- 5% inicial
    total = 0,
    employed = 0,
  },

  sectors = {},
}

--============================================================
-- Setores de Trabalho
--============================================================
local Sectors = {
  {
    id = 'police',
    name = 'Polícia',
    icon = '👮',
    baseMultiplier = 1.5,      -- 1.5x o salário mínimo
    minSalary = 3000,
    maxSalary = 16000,
    maxJobs = 50,
    currentJobs = 0,
  },
  {
    id = 'ambulance',
    name = 'Paramédico',
    icon = '🚑',
    baseMultiplier = 2.0,
    minSalary = 4000,
    maxSalary = 20000,
    maxJobs = 30,
    currentJobs = 0,
  },
  {
    id = 'mechanic',
    name = 'Mecânico',
    icon = '🔧',
    baseMultiplier = 1.2,
    minSalary = 2400,
    maxSalary = 10000,
    maxJobs = 40,
    currentJobs = 0,
  },
  {
    id = 'taxi',
    name = 'Taxista',
    icon = '🚕',
    baseMultiplier = 1.1,
    minSalary = 2200,
    maxSalary = 8000,
    maxJobs = 60,
    currentJobs = 0,
  },
  {
    id = 'trucker',
    name = 'Caminhoneiro',
    icon = '🚛',
    baseMultiplier = 1.4,
    minSalary = 2800,
    maxSalary = 12000,
    maxJobs = 40,
    currentJobs = 0,
  },
  {
    id = 'lawyer',
    name = 'Advogado',
    icon = '⚖️',
    baseMultiplier = 2.5,
    minSalary = 5000,
    maxSalary = 25000,
    maxJobs = 20,
    currentJobs = 0,
  },
  {
    id = 'reporter',
    name = 'Jornalista',
    icon = '📰',
    baseMultiplier = 1.75,
    minSalary = 3500,
    maxSalary = 15000,
    maxJobs = 15,
    currentJobs = 0,
  },
  {
    id = 'garbage',
    name = 'Lixeiro',
    icon = '🗑️',
    baseMultiplier = 1.05,
    minSalary = 2100,
    maxSalary = 6000,
    maxJobs = 30,
    currentJobs = 0,
  },
}

--============================================================
-- Configuração
--============================================================
local Config = {
  AdjustmentInterval = 7200,    -- Ajustar a cada 2 horas (em segundos)
  MinAdjustment = -0.05,        -- Máximo -5% por ajuste
  MaxAdjustment = 0.15,         -- Máximo +15% por ajuste
}

--============================================================
-- Calcular Taxa de Desemprego
--============================================================
function LM.CalculateUnemployment()
  local totalPlayers = #GetPlayers()
  local employed = 0

  -- Contar quantos players têm job
  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum and SE.Integrations then
      local job = SE.Bridge.GetJob(srcNum)
      if job and job.name and job.name ~= 'unemployed' then
        employed = employed + 1
      end
    end
  end

  -- Atualizar contadores por setor
  for _, sector in ipairs(Sectors) do
    sector.currentJobs = 0
  end

  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum and SE.Integrations then
      local job = SE.Bridge.GetJob(srcNum)
      if job and job.name then
        for _, sector in ipairs(Sectors) do
          if sector.id == job.name then
            sector.currentJobs = sector.currentJobs + 1
            break
          end
        end
      end
    end
  end

  -- Base populacional (preferir população ativa do Economy Monitor)
  local populationBase = totalPlayers
  if SE.EconomyMonitor and SE.EconomyMonitor.GetReport then
    local report = SE.EconomyMonitor.GetReport()
    local activePop = report and report.indicators and report.indicators.populationActive
    if activePop and activePop > 0 then
      populationBase = activePop
    end
  end

  -- Calcular taxa
  local unemployed = math.max(populationBase - employed, 0)
  local unemploymentRate = populationBase > 0 and (unemployed / populationBase) or 0

  LaborState.unemployment = {
    rate = unemploymentRate,
    total = unemployed,
    employed = employed,
  }

  return unemploymentRate
end

--============================================================
-- Ajustar Salário Mínimo
--============================================================
function LM.AdjustMinimumWage()
  local now = os.time()

  -- Verificar intervalo
  if LaborState.lastAdjustment > 0 and (now - LaborState.lastAdjustment) < Config.AdjustmentInterval then
    return
  end

  -- Fatores de ajuste
  local inflationRate = 0
  local pibGrowth = 0
  local unemploymentRate = LM.CalculateUnemployment()

  -- Pegar inflação
  if SE.MonetaryPolicy then
    inflationRate = SE.MonetaryPolicy.GetMonthlyInflation() or 0
  end

  -- Pegar crescimento do PIB (simplificado)
  if SE.EconomyMonitor then
    local report = SE.EconomyMonitor.GetReport()
    pibGrowth = report.pib.total > 0 and 0.02 or -0.01  -- Simulado
  end

  -- Calcular ajuste
  -- Salário mínimo deve acompanhar inflação + parte do crescimento do PIB
  local adjustment = inflationRate + (pibGrowth * 0.5)

  -- Limitar ajuste
  adjustment = math.max(Config.MinAdjustment, math.min(Config.MaxAdjustment, adjustment))

  -- Aplicar ajuste
  local oldWage = LaborState.minimumWage
  local newWage = math.floor(oldWage * (1 + adjustment))

  LaborState.minimumWage = newWage
  LaborState.lastAdjustment = now

  -- Adicionar ao histórico
  table.insert(LaborState.adjustmentHistory, {
    timestamp = now,
    oldWage = oldWage,
    newWage = newWage,
    adjustment = adjustment,
    inflation = inflationRate,
    pibGrowth = pibGrowth,
  })

  -- Limitar histórico
  if #LaborState.adjustmentHistory > 50 then
    table.remove(LaborState.adjustmentHistory, 1)
  end

  U.dbg(('[Labor Market] Minimum wage adjusted: $%d → $%d (%+.2f%%)'):format(
    oldWage,
    newWage,
    adjustment * 100
  ))

  -- Notificar admins
  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum and SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(srcNum) then
      TriggerClientEvent('ox_lib:notify', srcNum, {
        type = 'info',
        title = 'Salário Mínimo Ajustado',
        description = string.format('Novo valor: $%s (%+.1f%%)',
          U.formatNumber(newWage),
          adjustment * 100
        ),
        duration = 10000,
      })
    end
  end

  return newWage
end

--============================================================
-- Obter Piso Salarial do Setor
--============================================================
function LM.GetSectorMinSalary(sectorId)
  for _, sector in ipairs(Sectors) do
    if sector.id == sectorId then
      return math.max(sector.minSalary, LaborState.minimumWage * sector.baseMultiplier)
    end
  end

  return LaborState.minimumWage
end

--============================================================
-- Obter Relatório do Mercado de Trabalho
--============================================================
function LM.GetReport()
  LM.CalculateUnemployment()

  return {
    minimumWage = LaborState.minimumWage,
    lastAdjustment = LaborState.lastAdjustment,

    unemployment = LaborState.unemployment,

    sectors = (function()
      local result = {}
      for _, sector in ipairs(Sectors) do
        table.insert(result, {
          id = sector.id,
          name = sector.name,
          icon = sector.icon,
          minSalary = LM.GetSectorMinSalary(sector.id),
          maxSalary = sector.maxSalary,
          currentJobs = sector.currentJobs,
          maxJobs = sector.maxJobs,
          occupancyRate = sector.maxJobs > 0 and (sector.currentJobs / sector.maxJobs) or 0,
        })
      end
      return result
    end)(),
  }
end

--============================================================
-- Comando: Relatório de Trabalho
--============================================================
RegisterCommand('eco_trabalho', function(source, args)
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

  local report = LM.GetReport()

  print('\n========================================')
  print('MERCADO DE TRABALHO')
  print('========================================')
  print(string.format('Salário Mínimo: $%s', U.formatNumber(report.minimumWage)))
  print(string.format('Taxa de Desemprego: %.1f%%', report.unemployment.rate * 100))
  print(string.format('Empregados: %d / %d',
    report.unemployment.employed,
    report.unemployment.employed + report.unemployment.total
  ))
  print('')
  print('SETORES:')

  for _, sector in ipairs(report.sectors) do
    print(string.format('%s %-15s | Piso: $%-6s | Teto: $%-6s | Vagas: %2d/%2d (%.0f%%)',
      sector.icon,
      sector.name,
      U.formatNumber(sector.minSalary),
      U.formatNumber(sector.maxSalary),
      sector.currentJobs,
      sector.maxJobs,
      sector.occupancyRate * 100
    ))
  end

  print('========================================\n')

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Relatório gerado no console'
    })
  end
end, false)

--============================================================
-- Comando: Forçar Ajuste de Salário
--============================================================
RegisterCommand('eco_ajustar_salario', function(source, args)
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

  -- Forçar ajuste
  LaborState.lastAdjustment = 0
  local newWage = LM.AdjustMinimumWage()

  print(string.format('[Labor Market] Forced adjustment: $%s', U.formatNumber(newWage)))

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Salário ajustado: $' .. U.formatNumber(newWage)
    })
  end
end, false)

--============================================================
-- Thread de Ajuste Automático
--============================================================
CreateThread(function()
  -- Aguardar inicialização
  Wait(60000)

  while true do
    -- Verificar a cada 1 hora
    Wait(3600000)

    LM.AdjustMinimumWage()
  end
end)

--============================================================
-- Thread de Atualização de Desemprego
--============================================================
CreateThread(function()
  Wait(30000)

  while true do
    Wait(60000)  -- A cada 1 minuto

    LM.CalculateUnemployment()
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
      CREATE TABLE IF NOT EXISTS space_economy_wage_history (
        id INT AUTO_INCREMENT PRIMARY KEY,
        old_wage INT NOT NULL,
        new_wage INT NOT NULL,
        adjustment DOUBLE NOT NULL,
        inflation DOUBLE,
        pib_growth DOUBLE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_created_at (created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
  end)

  U.dbg('[Labor Market] Tables ensured')
end)

--============================================================
-- Exports
--============================================================
exports('GetMinimumWage', function() return LaborState.minimumWage end)
exports('GetUnemploymentRate', function() return LaborState.unemployment.rate end)
exports('GetSectorMinSalary', LM.GetSectorMinSalary)
exports('GetLaborMarketReport', LM.GetReport)
exports('ForceWageAdjustment', LM.AdjustMinimumWage)

print('^2[space_economy]^7 Labor Market loaded - Minimum wage: $' .. U.formatNumber(LaborState.minimumWage))
