--============================================================
-- space_economy - server/economic_events.lua
-- Sistema de Eventos Econômicos Dinâmicos
-- MELHORIA CRÍTICA #4 - Crises, Booms e Ciclos Econômicos
--============================================================
SE = SE or {}
SE.EconomicEvents = SE.EconomicEvents or {}

local U = SE.Util
local EE = SE.EconomicEvents

--============================================================
-- Catálogo de Eventos Econômicos
--============================================================
EE.EventCatalog = {
  -- CRISES
  {
    id = 'crise_financeira',
    nome = '🔴 Crise Financeira',
    tipo = 'crise',
    probabilidade = 0.03,  -- 3% por check
    duracao_min = 7200000,  -- 2 horas mínimo
    duracao_max = 14400000, -- 4 horas máximo
    efeitos = {
      pib_multiplicador = 0.85,       -- PIB cai 15%
      desemprego_ajuste = 0.08,       -- +8% desemprego
      inflacao_ajuste = 0.05,         -- +5% inflação
      selic_ajuste = 0.02,            -- SELIC sobe 2%
      confianca_ajuste = -30,         -- Confiança despenca
      salario_multiplicador = 0.95,   -- Salários caem 5%
    },
    mensagem_inicio = '⚠️ CRISE FINANCEIRA declarada! Economia em recessão. Prepare-se para tempos difíceis.',
    mensagem_fim = '📈 Crise financeira superada. Economia retoma crescimento gradual.',
    causas_possiveis = {
      'Dívida pública atingiu níveis críticos',
      'Massa monetária cresceu descontroladamente',
      'Falência de grandes empresas da cidade',
      'Desconfiança generalizada no sistema financeiro',
    },
  },

  {
    id = 'recessao',
    nome = '🟠 Recessão Econômica',
    tipo = 'recessao',
    probabilidade = 0.05,
    duracao_min = 3600000,   -- 1 hora
    duracao_max = 7200000,   -- 2 horas
    efeitos = {
      pib_multiplicador = 0.92,
      desemprego_ajuste = 0.05,
      inflacao_ajuste = 0.02,
      selic_ajuste = 0.01,
      confianca_ajuste = -20,
      salario_multiplicador = 0.98,
    },
    mensagem_inicio = '🟠 Recessão econômica detectada. PIB em queda.',
    mensagem_fim = '📊 Recessão finalizada. Sinais de recuperação.',
    causas_possiveis = {
      'Redução no consumo das famílias',
      'Queda nos investimentos',
      'Exportações em baixa',
    },
  },

  -- BOOMS
  {
    id = 'boom_economico',
    nome = '🟢 Boom Econômico',
    tipo = 'boom',
    probabilidade = 0.02,
    duracao_min = 7200000,
    duracao_max = 18000000,  -- 5 horas
    efeitos = {
      pib_multiplicador = 1.25,
      desemprego_ajuste = -0.05,
      inflacao_ajuste = 0.08,  -- Risco: inflação sobe
      selic_ajuste = 0.01,
      confianca_ajuste = 40,
      salario_multiplicador = 1.10,
    },
    mensagem_inicio = '🎉 BOOM ECONÔMICO! Economia aquecida, empregos em alta!',
    mensagem_fim = '📉 Boom econômico arrefece. Economia volta ao normal.',
    causas_possiveis = {
      'Descoberta de novos recursos',
      'Investimentos massivos',
      'Confiança do consumidor em alta',
      'Inovações tecnológicas',
    },
  },

  {
    id = 'crescimento_acelerado',
    nome = '🟢 Crescimento Acelerado',
    tipo = 'boom',
    probabilidade = 0.04,
    duracao_min = 3600000,
    duracao_max = 10800000,  -- 3 horas
    efeitos = {
      pib_multiplicador = 1.15,
      desemprego_ajuste = -0.03,
      inflacao_ajuste = 0.04,
      selic_ajuste = 0.005,
      confianca_ajuste = 25,
      salario_multiplicador = 1.05,
    },
    mensagem_inicio = '📈 Economia cresce acima da média! Oportunidades surgem.',
    mensagem_fim = '➡️ Crescimento volta ao ritmo normal.',
    causas_possiveis = {
      'Aumento da produtividade',
      'Exportações em alta',
      'Consumo aquecido',
    },
  },

  -- EVENTOS SETORIAIS
  {
    id = 'crise_combustivel',
    nome = '⛽ Crise de Combustível',
    tipo = 'setorial',
    setor = 'transporte',
    probabilidade = 0.04,
    duracao_min = 1800000,   -- 30 min
    duracao_max = 5400000,   -- 1.5 horas
    efeitos = {
      ipc_transporte = 0.30,   -- +30% no transporte
      ipc_alimentacao = 0.10,  -- +10% alimentos (frete)
      inflacao_ajuste = 0.05,
    },
    mensagem_inicio = '⛽ ALERTA: Escassez de combustível! Preços em alta.',
    mensagem_fim = '⛽ Abastecimento de combustível normalizado.',
  },

  {
    id = 'safra_recorde',
    nome = '🌾 Safra Recorde',
    tipo = 'setorial',
    setor = 'alimentacao',
    probabilidade = 0.03,
    duracao_min = 3600000,
    duracao_max = 7200000,
    efeitos = {
      ipc_alimentacao = -0.25,  -- -25% nos alimentos
      inflacao_ajuste = -0.03,
      confianca_ajuste = 10,
    },
    mensagem_inicio = '🌾 Safra recorde! Preços dos alimentos em queda.',
    mensagem_fim = '🌾 Safra normalizada.',
  },

  {
    id = 'bolha_imobiliaria',
    nome = '🏠 Bolha Imobiliária',
    tipo = 'setorial',
    setor = 'habitacao',
    probabilidade = 0.02,
    duracao_min = 7200000,
    duracao_max = 21600000,  -- 6 horas
    efeitos = {
      ipc_habitacao = 0.50,    -- +50% nos imóveis
      inflacao_ajuste = 0.10,
      selic_ajuste = 0.02,
    },
    mensagem_inicio = '🏠 BOLHA IMOBILIÁRIA! Preços de imóveis disparando.',
    mensagem_fim = '🏠 Mercado imobiliário se corrige. Preços em ajuste.',
  },

  -- EVENTOS POSITIVOS
  {
    id = 'inovacao_tecnologica',
    nome = '💡 Revolução Tecnológica',
    tipo = 'positivo',
    probabilidade = 0.02,
    duracao_min = 10800000,  -- 3 horas
    duracao_max = 21600000,  -- 6 horas
    efeitos = {
      pib_multiplicador = 1.20,
      desemprego_ajuste = -0.04,
      confianca_ajuste = 30,
      salario_multiplicador = 1.08,
    },
    mensagem_inicio = '💡 INOVAÇÃO! Nova tecnologia revoluciona a cidade.',
    mensagem_fim = '💡 Tecnologia implementada com sucesso.',
  },

  {
    id = 'investimento_estrangeiro',
    nome = '💰 Investimento Estrangeiro',
    tipo = 'positivo',
    probabilidade = 0.03,
    duracao_min = 5400000,
    duracao_max = 14400000,
    efeitos = {
      pib_multiplicador = 1.12,
      desemprego_ajuste = -0.03,
      confianca_ajuste = 20,
      tesouro_boost = 500000,  -- Injeção direta no tesouro
    },
    mensagem_inicio = '💰 Investidores estrangeiros chegam à cidade!',
    mensagem_fim = '💰 Investimento estrangeiro concluído.',
  },

  -- DESASTRES
  {
    id = 'desastre_natural',
    nome = '🌪️ Desastre Natural',
    tipo = 'desastre',
    probabilidade = 0.01,  -- Raro
    duracao_min = 1800000,
    duracao_max = 3600000,
    efeitos = {
      pib_multiplicador = 0.80,
      inflacao_ajuste = 0.15,
      confianca_ajuste = -40,
      tesouro_custo = 300000,  -- Custo de recuperação
    },
    mensagem_inicio = '🌪️ DESASTRE NATURAL! Danos severos à infraestrutura.',
    mensagem_fim = '🌪️ Cidade recuperada do desastre.',
  },
}

--============================================================
-- Estado Atual de Eventos
--============================================================
EE.State = {
  evento_ativo = nil,
  eventos_historico = {},
  ultimo_check = 0,
}

--============================================================
-- Configuração
--============================================================
local Config = {
  CheckIntervalMs = 1800000,  -- Verificar a cada 30 minutos
  MaxEventosSimultaneos = 1,  -- Apenas 1 evento por vez (pode aumentar)
  EnableNotifications = true,
  EnableAutoEvents = true,
}

--============================================================
-- Verificar e Disparar Evento
--============================================================
function EE.CheckAndTrigger()
  if not Config.EnableAutoEvents then return end

  -- Já tem evento ativo?
  if EE.State.evento_ativo then return end

  -- Sortear evento baseado em probabilidades
  for _, evento in ipairs(EE.EventCatalog) do
    local roll = math.random()

    if roll < evento.probabilidade then
      EE.TriggerEvent(evento.id)
      break
    end
  end

  EE.State.ultimo_check = os.time()
end

--============================================================
-- Disparar Evento Específico
--============================================================
function EE.TriggerEvent(eventoId, forcado)
  -- Buscar evento
  local evento = nil
  for _, e in ipairs(EE.EventCatalog) do
    if e.id == eventoId then
      evento = e
      break
    end
  end

  if not evento then
    U.dbg(('[EconomicEvents] Evento não encontrado: %s'):format(eventoId))
    return false
  end

  -- Já tem evento ativo?
  if EE.State.evento_ativo and not forcado then
    U.dbg('[EconomicEvents] Já existe evento ativo')
    return false
  end

  -- Duração aleatória
  local duracao = math.random(evento.duracao_min, evento.duracao_max)

  -- Ativar evento
  EE.State.evento_ativo = {
    id = evento.id,
    nome = evento.nome,
    tipo = evento.tipo,
    inicio = os.time(),
    fim = os.time() + math.floor(duracao / 1000),
    duracao_ms = duracao,
    efeitos = evento.efeitos,
    setor = evento.setor,
  }

  -- Escolher causa aleatória (se houver)
  local causa = 'Evento econômico automático'
  if evento.causas_possiveis and #evento.causas_possiveis > 0 then
    causa = evento.causas_possiveis[math.random(#evento.causas_possiveis)]
  end

  EE.State.evento_ativo.causa = causa

  -- Aplicar efeitos imediatos
  EE.ApplyEffects(evento.efeitos)

  -- Notificar todos
  if Config.EnableNotifications then
    TriggerClientEvent('chat:addMessage', -1, {
      args = { '[ECONOMIA]', evento.mensagem_inicio or ('Evento: ' .. evento.nome) }
    })
  end

  U.dbg(('[EconomicEvents] Evento iniciado: %s | Duração: %.1f min'):format(
    evento.nome,
    duracao / 60000
  ))

  -- Agendar fim do evento
  SetTimeout(duracao, function()
    EE.EndEvent()
  end)

  return true
end

--============================================================
-- Aplicar Efeitos do Evento
--============================================================
function EE.ApplyEffects(efeitos)
  if not efeitos then return end

  -- Ajustar SELIC
  if efeitos.selic_ajuste and SE.MonetaryPolicy then
    local selic_atual = SE.MonetaryPolicy.State.selic_atual or 0.0075
    SE.MonetaryPolicy.State.selic_atual = U.clamp(
      selic_atual + efeitos.selic_ajuste,
      0.002,
      0.15
    )
  end

  -- Ajustar Inflação
  if efeitos.inflacao_ajuste and SE.MonetaryPolicy then
    SE.MonetaryPolicy.State.inflacao_acumulada =
      SE.MonetaryPolicy.State.inflacao_acumulada + efeitos.inflacao_ajuste
  end

  -- Ajustar IPC por categoria
  if efeitos.ipc_alimentacao and SE.MonetaryPolicy then
    SE.MonetaryPolicy.AtualizarCategoriaIPC('alimentacao', efeitos.ipc_alimentacao)
  end
  if efeitos.ipc_transporte and SE.MonetaryPolicy then
    SE.MonetaryPolicy.AtualizarCategoriaIPC('transporte', efeitos.ipc_transporte)
  end
  if efeitos.ipc_habitacao and SE.MonetaryPolicy then
    SE.MonetaryPolicy.AtualizarCategoriaIPC('habitacao', efeitos.ipc_habitacao)
  end

  -- Tesouro: boost ou custo
  if efeitos.tesouro_boost and SE.Treasury then
    SE.Treasury.Deposit(efeitos.tesouro_boost, 'evento_economico_positivo')
  end
  if efeitos.tesouro_custo and SE.Treasury then
    SE.Treasury.Withdraw(efeitos.tesouro_custo, 'evento_economico_custo')
  end

  U.dbg('[EconomicEvents] Efeitos aplicados')
end

--============================================================
-- Reverter Efeitos (ao fim do evento)
--============================================================
function EE.RevertEffects(efeitos)
  if not efeitos then return end

  -- Reverter SELIC (gradual)
  if efeitos.selic_ajuste and SE.MonetaryPolicy then
    local selic_atual = SE.MonetaryPolicy.State.selic_atual or 0.0075
    SE.MonetaryPolicy.State.selic_atual = U.clamp(
      selic_atual - efeitos.selic_ajuste,
      0.002,
      0.15
    )
  end

  -- Reverter IPC
  if efeitos.ipc_alimentacao and SE.MonetaryPolicy then
    SE.MonetaryPolicy.AtualizarCategoriaIPC('alimentacao', -efeitos.ipc_alimentacao * 0.5)
  end
  if efeitos.ipc_transporte and SE.MonetaryPolicy then
    SE.MonetaryPolicy.AtualizarCategoriaIPC('transporte', -efeitos.ipc_transporte * 0.5)
  end
  if efeitos.ipc_habitacao and SE.MonetaryPolicy then
    SE.MonetaryPolicy.AtualizarCategoriaIPC('habitacao', -efeitos.ipc_habitacao * 0.5)
  end

  U.dbg('[EconomicEvents] Efeitos revertidos (parcial)')
end

--============================================================
-- Finalizar Evento Ativo
--============================================================
function EE.EndEvent()
  if not EE.State.evento_ativo then return end

  local evento = EE.State.evento_ativo

  -- Buscar evento completo do catálogo
  local evento_completo = nil
  for _, e in ipairs(EE.EventCatalog) do
    if e.id == evento.id then
      evento_completo = e
      break
    end
  end

  -- Reverter efeitos
  if evento.efeitos then
    EE.RevertEffects(evento.efeitos)
  end

  -- Notificar fim
  if Config.EnableNotifications and evento_completo then
    TriggerClientEvent('chat:addMessage', -1, {
      args = { '[ECONOMIA]', evento_completo.mensagem_fim or ('Fim: ' .. evento.nome) }
    })
  end

  -- Adicionar ao histórico
  table.insert(EE.State.eventos_historico, {
    id = evento.id,
    nome = evento.nome,
    tipo = evento.tipo,
    inicio = evento.inicio,
    fim = os.time(),
    duracao_real = os.time() - evento.inicio,
    causa = evento.causa,
  })

  -- Limitar histórico
  if #EE.State.eventos_historico > 50 then
    table.remove(EE.State.eventos_historico, 1)
  end

  U.dbg(('[EconomicEvents] Evento finalizado: %s'):format(evento.nome))

  -- Limpar evento ativo
  EE.State.evento_ativo = nil
end

--============================================================
-- Obter Evento Ativo
--============================================================
function EE.GetEventoAtivo()
  return EE.State.evento_ativo
end

--============================================================
-- Obter Histórico
--============================================================
function EE.GetHistorico(limit)
  limit = U.toInt(limit or 10, 10)
  local historico = {}

  for i = #EE.State.eventos_historico, math.max(1, #EE.State.eventos_historico - limit + 1), -1 do
    table.insert(historico, EE.State.eventos_historico[i])
  end

  return historico
end

--============================================================
-- Thread de Verificação Periódica
--============================================================
CreateThread(function()
  Wait(60000)  -- Aguardar 1 minuto após start

  while true do
    Wait(Config.CheckIntervalMs)
    EE.CheckAndTrigger()
  end
end)

--============================================================
-- Comando Admin - Ver Evento Ativo
--============================================================
RegisterCommand('eco_evento', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  local evento = EE.GetEventoAtivo()

  if evento then
    print('\n========================================')
    print('EVENTO ECONÔMICO ATIVO')
    print('========================================')
    print(string.format('Nome: %s', evento.nome))
    print(string.format('Tipo: %s', evento.tipo))
    print(string.format('Início: %s', os.date('%Y-%m-%d %H:%M:%S', evento.inicio)))
    print(string.format('Fim Previsto: %s', os.date('%Y-%m-%d %H:%M:%S', evento.fim)))
    local restante = evento.fim - os.time()
    print(string.format('Tempo Restante: %.1f minutos', restante / 60))
    if evento.causa then
      print(string.format('Causa: %s', evento.causa))
    end
    print('========================================\n')
  else
    print('[EconomicEvents] Nenhum evento ativo no momento')
  end
end, false)

--============================================================
-- Comando Admin - Disparar Evento Manualmente
--============================================================
RegisterCommand('eco_trigger', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  local eventoId = args[1]

  if not eventoId then
    print('Uso: /eco_trigger <evento_id>')
    print('IDs disponíveis:')
    for _, e in ipairs(EE.EventCatalog) do
      print(string.format('  - %s (%s)', e.id, e.nome))
    end
    return
  end

  if EE.TriggerEvent(eventoId, true) then
    print(('[EconomicEvents] Evento "%s" disparado manualmente'):format(eventoId))
  else
    print(('[EconomicEvents] Falha ao disparar evento "%s"'):format(eventoId))
  end
end, false)

--============================================================
-- Comando Admin - Histórico de Eventos
--============================================================
RegisterCommand('eco_historico', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  local historico = EE.GetHistorico(10)

  print('\n========================================')
  print('HISTÓRICO DE EVENTOS ECONÔMICOS')
  print('========================================')

  if #historico == 0 then
    print('Nenhum evento registrado ainda')
  else
    for i, evento in ipairs(historico) do
      print(string.format('%d. %s (%s)', i, evento.nome, evento.tipo))
      print(string.format('   Início: %s', os.date('%Y-%m-%d %H:%M', evento.inicio)))
      print(string.format('   Duração: %.1f min', evento.duracao_real / 60))
      if evento.causa then
        print(string.format('   Causa: %s', evento.causa))
      end
      print('')
    end
  end

  print('========================================\n')
end, false)

--============================================================
-- Exports
--============================================================
exports('TriggerEconomicEvent', EE.TriggerEvent)
exports('GetEventoAtivo', EE.GetEventoAtivo)
exports('GetHistoricoEventos', EE.GetHistorico)

print('^2[space_economy]^7 Economic Events loaded - Dynamic crises and booms system active')
