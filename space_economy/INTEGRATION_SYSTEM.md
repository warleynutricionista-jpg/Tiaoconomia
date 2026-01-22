# 🏦 Sistema de Integração Econômica Centralizada v4.1

## 📋 Visão Geral

O **Sistema de Integração Econômica Centralizada** é uma melhoria revolucionária que traz controle total sobre todas as transações financeiras do servidor. O sistema econômico agora funciona paralelamente ao banco e gerencia automaticamente todos os serviços legais e ilegais, com detecção automática de recursos não integrados.

## 🎯 Objetivos Principais

1. ✅ **Controle Centralizado**: Todo dinheiro que entra/sai do servidor passa pelo sistema econômico
2. ✅ **Detecção Automática**: Identifica serviços não integrados em tempo real
3. ✅ **Preços Dinâmicos**: Balanceamento automático baseado em fatores econômicos
4. ✅ **Transparência Total**: Rastreamento completo de todas as transações
5. ✅ **Facilidade de Integração**: Novos serviços podem ser integrados rapidamente

---

## 🏗️ Arquitetura do Sistema

### Componentes Principais

```
┌─────────────────────────────────────────────────────┐
│           SISTEMA ECONÔMICO CENTRAL                 │
│                (space_economy)                       │
└─────────────────────┬───────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   SERVICE    │ │   DYNAMIC    │ │ TRANSACTION  │
│   REGISTRY   │ │   PRICING    │ │ INTERCEPTOR  │
└──────────────┘ └──────────────┘ └──────────────┘
        │             │             │
        └─────────────┼─────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   SERVIÇOS   │ │   PREÇOS     │ │  TRANSAÇÕES  │
│  REGISTRADOS │ │   TABELA     │ │     LOG      │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## 📦 Novos Módulos

### 1. Service Registry (Registro de Serviços)

**Arquivo**: `server/service_registry.lua`

#### O que faz:
- Mantém registro central de todos os serviços que fazem transações
- Detecta automaticamente recursos não registrados
- Classifica serviços por tipo (legal, ilegal, banking, etc.)
- Rastreia estatísticas de cada serviço

#### Tipos de Serviços:
```lua
LEGAL        -- Lojas legais, empregos oficiais
ILLEGAL      -- Drogas, armas, lavagem
BANKING      -- Sistema bancário
HOUSING      -- Propriedades e imóveis
VEHICLES     -- Concessionárias e veículos
JOBS         -- Empregos/salários
ORGANIZATIONS -- Empresas de players
GOVERNMENT   -- Serviços governamentais
OTHER        -- Outros serviços
```

#### Status de Integração:
```lua
FULLY_INTEGRATED      -- Totalmente integrado
PARTIALLY_INTEGRATED  -- Parcialmente integrado
NOT_INTEGRATED        -- Não integrado
PENDING               -- Pendente de integração
DISABLED              -- Desabilitado
```

#### Como registrar um serviço:
```lua
exports['space_economy']:RegisterService('meu_recurso', {
    type = 'LEGAL',
    description = 'Minha loja de itens',
    uses_economy_api = true,
    supports_dynamic_pricing = true,
    applies_taxes = true,
    logs_transactions = true,

    -- Callbacks opcionais
    get_prices_callback = function()
        return {
            item1 = 100,
            item2 = 250
        }
    end,

    set_prices_callback = function(newPrices)
        -- Atualiza preços no seu sistema
    end
})
```

---

### 2. Dynamic Pricing (Preços Dinâmicos)

**Arquivo**: `server/dynamic_pricing.lua`

#### O que faz:
- Calcula preços automaticamente baseado em fatores econômicos
- Atualiza preços de todos os serviços registrados
- Permite balanceamento da economia
- Histórico de variação de preços

#### Fatores que Afetam Preços:

| Fator | Peso | Descrição |
|-------|------|-----------|
| **Inflação** | 30% | Baseado no sistema monetário |
| **PIB** | 25% | Demanda geral da economia |
| **Circulação Monetária** | 20% | Quanto dinheiro está circulando |
| **SELIC** | 15% | Custo de capital |
| **Eventos Econômicos** | 10% | Crises, booms, etc. |

#### Categorias de Preços:

```lua
FOOD        -- Alimentos (volatilidade: 15%)
WEAPONS     -- Armas (volatilidade: 25%)
DRUGS       -- Drogas (volatilidade: 40%)
VEHICLES    -- Veículos (volatilidade: 10%)
PROPERTIES  -- Propriedades (volatilidade: 5%)
SERVICES    -- Serviços (volatilidade: 20%)
GENERAL     -- Itens gerais (volatilidade: 20%)
```

#### Exemplo de uso:
```lua
-- Calcular preço final
local finalPrice = exports['space_economy']:CalcPrice(
    100,      -- Preço base
    'FOOD',   -- Categoria
    {}        -- Dados adicionais
)

-- Obter multiplicador global
local mult = exports['space_economy']:GetGlobalPriceMultiplier()
print('Multiplicador atual: ' .. mult .. 'x')
```

---

### 3. Transaction Interceptor (Interceptador de Transações)

**Arquivo**: `server/transaction_interceptor.lua`

#### O que faz:
- Intercepta TODAS as transações financeiras do servidor
- Detecta recursos que fazem transações sem registro
- Aplica impostos automaticamente (opcional)
- Bloqueia transações de recursos não autorizados (opcional)
- Log completo de todas as transações

#### Eventos Monitorados:
```lua
-- QBCore/QBX
'QBCore:Server:AddMoney'
'QBCore:Server:RemoveMoney'

-- ESX
'esx:addMoney'
'esx:removeMoney'

-- Banking
'ps-banking:server:transfer'
'qb-banking:server:depositMoney'

-- E muitos outros...
```

#### Configurações:
```lua
Config.enforce_integration = false  -- Bloqueia não registrados
Config.auto_apply_taxes = true      -- Aplica impostos auto
Config.log_all_transactions = true  -- Loga tudo
Config.alert_threshold = 10000      -- Alerta em transações > 10k
```

---

### 4. Integration Monitor (Painel de Monitoramento)

**Arquivo**: `server/integration_monitor.lua`

#### O que faz:
- Interface de administração para visualizar todo o sistema
- Relatórios automáticos diários
- Alertas em tempo real
- Gerenciamento de integrações

---

## 🗄️ Banco de Dados

### Novas Tabelas

#### 1. `space_economy_services`
Registro de todos os serviços integrados.

```sql
- service_name (VARCHAR 100)
- service_type (VARCHAR 50)
- description (TEXT)
- resource (VARCHAR 100)
- status (VARCHAR 50)
- integration_config (JSON)
- pricing_config (JSON)
- stats (JSON)
```

#### 2. `space_economy_unregistered_services`
Serviços detectados mas não integrados.

```sql
- resource_name (VARCHAR 100)
- first_detected (INT timestamp)
- last_seen (INT timestamp)
- transaction_count (INT)
- total_volume (DECIMAL)
- suggested_type (VARCHAR 50)
- sample_data (JSON)
```

#### 3. `space_economy_prices`
Preços dinâmicos de todos os itens.

```sql
- item_id (VARCHAR 200)
- base_price (DECIMAL)
- current_price (DECIMAL)
- category (VARCHAR 50)
- multiplier (DECIMAL)
- last_update (INT)
```

#### 4. `space_economy_price_history`
Histórico de variações de preço.

```sql
- item_id (VARCHAR 200)
- price (DECIMAL)
- multiplier (DECIMAL)
- economic_factors (JSON)
- timestamp (INT)
```

#### 5. `space_economy_intercepted_transactions`
Log de transações interceptadas.

```sql
- timestamp (INT)
- source (INT player)
- resource (VARCHAR 100)
- event_name (VARCHAR 200)
- amount (DECIMAL)
- transaction_type (VARCHAR 50)
- was_blocked (BOOLEAN)
- taxes_applied (DECIMAL)
```

#### 6. `space_economy_integration_reports`
Relatórios diários automáticos.

```sql
- report_date (DATE)
- total_registered_services (INT)
- total_unregistered_services (INT)
- total_transactions (INT)
- total_volume (DECIMAL)
- full_report (JSON)
```

### Views Úteis

```sql
-- Top serviços não registrados
v_top_unregistered_services

-- Estatísticas de serviços registrados
v_registered_services_stats

-- Atividade de transações por hora
v_transaction_activity_hourly

-- Resumo diário de economia
v_daily_economy_summary
```

---

## 🎮 Comandos de Administração

### Monitoramento

```bash
/se:overview
# Exibe visão geral completa do sistema

/se:monitor
# Abre painel de monitoramento (NUI)

/se:services
# Lista todos os serviços registrados

/se:unregistered
# Lista serviços não registrados detectados
```

### Gerenciamento de Serviços

```bash
/se:integrate <resource_name>
# Integra manualmente um serviço não registrado

/se:ignore <resource_name>
# Marca um serviço como ignorado (não alertar mais)
```

### Preços

```bash
/se:prices
# Relatório completo de preços dinâmicos

/se:updateprices
# Força atualização de todos os preços
```

### Interceptador

```bash
/se:intercept
# Estatísticas do interceptador de transações

/se:toggleblock
# Ativa/desativa modo de bloqueio

/se:blockmode
# Ativa/desativa bloqueio de não registrados
```

---

## 🔧 Instalação

### 1. Executar SQL

Execute o arquivo SQL para criar as tabelas:

```bash
# No MySQL/HeidiSQL/phpMyAdmin
source space_economy/database_integration_system.sql
```

### 2. Reiniciar Resource

```bash
ensure space_economy
```

### 3. Verificar Logs

Verifique o console F8 do servidor para confirmar:

```
[ServiceRegistry] Inicializando sistema de registro de serviços...
[DynamicPricing] Inicializando sistema de preços dinâmicos...
[TransactionInterceptor] Inicializando interceptador de transações...
[IntegrationMonitor] Inicializando painel de monitoramento...
```

---

## 📊 Fluxo de Transação Completo

```
1. TRANSAÇÃO INICIADA
   ├─> Recurso chama evento/export/função
   │
2. INTERCEPTADOR DETECTA
   ├─> Verifica se recurso está registrado
   ├─> Loga a transação
   │
3. VALIDAÇÃO
   ├─> Se NÃO registrado:
   │   ├─> Detecta e registra em unregistered_services
   │   ├─> Bloqueia OU permite (conforme config)
   │   └─> Alerta administradores
   ├─> Se REGISTRADO:
   │   ├─> Permite transação
   │   └─> Atualiza estatísticas do serviço
   │
4. IMPOSTOS (se habilitado)
   ├─> Calcula imposto baseado no tipo de serviço
   ├─> Aplica automaticamente
   └─> Deposita no tesouro
   │
5. PREÇOS DINÂMICOS
   ├─> Se item tem preço registrado:
   │   ├─> Aplica multiplicadores econômicos
   │   └─> Atualiza preço final
   │
6. CONCLUSÃO
   └─> Transação completa
       └─> Log salvo no banco de dados
```

---

## 🎯 Como Integrar Seu Recurso

### Método 1: Auto-registro no fxmanifest

```lua
-- No seu resource/fxmanifest.lua
dependency 'space_economy'

-- No seu resource/server/main.lua
Citizen.CreateThread(function()
    Wait(5000) -- Aguarda space_economy carregar

    exports['space_economy']:RegisterService('meu_recurso', {
        type = 'LEGAL',
        description = 'Loja de ferramentas',
        uses_economy_api = true,
        supports_dynamic_pricing = true,

        -- Callback para obter preços
        get_prices_callback = function()
            return Config.Items -- Seus itens
        end,

        -- Callback para atualizar preços
        set_prices_callback = function(newPrices)
            for item, price in pairs(newPrices) do
                Config.Items[item].price = price
            end
        end
    })
end)
```

### Método 2: Usar API do Space Economy

```lua
-- Para adicionar dinheiro
TriggerEvent('space_economy:AddMoney', source, amount, 'bank', 'venda_item')

-- Para remover dinheiro
TriggerEvent('space_economy:RemoveMoney', source, amount, 'cash', 'compra_item')

-- Para criar dívida
exports['space_economy']:CreateDebt(source, amount, 'IPVA', {
    reason = 'Imposto de veículo'
})
```

### Método 3: Integração via Comando

Se você NÃO é desenvolvedor do recurso, pode integrar via comando:

```bash
# 1. Espere o recurso ser detectado automaticamente
/se:unregistered

# 2. Integre manualmente
/se:integrate nome_do_recurso
```

---

## 🛡️ Segurança e Anti-Exploit

### Circuit Breakers

O sistema possui proteções automáticas:

```lua
-- Limites de segurança
MaxInflationDeltaPerHour = 0.05  -- Máx 5% inflação/hora
MaxTaxMultiplier = 0.40          -- Máx 40% de imposto
SuspiciousThreshold = 1000000    -- Alerta em transações > 1M
MaxGainPerMinute = 10000000      -- Limite de ganho/min
```

### Quarentena Automática

Dinheiro suspeito é automaticamente congelado e investigado.

### Auditoria Completa

Todas as ações são registradas com:
- Timestamp
- Quem executou
- O que foi feito
- Valores envolvidos
- Metadata completa

---

## 📈 Monitoramento em Tempo Real

### Alertas Automáticos

O sistema alerta administradores quando:

1. ✅ Serviço não registrado movimenta mais de R$ 100.000
2. ✅ Multiplicador de preços atinge valores extremos (< 0.7x ou > 2.0x)
3. ✅ Taxa de bloqueio ultrapassa 10%
4. ✅ Transação suspeita é detectada

### Relatórios Diários

Todo dia à meia-noite, o sistema gera automaticamente:

- Total de serviços registrados/não registrados
- Volume de transações
- Transações bloqueadas
- Top 10 serviços não integrados
- Variações de preços
- Saúde da economia

---

## 🔍 Troubleshooting

### Serviço não está sendo detectado

1. Verifique se o serviço realmente faz transações
2. Execute `/se:intercept` para ver estatísticas
3. Veja os logs do console

### Preços não estão atualizando

1. Execute `/se:updateprices` para forçar atualização
2. Verifique se o serviço está marcado como `supports_dynamic_pricing = true`
3. Veja o multiplicador global com `/se:prices`

### Transações sendo bloqueadas incorretamente

1. Verifique o modo de bloqueio: `/se:toggleblock`
2. Integre o serviço: `/se:integrate <resource>`
3. Ajuste as configurações no banco

---

## 📞 Suporte e Recursos

### Exports Disponíveis

```lua
-- Service Registry
exports['space_economy']:RegisterService(name, data)
exports['space_economy']:GetService(name)
exports['space_economy']:GetAllServices()
exports['space_economy']:GetUnregisteredServices()

-- Dynamic Pricing
exports['space_economy']:GetPrice(itemId)
exports['space_economy']:CalcPrice(basePrice, category, data)
exports['space_economy']:RegisterServicePrices(service, prices, category)
exports['space_economy']:GetServicePrices(service)
exports['space_economy']:GetGlobalPriceMultiplier()

-- Transaction Interceptor
exports['space_economy']:EnableBlocking(enable)
exports['space_economy']:GetStatistics()

-- Integration Monitor
exports['space_economy']:GetMonitoringData()
exports['space_economy']:GenerateDailyReport()
```

---

## 🎉 Benefícios do Sistema

### Para Administradores

✅ **Controle Total**: Veja tudo que acontece com dinheiro no servidor
✅ **Detecção Automática**: Não perca mais recursos não integrados
✅ **Balanceamento Fácil**: Ajuste a economia com um comando
✅ **Relatórios Automáticos**: Dados diários sem esforço
✅ **Segurança**: Anti-exploit integrado

### Para Desenvolvedores

✅ **API Simples**: Fácil de integrar
✅ **Callbacks Flexíveis**: Customize o comportamento
✅ **Preços Automáticos**: Não precisa se preocupar com balanceamento
✅ **Documentação Completa**: Tudo explicado
✅ **Suporte a Múltiplos Frameworks**: QBCore, QBX, ESX

### Para Jogadores

✅ **Economia Real**: Preços variam com oferta/demanda
✅ **Transparência**: Todos os impostos são claros
✅ **Justiça**: Todos seguem as mesmas regras
✅ **Realismo**: Sistema econômico complexo e realista

---

## 📝 Changelog v4.1

### Novidades

- ✨ Sistema de Registro Central de Serviços
- ✨ Detecção Automática de Recursos Não Integrados
- ✨ Preços Dinâmicos Baseados em Fatores Econômicos
- ✨ Interceptador de Transações em Tempo Real
- ✨ Painel de Monitoramento Avançado
- ✨ Aplicação Automática de Impostos
- ✨ Relatórios Diários Automatizados
- ✨ Sistema de Alertas em Tempo Real

### Melhorias

- 🔧 Performance otimizada com cache inteligente
- 🔧 Banco de dados otimizado com índices
- 🔧 Views SQL para consultas rápidas
- 🔧 Triggers para auditoria automática
- 🔧 Stored procedures para manutenção

---

## 🚀 Roadmap Futuro

- [ ] Interface NUI completa para o painel
- [ ] Gráficos de variação de preços
- [ ] Machine Learning para detecção de padrões
- [ ] API REST para integrações externas
- [ ] Mobile app para administração
- [ ] Integração com Discord para alertas

---

**Desenvolvido com ❤️ para o Tiaoconomia**

*Sistema de Integração Econômica Centralizada v4.1*
*© 2026 - Todos os direitos reservados*
