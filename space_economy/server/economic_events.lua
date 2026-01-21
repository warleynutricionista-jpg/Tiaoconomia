--============================================================
-- space_economy - server/economic_events.lua
-- Sistema de Eventos Econômicos Dinâmicos
-- Crises, Booms, Eventos Setoriais
--============================================================
SE = SE or {}
SE.EconomicEvents = SE.EconomicEvents or {}

local U = SE.Util
local EE = SE.EconomicEvents
local EventConfig = (Config and Config.EconomicEvents) or {}

--============================================================
-- Estado dos Eventos
--============================================================
local EventState = {
  currentEvent = nil,
  eventEndTime = 0,
  history = {},
  outcomeMode = (EventConfig.Outcome and EventConfig.Outcome.Mode) or 'auto',
  selectedOutcome = nil,
}

--============================================================
-- Desfechos (Outcomes)
--============================================================
local Outcomes = {
  crisis = {
    {
      id = 'recuperacao_rapida',
      name = 'Recuperação Rápida',
      effects = {
        inflation = -0.03,
        unemployment = -0.02,
        confidence = 10,
      },
    },
    {
      id = 'recuperacao_lenta',
      name = 'Recuperação Lenta',
      effects = {
        unemployment = 0.02,
        confidence = -5,
      },
    },
    {
      id = 'neutro',
      name = 'Neutralização',
      effects = {},
    },
  },
  boom = {
    {
      id = 'pouso_suave',
      name = 'Pouso Suave',
      effects = {
        inflation = -0.01,
        confidence = 5,
      },
    },
    {
      id = 'superaquecimento',
      name = 'Superaquecimento',
      effects = {
        inflation = 0.03,
        selic = 0.01,
        confidence = -5,
      },
    },
    {
      id = 'neutro',
      name = 'Neutralização',
      effects = {},
    },
  },
  sector = {
    {
      id = 'normalizacao',
      name = 'Normalização Setorial',
      effects = {
        inflation = -0.01,
        confidence = 5,
      },
    },
    {
      id = 'pressao_inflacionaria',
      name = 'Pressão Inflacionária',
      effects = {
        inflation = 0.02,
        confidence = -3,
      },
    },
    {
      id = 'neutro',
      name = 'Neutralização',
      effects = {},
    },
  },
  special = {
    {
      id = 'impacto_positivo',
      name = 'Impacto Positivo',
      effects = {
        confidence = 10,
        pib = 0.05,
      },
    },
    {
      id = 'impacto_negativo',
      name = 'Impacto Negativo',
      effects = {
        confidence = -10,
        pib = -0.03,
      },
    },
    {
      id = 'neutro',
      name = 'Neutralização',
      effects = {},
    },
  },
}

local function getOutcomeSet(event)
  if event and type(event.outcomes) == 'table' then
    return event.outcomes
  end
  return Outcomes[event and event.type or ''] or {}
end

local function findOutcomeById(event, outcomeId)
  for _, outcome in ipairs(getOutcomeSet(event)) do
    if outcome.id == outcomeId then
      return outcome
    end
  end
  return nil
end

local function pickAutoOutcome(event)
  local inflation = 0
  if SE.MonetaryPolicy and SE.MonetaryPolicy.GetMonthlyInflation then
    inflation = SE.MonetaryPolicy.GetMonthlyInflation() or 0
  elseif SE.Server and SE.Server.GetInflationRate then
    inflation = SE.Server.GetInflationRate() - 1.0
  end

  local unemployment = 0.05
  if SE.LaborMarket and SE.LaborMarket.GetUnemploymentRate then
    unemployment = SE.LaborMarket.GetUnemploymentRate() or unemployment
  end

  local treasury = (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.GetBalance()) or 0
  local lowTreasury = (Config.Treasury and Config.Treasury.LowBalanceThreshold) or 100000

  if event.type == 'crisis' then
    if inflation <= 0.03 and unemployment <= 0.06 and treasury > lowTreasury then
      return findOutcomeById(event, 'recuperacao_rapida')
    end
    return findOutcomeById(event, 'recuperacao_lenta')
  end

  if event.type == 'boom' then
    if inflation >= 0.08 or treasury <= lowTreasury then
      return findOutcomeById(event, 'superaquecimento')
    end
    return findOutcomeById(event, 'pouso_suave')
  end

  if inflation >= 0.06 then
    return findOutcomeById(event, 'pressao_inflacionaria')
  end

  return findOutcomeById(event, 'normalizacao') or findOutcomeById(event, 'neutro')
end

local function resolveOutcome(event)
  local mode = EventState.outcomeMode or (EventConfig.Outcome and EventConfig.Outcome.Mode) or 'auto'
  if mode == 'none' then return nil, mode end

  if mode == 'manual' then
    if EventState.selectedOutcome then
      return findOutcomeById(event, EventState.selectedOutcome), mode
    end
    local fallback = (EventConfig.Outcome and EventConfig.Outcome.Default) or 'neutro'
    return findOutcomeById(event, fallback), mode
  end

  if mode == 'auto' then
    return pickAutoOutcome(event), mode
  end

  return findOutcomeById(event, (EventConfig.Outcome and EventConfig.Outcome.Default) or 'neutro'), mode
end

local function clamp(v, minv, maxv)
  return math.max(minv, math.min(maxv, v))
end

local function getMacroMultiplier()
  local mult = 1.0

  if SE.EconomyMonitor and SE.EconomyMonitor.GetReport then
    local report = SE.EconomyMonitor.GetReport()
    local indicators = report and report.indicators or {}

    local gini = tonumber(indicators.gini) or 0
    local velocity = tonumber(indicators.velocity) or 0

    if gini > 0.55 then
      mult = mult + math.min((gini - 0.55) * 0.5, 0.15)
    end

    if velocity > 1.2 then
      mult = mult + 0.10
    elseif velocity < 0.6 then
      mult = mult - 0.10
    end
  end

  local inflation = 0
  if SE.MonetaryPolicy and SE.MonetaryPolicy.GetMonthlyInflation then
    inflation = SE.MonetaryPolicy.GetMonthlyInflation() or 0
  end
  if inflation > 0.06 then
    mult = mult + 0.10
  end

  return clamp(mult, 0.6, 1.5)
end

--============================================================
-- Catálogo de Eventos
--============================================================
local Events = {
  -- ==================== CRISES ====================
  {
    id = 'crise_financeira',
    name = 'Crise Financeira',
    type = 'crisis',
    icon = '🔴',
    probability = 0.05,  -- 5%
    duration = { min = 7200, max = 14400 },  -- 2-4 horas
    effects = {
      pib = -0.15,           -- PIB -15%
      unemployment = 0.08,   -- Desemprego +8%
      inflation = 0.05,      -- Inflação +5%
      selic = 0.02,          -- SELIC +2%
      confidence = -30,      -- Confiança -30 pontos
      salary = -0.05,        -- Salários -5%
    },
    description = 'Crise financeira global afeta economia local',
  },

  {
    id = 'recessao',
    name = 'Recessão Econômica',
    type = 'crisis',
    icon = '🔴',
    probability = 0.08,
    duration = { min = 3600, max = 7200 },  -- 1-2 horas
    effects = {
      pib = -0.08,
      unemployment = 0.05,
      inflation = -0.02,
      selic = -0.005,
      confidence = -15,
    },
    description = 'Economia entra em recessão técnica',
  },

  -- ==================== BOOMS ====================
  {
    id = 'boom_economico',
    name = 'Boom Econômico',
    type = 'boom',
    icon = '🟢',
    probability = 0.10,
    duration = { min = 7200, max = 18000 },  -- 2-5 horas
    effects = {
      pib = 0.25,
      unemployment = -0.05,
      inflation = 0.03,
      selic = 0.005,
      confidence = 20,
      salary = 0.10,
    },
    description = 'Economia experimenta crescimento acelerado',
  },

  {
    id = 'crescimento_acelerado',
    name = 'Crescimento Acelerado',
    type = 'boom',
    icon = '🟢',
    probability = 0.12,
    duration = { min = 3600, max = 10800 },  -- 1-3 horas
    effects = {
      pib = 0.15,
      unemployment = -0.03,
      inflation = 0.02,
      salary = 0.05,
    },
    description = 'PIB cresce acima do esperado',
  },

  -- ==================== EVENTOS SETORIAIS ====================
  {
    id = 'crise_combustivel',
    name = 'Crise de Combustível',
    type = 'sector',
    icon = '🟠',
    probability = 0.07,
    duration = { min = 1800, max = 5400 },  -- 30min-1.5h
    effects = {
      ipc_transporte = 0.30,   -- Transporte +30%
      ipc_alimentacao = 0.10,  -- Alimentos +10% (logística)
      inflation = 0.05,
    },
    description = 'Escassez de combustível eleva preços',
  },

  {
    id = 'safra_recorde',
    name = 'Safra Recorde',
    type = 'sector',
    icon = '🟢',
    probability = 0.08,
    duration = { min = 3600, max = 7200 },
    effects = {
      ipc_alimentacao = -0.25,  -- Alimentos -25%
      inflation = -0.03,
      pib = 0.05,
    },
    description = 'Safra recorde reduz preços de alimentos',
  },

  {
    id = 'bolha_imobiliaria',
    name = 'Bolha Imobiliária',
    type = 'sector',
    icon = '🟠',
    probability = 0.06,
    duration = { min = 7200, max = 21600 },  -- 2-6 horas
    effects = {
      ipc_habitacao = 0.50,     -- Habitação +50%
      inflation = 0.10,
      pib = 0.08,
      selic = 0.01,
    },
    description = 'Especulação imobiliária eleva preços',
  },

  {
    id = 'greve_saude',
    name = 'Greve no Setor de Saúde',
    type = 'sector',
    icon = '🟠',
    probability = 0.05,
    duration = { min = 1800, max = 7200 },
    effects = {
      ipc_saude = 0.40,
      confidence = -10,
    },
    description = 'Greve afeta serviços de saúde',
  },

  -- ==================== EVENTOS ESPECIAIS ====================
  {
    id = 'inovacao_tecnologica',
    name = 'Inovação Tecnológica',
    type = 'special',
    icon = '✨',
    probability = 0.04,
    duration = { min = 10800, max = 21600 },  -- 3-6 horas
    effects = {
      pib = 0.20,
      unemployment = -0.02,
      salary = 0.08,
      confidence = 15,
    },
    description = 'Avanço tecnológico impulsiona economia',
  },

  {
    id = 'investimento_estrangeiro',
    name = 'Investimento Estrangeiro',
    type = 'special',
    icon = '💰',
    probability = 0.06,
    duration = { min = 5400, max = 14400 },  -- 1.5-4 horas
    effects = {
      pib = 0.12,
      treasury_bonus = 500000,  -- +$500k no tesouro
      confidence = 10,
    },
    description = 'Capital estrangeiro entra no país',
  },

  {
    id = 'desastre_natural',
    name = 'Desastre Natural',
    type = 'special',
    icon = '⚠️',
    probability = 0.03,
    duration = { min = 1800, max = 3600 },
    effects = {
      pib = -0.20,
      treasury_cost = 300000,   -- -$300k do tesouro
      inflation = 0.08,
      confidence = -20,
    },
    description = 'Desastre natural causa perdas econômicas',
  },

  {
    id = 'acordo_comercial',
    name = 'Novo Acordo Comercial',
    type = 'special',
    icon = '🤝',
    probability = 0.05,
    duration = { min = 7200, max = 14400 },
    effects = {
      pib = 0.10,
      ipc_transporte = -0.05,
      inflation = -0.02,
    },
    description = 'Acordo comercial beneficia economia',
  },
}

--============================================================
-- Sortear Evento Aleatório
--============================================================
function EE.RollRandomEvent()
  -- Não sortear se já tiver evento ativo
  if EventState.currentEvent then return nil end

  -- Calcular probabilidade total
  local totalProb = 0
  for _, event in ipairs(Events) do
    totalProb = totalProb + event.probability
  end

  -- Sortear
  local roll = math.random() * totalProb
  local cumulative = 0

  for _, event in ipairs(Events) do
    cumulative = cumulative + event.probability
    if roll <= cumulative then
      return event
    end
  end

  return nil
end

--============================================================
-- Disparar Evento
--============================================================
function EE.TriggerEvent(eventId)
  -- Encontrar evento
  local event = nil
  if type(eventId) == 'table' then
    event = eventId
  else
    for _, ev in ipairs(Events) do
      if ev.id == eventId then
        event = ev
        break
      end
    end
  end

  if not event then
    U.dbg('[Economic Events] Event not found: ' .. tostring(eventId))
    return false
  end

  -- Já tem evento ativo?
  if EventState.currentEvent then
    U.dbg('[Economic Events] Event already active: ' .. EventState.currentEvent.name)
    return false
  end

  -- Calcular duração
  local duration = math.random(event.duration.min, event.duration.max)

  -- Ativar evento
  EventState.currentEvent = event
  EventState.eventEndTime = os.time() + duration
  EventState.outcomeMode = (EventConfig.Outcome and EventConfig.Outcome.Mode) or 'auto'
  EventState.selectedOutcome = nil

  U.dbg(('[Economic Events] %s "%s" triggered (duration: %ds)'):format(
    event.icon,
    event.name,
    duration
  ))

  -- Aplicar efeitos
  EE.ApplyEffects(event.effects, true, { event_id = event.id })

  -- Notificar todos os players
  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum then
      TriggerClientEvent('ox_lib:notify', srcNum, {
        type = event.type == 'crisis' and 'error' or (event.type == 'boom' and 'success' or 'info'),
        title = event.icon .. ' ' .. event.name,
        description = event.description,
        duration = 15000,
      })
    end
  end

  -- Adicionar ao histórico
  table.insert(EventState.history, {
    event = event.id,
    name = event.name,
    startTime = os.time(),
    endTime = EventState.eventEndTime,
    outcome = nil,
    outcomeMode = EventState.outcomeMode,
  })

  -- Limitar histórico a 10
  if #EventState.history > 10 then
    table.remove(EventState.history, 1)
  end

  return true
end

--============================================================
-- Aplicar Efeitos do Evento
--============================================================
function EE.ApplyEffects(effects, apply, context)
  local multiplier = (apply and 1 or -1) * getMacroMultiplier()
  context = context or {}

  -- PIB (via Economy Monitor)
  if effects.pib and SE.EconomyMonitor then
    -- Efeito será natural via transações
    U.dbg(('[Economic Events] PIB effect: %+.1f%%'):format(effects.pib * 100 * multiplier))
  end

  -- Inflação (via Monetary Policy)
  if effects.inflation and SE.MonetaryPolicy then
    local current = SE.MonetaryPolicy.GetMonthlyInflation() or 0
    local newInflation = current + (effects.inflation * multiplier)
    -- Aplicado automaticamente pelo sistema
    U.dbg(('[Economic Events] Inflation effect: %+.1f%%'):format(effects.inflation * 100 * multiplier))
  end

  -- SELIC (via Monetary Policy)
  if effects.selic and SE.MonetaryPolicy then
    local current = SE.MonetaryPolicy.GetSELIC() or 0
    -- COPOM ajustará automaticamente
    U.dbg(('[Economic Events] SELIC pressure: %+.2f%%'):format(effects.selic * 100 * multiplier))
  end

  -- IPC por categoria
  if SE.MonetaryPolicy then
    if effects.ipc_alimentacao then
      SE.MonetaryPolicy.AdjustIPCCategory('alimentacao', effects.ipc_alimentacao * 100 * multiplier)
    end
    if effects.ipc_transporte then
      SE.MonetaryPolicy.AdjustIPCCategory('transporte', effects.ipc_transporte * 100 * multiplier)
    end
    if effects.ipc_habitacao then
      SE.MonetaryPolicy.AdjustIPCCategory('habitacao', effects.ipc_habitacao * 100 * multiplier)
    end
    if effects.ipc_saude then
      SE.MonetaryPolicy.AdjustIPCCategory('saude', effects.ipc_saude * 100 * multiplier)
    end
    if effects.ipc_lazer then
      SE.MonetaryPolicy.AdjustIPCCategory('lazer', effects.ipc_lazer * 100 * multiplier)
    end
  end

  -- Tesouro
  if effects.treasury_bonus and apply then
    local amount = effects.treasury_bonus
    if SE.Server and SE.Server.AddToVault then
      SE.Server.AddToVault(amount, 'evento_economico', {
        from_type = 'system',
        to_type = 'treasury',
        event_id = context.event_id,
      })
      U.dbg(('[Economic Events] Treasury bonus: +$%d'):format(amount))
    end
  end

  if effects.treasury_cost and apply then
    local amount = effects.treasury_cost
    if SE.Server and SE.Server.RemoveFromVault then
      SE.Server.RemoveFromVault(amount, 'evento_economico', {
        from_type = 'treasury',
        to_type = 'system',
        event_id = context.event_id,
      })
      U.dbg(('[Economic Events] Treasury cost: -$%d'):format(amount))
    end
  end

  -- Salários (via Labor Market - se existir)
  if effects.salary and SE.LaborMarket then
    -- Será aplicado pelo sistema de mercado de trabalho
    U.dbg(('[Economic Events] Salary effect: %+.1f%%'):format(effects.salary * 100 * multiplier))
  end

  -- Desemprego (via Labor Market - se existir)
  if effects.unemployment and SE.LaborMarket then
    U.dbg(('[Economic Events] Unemployment effect: %+.1f%%'):format(effects.unemployment * 100 * multiplier))
  end
end

--============================================================
-- Finalizar Evento Ativo
--============================================================
function EE.EndEvent()
  if not EventState.currentEvent then return end

  local event = EventState.currentEvent

  local outcome, outcomeMode = resolveOutcome(event)

  U.dbg(('[Economic Events] %s "%s" ended'):format(event.icon, event.name))

  -- Reverter efeitos (parcialmente)
  EE.ApplyEffects(event.effects, false, { event_id = event.id })

  if outcome then
    EE.ApplyEffects(outcome.effects, true, { event_id = event.id, outcome_id = outcome.id })
    U.dbg(('[Economic Events] Outcome "%s" aplicado (%s)'):format(outcome.id, outcomeMode))
  end

  -- Notificar players
  for _, src in ipairs(GetPlayers()) do
    local srcNum = tonumber(src)
    if srcNum then
      TriggerClientEvent('ox_lib:notify', srcNum, {
        type = 'info',
        title = '📈 Evento Finalizado',
        description = event.name .. ' foi superado',
        duration = 10000,
      })
    end
  end

  -- Limpar evento
  EventState.currentEvent = nil
  EventState.eventEndTime = 0
  EventState.selectedOutcome = nil

  local last = EventState.history[#EventState.history]
  if last and last.event == event.id and not last.outcome then
    last.outcome = outcome and outcome.id or nil
    last.outcomeMode = outcomeMode
  end
end

--============================================================
-- Obter Evento Atual
--============================================================
function EE.GetCurrentEvent()
  if not EventState.currentEvent then return nil end

  return {
    event = EventState.currentEvent,
    endTime = EventState.eventEndTime,
    timeRemaining = math.max(0, EventState.eventEndTime - os.time()),
  }
end

--============================================================
-- Comando: Ver Evento Ativo
--============================================================
RegisterCommand('eco_evento', function(source, args)
  local src = tonumber(source)

  local current = EE.GetCurrentEvent()

  if not current then
    print('[Economic Events] Nenhum evento ativo no momento')

    if src ~= 0 then
      TriggerClientEvent('ox_lib:notify', src, {
        type = 'info',
        description = 'Nenhum evento econômico ativo'
      })
    end
    return
  end

  local event = current.event
  local remaining = math.floor(current.timeRemaining / 60)
  local outcomeInfo = EventState.selectedOutcome or EventState.outcomeMode or 'auto'

  print(string.format('\n%s %s', event.icon, event.name))
  print(event.description)
  print(string.format('Tempo restante: %d minutos\n', remaining))
  print(string.format('Desfecho: %s\n', outcomeInfo))

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'info',
      title = event.icon .. ' ' .. event.name,
      description = string.format('%s (%d min restantes) | Desfecho: %s', event.description, remaining, outcomeInfo),
      duration = 10000,
    })
  end
end, false)

--============================================================
-- Comando: Disparar Evento Manualmente
--============================================================
RegisterCommand('eco_trigger', function(source, args)
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

  local eventId = args[1]

  if not eventId then
    print('Uso: /eco_trigger <evento_id>')
    print('Eventos disponíveis:')
    for _, ev in ipairs(Events) do
      print(string.format('  %s - %s (%s)', ev.id, ev.name, ev.type))
    end
    return
  end

  local success = EE.TriggerEvent(eventId)

  if success then
    print('[Economic Events] Evento disparado: ' .. eventId)

    if src ~= 0 then
      TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        description = 'Evento disparado'
      })
    end
  else
    print('[Economic Events] Falha ao disparar evento')
  end
end, false)

--============================================================
-- Comando: Definir Desfecho do Evento
--============================================================
RegisterCommand('eco_desfecho', function(source, args)
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

  if not EventState.currentEvent then
    if src ~= 0 then
      TriggerClientEvent('ox_lib:notify', src, {
        type = 'info',
        description = 'Nenhum evento ativo para definir desfecho'
      })
    end
    print('[Economic Events] Nenhum evento ativo para definir desfecho')
    return
  end

  local modeOrId = args[1]
  if not modeOrId then
    print('Uso: /eco_desfecho <auto|manual|none|random|outcome_id>')
    print('Outcomes disponíveis:')
    for _, outcome in ipairs(getOutcomeSet(EventState.currentEvent)) do
      print(string.format('  %s - %s', outcome.id, outcome.name))
    end
    return
  end

  modeOrId = tostring(modeOrId)
  if modeOrId == 'auto' or modeOrId == 'manual' or modeOrId == 'none' then
    EventState.outcomeMode = modeOrId
    EventState.selectedOutcome = nil
  elseif modeOrId == 'random' then
    local outcomes = getOutcomeSet(EventState.currentEvent)
    if #outcomes > 0 then
      local choice = outcomes[math.random(1, #outcomes)]
      EventState.outcomeMode = 'manual'
      EventState.selectedOutcome = choice.id
    end
  else
    local found = findOutcomeById(EventState.currentEvent, modeOrId)
    if not found then
      print('[Economic Events] Desfecho não encontrado: ' .. modeOrId)
      return
    end
    EventState.outcomeMode = 'manual'
    EventState.selectedOutcome = found.id
  end

  local status = EventState.selectedOutcome or EventState.outcomeMode
  print(('[Economic Events] Desfecho definido: %s'):format(status))
  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = ('Desfecho definido: %s'):format(status)
    })
  end
end, false)

--============================================================
-- Comando: Histórico de Eventos
--============================================================
RegisterCommand('eco_historico', function(source, args)
  local src = tonumber(source)

  print('\n========================================')
  print('HISTÓRICO DE EVENTOS ECONÔMICOS')
  print('========================================')

  if #EventState.history == 0 then
    print('Nenhum evento registrado ainda')
  else
    for i, record in ipairs(EventState.history) do
      local duration = record.endTime - record.startTime
      print(string.format('%d. %s (%d min) - %s',
        i,
        record.name,
        math.floor(duration / 60),
        os.date('%H:%M', record.startTime)
      ))
      if record.outcome then
        print(string.format('   Desfecho: %s (%s)', record.outcome, record.outcomeMode or 'auto'))
      end
    end
  end

  print('========================================\n')

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Histórico gerado no console'
    })
  end
end, false)

--============================================================
-- Thread de Eventos Automáticos
--============================================================
CreateThread(function()
  -- Aguardar inicialização
  Wait(30000)

  while true do
    local intervalMinutes = EventConfig.AutoIntervalMinutes or 30
    local intervalMs = math.max(1, intervalMinutes) * 60000
    -- Verificar no intervalo configurado
    Wait(intervalMs)

    -- Verificar se evento terminou
    if EventState.currentEvent then
      if os.time() >= EventState.eventEndTime then
        EE.EndEvent()
      end
    end

    if EventConfig.AutoTrigger ~= false and not EventState.currentEvent then
      -- Tentar sortear novo evento
      local event = EE.RollRandomEvent()
      if event then
        EE.TriggerEvent(event)
      end
    end
  end
end)

-- Thread para verificar fim de eventos (mais frequente)
CreateThread(function()
  Wait(30000)

  while true do
    Wait(60000)  -- A cada 1 minuto

    if EventState.currentEvent and os.time() >= EventState.eventEndTime then
      EE.EndEvent()
    end
  end
end)

--============================================================
-- Exports
--============================================================
exports('TriggerEconomicEvent', EE.TriggerEvent)
exports('GetCurrentEvent', EE.GetCurrentEvent)
exports('GetEventHistory', function() return EventState.history end)

print('^2[space_economy]^7 Economic Events loaded - ' .. #Events .. ' events available')
