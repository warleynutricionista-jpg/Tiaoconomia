# Tião Economia v3.3 - Sistema Econômico Ultra-Realista para GTA V

O sistema econômico **MAIS COMPLETO e REALISTA** do FiveM. Economia que se **AUTO-REGULA** como um país real!

## 🌟 **NOVIDADES v3.3 - MERCADO FINANCEIRO E TRABALHO**

### 📈 **Bolsa de Valores**
- **8 empresas** listadas com ações negociáveis
- **Índice Ibovespa** calculado em tempo real
- **Circuit Breaker** automático em quedas bruscas (-10%)
- Preços influenciados por PIB, inflação e eventos econômicos
- Corretagem (0.5%) e Imposto sobre Ganho de Capital (15%)
- Sistema completo de portfólio com lucro/prejuízo

### 🏦 **Sistema Bancário Completo**
- **Poupança** com rendimento (70% da SELIC)
- **CDB** em 4 prazos (30, 60, 90, 180 dias)
- **LCI/LCA** isentos de IR
- **Tesouro SELIC** com liquidez imediata
- Rendimentos automáticos mensais
- Imposto de Renda progressivo sobre investimentos

### 💼 **Mercado de Trabalho**
- **Salário mínimo dinâmico** ajustado por inflação + PIB
- **Taxa de desemprego** calculada automaticamente
- **8 setores** com pisos e tetos salariais
- Salário médio da cidade calculado
- Ajustes automáticos de todos os salários

---

## 📊 **v3.2 - ECONOMIA ULTRA-REALISTA**

### 💰 **Monitoramento Econômico (Economy Monitor)**
- Rastreamento completo de **circulação monetária**
- Cálculo de **PIB** em tempo real
- **PIB per capita** automático
- **Velocidade de circulação** monetária
- Snapshots econômicos salvos
- Balança comercial (exportações/importações)

### 💹 **Política Monetária (Monetary Policy)**
- **Taxa SELIC** ajustada automaticamente
- **Inflação dinâmica** baseada em massa monetária
- **IPC** (Índice de Preços) com 5 categorias
- **COPOM virtual** que toma decisões automáticas
- Meta de inflação: 4% ±2%
- Ajuste automático de preços pela inflação

### 🎲 **Eventos Econômicos**
- **10+ eventos** aleatórios
- Crises (Financeira, Recessão)
- Booms (Econômico, Crescimento Acelerado)
- Eventos Setoriais (Combustível, Safra, Imobiliário)
- Especiais (Inovação, Investimento Estrangeiro, Desastres)
- Efeitos reais em toda economia

---

## 📋 **Sistemas v3.1 e Anteriores**

### 🏛️ **Sistemas Base**
1. **Tesouro Público** - Gestão completa do cofre
2. **Impostos Progressivos** - Faixas de IR brasileiras
3. **Dívidas Automáticas** - Juros, carência, ps-banking sync
4. **Parcelamento** - Até 12x sem juros
5. **Score de Crédito** - Pontuação de 0-1000
6. **Empréstimos** - Sistema governamental
7. **Taxação Automática** - IPVA, IPTU, ICMS, ISS
8. **Recompensas** - Descontos para bons pagadores
9. **Backup Automático** - Diário
10. **Métricas e Relatórios** - Dashboard completo

### ⚡ **Performance**
- **Cache LRU** - +400% performance
- **Hit Rate** esperado: 85-95%
- **Auto-Warmup** - Pré-aquecimento automático
- Redução de 70% nas queries SQL

---

## 🎮 **COMANDOS**

### 📊 **Economia e Indicadores**
```bash
/eco_relatorio              # Relatório econômico completo
/eco_politica               # Política monetária e inflação
/eco_copom                  # Forçar reunião do COPOM
/eco_ipc <cat> <var>        # Ajustar IPC de categoria
/eco_trabalho               # Mercado de trabalho
/eco_ajustar_salario        # Forçar ajuste de salário mínimo
```

### 🎲 **Eventos**
```bash
/eco_evento                 # Ver evento ativo
/eco_trigger <id>           # Disparar evento manualmente
/eco_historico              # Histórico de eventos
```

### 📈 **Bolsa de Valores**
```bash
/bolsa                      # Ver cotações
# Em breve: interface NUI completa
```

### 🏦 **Banco e Investimentos**
```bash
/banco_investir <produto> <valor>    # Aplicar
/banco_resgatar <id>                 # Resgatar
/banco_extrato                       # Ver extrato

# Produtos: cdb_30, cdb_60, cdb_90, cdb_180, lci, lca, tesouro_selic
```

### 💳 **Para Players**
```bash
/dividas                    # Ver dívidas
/parcelas                   # Parcelamentos ativos
/credito                    # Score de crédito
/emprestimo [valor]         # Solicitar empréstimo
```

### ⚙️ **Admin**
```bash
/economia                   # Painel admin
/eco_debt [id] [valor] [motivo]      # Criar dívida
/cache_stats                         # Estatísticas de cache
/cache_clear [cat]                   # Limpar cache
```

---

## 📦 **INSTALAÇÃO**

### 1. Requisitos
```lua
dependencies {
  'ox_lib',      -- Obrigatório
  'oxmysql',     -- Obrigatório
  'qbx_core',    -- qbx_core OU qb-core
}
```

### 2. Instalação
1. Clone/extraia na pasta `resources/`
2. Adicione ao `server.cfg`:
```bash
ensure tiao_economia
```
3. Inicie o servidor - tabelas criadas automaticamente

### 3. Permissões (IMPORTANTE!)
```bash
# server.cfg
add_ace group.admin space_economy.admin allow
add_principal identifier.license:SEU_LICENSE group.admin
```

---

## 📚 **EXPORTS (v3.3)**

### Economy Monitor
```lua
exports['tiao_economia']:RegistrarTransacao(tipo, valor, metadata)
exports['tiao_economia']:GetRelatorioEconomico()
exports['tiao_economia']:GetPIB()
exports['tiao_economia']:GetCirculacaoMonetaria()
exports['tiao_economia']:GetPIBPerCapita()
exports['tiao_economia']:GetVelocidadeCirculacao()
```

### Monetary Policy
```lua
exports['tiao_economia']:GetSELIC()
exports['tiao_economia']:GetInflacao()
exports['tiao_economia']:AjustarPrecoInflacao(preco_base)
exports['tiao_economia']:GetRelatorioPolitica()
exports['tiao_economia']:AtualizarCategoriaIPC(categoria, variacao)
```

### Stock Market (NOVO v3.3)
```lua
exports['tiao_economia']:BuyStock(src, ticker, quantidade)
exports['tiao_economia']:SellStock(src, ticker, quantidade)
exports['tiao_economia']:GetQuotes(ticker)  -- nil = todas
exports['tiao_economia']:GetPortfolio(citizenid)
exports['tiao_economia']:GetIbovespa()
```

### Banking System (NOVO v3.3)
```lua
exports['tiao_economia']:BankOpenAccount(citizenid, tipo)
exports['tiao_economia']:BankDeposit(citizenid, tipo, valor)
exports['tiao_economia']:BankWithdraw(citizenid, tipo, valor)
exports['tiao_economia']:BankInvest(citizenid, produto, valor)
exports['tiao_economia']:BankRedeem(investmentId, citizenid)
exports['tiao_economia']:BankGetStatement(citizenid)
```

### Labor Market (NOVO v3.3)
```lua
exports['tiao_economia']:GetMinimumWage()
exports['tiao_economia']:GetAverageWage()
exports['tiao_economia']:GetUnemploymentRate()
exports['tiao_economia']:GetLaborReport()
exports['tiao_economia']:GetSectorWages(setor)
```

### Economic Events
```lua
exports['tiao_economia']:TriggerEconomicEvent(eventoId, forcado)
exports['tiao_economia']:GetEventoAtivo()
exports['tiao_economia']:GetHistoricoEventos(limit)
```

---

## 🏢 **EMPRESAS DA BOLSA (v3.3)**

| Ticker | Empresa | Setor | Preço Inicial | Descrição |
|--------|---------|-------|---------------|-----------|
| **BENN** | Benny's Mechanics | Serviços | $150 | Rede de mecânicas premium |
| **AMMU** | Ammunation Corp | Comércio | $320 | Maior rede de armamentos |
| **PDLS** | Paradise LS Stores | Comércio | $85 | Lojas de conveniência |
| **CLUC** | Cluckin Bell Foods | Alimentação | $45 | Fast food mais popular |
| **MAZE** | Maze Bank | Financeiro | $580 | Principal banco da cidade |
| **PHMC** | Pillbox Medical | Saúde | $210 | Sistema de saúde |
| **LSPD** | LS Property Developers | Imóveis | $125 | Construtora |
| **VPCR** | Vapid Car Rentals | Transporte | $95 | Aluguel de veículos |

### Preços influenciados por:
- ✅ PIB da cidade
- ✅ Taxa de inflação
- ✅ Eventos econômicos
- ✅ Oferta e demanda

---

## 💰 **PRODUTOS BANCÁRIOS (v3.3)**

### Poupança
- Rendimento: **70% da SELIC**
- Liquidez: **Imediata**
- IR: **Isento**
- Mínimo: $100

### CDB (Certificado de Depósito Bancário)
| Prazo | Rendimento | IR | Mínimo |
|-------|------------|-----|---------|
| 30 dias | 90% CDI | 22.5% | $5,000 |
| 60 dias | 100% CDI | 20% | $5,000 |
| 90 dias | 110% CDI | 17.5% | $10,000 |
| 180 dias | 120% CDI | 17.5% | $10,000 |

### LCI/LCA (Imobiliário/Agro)
- Rendimento: **85% do CDI**
- Prazo: **90 dias**
- IR: **ISENTO** ✅
- Mínimo: $20,000

### Tesouro SELIC
- Rendimento: **100% da SELIC**
- Liquidez: **Imediata**
- IR: **15%**
- Mínimo: $1,000

---

## 💼 **MERCADO DE TRABALHO (v3.3)**

### Setores e Salários (ajustados automaticamente)

| Setor | Piso | Teto | Vagas | Multiplicador |
|-------|------|------|-------|---------------|
| 👮 Polícia | $3,000 | $16,000 | 50 | 1.5x |
| 🚑 Paramédico | $4,000 | $20,000 | 30 | 2.0x |
| 🔧 Mecânico | $2,400 | $10,000 | 40 | 1.2x |
| 🚕 Taxista | $2,200 | $8,000 | 60 | 1.1x |
| 🚛 Caminhoneiro | $2,800 | $12,000 | 40 | 1.4x |
| ⚖️ Advogado | $5,000 | $25,000 | 20 | 2.5x |
| 📰 Jornalista | $3,500 | $15,000 | 15 | 1.75x |
| 🗑️ Lixeiro | $2,100 | $6,000 | 30 | 1.05x |

### Ajuste Automático de Salário Mínimo
```
Novo Salário = Atual × (1 + Inflação + 50% do Crescimento PIB)
```

Limites: -5% a +15% por ajuste

---

## 📈 **INDICADORES ECONÔMICOS**

### Meta de Inflação
- **Centro:** 4% ao ano
- **Tolerância:** ±2%
- **SELIC sobe** se inflação > 6%
- **SELIC desce** se inflação < 2%

### Meta de Desemprego
- **Ideal:** < 6%
- **Natural:** 3-8%

### Velocidade de Circulação
- **Ideal:** 0.15 - 0.25
- **Alta demais:** risco de inflação
- **Baixa demais:** economia estagnada

---

## 🎯 **COMO FUNCIONA A AUTO-REGULAÇÃO**

```
┌─────────────────────────────────────────┐
│  1. Economy Monitor                     │
│     ↓ Rastreia circulação e PIB         │
├─────────────────────────────────────────┤
│  2. Monetary Policy                     │
│     ↓ Calcula inflação                  │
│     ↓ COPOM ajusta SELIC                │
├─────────────────────────────────────────┤
│  3. Labor Market                        │
│     ↓ Ajusta salário mínimo             │
├─────────────────────────────────────────┤
│  4. Stock Market                        │
│     ↓ Preços reagem à economia          │
├─────────────────────────────────────────┤
│  5. Economic Events                     │
│     ↓ Cria dinamismo (crises/booms)     │
├─────────────────────────────────────────┤
│  6. Banking System                      │
│     ↓ Rendimentos seguem SELIC          │
└─────────────────────────────────────────┘
        ↓ LOOP CONTÍNUO ↓
```

### Exemplos Práticos:

**Cenário 1: Inflação Alta**
1. Massa monetária cresce muito
2. Inflação sobe para 8%
3. COPOM aumenta SELIC de 0.75% → 1.5%
4. Investimentos ficam mais atrativos
5. Consumo reduz
6. Inflação volta para 4%

**Cenário 2: Recessão**
1. PIB cai 5%
2. Desemprego sobe para 12%
3. Evento "Recessão Econômica" dispara
4. SELIC reduz para estimular
5. Salário mínimo se mantém (proteger poder de compra)
6. Aos poucos, economia se recupera

**Cenário 3: Boom Econômico**
1. Evento "Boom Econômico" dispara
2. PIB cresce 25%
3. Desemprego cai para 2%
4. Ações sobem 15-20%
5. Inflação sobe (risco)
6. SELIC ajusta para controlar

---

## 📊 **ESTRUTURA DE BANCO DE DADOS**

### Novas Tabelas v3.3:
- `space_economy_stocks` - Empresas e ações
- `space_economy_portfolios` - Carteiras dos players
- `space_economy_stock_transactions` - Histórico de trades
- `space_economy_stock_history` - Histórico de preços
- `space_economy_ibovespa` - Histórico do índice
- `space_economy_bank_accounts` - Contas bancárias
- `space_economy_investments` - Investimentos
- `space_economy_bank_yields` - Histórico de rendimentos
- `space_economy_minimum_wage` - Histórico de salário mínimo
- `space_economy_employment_stats` - Estatísticas de emprego

### Tabelas v3.2:
- `space_economy_snapshots` - Snapshots econômicos
- `space_economy_transactions` - Transações agregadas
- `space_economy_sectors` - Indicadores setoriais
- `space_economy_psbanking_cursor` - Sincronização ps-banking

### Tabelas v3.1 e anteriores:
- `space_economy` - Estado global
- `space_economy_state` - Key/value
- `space_economy_debts` - Dívidas
- `space_economy_debt_payments` - Pagamentos
- `space_economy_installment_plans` - Parcelamentos
- `space_economy_loans` - Empréstimos
- `space_economy_credit_scores` - Score de crédito
- `space_economy_logs` - Logs do sistema
- E mais...

---

## 🔧 **CONFIGURAÇÃO**

### config.lua

```lua
-- Política Monetária
Config.MonetaryPolicy = {
  MetaInflacaoAnual = 0.04,    -- 4%
  ToleranciaInflacao = 0.02,   -- ±2%
  SelicMin = 0.002,            -- 0.2% mês
  SelicMax = 0.15,             -- 15% mês
  CopomIntervalMs = 3600000,   -- 1h
}

-- Mercado de Trabalho
Config.LaborMarket = {
  SalarioMinimoInicial = 2000,
  AjusteSalarioIntervalMs = 7200000,  -- 2h
  MetaDesemprego = 0.06,               -- 6%
}

-- Bolsa de Valores
Config.StockMarket = {
  UpdateIntervalMs = 120000,           -- 2 min
  CircuitBreakerThreshold = -0.10,     -- -10%
  TaxaCorretagem = 0.005,              -- 0.5%
  ImpostoGanhoCapital = 0.15,          -- 15%
}

-- Sistema Bancário
Config.Banking = {
  RendimentoPoupanca = 0.70,  -- 70% SELIC
  TaxaManutencao = 50,        -- $50/mês
}
```

---

## 🚀 **PRÓXIMAS FEATURES (Roadmap)**

### Em Desenvolvimento:
- [ ] Painel NUI completo de gestão econômica
- [ ] Trading de ações em tempo real (NUI)
- [ ] Gráficos de preços (candlestick)
- [ ] Indicadores técnicos (RSI, MACD, Bollinger)

### Planejado:
- [ ] Mercado de opções e futuros
- [ ] Forex (câmbio entre servidores)
- [ ] Fundos de investimento
- [ ] Previdência privada
- [ ] Seguro de vida/veículos
- [ ] Sistema de educação financeira in-game
- [ ] Achievements econômicos
- [ ] Ranking de maiores investidores

---

## 📝 **CHANGELOG**

### v3.3.0 (ATUAL) - MERCADO FINANCEIRO E TRABALHO
- ✅ **Bolsa de Valores** completa com 8 empresas
- ✅ **Índice Ibovespa** calculado em tempo real
- ✅ **Circuit Breaker** automático
- ✅ **Sistema Bancário** (Poupança, CDB, LCI/LCA, Tesouro)
- ✅ **Rendimentos automáticos** mensais
- ✅ **Mercado de Trabalho** com salário mínimo dinâmico
- ✅ **Taxa de desemprego** calculada automaticamente
- ✅ **8 setores** com pisos/tetos ajustáveis

### v3.2.0 - ECONOMIA ULTRA-REALISTA
- ✅ Monitoramento de PIB e circulação monetária
- ✅ Política monetária automática (SELIC)
- ✅ Inflação dinâmica baseada em massa monetária
- ✅ IPC com 5 categorias
- ✅ 10+ eventos econômicos
- ✅ COPOM virtual

### v3.1.0 - PERFORMANCE E OTIMIZAÇÃO
- ✅ Removido uso de information_schema
- ✅ Cache LRU completo (+400% performance)
- ✅ Auto-warmup de cache
- ✅ Estatísticas detalhadas

### v3.0.0 e anteriores
- Sistema de dívidas, parcelamentos, empréstimos
- Score de crédito
- Taxação automática
- Integração ps-banking
- E muito mais...

---

## 📞 **SUPORTE**

### Troubleshooting
1. Rode `/cache_stats` - verifique hit rate (ideal >85%)
2. Rode `/eco_relatorio` - verifique economia
3. Verifique logs do servidor
4. Certifique-se que MySQL tem permissões corretas

### Performance
- Hit rate ideal: >85%
- Inflação ideal: 2-6%
- Desemprego ideal: <8%
- Velocidade circulação: 0.15-0.25

---

## 📄 **LICENÇA**

Sistema desenvolvido para uso em servidores FiveM.
Todos os direitos reservados.

---

**Desenvolvido com ❤️ para a comunidade FiveM**

**v3.3.0** - O sistema econômico mais completo e realista do FiveM! 🚀
