Config = Config or {}

-- ============================================================
-- GERAL
-- ============================================================
Config.Debug = false
Config.Locale = 'pt-BR'

-- ============================================================
-- IMPOSTOS
-- ============================================================
Config.TaxMultiplierDefault = 1.0

-- Sistema de alíquotas progressivas (brasileiro)
Config.TaxBrackets = {
  { min = 0,      max = 2112,    rate = 0.00 },  -- Isento
  { min = 2112,   max = 2826,    rate = 0.075 }, -- 7,5%
  { min = 2826,   max = 3751,    rate = 0.15 },  -- 15%
  { min = 3751,   max = 4664,    rate = 0.225 }, -- 22,5%
  { min = 4664,   max = nil,     rate = 0.275 }, -- 27,5%
}

-- Catálogo de tributos (usado no painel admin)
Config.TaxCatalog = {
  {
    key = 'IPTU',
    label = 'IPTU (Imóvel)',
    mode = 'base_percent',
    percent = 0.3,
    description = 'Imposto sobre propriedade imobiliária'
  },
  {
    key = 'IPVA',
    label = 'IPVA (Veículo)',
    mode = 'base_percent',
    percent = 1.5,
    description = 'Imposto sobre veículos automotores'
  },
  {
    key = 'IRPF',
    label = 'Imposto de Renda',
    mode = 'progressive',
    description = 'Imposto progressivo sobre renda'
  },
  {
    key = 'ISS',
    label = 'ISS (Serviços)',
    mode = 'base_percent',
    percent = 2.0,
    description = 'Imposto sobre serviços prestados'
  },
  {
    key = 'ICMS',
    label = 'ICMS (Mercadorias)',
    mode = 'base_percent',
    percent = 12.0,
    description = 'Imposto sobre circulação de mercadorias'
  },
  {
    key = 'MULTA',
    label = 'Multa Administrativa',
    mode = 'fixed',
    fixed = 1000,
    description = 'Multas governamentais'
  },
  {
    key = 'TAXA_GOV',
    label = 'Taxa Governamental',
    mode = 'fixed',
    fixed = 500,
    description = 'Taxas diversas do governo'
  },
  {
    key = 'OUTRO',
    label = 'Outro Tributo',
    mode = 'fixed',
    fixed = 0,
    description = 'Lançamento manual'
  },
}

-- IVA / Taxa transacional (futuro: integrar com shops/banking)
Config.TransactionTax = {
  Enabled = false,
  Percent = 1.0,
  Min = 0,
  Max = 50000,
  ExemptAccounts = { 'cash' }, -- Isentar cash, taxar apenas bank
}

-- Alíquotas dinâmicas baseadas na realidade econômica (PIB per Capita)
Config.DynamicTax = {
  Enabled = true,
  FallbackPIBPerCapita = 5000,
  Brackets = {
    { minMultiplier = 0.0, maxMultiplier = 0.5, rate = 0.00 }, -- Isento até 50% da média
    { minMultiplier = 0.5, maxMultiplier = 1.5, rate = 0.10 }, -- Classe Média Baixa
    { minMultiplier = 1.5, maxMultiplier = 5.0, rate = 0.20 }, -- Classe Média Alta
    { minMultiplier = 5.0, maxMultiplier = 20.0, rate = 0.35 }, -- Ricos
    { minMultiplier = 20.0, maxMultiplier = nil, rate = 0.60 }, -- Super ricos
  }
}

-- Imposto sobre Grandes Fortunas (IGF)
Config.WealthTax = {
  Enabled = true,
  TopPercentile = 0.05, -- Top 5% mais ricos
  BaseRate = 0.02, -- 2% do patrimônio
  ProgressiveMultiplier = 1.5, -- Escala progressiva
  DueDays = 7,
  CycleHours = 168, -- 1x por semana
}

-- Imposto de ociosidade (inativos)
Config.WealthDecay = {
  Enabled = true,
  InactiveDays = 30,
  MinWealth = 1000000,
  DailyRate = 0.05,
  MaxDailyRate = 0.10,
}

-- Anti-hoarding: imposto exponencial por quantidade de bens
Config.AssetTax = {
  Enabled = true,
  VehicleMultiplier = 0.5, -- +50% por veículo extra
  PropertyMultiplier = 0.5, -- +50% por propriedade extra
  MaxMultiplier = 6.0,
  IdleVehicleDays = 30,
  IdleVehicleMultiplier = 3.0, -- IPVA triplicado para veículos ociosos
}

-- ============================================================
-- LAVAGEM OFICIAL
-- ============================================================
Config.MoneyLaundering = {
  Enabled = true,
  FeePercent = 0.35, -- 35% de taxa
  MinAmount = 10000,
  MaxAmount = 2000000,
  TreasuryShare = 1.0,
  Reason = 'lavagem_oficial',
}

-- Renda Básica Universal (UBI)
Config.UBI = {
  Enabled = true,
  CheckIntervalHours = 12,
  MinPlayers = 3,
  MaxWealth = 20000,
  MaxInactiveHours = 48,
  Reason = 'Bolsa Cidadão (Redistribuição)',
}

-- ============================================================
-- PERMISSÕES (Granular)
-- ============================================================
Config.Permissions = {
  -- ACE Permission
  Ace = 'space_economy.admin',
  
  -- QBOX Staff Metadata
  AllowStaffMeta = true,
  
  -- Permissões por Job + Grade mínimo
  Jobs = {
    ['government'] = { minGrade = 3 },
    ['police'] = { minGrade = 5 },
  },
  
  -- Permissões específicas (futuro)
  Granular = {
    ViewTreasury = { ace = 'space_economy.view_treasury' },
    ModifyTreasury = { ace = 'space_economy.modify_treasury' },
    IssueDebts = { ace = 'space_economy.issue_debts' },
    ViewLogs = { ace = 'space_economy.view_logs' },
  }
}

-- ============================================================
-- DÍVIDAS
-- ============================================================
Config.DebtSystem = {
  Enabled = true,
  
  -- Juros
  InterestDailyRate = 0.01, -- 1% ao dia
  CompoundInterest = false,  -- Juros compostos (false = simples)
  
  -- Períodos
  GraceHours = 24,              -- Carência antes de juros
  WarnEveryHours = 12,          -- Avisar player a cada X horas
  WarrantAfterDaysOverdue = 7,  -- Mandado após X dias de atraso
  
  -- Restrições (futuro)
  LockThreshold = 50000,        -- Acima disso, pode bloquear CNH, etc
  BlockVehicleSpawn = false,    -- Bloquear spawn de veículos se devedor
  BlockPropertyAccess = false,  -- Bloquear acesso a propriedades
  
  -- Parcelamento
  AllowInstallments = true,
  MaxInstallments = 12,
  MinInstallmentValue = 100,
  InstallmentFee = 0.05, -- 5% de taxa administrativa
}

-- Alertas de mandado
Config.WarrantAlert = {
  Enabled = true,
  UsePsDispatch = true,
  UsePsMdt = true,
  Title = 'Dívida Ativa',
  Message = 'Cidadão com dívida vencida há mais de 7 dias. Verificar pendências tributárias.',
  DispatchCode = '10-90',
}

-- ============================================================
-- TESOURO
-- ============================================================
Config.Treasury = {
  StartBalance = 0,
  MaxBalance = 999999999999, -- Limite máximo
  MaxReserves = 5000000, -- Acima disso redistribui (UBI)
  
  -- Auditoria
  LogAllTransactions = true,
  RequireReason = true,
  
  -- Notificações
  NotifyOnLowBalance = true,
  LowBalanceThreshold = 100000,
}

-- ============================================================
-- RASTREAMENTO DE TRAJETO DO DINHEIRO (AUDITORIA AVANÇADA)
-- ============================================================
Config.MoneyTrail = {
  Enabled = true,
  MinAmount = 50000, -- Só registra acima desse valor
  LogAccounts = {
    bank = true,
    cash = false,
  },
  Dynamic = {
    Enabled = true,
    PercentOfCirculation = 0.001, -- 0.1% da circulação total
    Min = 10000,
    Max = 500000,
  },
  RetentionDays = 30,
  IgnoreReasons = { 'rollback', 'liberacao_quarentena' },
}

-- ============================================================
-- EVENTOS ECONÔMICOS (AUTÔNOMO + DESFECHO MANUAL)
-- ============================================================
Config.EconomicEvents = {
  AutoTrigger = true,
  AutoIntervalMinutes = 30,
  Outcome = {
    Mode = 'auto', -- auto | manual | none
    Default = 'neutro',
  },
}

-- ============================================================
-- INFLAÇÃO
-- ============================================================
Config.Inflation = {
  Enabled = true,
  DefaultRate = 1.0,
  MinRate = 0.70,
  MaxRate = 2.00,
  
  -- Auto-ajuste (futuro: baseado em economia da cidade)
  AutoAdjust = true,
  AdjustIntervalHours = 6,
  TargetRange = { min = 0.95, max = 1.05 },
  VelocityHigh = 1.20,
  VelocityLow = 0.60,
  InflationStep = 0.05,
  TaxStep = 0.05,
}

-- ============================================================
-- SEGURANÇA ECONÔMICA (Economy Guard)
-- ============================================================
Config.Security = {
  Enabled = true,
  SuspiciousThreshold = 1000000, -- 1 milhão
  MaxGenericAmount = 100000,
  MaxGainPerMinute = 10000000,
  EnforceReasonCatalog = false,
  AllowedReasons = {}, -- quando vazio, não bloqueia por catálogo
  GenericReasons = { 'script', 'unknown', 'space_economy', 'reward' },

  QuarantineEnabled = true,

  Emergency = {
    Enabled = true,
    CirculationSpikePercent = 0.05, -- 5% por hora
    WindowSeconds = 3600,
    CheckIntervalSeconds = 300,
    HighValueBlock = 250000, -- bloqueia compras altas em emergência
  },

  -- Disjuntores de segurança (Circuit Breakers)
  CircuitBreaker = {
    MaxInflationDeltaPerHour = 0.05, -- 5% por hora
    MaxTaxMultiplier = 0.40, -- 40% absoluto
    MaxSelicMonthly = 0.05, -- 5% ao mês
    CooldownHours = 6, -- bloqueia ajustes automáticos após disparo
  },
}

-- ============================================================
-- ALERTAS DE DINHEIRO ILEGAL (RP/INVESTIGAÇÕES)
-- ============================================================
Config.IllegalMoney = {
  Enabled = true,
  Reasons = {
    'dirty', 'ilegal', 'illegal', 'contrabando', 'drogas', 'drugs', 'launder', 'lavagem'
  },
  Dispatch = {
    Enabled = true,
    Resource = 'ps-dispatch',
    Code = '10-75',
    Title = 'Investigação Financeira',
    Message = 'Movimentação suspeita de dinheiro ilegal detectada.',
  },
  MDT = {
    Enabled = true,
    Resource = 'ps-mdt',
    Title = 'Investigação Financeira',
    Tags = { 'financeiro', 'lavagem', 'ilegal' },
  },
}

-- ============================================================
-- PERSISTÊNCIA
-- ============================================================
Config.Persistence = {
  IntervalMs = 60000, -- 1 minuto
  SaveOnShutdown = true,
  BackupOnStart = true,
}

-- ============================================================
-- LOGS
-- ============================================================
Config.Logging = {
  Enabled = true,
  MaxAge = 30, -- dias
  Categories = {
    'system', 'tax', 'debt', 'vault', 'admin', 'player'
  },
  
  -- Discord Webhook (opcional)
  Discord = {
    Enabled = false,
    Webhook = '',
    LogLevels = { 'admin', 'vault' }, -- Apenas críticos
  }
}

-- ============================================================
-- NUI / INTERFACE
-- ============================================================
Config.UI = {
  DefaultCurrency = 'BRL',
  CurrencySymbol = 'R$',
  DateFormat = '%d/%m/%Y %H:%M',
  
  -- Keybinds padrão
  Keybinds = {
    OpenTax = 'F7',
    OpenAdmin = 'F9',
  },
  
  -- Temas (futuro)
  Theme = 'dark',
}

-- ============================================================
-- INTEGRAÇÕES (CORRIGIDO - 24/12/2025)
-- ============================================================
Config.Integrations = {
  -- Banking
  Banking = {
    Enabled = true,
    Resource = 'auto', -- auto-detect: qbx_core, qb-core, ps-banking
  },

  -- Dispatch (DESABILITADO até instalar ps-dispatch)
  Dispatch = {
    Enabled = false,  -- ← ALTERADO: true → false
    Resource = 'ps-dispatch',
  },

  -- MDT (DESABILITADO até instalar ps-mdt)
  MDT = {
    Enabled = false,  -- ← ALTERADO: true → false
    Resource = 'ps-mdt',
  },

  -- Shops (DESABILITADO - não integrado)
  Shops = {
    Enabled = false,
    TaxPurchases = false,
    TaxRate = 1.0,
  },

  -- Real Estate (DESABILITADO - não integrado)
  RealEstate = {
    Enabled = false,
    AutoIPTU = false,
    IPTUFrequencyDays = 30,
  },

  -- Garages (DESABILITADO - não integrado)
  Garages = {
    Enabled = false,
    AutoIPVA = false,
    IPVAFrequencyDays = 365,
  },
}

-- ============================================================
-- INTEGRAÇÕES EXTERNAS (EVENTOS/COMPRA/TRANSFERÊNCIA)
-- ============================================================
-- Use este bloco para sobrescrever os defaults do arquivo
-- server/external_integrations.lua. Mantido comentado para evitar
-- alterações involuntárias no comportamento padrão.
--[[
Config.ExternalIntegrations = {
  General = {
    Enabled = true,
    Debug = false,
    StartDelayMs = 2000,
    DefaultDueDays = 7,
    DedupeWindowSec = 6,
  },
  Banking = {
    Enabled = true,
    Mode = 'debt',
    DueDays = 7,
    TaxTransfers = true,
    TransferTaxRate = 0.5,
    TransferMinTax = 10,
    TransferMinBase = 100,
  },
}
]]

-- ============================================================
-- INTEGRAÇÕES VIA BANCO DE DADOS (DB INTEGRATIONS)
-- ============================================================
-- Sobrescreve defaults de server/db_integrations.lua.
--[[
Config.DBIntegrations = {
  Enabled = true,
  DebugMode = true,
  DueDays = 7,
  Systems = {
    ['ps-banking'] = { enabled = true, interval = 60000 },
    ['dealership'] = { enabled = true, interval = 120000 },
    ['properties'] = { enabled = true, interval = 120000 },
  }
}
]]

-- ============================================================
-- WEBHOOKS / NOTIFICAÇÕES EXTERNAS
-- ============================================================
Config.Webhooks = {
  Treasury = '',
  Debts = '',
  Admin = '',
}

-- ============================================================
-- SISTEMAS AVANÇADOS (Agora Ativos)
-- ============================================================
Config.AdvancedSystems = {
  -- Sistema de crédito/score
  CreditScore = true,
  
  -- Empréstimos governamentais
  GovernmentLoans = true,
  
  -- Parcelamento de dívidas
  Installments = true,
  
  -- Taxação automática
  AutoTax = true,
}

-- ============================================================
-- EXPERIMENTAL (Recursos futuros)
-- ============================================================
Config.Experimental = {
  -- Programas sociais (bolsa família, etc)
  SocialPrograms = false,

  -- Mercado de títulos públicos
  PublicBonds = false,

  -- Previdência social
  SocialSecurity = false,
}

-- ============================================================
-- MELHORIAS v3.1 (Performance, UX, Segurança)
-- ============================================================

-- Notificações Push Automáticas
Config.DebtNotifications = {
  Enabled = true,
  IntervalMinutes = 60,          -- Notificar a cada 1 hora
  MinDebtAmount = 1000,          -- Só notificar se dívida > 1000
  ShowOnConnect = true,          -- Mostrar ao entrar no servidor
  ShowOnDisconnect = false,      -- Mostrar ao sair
  MaxDebtsToShow = 5,            -- Mostrar no máximo 5 dívidas
}

-- Sistema de Backup Automático
Config.Backup = {
  Enabled = true,
  IntervalHours = 24,            -- Backup a cada 24 horas
  RetentionDays = 30,            -- Manter backups por 30 dias
  BackupOnShutdown = true,       -- Backup ao desligar servidor
  BackupOnStart = false,         -- Backup ao iniciar
  MinIntervalMinutes = 60,       -- Intervalo mínimo entre backups
}

-- Sistema de Recompensas (Bom Pagador)
Config.PaymentRewards = {
  Enabled = true,
  DiscountTiers = {
    { paymentsOnTime = 5,  discount = 0.02, label = 'Bronze' },   -- 2%
    { paymentsOnTime = 10, discount = 0.05, label = 'Prata' },    -- 5%
    { paymentsOnTime = 20, discount = 0.10, label = 'Ouro' },     -- 10%
    { paymentsOnTime = 50, discount = 0.15, label = 'Platina' },  -- 15%
  },
  StreakResetDays = 14,
  NotifyLevelUp = true,
}

-- Discord Webhooks Detalhados
Config.DiscordWebhooks = {
  Enabled = false, -- Ativar quando configurar os webhooks

  Webhooks = {
    treasury = '',  -- URL do webhook para transações do tesouro
    debts = '',     -- URL do webhook para dívidas
    admin = '',     -- URL do webhook para ações admin
    alerts = '',    -- URL do webhook para alertas críticos
    daily = '',     -- URL do webhook para relatórios diários
  },

  DailyReport = {
    enabled = false,
    hour = 20,      -- 20:00 (8 PM)
    minute = 0,
  }
}
