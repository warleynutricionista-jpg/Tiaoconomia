# 🏛️ Melhorias Econômicas Avançadas - Sistema Ultra-Realista

## Visão Geral
Este documento detalha melhorias para transformar o tiao_economia em um sistema econômico **ultra-realista**, com ajuste automático baseado na circulação monetária, simulando a gestão de um país real bem administrado.

---

## 📊 1. SISTEMA DE CIRCULAÇÃO MONETÁRIA E PIB

### 1.1 Rastreamento de Dinheiro Circulante
```lua
-- Monitorar TODO o dinheiro da cidade
{
  total_em_circulacao: 15000000,     -- Soma de todo dinheiro
  dinheiro_players: 8000000,          -- Cash + bank de players
  dinheiro_empresas: 3000000,         -- Sociedades/gangs
  tesouro_publico: 4000000,           -- Cofre da cidade
  dinheiro_em_caixa: 2000000,         -- Cash físico
  dinheiro_em_banco: 13000000,        -- Bancarizado
}
```

### 1.2 PIB (Produto Interno Bruto) da Cidade
```lua
-- Calcular PIB baseado em transações
PIB = {
  consumo_privado: 500000,      -- Compras em lojas
  investimento: 200000,         -- Compra de veículos, propriedades
  gastos_governo: 150000,       -- Salários públicos, subsídios
  exportacoes: 100000,          -- Vendas para NPCs/outros servidores
  importacoes: -80000,          -- Compras de NPCs/outros servidores
}

PIB_Total = Consumo + Investimento + Gastos_Governo + (Exportações - Importações)
```

### 1.3 Velocidade de Circulação
```lua
-- Quanto cada $ é usado por período
Velocidade = Total_Transacoes / Dinheiro_Circulante

-- Exemplo:
-- $15M circulando, $3M em transações/dia = velocidade de 0.2/dia
```

---

## 💹 2. INFLAÇÃO DINÂMICA AUTOMÁTICA

### 2.1 Cálculo de Inflação Real
```lua
Inflação = (Dinheiro_Novo - Dinheiro_Destruído) / PIB

Dinheiro_Novo:
  + Salários pagos por NPCs
  + Recompensas de missões
  + Vendas para NPCs
  + Hacks/roubos bem-sucedidos

Dinheiro_Destruído:
  - Compras em lojas (NPC shops)
  - Impostos recolhidos
  - Multas pagas
  - Upgrades de veículos/armas
```

### 2.2 Ajuste Automático de Preços
```lua
-- TODOS os preços se ajustam automaticamente
PrecoAjustado = PrecoBase * (1 + InflaçãoAcumulada)

Exemplos:
- Pão custava $5, inflação de 10% = agora custa $5.50
- Veículo custava $50000, inflação 10% = agora $55000
- Salários ajustados automaticamente para compensar
```

### 2.3 Índice de Preços ao Consumidor (IPC)
```lua
IPC = {
  alimentacao: { peso: 0.25, variacao: 1.05 },
  transporte: { peso: 0.20, variacao: 1.03 },
  habitacao: { peso: 0.35, variacao: 1.08 },
  saude: { peso: 0.10, variacao: 1.02 },
  lazer: { peso: 0.10, variacao: 1.04 },
}

IPC_Total = Σ(categoria.peso * categoria.variacao)
```

---

## 🏦 3. POLÍTICA MONETÁRIA AUTOMÁTICA

### 3.1 Taxa SELIC (Taxa Básica de Juros)
```lua
-- Ajuste automático baseado em inflação
function AjustarSELIC()
  if Inflacao > Meta_Inflacao + 0.02 then
    -- Inflação alta: AUMENTAR juros (reduz consumo)
    SELIC = SELIC + 0.005
  elseif Inflacao < Meta_Inflacao - 0.02 then
    -- Inflação baixa: REDUZIR juros (estimula economia)
    SELIC = SELIC - 0.005
  end

  -- Limites: 0.5% a 15% ao mês
  SELIC = clamp(SELIC, 0.005, 0.15)
end
```

### 3.2 Reserva Compulsória Bancária
```lua
-- Bancos devem manter % em reserva
ReservaCompulsoria = 0.15  -- 15% do total depositado

-- Se circulação muito alta:
if Velocidade_Circulacao > 0.3 then
  ReservaCompulsoria = 0.25  -- Aumenta para 25% (tira dinheiro de circulação)
end
```

### 3.3 Operações de Mercado Aberto
```lua
-- Governo COMPRA/VENDE bonds para controlar dinheiro
if Inflacao > Meta then
  -- VENDER bonds: players compram, dinheiro sai de circulação
  Tesouro:VenderBonds(valor, SELIC)
else
  -- COMPRAR bonds de volta: injeta dinheiro
  Tesouro:ComprarBonds(valor)
end
```

---

## 📈 4. INDICADORES ECONÔMICOS COMPLETOS

### 4.1 Dashboard em Tempo Real
```lua
Indicadores = {
  -- Monetários
  pib: 15000000,
  pib_per_capita: 75000,  -- PIB / num_players
  inflacao_mensal: 0.02,
  inflacao_anual: 0.24,
  selic: 0.0075,

  -- Mercado de Trabalho
  taxa_desemprego: 0.05,  -- 5%
  salario_medio: 5000,
  salario_minimo: 2000,   -- Ajustado automaticamente

  -- Distribuição de Renda
  gini: 0.45,             -- 0 = igualdade total, 1 = desigualdade total
  renda_top10: 0.35,      -- Top 10% possui 35% da riqueza

  -- Dívida
  divida_publica: 2000000,
  divida_publica_pib: 0.13, -- 13% do PIB

  -- Setores
  consumo_varejo: 500000,
  investimento_imoveis: 200000,
  investimento_veiculos: 150000,
}
```

### 4.2 Relatórios Automáticos
```lua
-- Relatório diário/semanal/mensal
{
  periodo: "Semana 12/2024",
  resumo: {
    pib_crescimento: "+2.5%",
    inflacao: "+1.2%",
    desemprego: "5.1%",
    confianca_consumidor: 78,  -- 0-100
  },
  destaques: [
    "PIB cresceu 2.5% devido aumento em investimentos",
    "Inflação controlada dentro da meta",
    "Desemprego estável",
  ]
}
```

---

## 💼 5. MERCADO DE TRABALHO DINÂMICO

### 5.1 Salário Mínimo Automático
```lua
-- Ajustado para acompanhar inflação + produtividade
SalarioMinimo = SalarioMinimo_Anterior * (1 + Inflacao + Crescimento_PIB/2)

-- Exemplo:
-- Salário $2000
-- Inflação 2%
-- PIB cresceu 3%
-- Novo salário: $2000 * (1 + 0.02 + 0.015) = $2070
```

### 5.2 Taxa de Desemprego
```lua
Desemprego = Players_Sem_Job / Total_Players

-- Se desemprego ALTO (>10%):
  - Reduzir SELIC (estimular contratações)
  - Aumentar gastos governo (mais vagas públicas)
  - Subsídios para empresas contratarem

-- Se desemprego BAIXO (<3%):
  - Economia aquecida
  - Risco de inflação
  - Pode aumentar SELIC
```

### 5.3 Salários por Setor
```lua
-- Cada job tem piso salarial que se ajusta
Jobs = {
  policia = {
    piso: SalarioMinimo * 1.5,
    teto: SalarioMinimo * 8,
    ajuste_inflacao: true,
  },
  medico = {
    piso: SalarioMinimo * 2,
    teto: SalarioMinimo * 10,
    ajuste_inflacao: true,
  },
  mecanico = {
    piso: SalarioMinimo * 1.2,
    teto: SalarioMinimo * 5,
    ajuste_inflacao: true,
  }
}
```

---

## 📉 6. SISTEMA DE OFERTA E DEMANDA

### 6.1 Preços Dinâmicos em Lojas
```lua
-- Quanto mais compram, mais caro fica
PrecoItem = PrecoBase * (1 + (Demanda / Oferta - 1) * 0.5)

Exemplo:
- Arma: PrecoBase $5000
- Demanda = 100 compras/dia
- Oferta = 80 unidades/dia
- Razão = 100/80 = 1.25
- Preço = $5000 * (1 + (1.25 - 1) * 0.5) = $5625

-- Se ninguém compra:
- Demanda = 10
- Oferta = 80
- Razão = 10/80 = 0.125
- Preço = $5000 * (1 + (0.125 - 1) * 0.5) = $2812
```

### 6.2 Estoque Dinâmico
```lua
-- Lojas têm estoque limitado que se reabastece
{
  item: "bread",
  estoque_atual: 45,
  estoque_maximo: 100,
  reabastecimento: 10/hora,
  preco_base: 5,
  preco_atual: 5 * (1 + (100 - 45) / 100) = $7.75  -- Pouco estoque = mais caro
}
```

---

## 💰 7. SISTEMA BANCÁRIO REALISTA

### 7.1 Contas com Rendimento
```lua
Conta_Poupanca = {
  saldo: 50000,
  rendimento_mensal: SELIC * 0.7,  -- 70% da SELIC
  isento_ir: true,  -- Até certo valor
}

Conta_Corrente = {
  saldo: 10000,
  rendimento: 0,
  taxa_manutencao: 50/mes,
}

CDB = {
  valor_aplicado: 100000,
  prazo_meses: 6,
  rendimento: SELIC * 1.1,  -- 110% da SELIC
  liquidez: "no_vencimento",
}
```

### 7.2 Empréstimos Realistas
```lua
Emprestimo = {
  valor: 50000,
  parcelas: 12,
  juros_mes: SELIC + 0.05,  -- SELIC + spread de risco
  valor_parcela: calcular_price(50000, 12, juros),
  score_necessario: 600,

  -- Garantias
  garantia_veiculo: true,
  garantia_imovel: false,
}

-- Taxa varia com score:
if score > 800 then juros = SELIC + 0.02 end  -- Excelente
if score < 500 then juros = SELIC + 0.10 end  -- Alto risco
```

---

## 📊 8. BOLSA DE VALORES DA CIDADE

### 8.1 Ações de Empresas Principais
```lua
Acoes = {
  {
    empresa: "Bennys Mechanics",
    ticker: "BENN",
    preco: 150,
    variacao_dia: +2.5,
    volume: 1500,  -- Ações negociadas hoje
    market_cap: 450000,
    pe_ratio: 12,
  },
  {
    empresa: "Ammunation Corp",
    ticker: "AMMU",
    preco: 320,
    variacao_dia: -1.2,
    volume: 800,
    market_cap: 960000,
    pe_ratio: 15,
  }
}
```

### 8.2 Preço Baseado em Performance
```lua
-- Preço da ação varia com lucro da empresa
function AtualizarPrecoAcao(empresa)
  local lucro_mes = empresa.receita - empresa.despesas
  local lucro_esperado = empresa.market_cap * 0.01

  if lucro_mes > lucro_esperado then
    -- Lucro acima do esperado: ação sobe
    empresa.preco = empresa.preco * 1.05
  else
    -- Lucro abaixo: ação cai
    empresa.preco = empresa.preco * 0.98
  end
end
```

### 8.3 Índice Ibovespa da Cidade
```lua
-- Média ponderada das principais ações
Ibovespa_Cidade = Σ(acao.preco * acao.peso) / Divisor

-- Benchmark da economia:
if Ibovespa_hoje > Ibovespa_ontem then
  -- Economia em alta
  Confianca_Consumidor += 1
end
```

---

## 🏢 9. GESTÃO DE EMPRESAS/SOCIEDADES

### 9.1 Balanço Patrimonial Real
```lua
Empresa = {
  -- Ativo
  caixa: 50000,
  estoque: 30000,
  imoveis: 200000,
  veiculos: 100000,
  ativo_total: 380000,

  -- Passivo
  dividas: 50000,
  impostos_pendentes: 10000,
  passivo_total: 60000,

  -- Patrimônio Líquido
  patrimonio_liquido: 380000 - 60000 = 320000,

  -- DRE (Demonstrativo Resultado)
  receita_mes: 80000,
  custos_mes: 40000,
  impostos_mes: 8000,
  lucro_liquido: 32000,
  margem_lucro: 40%,
}
```

### 9.2 Indicadores Empresariais
```lua
-- ROI (Return on Investment)
ROI = (Lucro / Investimento_Total) * 100

-- ROE (Return on Equity)
ROE = (Lucro / Patrimonio_Liquido) * 100

-- Liquidez Corrente
Liquidez = Ativo_Circulante / Passivo_Circulante

-- Endividamento
Endividamento = Passivo_Total / Ativo_Total
```

---

## 🎲 10. EVENTOS ECONÔMICOS ALEATÓRIOS

### 10.1 Crises Econômicas
```lua
Eventos = {
  {
    nome: "Crise Financeira",
    probabilidade: 0.05,  -- 5% por mês
    efeitos: {
      pib: -0.15,           -- PIB cai 15%
      desemprego: +0.08,    -- Desemprego sobe 8%
      inflacao: +0.05,      -- Inflação sobe 5%
      confianca: -30,       -- Confiança do consumidor despenca
    },
    duracao: "3-6 meses",
  },
  {
    nome: "Boom Econômico",
    probabilidade: 0.03,
    efeitos: {
      pib: +0.25,
      desemprego: -0.05,
      inflacao: +0.08,      -- Risco: inflação aumenta
      confianca: +40,
    },
    duracao: "6-12 meses",
  }
}
```

### 10.2 Eventos Setoriais
```lua
{
  nome: "Aumento do Petróleo",
  setor: "transporte",
  efeitos: {
    preco_combustivel: +0.30,  -- +30%
    preco_frete: +0.15,
    inflacao_transporte: +0.10,
  }
}

{
  nome: "Safra Recorde",
  setor: "alimentacao",
  efeitos: {
    preco_alimentos: -0.20,    -- -20%
    inflacao_alimentacao: -0.08,
  }
}
```

---

## 🎯 11. SISTEMA DE METAS ECONÔMICAS

### 11.1 Metas do Governo
```lua
Metas = {
  inflacao: {
    centro: 0.04,      -- 4% ao ano
    tolerancia: 0.02,  -- Pode variar 2-6%
    atual: 0.045,
    status: "✅ Dentro da meta",
  },

  desemprego: {
    meta: 0.06,        -- Máximo 6%
    atual: 0.051,
    status: "✅ Abaixo da meta",
  },

  divida_publica: {
    meta_pib: 0.50,    -- Máximo 50% do PIB
    atual: 0.13,
    status: "✅ Sustentável",
  },

  crescimento_pib: {
    meta: 0.03,        -- Crescer 3% ao ano
    atual: 0.025,
    status: "⚠️ Abaixo da meta",
  }
}
```

### 11.2 Ações Automáticas para Atingir Metas
```lua
-- Se inflação acima da meta:
if Inflacao > Meta_Inflacao + Tolerancia then
  SELIC += 0.01              -- Aumenta juros
  Gastos_Governo *= 0.95     -- Reduz gastos públicos
  Impostos *= 1.02           -- Aumenta impostos (tira dinheiro)
end

-- Se desemprego alto:
if Desemprego > Meta_Desemprego then
  Gastos_Governo *= 1.10     -- Aumenta gastos (gera empregos)
  SELIC -= 0.005             -- Reduz juros (facilita crédito)
  Subsidios_Empresas += 0.15 -- Incentiva contratações
end
```

---

## 💳 12. SISTEMA FISCAL AVANÇADO

### 12.1 Impostos Progressivos por Riqueza Total
```lua
-- Não só renda, mas patrimônio total
Patrimonio = Dinheiro + Veiculos + Imoveis + Acoes + Estoque

Faixas_Patrimonio = {
  {max: 100000,   aliquota: 0.00},   -- Isento
  {max: 500000,   aliquota: 0.005},  -- 0.5% sobre excedente
  {max: 1000000,  aliquota: 0.01},   -- 1%
  {max: 5000000,  aliquota: 0.015},  -- 1.5%
  {max: nil,      aliquota: 0.02},   -- 2% (grandes fortunas)
}

-- Imposto anual sobre patrimônio (IGF)
IGF = calcularProgressivo(Patrimonio, Faixas_Patrimonio)
```

### 12.2 Imposto sobre Ganho de Capital
```lua
-- Venda de ações, veículos, imóveis
Ganho_Capital = Preco_Venda - Preco_Compra

if Ganho_Capital > 0 then
  Imposto = Ganho_Capital * 0.15  -- 15% sobre lucro
end
```

### 12.3 Incentivos Fiscais
```lua
Incentivos = {
  primeiro_emprego: {
    isencao_ir: 6_meses,
    reducao_inss: 0.50,
  },

  pequena_empresa: {
    isencao_faturamento: 50000,  -- Primeiros $50k isentos
    aliquota_reduzida: 0.08,     -- 8% ao invés de padrão
  },

  investimento_producao: {
    credito_tributario: 0.20,    -- Recupera 20% do investimento
  }
}
```

---

## 📱 13. PAINEL DE GESTÃO ECONÔMICA

### 13.1 Dashboard Interativo
```lua
-- Interface NUI para admins
Painel = {
  visao_geral: {
    pib_tempo_real: grafico_linha,
    inflacao: grafico_linha,
    desemprego: gauge,
    velocidade_circulacao: gauge,
  },

  setores: {
    comercio: { participacao_pib: 0.30, crescimento: +2.5 },
    servicos: { participacao_pib: 0.45, crescimento: +1.8 },
    industria: { participacao_pib: 0.25, crescimento: -0.5 },
  },

  acoes_disponiveis: [
    "Ajustar SELIC manualmente",
    "Criar programa de estímulo ($500k)",
    "Aumentar/reduzir impostos",
    "Emitir bonds governamentais",
    "Congelar preços temporariamente",
  ],

  simulador: {
    -- "E se eu aumentar SELIC em 2%?"
    -- Mostra previsão de impactos
  }
}
```

### 13.2 Alertas Automáticos
```lua
Alertas = {
  {
    tipo: "CRÍTICO",
    mensagem: "Inflação subiu para 8% (meta: 4±2%)",
    sugestao: "Aumentar SELIC de 0.75% para 1.5%",
    urgencia: "ALTA",
  },
  {
    tipo: "AVISO",
    mensagem: "PIB cresceu apenas 0.5% este mês (meta: 3%/ano)",
    sugestao: "Considerar reduzir impostos ou aumentar gastos",
    urgencia: "MÉDIA",
  }
}
```

---

## 🔄 14. BALANÇA COMERCIAL

### 14.1 Importação/Exportação
```lua
-- Comércio com "exterior" (NPCs ou outros servidores)
Balanca = {
  exportacoes: {
    drogas: 50000,      -- Vendas para NPCs
    veiculos: 30000,
    servicos: 20000,
    total: 100000,
  },

  importacoes: {
    armas: 40000,       -- Compras de NPCs
    alimentos: 25000,
    combustivel: 15000,
    total: 80000,
  },

  saldo: 100000 - 80000 = 20000,  -- Superávit
  taxa_cambio: 1.0,  -- Pode variar se multi-servidor
}
```

### 14.2 Impacto no PIB
```lua
PIB = Consumo + Investimento + Gastos_Gov + (Exportacoes - Importacoes)

-- Superávit comercial = bom para PIB
-- Déficit = ruim para PIB
```

---

## 🎓 15. EDUCAÇÃO FINANCEIRA

### 15.1 Tutorial Interativo para Players
```lua
-- Ensinar economia para players
Tutorial = {
  licao_1: "Como funcionam os impostos progressivos",
  licao_2: "Por que inflação afeta você",
  licao_3: "Como investir em ações",
  licao_4: "Empréstimos: quando vale a pena",

  recompensa: "Score de crédito +50",
}
```

### 15.2 Relatório Pessoal Mensal
```lua
-- Cada player recebe
Relatorio_Pessoal = {
  renda_mes: 8000,
  gastos_mes: 6500,
  economia: 1500,

  impostos_pagos: {
    ir: 800,
    ipva: 200,
    iptu: 150,
    total: 1150,
  },

  patrimonio_variacao: "+15%",
  score_credito: 720,

  dicas: [
    "Você gastou 15% a mais que mês passado",
    "Seu score subiu 20 pontos!",
    "Inflação foi 2%, seu salário deve ser ajustado",
  ]
}
```

---

## 🚀 ROADMAP DE IMPLEMENTAÇÃO

### Fase 1 - Fundação (Semana 1-2)
- ✅ Rastreamento de circulação monetária
- ✅ Cálculo de PIB em tempo real
- ✅ Sistema de inflação dinâmica
- ✅ Ajuste automático de preços

### Fase 2 - Política Monetária (Semana 3-4)
- ✅ Taxa SELIC automática
- ✅ Reserva compulsória
- ✅ Sistema de bonds
- ✅ Indicadores econômicos

### Fase 3 - Mercado de Trabalho (Semana 5-6)
- ✅ Salário mínimo dinâmico
- ✅ Taxa de desemprego
- ✅ Ajuste salarial automático

### Fase 4 - Sistema Bancário (Semana 7-8)
- ✅ Poupança com rendimento
- ✅ CDB e investimentos
- ✅ Empréstimos com juros SELIC

### Fase 5 - Bolsa de Valores (Semana 9-10)
- ✅ Ações de empresas
- ✅ Índice Ibovespa
- ✅ Trading system

### Fase 6 - Eventos e Gestão (Semana 11-12)
- ✅ Eventos econômicos
- ✅ Painel de gestão
- ✅ Sistema de alertas
- ✅ Educação financeira

---

## 📊 MÉTRICAS DE SUCESSO

### KPIs do Sistema
```lua
Metricas_Sucesso = {
  estabilidade_inflacao: "Variação < 3% ao mês",
  crescimento_pib: "> 2% ao mês",
  desemprego: "< 8%",
  divida_publica: "< 50% do PIB",
  confianca_consumidor: "> 60/100",
  velocidade_circulacao: "0.15 - 0.25",
  distribuicao_renda: "Gini < 0.50",
}
```

---

## 🎯 RESULTADO ESPERADO

### Economia Auto-Regulada
✅ **Ajusta inflação automaticamente** baseado em circulação
✅ **Salários acompanham custo de vida**
✅ **Preços se ajustam por oferta/demanda**
✅ **Governo age automaticamente para atingir metas**
✅ **Sistema bancário realista com investimentos**
✅ **Eventos econômicos criam dinamismo**
✅ **Gestão detalhada de todos os aspectos**
✅ **Educação financeira para players**

### Uma Economia Viva e Realista! 🌍
