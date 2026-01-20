fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'space_economy (QBOX Advanced v4.0)'
description 'Sistema econômico ultra-realista: PIB, SELIC, Bolsa de Valores, Banking, Mercado de Trabalho, Eventos Econômicos + v3.1'
version '4.0.0'

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
  'server/wealth_tax.lua',      -- NOVO: IGF + taxa de ociosidade
  'server/social_programs.lua', -- NOVO: Redistribuição (UBI)
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
  'server/security_guard.lua',  -- Economy Guard
  'server/rewards.lua',         -- Sistema de recompensas
  'server/discord.lua',         -- Discord webhooks

  -- Sistemas Econômicos Avançados v4.0
  'server/economy_monitor.lua',  -- PIB, Circulação Monetária
  'server/monetary_policy.lua',  -- SELIC, Inflação, IPC, COPOM
  'server/economic_events.lua',  -- Eventos econômicos dinâmicos
  'server/stock_market.lua',     -- Bolsa de valores
  'server/banking_system.lua',   -- Produtos bancários
  'server/money_laundering.lua', -- Lavagem oficial
  'server/labor_market.lua',     -- Salário mínimo, desemprego

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

-- Economy Monitor (v4.0)
exports {
  'RegisterTransaction',
  'GetEconomyReport',
  'GetPIB',
  'GetPIBPerCapita',
  'GetMoneyCirculation',
  'GetVelocity',
}

-- Monetary Policy (v4.0)
exports {
  'GetSELIC',
  'GetInflation',
  'GetMonthlyInflation',
  'AdjustPriceForInflation',
  'GetMonetaryPolicyReport',
  'AdjustIPCCategory',
  'ForceCOPOMMeeting',
}

-- Economic Events (v4.0)
exports {
  'TriggerEconomicEvent',
  'GetCurrentEvent',
  'GetEventHistory',
}

-- Stock Market (v4.0)
exports {
  'BuyStock',
  'SellStock',
  'GetPortfolio',
  'GetStockQuotes',
}

-- Banking System (v4.0)
exports {
  'Invest',
  'RedeemInvestment',
  'GetInvestments',
}

-- Labor Market (v4.0)
exports {
  'GetMinimumWage',
  'GetUnemploymentRate',
  'GetSectorMinSalary',
  'GetLaborMarketReport',
  'ForceWageAdjustment',
}
