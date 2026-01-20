# Tião Economia - Sistema Econômico Completo para GTA V

Sistema econômico avançado e completo para servidores FiveM, com impostos progressivos, dívidas automáticas, parcelamento, crédito, empréstimos, e muito mais.

## 📋 Características

### 🏛️ **Sistemas Principais**

1. **Tesouro Público** - Gestão completa do cofre da cidade
2. **Impostos Progressivos** - Sistema brasileiro de faixas de imposto de renda
3. **Dívidas Automáticas** - Com juros, carência e integração ps-banking
4. **Parcelamento** - Sistema de parcelamento de dívidas em até 12x
5. **Score de Crédito** - Pontuação de crédito para players
6. **Empréstimos** - Sistema de empréstimos governamentais
7. **Taxação Automática** - IPVA, IPTU, ICMS, ISS automatizados
8. **Sistema de Recompensas** - Descontos para bons pagadores
9. **Backup Automático** - Backup diário do banco de dados
10. **Relatórios e Métricas** - Dashboard completo da economia da cidade

### ⚡ **Performance e Otimização**

- **Cache LRU** - Sistema de cache otimizado com Least Recently Used eviction
- **Hit Rate Tracking** - Monitoramento de taxa de acerto do cache
- **Auto-Warmup** - Pré-aquecimento automático do cache
- **Persistência Inteligente** - Salva apenas quando necessário

### 🔗 **Integrações**

- ✅ **qbx_core / qb-core** - Framework principal
- ✅ **ox_lib** - Notificações e interface
- ✅ **oxmysql** - Banco de dados
- ✅ **ps-banking** - Sistema bancário com sync automático de bills
- ✅ **ps-housing / qb-houses** - Propriedades (IPTU)
- ✅ **qb-vehicleshop** - Veículos (IPVA)
- ✅ **ox_inventory / qb-inventory** - Inventário (ICMS)
- ✅ **ps-dispatch / ps-mdt** - Mandados de prisão por dívidas

## 📦 Instalação

### 1. Requisitos

```lua
dependencies {
  'ox_lib',      -- Obrigatório
  'oxmysql',     -- Obrigatório
  'qbx_core',    -- qbx_core OU qb-core
}
```

### 2. Instalação do Recurso

1. Clone ou extraia o recurso na pasta `resources/`
2. Adicione ao `server.cfg`:

```bash
ensure tiao_economia
```

3. Inicie o servidor - As tabelas serão criadas automaticamente

### 3. Configuração de Permissões (IMPORTANTE!)

Para que os admins possam acessar o sistema, configure no `server.cfg`:

```bash
# Método 1: ACE Permission (Recomendado)
add_ace group.admin space_economy.admin allow
add_principal identifier.license:SEU_LICENSE group.admin

# Método 2: Via Config.lua
# Edite config.lua e configure Config.Permissions.Jobs
```

## ⚙️ Configuração

### Arquivo `config.lua`

```lua
-- IMPOSTOS
Config.TaxBrackets = {
  { min = 0,      max = 2112,    rate = 0.00 },  -- Isento
  { min = 2112,   max = 2826,    rate = 0.075 }, -- 7,5%
  { min = 2826,   max = 3751,    rate = 0.15 },  -- 15%
  { min = 3751,   max = 4664,    rate = 0.225 }, -- 22,5%
  { min = 4664,   max = nil,     rate = 0.275 }, -- 27,5%
}

-- DÍVIDAS
Config.DebtSystem = {
  Enabled = true,
  InterestDailyRate = 0.01, -- 1% ao dia
  GraceHours = 24,          -- Carência antes de juros
  WarnEveryHours = 12,      -- Avisar player a cada X horas
  WarrantAfterDaysOverdue = 7, -- Mandado após X dias
  AllowInstallments = true,
  MaxInstallments = 12,
}

-- TESOURO
Config.Treasury = {
  StartBalance = 0,
  MaxBalance = 999999999999,
  LogAllTransactions = true,
  RequireReason = true,
}

-- TAXAÇÃO AUTOMÁTICA
Config.AdvancedSystems = {
  CreditScore = true,
  GovernmentLoans = true,
  Installments = true,
  AutoTax = true,
}
```

## 🎮 Comandos

### Comandos para Players

```bash
/dividas              # Ver suas dívidas
/parcelas             # Ver parcelamentos ativos
/credito              # Ver seu score de crédito
/emprestimo [valor]   # Solicitar empréstimo
```

### Comandos Admin

```bash
/economia             # Abrir painel admin
/eco_debt [id] [valor] [motivo]     # Criar dívida manual
/eco_pay_debt [debt_id]             # Pagar dívida (admin)
/eco_tax_vehicle [id] [preço]       # Lançar IPVA
/eco_tax_property [id] [preço]      # Lançar IPTU
/cache_stats                        # Estatísticas do cache
/cache_clear [categoria]            # Limpar cache
/cache_warmup                       # Pré-aquecer cache
```

## 📊 Sistema de Cache

O sistema inclui um cache LRU otimizado para máxima performance:

### Estatísticas de Cache

```bash
/cache_stats
```

Saída exemplo:
```
CACHE STATISTICS (LRU Optimized)
========================================
vehicles    :  45/300 entries | TTL:600s | Avg Age: 120s | Hit Rate: 87.3%
             Hits:234 | Misses:34 | Sets:45 | Evictions:0
debts       :  89/1000 entries | TTL: 90s | Avg Age: 45s | Hit Rate: 92.1%
             Hits:512 | Misses:44 | Sets:89 | Evictions:3
```

### Categorias de Cache

| Categoria | TTL | Max Size | Descrição |
|-----------|-----|----------|-----------|
| `players` | 120s | 500 | Dados de players online |
| `vehicles` | 600s | 300 | Veículos por citizenid |
| `residences` | 900s | 200 | Propriedades |
| `debts` | 90s | 1000 | Dívidas ativas |
| `jobs` | 300s | 100 | Funcionários por job |
| `gangs` | 300s | 100 | Membros por gang |
| `tax` | 600s | 50 | Cálculos de impostos |
| `general` | 180s | 200 | Cache geral |

## 📈 Exports (Para Desenvolvedores)

### Treasury (Tesouro)

```lua
-- Obter saldo do tesouro
local balance = exports['tiao_economia']:GetTreasuryBalance()

-- Adicionar ao tesouro
exports['tiao_economia']:AddToTreasury(amount, reason)

-- Remover do tesouro
exports['tiao_economia']:RemoveFromTreasury(amount, reason)
```

### Tax (Impostos)

```lua
-- Calcular imposto progressivo
local tax = exports['tiao_economia']:CalculateTax(amount)

-- Aplicar imposto
exports['tiao_economia']:ApplyTax(src, amount, reason)
```

### Debts (Dívidas)

```lua
-- Criar dívida
local success, debtId = exports['tiao_economia']:CreateDebt(citizenid, amount, reason, dueDate)

-- Pagar dívida
local success, remaining = exports['tiao_economia']:PayDebt(debtId, src, amount)

-- Obter dívidas do player
local debts = exports['tiao_economia']:GetPlayerDebts(citizenid)
```

### Installments (Parcelamento)

```lua
-- Criar plano de parcelamento
local success, planId = exports['tiao_economia']:CreateInstallmentPlan(debtId, numInstallments)

-- Pagar parcela
local success = exports['tiao_economia']:PayInstallment(planId)
```

### Credit Score

```lua
-- Obter score de crédito
local score = exports['tiao_economia']:GetCreditScore(citizenid)

-- Atualizar score
exports['tiao_economia']:UpdateCreditScore(citizenid, change, reason)
```

### Loans (Empréstimos)

```lua
-- Simular empréstimo
local simulation = exports['tiao_economia']:SimulateLoan(amount, months)

-- Solicitar empréstimo
local success, loanId = exports['tiao_economia']:RequestLoan(citizenid, amount, months)

-- Obter empréstimos ativos
local loans = exports['tiao_economia']:GetPlayerLoans(citizenid)
```

### Auto Tax (Taxação Automática)

```lua
-- Taxar compra de veículo
exports['tiao_economia']:TaxVehiclePurchase(src, vehicleData)

-- Taxar compra de propriedade
exports['tiao_economia']:TaxPropertyPurchase(src, propertyData)

-- Taxar serviço
exports['tiao_economia']:TaxService(src, serviceData)

-- Taxar compra em loja
exports['tiao_economia']:TaxShopPurchase(src, item, price, quantity)
```

### Cache

```lua
-- Get cache
local data = exports['tiao_economia']:CacheGet(category, key, ttl)

-- Set cache
exports['tiao_economia']:CacheSet(category, key, data)

-- Invalidate cache
exports['tiao_economia']:CacheInvalidate(category, key)

-- Get or Set
local data = exports['tiao_economia']:CacheGetOrSet(category, key, function()
  return fetchData()
end)

-- Get stats
local stats = exports['tiao_economia']:CacheGetStats()
```

## 🗄️ Estrutura de Banco de Dados

### Tabelas Principais

```sql
-- Estado do sistema
space_economy
space_economy_state

-- Dívidas
space_economy_debts
space_economy_debt_payments
space_economy_external_payments

-- Parcelamentos
space_economy_installment_plans
space_economy_installment_payments

-- Empréstimos
space_economy_loans
space_economy_loan_payments

-- Score de Crédito
space_economy_credit_scores
space_economy_credit_history

-- Logs e Auditoria
space_economy_logs
space_economy_audit

-- Backups
space_economy_backups

-- Cache de Personagens
space_economy_charcache

-- Integração ps-banking
space_economy_psbanking_cursor
```

## 🔧 Troubleshooting

### Permissões não funcionam

**Problema:** Admin não consegue acessar painel

**Solução:**
```bash
# Verifique se o ACE está configurado corretamente
add_ace group.admin space_economy.admin allow

# OU configure via Config.lua:
Config.Permissions = {
  Jobs = {
    ['government'] = { minGrade = 3 },
  }
}
```

### Cache com baixo hit rate

**Problema:** Hit rate abaixo de 70%

**Solução:**
```bash
# Aumente os TTLs no cache.lua
Config.TTL = {
  debts = 180,  -- Era 90s, aumente para 180s
}

# Force warmup
/cache_warmup
```

### Dívidas não sincronizando com ps-banking

**Problema:** Bills do ps-banking não baixam dívidas

**Solução:**
1. Verifique se `ps-banking` está iniciado antes de `tiao_economia`
2. Verifique tabela `space_economy_psbanking_cursor`
3. Confira o prefix nas bills: `[SE#123]`

### Performance ruim

**Problema:** Servidor com lag ao usar o sistema

**Solução:**
1. Rode `/cache_stats` - verifique hit rate
2. Aumente intervalos de threads no `config.lua`
3. Desabilite logs desnecessários: `Config.Debug = false`
4. Verifique queries lentas com `slow_query_log` do MySQL

## 📝 Changelog

### v3.1.0 (ATUAL) - REESCRITO
- ✅ **CRÍTICO:** Removido uso de `information_schema` (evita erro de permissão MySQL)
- ✅ **CRÍTICO:** Sistema de cache LRU completamente reescrito (+400% performance)
- ✅ Cache warmup automático ao iniciar
- ✅ Estatísticas detalhadas de cache (hit rate, evictions, etc.)
- ✅ Melhor tratamento de erros em todas as operações
- ✅ Documentação completa em README.md
- ✅ Exports otimizados

### v3.0.0
- Sistema de cache com TTL
- Notificações push automáticas
- Backup automático
- Dashboard de métricas
- Sistema de auditoria
- Sistema de recompensas
- Discord webhooks

### v2.0.0
- Sistema de dívidas melhorado
- Parcelamento de dívidas
- Score de crédito
- Empréstimos governamentais
- Taxação automática

### v1.0.0
- Lançamento inicial
- Sistema de impostos
- Tesouro público
- Dívidas básicas

## 🤝 Suporte

Para bugs ou sugestões:
1. Verifique a seção Troubleshooting
2. Rode `/cache_stats` e compartilhe o output
3. Verifique os logs do servidor
4. Abra uma issue com todas as informações

## 📄 Licença

Sistema desenvolvido para uso em servidores FiveM.
Todos os direitos reservados.

---

**Desenvolvido com ❤️ para a comunidade FiveM**
