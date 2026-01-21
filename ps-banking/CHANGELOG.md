# Changelog - PS-Banking Enhanced

## Melhorias Implementadas

### 🗄️ Banco de Dados (ps-banking.sql)

#### Novas Tabelas
- **ps_banking_investments**: Sistema de investimentos para jogadores
- **ps_banking_audit_log**: Log de auditoria para todas operações bancárias
- **ps_banking_transfer_limits**: Controle de limites diários de transferência

#### Melhorias nas Tabelas Existentes
- ✅ Adicionado índices para melhor performance
  - `idx_identifier`, `idx_date`, `idx_type` em transactions
  - `idx_identifier_date` para queries complexas
  - `idx_isPaid`, `idx_due_date` em bills
  - `idx_status`, `idx_holder` em accounts

- ✅ Adicionado constraints de integridade
  - CHECK para garantir valores positivos
  - UNIQUE KEY para evitar duplicatas
  - Valores DEFAULT apropriados

- ✅ Novos campos
  - `identifier2` em bills (para rastrear quem criou a fatura)
  - `due_date` e `paid_date` em bills
  - `status` em accounts (active, frozen, closed)
  - `created_at` e `updated_at` com timestamps automáticos
  - `metadata` JSON em transactions

- ✅ Melhor charset e collation (utf8mb4_unicode_ci)

### ⚙️ Configuração (config.lua)

#### Novas Configurações

**Config.Debug**
- Modo debug para prints detalhados

**Config.Security** (Novo)
- `EnableTransferLimits`: Habilitar limites de transferência
- `DailyTransferLimit`: Limite diário de transferências (1.000.000)
- `MaxTransferAmount`: Valor máximo por transferência (500.000)
- `MinTransferAmount`: Valor mínimo por transferência (1)
- `MaxWithdrawAmount`: Valor máximo de saque no ATM (100.000)
- `MaxDepositAmount`: Valor máximo de depósito no ATM (500.000)
- `EnableAuditLog`: Habilitar log de auditoria
- `RequireOnlineForBills`: Requer jogador online para enviar faturas

**Config.Accounts** (Novo)
- `MaxAccountsPerPlayer`: Máximo de contas por jogador (5)
- `MinAccountBalance`: Saldo mínimo (0)
- `InitialAccountBalance`: Saldo inicial (0)
- `AllowNegativeBalance`: Permitir saldo negativo (false)

**Config.Fees** (Novo)
- `EnableFees`: Habilitar taxas de transação
- `TransferFee`: Taxa fixa por transferência
- `TransferFeePercent`: Taxa percentual por transferência
- `ATMWithdrawFee`: Taxa de saque no ATM
- `BillFee`: Taxa para criar faturas

**Config.Bills** (Novo)
- `MaxBillAmount`: Valor máximo de fatura (1.000.000)
- `MinBillAmount`: Valor mínimo de fatura (1)
- `EnableDueDates`: Habilitar vencimento de faturas
- `DefaultDueDays`: Dias padrão até vencimento (7)

**Config.History** (Novo)
- `MaxTransactionsShown`: Máximo de transações mostradas (100)
- `EnableTransactionDelete`: Permitir deletar histórico
- `EnableTransactionExport`: Permitir exportar histórico

**Config.Notifications** (Novo)
- `EnableBillNotifications`: Notificar ao receber faturas
- `EnableTransferNotifications`: Notificar ao receber transferências
- `EnableLowBalanceWarning`: Avisar quando saldo baixo
- `LowBalanceThreshold`: Limite para aviso de saldo baixo (1.000)

**Config.Webhooks** (Novo)
- Integração com Discord Webhooks
- `TransferWebhook`: Webhook para transferências
- `BillWebhook`: Webhook para faturas
- `AccountWebhook`: Webhook para contas
- `AuditWebhook`: Webhook para logs de auditoria

### 🔐 Servidor (server/main.lua)

#### Novas Funções Utilitárias

**debugPrint(message)**
- Prints de debug controlados por Config.Debug

**logAudit(action, identifier, targetIdentifier, accountId, amount, details)**
- Sistema de auditoria completo
- Registra todas operações importantes

**validateAmount(amount, minAmount, maxAmount)**
- Validação de valores
- Previne valores inválidos ou fora dos limites

**checkDailyLimit(identifier, amount)**
- Verifica limites diários de transferência
- Previne abuso e lavagem de dinheiro

**updateDailyLimit(identifier, amount)**
- Atualiza contador de transferências diárias
- Reset automático a cada dia

**calculateFee(amount, feeType)**
- Calcula taxas de transação
- Suporta taxas fixas e percentuais

**sendWebhook(webhookUrl, title, description, color)**
- Envia notificações para Discord
- Logs detalhados de operações

#### Melhorias nas Funções Existentes

**transferMoney**
- ✅ Validação de valores
- ✅ Verificação de limites diários
- ✅ Cálculo de taxas
- ✅ Log de auditoria
- ✅ Webhook notifications
- ✅ Debug logging

**ATMwithdraw / ATMdeposit**
- ✅ Validação de valores mínimos/máximos
- ✅ Cálculo de taxas
- ✅ Log de auditoria
- ✅ Debug logging

**createNewAccount**
- ✅ Validação de nome único
- ✅ Limite máximo de contas por jogador
- ✅ Saldo inicial configurável
- ✅ Log de auditoria
- ✅ Webhook notifications

**createBill**
- ✅ Validação de valores
- ✅ Data de vencimento
- ✅ Cálculo de taxas
- ✅ Log de auditoria
- ✅ Webhook notifications

#### Novas Funções Exportáveis

**GetPlayerAllAccounts(identifier)**
```lua
-- Retorna todas as contas de um jogador (owner ou user)
local accounts = exports["ps-banking"]:GetPlayerAllAccounts(identifier)
```

**SetAccountStatus(accountId, status)**
```lua
-- Define status da conta: 'active', 'frozen', 'closed'
local success = exports["ps-banking"]:SetAccountStatus(accountId, "frozen")
```

**FreezeAccount(accountId) / UnfreezeAccount(accountId)**
```lua
-- Congela ou descongela uma conta
exports["ps-banking"]:FreezeAccount(accountId)
exports["ps-banking"]:UnfreezeAccount(accountId)
```

**CloseAccount(accountId)**
```lua
-- Fecha uma conta permanentemente
exports["ps-banking"]:CloseAccount(accountId)
```

**GetAccountTransactions(accountId, limit)**
```lua
-- Retorna transações de uma conta
local transactions = exports["ps-banking"]:GetAccountTransactions(accountId, 50)
```

**GetUnpaidBills(identifier)**
```lua
-- Retorna faturas não pagas de um jogador
local bills = exports["ps-banking"]:GetUnpaidBills(identifier)
```

**HasSufficientBalance(source, amount, accountType)**
```lua
-- Verifica se jogador tem saldo suficiente
local hasMoney = exports["ps-banking"]:HasSufficientBalance(source, 5000, "bank")
```

**GetAccountOwner(accountId)**
```lua
-- Retorna informações do dono da conta
local owner = exports["ps-banking"]:GetAccountOwner(accountId)
```

**TransferBetweenAccounts(fromAccountId, toAccountId, amount, reason)**
```lua
-- Transfere entre contas bancárias
local success = exports["ps-banking"]:TransferBetweenAccounts(1, 2, 10000, "Pagamento")
```

### 📊 Recursos de Segurança

1. **Limites de Transferência**
   - Limite diário por jogador
   - Limite máximo por transação
   - Reset automático diário

2. **Validação de Valores**
   - Valores mínimos e máximos
   - Verificação de tipos
   - Prevenção de valores negativos

3. **Sistema de Auditoria**
   - Log de todas operações
   - Rastreamento de IP
   - Metadata em JSON

4. **Taxas de Transação**
   - Taxas fixas
   - Taxas percentuais
   - Configurável por tipo de operação

5. **Status de Contas**
   - Contas ativas
   - Contas congeladas
   - Contas fechadas

### 🔔 Integrações

1. **Discord Webhooks**
   - Notificações de transferências
   - Alertas de faturas
   - Logs de criação/exclusão de contas
   - Auditoria completa

2. **Sistema de Investimentos**
   - Integração com space_economy
   - Integração com tiao_economia
   - Tabela dedicada para investimentos

### 📈 Performance

1. **Índices de Banco de Dados**
   - Queries mais rápidas
   - Melhor performance em grandes volumes

2. **Queries Otimizadas**
   - Uso de índices compostos
   - Redução de full table scans

### 🔧 Manutenção

1. **Debug Mode**
   - Logs detalhados quando habilitado
   - Facilita troubleshooting

2. **Timestamps Automáticos**
   - created_at e updated_at automáticos
   - Rastreamento de mudanças

3. **Validação de Dados**
   - Constraints no banco
   - Validação em Lua
   - Prevenção de dados inválidos

## Como Atualizar

1. **Backup do banco de dados atual**
2. **Execute o novo ps-banking.sql** (ele usará IF NOT EXISTS)
3. **Substitua o config.lua** e ajuste as configurações
4. **Substitua o server/main.lua**
5. **Reinicie o resource**

## Notas Importantes

- As configurações padrão são conservadoras e seguras
- Ajuste os limites conforme sua economia do servidor
- O sistema de taxas está desabilitado por padrão
- Os webhooks precisam ser configurados manualmente
- O modo debug deve ser desabilitado em produção

## Compatibilidade

- ✅ QBCore
- ✅ ESX
- ✅ ox_lib 3.20.0+
- ✅ oxmysql
- ✅ lb-phone (opcional)
- ✅ space_economy (opcional)
- ✅ tiao_economia (opcional)
