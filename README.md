# Tiãoconomia - Sistema Econômico (QBCore/QBX) v4.0

Sistema econômico completo e ultra-realista para servidores FiveM/QBCore/QBX, com PIB, SELIC, inflação dinâmica, bolsa de valores, banco, mercado de trabalho, dívidas, tributos e integrações avançadas.

Este README reúne **todas as funções (exports), comandos e instruções essenciais** para instalação, configuração e uso do sistema.

---

## 📦 Instalação rápida

1. **Dependências obrigatórias** (no `server.cfg`):
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure tiao_economia
   ```
2. **Clone o recurso** para `resources/[qb]` e suba o SQL (veja a pasta `tiao_economia/sql/`).
3. **Configure** o arquivo `tiao_economia/config.lua` conforme sua economia.
4. **Reinicie** o servidor.

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
