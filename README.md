# Tiãoconomia - Sistema Econômico (QBCore/QBX) v4.0

Sistema econômico completo e ultra-realista para servidores FiveM/QBCore/QBX. Ele simula uma economia real com **PIB, SELIC, inflação dinâmica, bolsa de valores, banco, mercado de trabalho, dívidas, tributos progressivos, políticas monetárias automáticas, eventos econômicos, trilha de dinheiro e integrações avançadas**.

Este README é **explicativo e detalhado**, cobrindo **toda a amplitude do script**, incluindo: arquitetura, fluxo da economia, funcionalidades, comandos, exports, integrações, instalação, SQL e configuração.

---

## ✅ O que o sistema entrega (amplitude completa)

### 🧠 Núcleo econômico
- **Economy Monitor**: calcula PIB, circulação monetária, velocidade de circulação, PIB per capita e bancarização.
- **Política Monetária**: SELIC dinâmica, inflação, IPC por categoria e COPOM automático.
- **Eventos Econômicos**: crises, booms e eventos setoriais que afetam preços, PIB e mercado.
- **Stock Market**: bolsa com empresas listadas, Ibovespa, circuit breaker, lucro/prejuízo.
- **Banco e investimentos**: poupança, CDBs, LCI/LCA e Tesouro SELIC com IR/regra de prazo.
- **Mercado de trabalho**: salário mínimo dinâmico, pisos setoriais, desemprego.

### 💰 Tributos, dívidas e crédito
- **Impostos progressivos e baseados em patrimônio**.
- **Dívidas com juros e parcelamento**.
- **Score de crédito** que impacta empréstimos.
- **Taxação automática** em compras/serviços (configurável).

### 🛡️ Governança e segurança
- **Economy Guard**: bloqueio de transações suspeitas, circuit breakers, quarentena.
- **Money Trail**: rastreia transações grandes para auditoria.
- **Auditoria e logs** com retenção e webhook.

### 🔌 Integrações
- **Frameworks**: QBX/QBCore (detecção automática).
- **Banking/Dispatch/MDT/Housing/Garages/Dealership/Inventário**.
- **Integrações via DB** para sistemas externos.

---

## 📦 Instalação rápida

1. **Dependências obrigatórias** (no `server.cfg`):
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure tiao_economia
   ```
2. **Clone o recurso** para `resources/[qb]`.
3. **Importe o SQL** na sua base (arquivos em `tiao_economia/sql/`).
4. **Configure** `tiao_economia/config.lua` conforme sua economia.
5. **Reinicie** o servidor.

---

## ✅ Dependências

**Obrigatórias**
- `ox_lib`
- `oxmysql`
- `qbx_core` (ou `qb-core`)

**Opcionais**
- `ps-dispatch` / `ps-mdt`
- `ps-banking`
- `ps-housing`
- `rhd_garage`
- `rm-dealership`
- `ox_inventory` / `ps-inventory` / `qb-inventory`

---

## 🧭 Como a economia funciona (fluxo geral)

1. **Economy Monitor** registra transações (internas e externas) e recalcula PIB/circulação.
2. **Política Monetária** ajusta SELIC e inflação conforme velocidade do dinheiro.
3. **Mercado** reage: preços e investimentos mudam com SELIC/inflação.
4. **Eventos Econômicos** podem disparar impactos (crises, booms, setoriais).
5. **Tesouro** coleta impostos e distribui recursos (UBI/benefícios).
6. **Segurança** monitora transações suspeitas e aplica bloqueios.

---

## 🎮 Comandos e atalhos

### 👥 Jogadores
- `/taxas` → painel de impostos/pagamentos
- `/economia` → painel administrativo (com permissão)
- `/eco_testui` → abre a NUI local para diagnóstico

**Keybinds padrão**
- `F7` → painel de impostos
- `F12` → painel administrativo
- `5` → teste de UI

### 🛡️ Admin/GM
- `/eco_eventos` → menu de intervenção econômica (boom/crise/estímulos)
- `/eco_checkperm` → diagnóstico de permissões (console/in-game)

---

## 🧩 Exports (Funções)

As funções abaixo estão disponíveis via `exports['tiao_economia']:<Funcao>()`:

### 🏛️ Treasury (Tesouro)
- `GetTreasuryBalance()`
- `AddToTreasury(amount, reason)`
- `RemoveFromTreasury(amount, reason)`

### 🧾 Tax (Impostos)
- `CalculateTax(amount)`
- `ApplyTax(src, amount, reason)`

### 💳 Debts (Dívidas)
- `CreateDebt(citizenid, amount, reason)`
- `PayDebt(debtId)`
- `GetPlayerDebts(citizenid)`

### 📆 Installments (Parcelamento)
- `CreateInstallmentPlan(citizenid, totalAmount, installments)`
- `PayInstallment(installmentId)`

### 📈 Credit Score
- `GetCreditScore(citizenid)`
- `UpdateCreditScore(citizenid, points)`

### 💵 Loans (Empréstimos)
- `SimulateLoan(amount, installments)`
- `RequestLoan(citizenid, amount, installments)`
- `GetPlayerLoans(citizenid)`

### 🧾 Auto Tax (Taxação automática)
- `TaxVehiclePurchase(src, vehiclePrice)`
- `TaxPropertyPurchase(src, propertyPrice)`
- `TaxService(src, serviceAmount)`
- `TaxShopPurchase(src, purchaseAmount)`

### 📊 Reports
- `GetEconomyReport()`
- `GetDailyMetrics()`

### ⚡ Cache (v3.1)
- `CacheGet(key)`
- `CacheSet(key, value, ttl)`
- `CacheInvalidate(key)`
- `CacheGetOrSet(key, ttl, cb)`
- `CacheGetStats()`

### 🔔 Notifications (v3.1)
- `NotifyDebts()`
- `NotifyInstallments()`

### 🧰 Backup (v3.1)
- `CreateBackup()`
- `RestoreBackup(filename)`
- `ListBackups()`

### 📉 Metrics (v3.1)
- `GetDashboardData()`
- `GetWeeklyRevenue()`
- `GetTopDebtors()`

### 🧾 Money Trail
- `LogMoneyTrail(payload)`
- `GetMoneyTrail(limit)`

### 🕵️ Audit (v3.1)
- `AuditLog(category, message, meta)`
- `AuditGetLogs(limit)`
- `AuditGetStats()`

### 🎁 Rewards (v3.1)
- `RecordPayment(citizenid, amount)`
- `GetDiscount(citizenid)`
- `ApplyDiscount(amount, citizenid)`
- `GetPlayerRewardInfo(citizenid)`
- `GetTopPayers()`

### 💬 Discord (v3.1)
- `SendDiscordEmbed(payload)`
- `DiscordTreasuryTransaction(payload)`
- `DiscordDebtCreated(payload)`
- `DiscordDebtPaid(payload)`
- `DiscordAdminAction(payload)`
- `DiscordAlert(payload)`

### 🗄️ DB Integrations (v3.1)
- `GetDBIntegrationStats()`
- `ForceCheckSystem()`

### 📊 Economy Monitor (v4.0)
- `RegisterTransaction(reason, amount, meta)`
- `GetEconomyReport()`
- `GetPIB()`
- `GetPIBPerCapita()`
- `GetMoneyCirculation()`
- `GetVelocity()`

### 💰 Monetary Policy (v4.0)
- `GetSELIC()`
- `GetInflation()`
- `GetMonthlyInflation()`
- `AdjustPriceForInflation(basePrice)`
- `GetMonetaryPolicyReport()`
- `AdjustIPCCategory(category, delta)`
- `ForceCOPOMMeeting()`

### 🎲 Economic Events (v4.0)
- `TriggerEconomicEvent(eventId)`
- `GetCurrentEvent()`
- `GetEventHistory()`

### 📈 Stock Market (v4.0)
- `BuyStock(src, symbol, amount)`
- `SellStock(src, symbol, amount)`
- `GetPortfolio(citizenid)`
- `GetStockQuotes()`

### 🏦 Banking System (v4.0)
- `Invest(src, productId, amount)`
- `RedeemInvestment(src, investmentId)`
- `GetInvestments(citizenid)`

### 👷 Labor Market (v4.0)
- `GetMinimumWage()`
- `GetUnemploymentRate()`
- `GetSectorMinSalary(sector)`
- `GetLaborMarketReport()`
- `ForceWageAdjustment()`

---

## 🏦 Produtos bancários (detalhe)

- **Poupança**: rendimento baseado na SELIC (isento de IR).
- **CDB**: prazos 30/60/90/180 com % do CDI.
- **LCI/LCA**: isento de IR.
- **Tesouro SELIC**: liquidez imediata.

---

## 📈 Bolsa de Valores

- Empresas listadas com cotações dinâmicas.
- **Ibovespa** calculado em tempo real.
- **Circuit breaker** automático em grandes quedas.

---

## 🎲 Eventos Econômicos

Eventos disponíveis (exemplos):
- `crise_financeira`, `recessao`, `boom_economico`, `crescimento_acelerado`
- `crise_combustivel`, `safra_recorde`, `bolha_imobiliaria`, `greve_saude`
- `inovacao_tecnologica`, `investimento_estrangeiro`, `desastre_natural`, `acordo_comercial`

---

## ⚙️ Configuração (principais blocos)

Edite `tiao_economia/config.lua` para ajustar a economia:

- **Impostos**: `Config.TaxBrackets`, `Config.TaxCatalog`, `Config.TransactionTax`
- **Tributação dinâmica**: `Config.DynamicTax`, `Config.WealthTax`, `Config.WealthDecay`, `Config.AssetTax`
- **Lavagem oficial**: `Config.MoneyLaundering`
- **UBI/Redistribuição**: `Config.UBI`
- **Permissões**: `Config.Permissions`
- **Dívidas/Parcelamento**: `Config.DebtSystem`, `Config.WarrantAlert`
- **Tesouro**: `Config.Treasury`
- **Money Trail**: `Config.MoneyTrail`
- **Eventos econômicos**: `Config.EconomicEvents`
- **Inflação**: `Config.Inflation`
- **Segurança/Economy Guard**: `Config.Security`
- **Logs e Webhooks**: `Config.Logging`, `Config.Webhooks`, `Config.DiscordWebhooks`
- **Integrações**: `Config.Integrations`, `Config.ExternalIntegrations`, `Config.DBIntegrations`

---

## 🗄️ Banco de dados (SQL)

Tabelas principais:
- `space_economy_state`
- `space_economy_logs`
- `space_economy_debts`
- `space_economy_installments`
- `space_economy_loans`
- `space_economy_credit_scores`
- `space_economy_processed_transactions`
- `space_economy_integration_config`

---

## 🔌 Integrações suportadas

### Framework
- **QBX Core** (qbx_core)
- **QBCore** (qb-core)

### Sistemas
- **Banking**: ps-banking (fallback qbx/qb)
- **Dispatch/MDT**: ps-dispatch / ps-mdt
- **Housing**: ps-housing, qb-houses
- **Garages**: rhd_garage, qb-garage/qbx-garages
- **Dealership**: rm-dealership, qb-vehicleshop
- **Inventário**: ox_inventory, ps-inventory, qb-inventory

---

## 🧪 Dicas de uso rápido

- Use `/economia` para acessar o painel administrativo e acompanhar indicadores.
- Utilize `RegisterTransaction` para registrar transações externas e enriquecer o PIB.
- Ajuste `Config.EconomicEvents` para controlar eventos automáticos.
- Para economia realista, mantenha `Config.Inflation.AutoAdjust = true`.

---

## 📁 Estrutura do recurso

- `tiao_economia/` → resource principal (server/client/shared/html/sql)
- `tiao_economia/config.lua` → configuração global
- `tiao_economia/fxmanifest.lua` → dependências e exports

---

## 📄 Licença

MIT (se aplicável). Ajuste conforme seu projeto.
