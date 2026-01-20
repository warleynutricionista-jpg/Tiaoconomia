--============================================================
-- space_economy - server/monetary_policy.lua
-- Política Monetária Automática Ultra-Realista
-- MELHORIA CRÍTICA #3 - Inflação Dinâmica e SELIC Automática
--============================================================
SE = SE or {}
SE.MonetaryPolicy = SE.MonetaryPolicy or {}

local U = SE.Util
local MP = SE.MonetaryPolicy

--============================================================
-- Estado da Política Monetária
--============================================================
MP.State = {
  -- Taxa SELIC (Sistema Especial de Liquidação e Custódia)
  selic_atual = 0.0075,        -- 0.75% ao mês (padrão)
  selic_anterior = 0.0075,

  -- Meta de Inflação
  meta_inflacao = 0.04,        -- 4% ao ano
  tolerancia_inflacao = 0.02,  -- ±2%

  -- Inflação Atual
  inflacao_mensal = 0,
  inflacao_anual = 0,
  inflacao_acumulada = 0,

  -- IPC (Índice de Preços ao Consumidor)
  ipc_atual = 100,
  ipc_anterior = 100,
  ipc_categorias = {
    alimentacao = { peso = 0.25, indice = 100, variacao = 0 },
    transporte = { peso = 0.20, indice = 100, variacao = 0 },
    habitacao = { peso = 0.35, indice = 100, variacao = 0 },
    saude = { peso = 0.10, indice = 100, variacao = 0 },
    lazer = { peso = 0.10, indice = 100, variacao = 0 },
  },

  -- Massa Monetária
  m1_anterior = 0,  -- Dinheiro em circulação período anterior
  m1_atual = 0,     -- Atual

  -- Decisões do COPOM (Comitê de Política Monetária)
  ultima_decisao = {
    timestamp = 0,
    decisao = 'MANTER',  -- MANTER, SUBIR, BAIXAR
    variacao = 0,
    justificativa = '',
  },

  -- Histórico de decisões
  historico_decisoes = {},
  historico_inflacao = {},
  historico_selic = {},
}

--============================================================
-- Configuração
--============================================================
local Config = {
  -- Reunião do COPOM (Comitê)
  CopomIntervalMs = 3600000,  -- 1 hora (em prod seria semanal)

  -- Meta de Inflação
  MetaInflacaoAnual = 0.04,   -- 4% ao ano
  ToleranciaInflacao = 0.02,  -- ±2%

  -- Limites da SELIC
  SelicMin = 0.002,           -- 0.2% ao mês (mínimo)
  SelicMax = 0.15,            -- 15% ao mês (máximo)

  -- Agressividade do ajuste
  AjusteAgressivo = 0.01,     -- 1% de ajuste por decisão
  AjusteModerado = 0.005,     -- 0.5%
  AjusteSutil = 0.0025,       -- 0.25%

  -- Cálculo de Inflação
  InflacaoUpdateMs = 900000,  -- Recalcular a cada 15 minutos

  -- IPC Weights (devem somar 1.0)
  IPCPesos = {
    alimentacao = 0.25,
    transporte = 0.20,
    habitacao = 0.35,
    saude = 0.10,
    lazer = 0.10,
  },
}

--============================================================
-- Calcular Inflação pela Massa Monetária
--============================================================
function MP.CalcularInflacaoPorMassa()
  if not SE.EconomyMonitor then return 0 end

  local m1_atual = SE.EconomyMonitor.State.total_circulacao or 0
  local m1_anterior = MP.State.m1_anterior or m1_atual
  local pib = SE.EconomyMonitor.State.pib_total or 1

  if m1_anterior <= 0 or pib <= 0 then return 0 end

  -- Teoria Quantitativa da Moeda: MV = PY
  -- Inflação = (ΔM / M) - (ΔPIB / PIB)

  local delta_m = m1_atual - m1_anterior
  local variacao_percentual_m = delta_m / m1_anterior

  -- Simplificado: inflação = crescimento da massa - crescimento do PIB
  local inflacao = variacao_percentual_m

  MP.State.m1_anterior = m1_atual
  MP.State.m1_atual = m1_atual

  return inflacao
end

--============================================================
-- Calcular IPC (Índice de Preços ao Consumidor)
--============================================================
function MP.CalcularIPC()
  -- IPC agregado = Σ(peso_categoria * variacao_categoria)
  local ipc_total = 0

  for categoria, dados in pairs(MP.State.ipc_categorias) do
    local peso = dados.peso or 0
    local variacao = dados.variacao or 0

    ipc_total = ipc_total + (peso * (1 + variacao))
  end

  MP.State.ipc_anterior = MP.State.ipc_atual
  MP.State.ipc_atual = MP.State.ipc_anterior * ipc_total

  -- Calcular inflação pelo IPC
  local inflacao_ipc = (MP.State.ipc_atual / MP.State.ipc_anterior) - 1

  return inflacao_ipc
end

--============================================================
-- Atualizar Variação de Categoria do IPC
--============================================================
function MP.AtualizarCategoriaIPC(categoria, variacao)
  categoria = U.safeStr(categoria, '')
  variacao = U.toNumber(variacao, 0)

  if not MP.State.ipc_categorias[categoria] then
    return false
  end

  MP.State.ipc_categorias[categoria].variacao = variacao
  MP.State.ipc_categorias[categoria].indice = MP.State.ipc_categorias[categoria].indice * (1 + variacao)

  return true
end

--============================================================
-- Calcular Inflação Total
--============================================================
function MP.CalcularInflacao()
  -- Combinar inflação por massa monetária e IPC
  local inflacao_massa = MP.CalcularInflacaoPorMassa()
  local inflacao_ipc = MP.CalcularIPC()

  -- Média ponderada (60% massa, 40% IPC)
  local inflacao_mensal = (inflacao_massa * 0.6) + (inflacao_ipc * 0.4)

  MP.State.inflacao_mensal = inflacao_mensal

  -- Inflação acumulada
  MP.State.inflacao_acumulada = MP.State.inflacao_acumulada + inflacao_mensal

  -- Inflação anualizada (aproximação)
  MP.State.inflacao_anual = inflacao_mensal * 12

  -- Adicionar ao histórico
  table.insert(MP.State.historico_inflacao, {
    timestamp = os.time(),
    inflacao_mensal = inflacao_mensal,
    inflacao_anual = MP.State.inflacao_anual,
  })

  -- Limitar histórico
  if #MP.State.historico_inflacao > 288 then  -- 24h (se atualizar a cada 5min)
    table.remove(MP.State.historico_inflacao, 1)
  end

  U.dbg(('[MonetaryPolicy] Inflação calculada - Mensal: %.2f%% | Anual: %.2f%%'):format(
    inflacao_mensal * 100,
    MP.State.inflacao_anual * 100
  ))

  -- Notificar sistema de estado
  if SE.Server and SE.Server.SetInflationRate then
    SE.Server.SetInflationRate(1 + MP.State.inflacao_acumulada)
  end

  return inflacao_mensal
end

--============================================================
-- Decisão do COPOM (Ajustar SELIC)
--============================================================
function MP.DecisaoCOPOM()
  local inflacao_anual = MP.State.inflacao_anual
  local meta = Config.MetaInflacaoAnual
  local tolerancia = Config.ToleranciaInflacao

  local selic_atual = MP.State.selic_atual
  local nova_selic = selic_atual

  local decisao = 'MANTER'
  local variacao = 0
  local justificativa = ''

  -- Desvio da meta
  local desvio = inflacao_anual - meta

  -- INFLAÇÃO ACIMA DA META (+ tolerância)
  if inflacao_anual > (meta + tolerancia) then
    -- SUBIR JUROS (reduz consumo e inflação)
    local urgencia = math.abs(desvio)

    if urgencia > 0.05 then
      -- Muito acima: ajuste agressivo
      variacao = Config.AjusteAgressivo
      justificativa = string.format('Inflação em %.1f%% (meta: %.1f%%). Ajuste agressivo necessário.',
        inflacao_anual * 100, meta * 100)
    elseif urgencia > 0.03 then
      -- Moderadamente acima: ajuste moderado
      variacao = Config.AjusteModerado
      justificativa = string.format('Inflação em %.1f%% (meta: %.1f%%). Ajuste moderado.',
        inflacao_anual * 100, meta * 100)
    else
      -- Pouco acima: ajuste sutil
      variacao = Config.AjusteSutil
      justificativa = string.format('Inflação em %.1f%% (meta: %.1f%%). Ajuste preventivo.',
        inflacao_anual * 100, meta * 100)
    end

    nova_selic = selic_atual + variacao
    decisao = 'SUBIR'

  -- INFLAÇÃO ABAIXO DA META (- tolerância)
  elseif inflacao_anual < (meta - tolerancia) then
    -- BAIXAR JUROS (estimula consumo e eleva inflação)
    local urgencia = math.abs(desvio)

    if urgencia > 0.05 then
      variacao = -Config.AjusteAgressivo
      justificativa = string.format('Inflação em %.1f%% (meta: %.1f%%). Estímulo agressivo.',
        inflacao_anual * 100, meta * 100)
    elseif urgencia > 0.03 then
      variacao = -Config.AjusteModerado
      justificativa = string.format('Inflação em %.1f%% (meta: %.1f%%). Estímulo moderado.',
        inflacao_anual * 100, meta * 100)
    else
      variacao = -Config.AjusteSutil
      justificativa = string.format('Inflação em %.1f%% (meta: %.1f%%). Ajuste fino.',
        inflacao_anual * 100, meta * 100)
    end

    nova_selic = selic_atual + variacao
    decisao = 'BAIXAR'

  -- INFLAÇÃO DENTRO DA META
  else
    justificativa = string.format('Inflação em %.1f%% dentro da meta (%.1f%% ±%.1f%%). SELIC mantida em %.2f%%.',
      inflacao_anual * 100, meta * 100, tolerancia * 100, selic_atual * 100)
  end

  -- Aplicar limites
  nova_selic = U.clamp(nova_selic, Config.SelicMin, Config.SelicMax)

  -- Atualizar estado
  MP.State.selic_anterior = MP.State.selic_atual
  MP.State.selic_atual = nova_selic

  -- Registrar decisão
  local decisao_obj = {
    timestamp = os.time(),
    decisao = decisao,
    selic_anterior = selic_atual,
    selic_nova = nova_selic,
    variacao = variacao,
    inflacao_atual = inflacao_anual,
    meta_inflacao = meta,
    justificativa = justificativa,
  }

  MP.State.ultima_decisao = decisao_obj
  table.insert(MP.State.historico_decisoes, decisao_obj)

  -- Limitar histórico
  if #MP.State.historico_decisoes > 100 then
    table.remove(MP.State.historico_decisoes, 1)
  end

  table.insert(MP.State.historico_selic, {
    timestamp = os.time(),
    selic = nova_selic,
  })

  if #MP.State.historico_selic > 288 then
    table.remove(MP.State.historico_selic, 1)
  end

  -- Log da decisão
  U.dbg(('[COPOM] %s | SELIC: %.2f%% → %.2f%% | %s'):format(
    decisao,
    selic_atual * 100,
    nova_selic * 100,
    justificativa
  ))

  -- Notificar admins online (se configurado)
  if SE.Admin and SE.Admin.NotifyAll then
    SE.Admin.NotifyAll(
      ('📊 COPOM: %s SELIC para %.2f%% | Inflação: %.1f%% (meta: %.1f%%)'):format(
        decisao == 'SUBIR' and '⬆️ ELEVOU' or (decisao == 'BAIXAR' and '⬇️ REDUZIU' or '➡️ MANTEVE'),
        nova_selic * 100,
        inflacao_anual * 100,
        meta * 100
      ),
      'inform'
    )
  end

  return nova_selic
end

--============================================================
-- Ajustar Preços Automaticamente pela Inflação
--============================================================
function MP.AjustarPrecosInflacao(preco_base)
  preco_base = U.toNumber(preco_base, 0)
  if preco_base <= 0 then return 0 end

  -- Preço ajustado = Preço Base × (1 + Inflação Acumulada)
  local preco_ajustado = preco_base * (1 + MP.State.inflacao_acumulada)

  return math.floor(preco_ajustado + 0.5)
end

--============================================================
-- Obter Taxa SELIC Atual
--============================================================
function MP.GetSELIC()
  return MP.State.selic_atual
end

--============================================================
-- Obter Inflação Atual
--============================================================
function MP.GetInflacao()
  return {
    mensal = MP.State.inflacao_mensal,
    anual = MP.State.inflacao_anual,
    acumulada = MP.State.inflacao_acumulada,
    meta = Config.MetaInflacaoAnual,
    tolerancia = Config.ToleranciaInflacao,
  }
end

--============================================================
-- Obter Relatório de Política Monetária
--============================================================
function MP.GetRelatorio()
  return {
    selic = {
      atual = MP.State.selic_atual,
      anterior = MP.State.selic_anterior,
      variacao = MP.State.selic_atual - MP.State.selic_anterior,
    },

    inflacao = {
      mensal = MP.State.inflacao_mensal,
      anual = MP.State.inflacao_anual,
      acumulada = MP.State.inflacao_acumulada,
      meta = Config.MetaInflacaoAnual,
      tolerancia = Config.ToleranciaInflacao,
      dentro_meta = math.abs(MP.State.inflacao_anual - Config.MetaInflacaoAnual) <= Config.ToleranciaInflacao,
    },

    ipc = {
      atual = MP.State.ipc_atual,
      anterior = MP.State.ipc_anterior,
      variacao = ((MP.State.ipc_atual / MP.State.ipc_anterior) - 1) * 100,
      categorias = MP.State.ipc_categorias,
    },

    massa_monetaria = {
      atual = MP.State.m1_atual,
      anterior = MP.State.m1_anterior,
      variacao = MP.State.m1_anterior > 0 and
        ((MP.State.m1_atual / MP.State.m1_anterior - 1) * 100) or 0,
    },

    ultima_decisao = MP.State.ultima_decisao,
  }
end

--============================================================
-- Thread de Cálculo de Inflação
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end

  -- Aguardar Economy Monitor estar pronto
  Wait(5000)

  while true do
    Wait(Config.InflacaoUpdateMs)
    MP.CalcularInflacao()
  end
end)

--============================================================
-- Thread de Reunião do COPOM
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end

  -- Aguardar um ciclo completo de inflação
  Wait(Config.InflacaoUpdateMs + 5000)

  while true do
    Wait(Config.CopomIntervalMs)
    MP.DecisaoCOPOM()
  end
end)

--============================================================
-- Comando Admin - Relatório de Política Monetária
--============================================================
RegisterCommand('eco_politica', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      print('[MonetaryPolicy] Acesso negado')
      return
    end
  end

  local relatorio = MP.GetRelatorio()

  print('\n========================================')
  print('POLÍTICA MONETÁRIA')
  print('========================================')
  print('TAXA SELIC:')
  print(string.format('  Atual: %.2f%% ao mês', relatorio.selic.atual * 100))
  print(string.format('  Anterior: %.2f%%', relatorio.selic.anterior * 100))
  print(string.format('  Variação: %+.2f%%', relatorio.selic.variacao * 100))
  print('')
  print('INFLAÇÃO:')
  print(string.format('  Mensal: %.2f%%', relatorio.inflacao.mensal * 100))
  print(string.format('  Anual: %.2f%%', relatorio.inflacao.anual * 100))
  print(string.format('  Acumulada: %.2f%%', relatorio.inflacao.acumulada * 100))
  print(string.format('  Meta: %.2f%% (±%.2f%%)', relatorio.inflacao.meta * 100, relatorio.inflacao.tolerancia * 100))
  print(string.format('  Status: %s', relatorio.inflacao.dentro_meta and '✅ DENTRO DA META' or '⚠️ FORA DA META'))
  print('')
  print('IPC (Índice de Preços):')
  print(string.format('  Atual: %.2f', relatorio.ipc.atual))
  print(string.format('  Variação: %+.2f%%', relatorio.ipc.variacao))
  print('  Por Categoria:')
  for cat, dados in pairs(relatorio.ipc.categorias) do
    print(string.format('    %s: Índice %.2f | Variação %+.2f%%',
      cat:upper(), dados.indice, (dados.variacao or 0) * 100))
  end
  print('')
  print('MASSA MONETÁRIA (M1):')
  print(string.format('  Atual: $%d', relatorio.massa_monetaria.atual))
  print(string.format('  Anterior: $%d', relatorio.massa_monetaria.anterior))
  print(string.format('  Variação: %+.2f%%', relatorio.massa_monetaria.variacao))
  print('')
  print('ÚLTIMA DECISÃO COPOM:')
  if relatorio.ultima_decisao and relatorio.ultima_decisao.timestamp > 0 then
    print(string.format('  Data: %s', os.date('%Y-%m-%d %H:%M', relatorio.ultima_decisao.timestamp)))
    print(string.format('  Decisão: %s', relatorio.ultima_decisao.decisao))
    print(string.format('  SELIC: %.2f%% → %.2f%%',
      relatorio.ultima_decisao.selic_anterior * 100,
      relatorio.ultima_decisao.selic_nova * 100))
    print(string.format('  Justificativa: %s', relatorio.ultima_decisao.justificativa))
  else
    print('  Aguardando primeira reunião do COPOM')
  end
  print('========================================\n')
end, false)

--============================================================
-- Comando Admin - Forçar Reunião do COPOM
--============================================================
RegisterCommand('eco_copom', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  print('[COPOM] Reunião forçada por admin')
  MP.CalcularInflacao()
  MP.DecisaoCOPOM()
end, false)

--============================================================
-- Comando Admin - Ajustar IPC de Categoria
--============================================================
RegisterCommand('eco_ipc', function(source, args)
  local src = tonumber(source)

  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then return end
  end

  local categoria = args[1]
  local variacao = tonumber(args[2])

  if not categoria or not variacao then
    print('Uso: /eco_ipc <categoria> <variacao_percentual>')
    print('Categorias: alimentacao, transporte, habitacao, saude, lazer')
    print('Exemplo: /eco_ipc alimentacao 5 (aumenta 5%)')
    return
  end

  variacao = variacao / 100  -- Converter % para decimal

  if MP.AtualizarCategoriaIPC(categoria, variacao) then
    print(('[IPC] Categoria "%s" ajustada: %+.2f%%'):format(categoria, variacao * 100))
    MP.CalcularInflacao()
  else
    print(('[IPC] Categoria inválida: %s'):format(categoria))
  end
end, false)

--============================================================
-- Exports
--============================================================
exports('GetSELIC', MP.GetSELIC)
exports('GetInflacao', MP.GetInflacao)
exports('AjustarPrecoInflacao', MP.AjustarPrecosInflacao)
exports('GetRelatorioPolitica', MP.GetRelatorio)
exports('AtualizarCategoriaIPC', MP.AtualizarCategoriaIPC)

print('^2[space_economy]^7 Monetary Policy loaded - SELIC and dynamic inflation system active')
