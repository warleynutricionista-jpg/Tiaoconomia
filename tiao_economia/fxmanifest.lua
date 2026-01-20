fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'space_economy (QBOX Advanced v3.3)'
description 'Sistema econômico ultra-realista: PIB, inflação, SELIC, eventos econômicos, bolsa de valores, investimentos, mercado de trabalho + economia auto-regulada'
version '3.3.0'

-- ============================================================
-- SHARED (Client + Server)
-- ============================================================
shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/init.lua',
  'shared/utils.lua',
  'shared/bridge.lua',
}

-- ============================================================
-- SERVER
-- ============================================================
server_scripts {
  '@oxmysql/lib/MySQL.lua',

  -- Core
  'server/init.lua',
  'server/state.lua',
  'server/locks.lua',
  
  -- Sistemas Base
  'server/treasury.lua',
  'server/tax.lua',
  'server/charcache.lua',
  'server/integrations.lua',

  -- Sistemas Avançados (NOVOS)
  'server/debts.lua',           -- Melhorado
  'server/installments.lua',    -- NOVO: Parcelamento
  'server/credit_score.lua',    -- NOVO: Score de crédito
  'server/loans.lua',           -- NOVO: Empréstimos
  'server/auto_tax.lua',        -- NOVO: Taxação automática
  'server/reports.lua',         -- NOVO: Relatórios e analytics
  'server/external_integrations.lua', -- NOVO: Integrações externas
  'server/db_integrations.lua', -- NOVO: Integrações diretas com banco de dados
  'server/bills_export.lua',
  -- Melhorias v3.1 (Performance & UX)
  'server/cache.lua',           -- Sistema de cache com TTL
  'server/notifications.lua',   -- Notificações push automáticas
  'server/backup.lua',          -- Backup automático
  'server/metrics.lua',         -- Dashboard de métricas
  'server/audit.lua',           -- Sistema de auditoria
  'server/rewards.lua',         -- Sistema de recompensas
  'server/discord.lua',         -- Discord webhooks

  -- Melhorias v3.2 (Economia Ultra-Realista)
  'server/economy_monitor.lua', -- Monitoramento PIB e circulação monetária
  'server/monetary_policy.lua', -- Política monetária automática (SELIC, inflação)
  'server/economic_events.lua', -- Eventos econômicos (crises, booms)

  -- Fase 3.3 (Mercado Financeiro e Trabalho)
  'server/stock_market.lua',    -- Bolsa de valores com ações e Ibovespa
  'server/banking_system.lua',  -- Sistema bancário (poupança, CDB, investimentos)
  'server/labor_market.lua',    -- Mercado de trabalho (salário mínimo, desemprego)

  -- Admin & Events
  'server/admin.lua',
  'server/events.lua',
}

-- ============================================================
-- CLIENT
-- ============================================================
client_scripts {
  'client/init.lua',
  'client/nui.lua',
  'client/commands.lua',
}

-- ============================================================
-- NUI
-- ============================================================
ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js',
}

-- ============================================================
-- DEPENDENCIES
-- ============================================================
dependencies {
  'ox_lib',
  'oxmysql',
  'qbx_core',
}

-- ============================================================
-- EXPORTS (Para outros recursos)
-- ============================================================

-- Treasury
exports {
  'GetTreasuryBalance',
  'AddToTreasury',
  'RemoveFromTreasury',
}

-- Tax
exports {
  'CalculateTax',
  'ApplyTax',
}

-- Debts
exports {
  'CreateDebt',
  'PayDebt',
  'GetPlayerDebts',
}

-- Installments
exports {
  'CreateInstallmentPlan',
  'PayInstallment',
}

-- Credit Score
exports {
  'GetCreditScore',
  'UpdateCreditScore',
}

-- Loans
exports {
  'SimulateLoan',
  'RequestLoan',
  'GetPlayerLoans',
}

-- Auto Tax
exports {
  'TaxVehiclePurchase',
  'TaxPropertyPurchase',
  'TaxService',
  'TaxShopPurchase',
}

-- Reports
exports {
  'GetEconomyReport',
  'GetDailyMetrics',
}

-- Cache (v3.1)
exports {
  'CacheGet',
  'CacheSet',
  'CacheInvalidate',
  'CacheGetOrSet',
  'CacheGetStats',
}

-- Notifications (v3.1)
exports {
  'NotifyDebts',
  'NotifyInstallments',
}

-- Backup (v3.1)
exports {
  'CreateBackup',
  'RestoreBackup',
  'ListBackups',
}

-- Metrics (v3.1)
exports {
  'GetDashboardData',
  'GetWeeklyRevenue',
  'GetTopDebtors',
}

-- Audit (v3.1)
exports {
  'AuditLog',
  'AuditGetLogs',
  'AuditGetStats',
}

-- Rewards (v3.1)
exports {
  'RecordPayment',
  'GetDiscount',
  'ApplyDiscount',
  'GetPlayerRewardInfo',
  'GetTopPayers',
}

-- Discord (v3.1)
exports {
  'SendDiscordEmbed',
  'DiscordTreasuryTransaction',
  'DiscordDebtCreated',
  'DiscordDebtPaid',
  'DiscordAdminAction',
  'DiscordAlert',
}

-- DB Integrations (v3.1)
exports {
  'GetDBIntegrationStats',
  'ForceCheckSystem',
}

-- Economy Monitor (v3.2)
exports {
  'RegistrarTransacao',
  'GetRelatorioEconomico',
  'GetCirculacaoMonetaria',
  'GetPIB',
  'GetPIBPerCapita',
  'GetVelocidadeCirculacao',
}

-- Monetary Policy (v3.2)
exports {
  'GetSELIC',
  'GetInflacao',
  'AjustarPrecoInflacao',
  'GetRelatorioPolitica',
  'AtualizarCategoriaIPC',
}

-- Economic Events (v3.2)
exports {
  'TriggerEconomicEvent',
  'GetEventoAtivo',
  'GetHistoricoEventos',
}

-- Stock Market (v3.3)
exports {
  'BuyStock',
  'SellStock',
  'GetQuotes',
  'GetPortfolio',
  'GetIbovespa',
}

-- Banking System (v3.3)
exports {
  'BankOpenAccount',
  'BankDeposit',
  'BankWithdraw',
  'BankInvest',
  'BankRedeem',
  'BankGetStatement',
}

-- Labor Market (v3.3)
exports {
  'GetMinimumWage',
  'GetAverageWage',
  'GetUnemploymentRate',
  'GetLaborReport',
  'GetSectorWages',
}