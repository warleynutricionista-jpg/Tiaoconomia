-- =====================================================
-- PS-Banking Configuration
-- Enhanced configuration with security and limits
-- =====================================================

lib.locale()
Config = {}

-- Debug mode
Config.Debug = false -- Enable debug prints

-- Integrations
Config.LBPhone = false -- Does your server use lb-phone?
Config.TargetSystem = "ox_target" -- Change to your target script: ox_target, qb-target, or interact

-- Currency settings
Config.Currency = {
    lang = "pt-br", -- en-US
    currency = "BRL", -- USD
}

-- Security settings
Config.Security = {
    EnableTransferLimits = true, -- Enable daily transfer limits
    DailyTransferLimit = 1000000, -- Maximum amount that can be transferred per day
    MaxTransferAmount = 500000, -- Maximum amount per single transfer
    MinTransferAmount = 1, -- Minimum amount per transfer
    MaxWithdrawAmount = 100000, -- Maximum ATM withdrawal amount
    MinWithdrawAmount = 1, -- Minimum ATM withdrawal amount
    MaxDepositAmount = 500000, -- Maximum ATM deposit amount
    MinDepositAmount = 1, -- Minimum ATM deposit amount
    EnableAuditLog = true, -- Enable audit logging
    RequireOnlineForBills = true, -- Require target player to be online to send bills
}

-- Account settings
Config.Accounts = {
    MaxAccountsPerPlayer = 5, -- Maximum number of accounts a player can create
    MinAccountBalance = 0, -- Minimum balance required to keep account open
    InitialAccountBalance = 0, -- Initial balance when creating new account
    AllowNegativeBalance = false, -- Allow accounts to go negative
}

-- Transaction fees (set to 0 to disable)
Config.Fees = {
    EnableFees = false, -- Enable transaction fees
    TransferFee = 0, -- Fee for transfers (flat amount)
    TransferFeePercent = 0, -- Fee for transfers (percentage)
    ATMWithdrawFee = 0, -- Fee for ATM withdrawals
    BillFee = 0, -- Fee for creating bills
}

-- Bank locations
Config.BankLocations = {
    Coords = {
        vector3(149.05, -1041.3, 29.37),
        vector3(313.32, -280.03, 54.17),
        vector3(-351.94, -50.72, 49.04),
        vector3(-1212.68, -331.83, 37.78),
        vector3(-2961.67, 482.31, 15.7),
        vector3(1175.64, 2707.71, 38.09),
        vector3(247.65, 223.87, 106.29),
        vector3(-111.98, 6470.56, 31.63),
    },
    Blips = {
        name = "Banco",
        sprite = 108,
        color = 2,
        scale = 0.55,
    },
}

-- ATM settings
Config.PresetATM_Amounts = {
    Amounts = {
        2000,
        5000,
        10000,
    },
    Grid = 3, -- How many preset buttons to show
}

Config.ATM_Animation = {
    dict = "anim@amb@prop_human_atm@interior@male@enter",
    name = "enter",
    flag = 49,
}

Config.ATM_Models = {
    "prop_atm_01",
    "prop_atm_02",
    "prop_atm_03",
    "prop_fleeca_atm",
}

-- Bills settings
Config.Bills = {
    MaxBillAmount = 1000000, -- Maximum bill amount
    MinBillAmount = 1, -- Minimum bill amount
    EnableDueDates = true, -- Enable due dates for bills
    DefaultDueDays = 7, -- Default days until bill is due
}

-- Transaction history
Config.History = {
    MaxTransactionsShown = 100, -- Maximum transactions to show in history
    EnableTransactionDelete = true, -- Allow players to delete their history
    EnableTransactionExport = false, -- Allow exporting transaction history
}

-- Notifications
Config.Notifications = {
    EnableBillNotifications = true, -- Notify when receiving bills
    EnableTransferNotifications = true, -- Notify when receiving transfers
    EnableLowBalanceWarning = true, -- Warn when balance is low
    LowBalanceThreshold = 1000, -- Threshold for low balance warning
}

-- Webhooks for logging (Discord)
Config.Webhooks = {
    Enable = false,
    TransferWebhook = "", -- Webhook URL for transfers
    BillWebhook = "", -- Webhook URL for bills
    AccountWebhook = "", -- Webhook URL for account creation/deletion
    AuditWebhook = "", -- Webhook URL for audit logs
}
