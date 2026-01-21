-- =====================================================
-- PS-Banking Server
-- Enhanced with security, validation, and audit logging
-- =====================================================

lib.versionCheck("Project-Sloth/ps-banking")
assert(lib.checkDependency("ox_lib", "3.20.0", true))

local framework = nil

if GetResourceState("es_extended") == "started" then
	framework = "ESX"
	ESX = exports["es_extended"]:getSharedObject()
elseif GetResourceState("qb-core") == "started" then
	framework = "QBCore"
	QBCore = exports["qb-core"]:GetCoreObject()
else
	return error(locale("no_framework_found"))
end

-- =====================================================
-- Utility Functions
-- =====================================================

local function debugPrint(message)
	if Config.Debug then
		print("[ps-banking] " .. message)
	end
end

local function logAudit(action, identifier, targetIdentifier, accountId, amount, details)
	if not Config.Security or not Config.Security.EnableAuditLog then
		return
	end

	MySQL.insert("INSERT INTO ps_banking_audit_log (action, identifier, target_identifier, account_id, amount, details) VALUES (?, ?, ?, ?, ?, ?)",
		{ action, identifier, targetIdentifier, accountId, amount, json.encode(details) }
	)
end

local function validateAmount(amount, minAmount, maxAmount)
	if not amount or type(amount) ~= "number" then
		return false, "Invalid amount"
	end

	if amount < minAmount then
		return false, "Amount below minimum limit"
	end

	if amount > maxAmount then
		return false, "Amount exceeds maximum limit"
	end

	return true
end

local function checkDailyLimit(identifier, amount)
	if not Config.Security or not Config.Security.EnableTransferLimits then
		return true
	end

	local today = os.date("%Y-%m-%d")
	local result = MySQL.query.await(
		"SELECT daily_transferred FROM ps_banking_transfer_limits WHERE identifier = ? AND last_reset = ?",
		{ identifier, today }
	)

	local currentTotal = 0
	if #result > 0 then
		currentTotal = result[1].daily_transferred
	end

	if currentTotal + amount > Config.Security.DailyTransferLimit then
		return false, "Daily transfer limit exceeded"
	end

	return true
end

local function updateDailyLimit(identifier, amount)
	if not Config.Security or not Config.Security.EnableTransferLimits then
		return
	end

	local today = os.date("%Y-%m-%d")
	MySQL.query(
		"INSERT INTO ps_banking_transfer_limits (identifier, daily_transferred, last_reset) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE daily_transferred = daily_transferred + ?",
		{ identifier, amount, today, amount }
	)
end

local function calculateFee(amount, feeType)
	if not Config.Fees or not Config.Fees.EnableFees then
		return 0
	end

	local fee = 0
	if feeType == "transfer" then
		fee = Config.Fees.TransferFee or 0
		if Config.Fees.TransferFeePercent then
			fee = fee + (amount * (Config.Fees.TransferFeePercent / 100))
		end
	elseif feeType == "atm_withdraw" then
		fee = Config.Fees.ATMWithdrawFee or 0
	elseif feeType == "bill" then
		fee = Config.Fees.BillFee or 0
	end

	return math.floor(fee)
end

local function sendWebhook(webhookUrl, title, description, color)
	if not Config.Webhooks or not Config.Webhooks.Enable or not webhookUrl or webhookUrl == "" then
		return
	end

	local embed = {
		{
			["title"] = title,
			["description"] = description,
			["color"] = color or 3447003,
			["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%S")
		}
	}

	PerformHttpRequest(webhookUrl, function(err, text, headers) end, 'POST', json.encode({
		username = "PS-Banking",
		embeds = embed
	}), { ['Content-Type'] = 'application/json' })
end

local function getPlayerIdentifier(player)
	if framework == "ESX" then
		return player.getIdentifier()
	elseif framework == "QBCore" then
		return player.PlayerData.citizenid
	end
end

local function getPlayerFromId(source)
	if framework == "ESX" then
		return ESX.GetPlayerFromId(source)
	elseif framework == "QBCore" then
		return QBCore.Functions.GetPlayer(source)
	end
end

local function getPlayerAccounts(player)
	if framework == "ESX" then
		return player.getAccount("bank").money
	elseif framework == "QBCore" then
		return player.PlayerData.money["bank"]
	end
end

local function getName(player)
	if framework == "ESX" then
		return player.getName()
	elseif framework == "QBCore" then
		return player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
	end
end

local function logTransaction(identifier, description, accountName, amount, isIncome)
	MySQL.insert.await(
		"INSERT INTO ps_banking_transactions (identifier, description, type, amount, date, isIncome) VALUES (?, ?, ?, ?, NOW(), ?)",
		{ identifier, description, accountName, amount, isIncome }
	)
end

local function getEconomyResource()
	if GetResourceState("space_economy") == "started" then
		return "space_economy"
	end
	if GetResourceState("tiao_economia") == "started" then
		return "tiao_economia"
	end
	return nil
end

local function getEconomyExports()
	local resource = getEconomyResource()
	if resource then
		return exports[resource]
	end
	return nil
end

local InvestmentProducts = {
	{
		id = "poupanca",
		name = "Poupança",
		description = "Rendimento mensal baseado na SELIC",
		minInvestment = 100,
		liquidity = "Imediata",
	},
	{
		id = "cdb_30",
		name = "CDB 30 dias",
		description = "90% do CDI - Liquidez em 30 dias",
		minInvestment = 5000,
		liquidity = "30 dias",
	},
	{
		id = "cdb_60",
		name = "CDB 60 dias",
		description = "100% do CDI - Liquidez em 60 dias",
		minInvestment = 5000,
		liquidity = "60 dias",
	},
	{
		id = "cdb_90",
		name = "CDB 90 dias",
		description = "110% do CDI - Liquidez em 90 dias",
		minInvestment = 10000,
		liquidity = "90 dias",
	},
	{
		id = "cdb_180",
		name = "CDB 180 dias",
		description = "120% do CDI - Liquidez em 180 dias",
		minInvestment = 10000,
		liquidity = "180 dias",
	},
	{
		id = "lci",
		name = "LCI/LCA",
		description = "85% do CDI - Isento de IR",
		minInvestment = 20000,
		liquidity = "90 dias",
	},
	{
		id = "tesouro",
		name = "Tesouro SELIC",
		description = "100% da SELIC - Liquidez imediata",
		minInvestment = 1000,
		liquidity = "Imediata",
	},
}

-- Society Compat MRI
local function exportHandler(exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format('qb-banking', exportName), function(setCB)
        setCB(func)
    end)
end

local PlayerJob = nil
local PlayerGang = nil

local function generateCardNumber()
    local rawNumber = tostring(math.random(1e15, 9e15))
    local formattedNumber = rawNumber:gsub("(%d%d%d%d)", "%1 "):sub(1, -2)
    return formattedNumber
end

local function validateGroup(group)
	local JOBS = exports.qbx_core:GetJobs()
	local GANGS = exports.qbx_core:GetGangs()
	if JOBS[group] or GANGS[group] then
		return false
	end
	return true
end

local function addMoney(accountName, amount, reason)
    local account = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE holder = ?", { accountName })
    if #account > 0 then
        MySQL.update.await(
            "UPDATE ps_banking_accounts SET balance = balance + ? WHERE holder = ?",
            { amount, accountName }
        )

        local ownerData = json.decode(account[1].owner or "{}")
        local identifier = ownerData and ownerData.identifier or nil

        if identifier then
            logTransaction(identifier, reason, accountName, amount, true)
        end

        return true
    end
    return false
end
exports("AddMoney", addMoney)
exportHandler("AddMoney", addMoney)

local function removeMoney(accountName, amount, reason)
    local account = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE holder = ?", { accountName })
    if #account > 0 and account[1].balance >= amount then
        MySQL.update.await(
            "UPDATE ps_banking_accounts SET balance = balance - ? WHERE holder = ?",
            { amount, accountName }
        )

        local ownerData = json.decode(account[1].owner or "{}")
        local identifier = ownerData and ownerData.identifier or nil

        if identifier then
            logTransaction(identifier, reason, accountName, amount, false)
        end

        return true
    end
    return false
end
exports("RemoveMoney", removeMoney)
exportHandler("RemoveMoney", removeMoney)

local function createPlayerAccount(playerId, accountName, accountBalance, accountUsers)
    local xPlayer = getPlayerFromId(playerId)

    if not xPlayer then
        return false
    end

    local cardNumber = generateCardNumber()

    local ownerData = {
        name = getName(xPlayer),
        state = true,
        identifier = getPlayerIdentifier(xPlayer)
    }

    MySQL.insert.await(
        "INSERT INTO ps_banking_accounts (balance, holder, cardNumber, users, owner) VALUES (?, ?, ?, ?, ?)",
        {
            accountBalance,
            accountName,
            cardNumber,
            json.encode(accountUsers),
            json.encode(ownerData)
        }
    )

    return true
end
exports("CreatePlayerAccount", createPlayerAccount)

local function getAccountById(accountId)
    local account = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE id = ?", { accountId })
    return account[1] or nil
end
exports("GetAccountById", getAccountById)

local function getAccountByHolder(accountName)
	local account = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE holder = ?", { accountName })
	return account[1] or nil
end
exports("GetAccountByHolder", getAccountByHolder)
exports("GetAccount", getAccountByHolder) -- provavelmente temos que preparar os dados antes de enviar
exportHandler("GetAccount", getAccountByHolder)

local function getAccountBalance(accountName)
	local account = getAccountByHolder(accountName)
	return account and account.balance or 0
end
exports("GetAccountBalance", getAccountBalance)
exportHandler("GetAccountBalance", getAccountBalance)

local function createBankStatement(playerId, account, amount, reason, statementType, accountType)
	local xPlayer = getPlayerFromId(playerId)
	if not xPlayer then
		return false
	end

	logTransaction(getPlayerIdentifier(xPlayer), reason, account, amount, statementType == "deposit")
	return true
end
exports("CreateBankStatement", createBankStatement)

local function addUserToAccountByHolder(accountName, userId)
    local account = getAccountByHolder(accountName)
    if not account then
        return false
    end
    local users = json.decode(account.users or "[]")
    table.insert(users, { identifier = userId })
    MySQL.update.await(
        "UPDATE ps_banking_accounts SET users = ? WHERE holder = ?",
        { json.encode(users), accountName }
    )
    return true
end
exports("AddUserToAccountByHolder", addUserToAccountByHolder)

local function removeUserFromAccountByHolder(accountName, userId)
    local account = getAccountByHolder(accountName)
    if not account then
        return false
    end
    local users = json.decode(account.users or "[]")
    local updatedUsers = {}
    for _, user in ipairs(users) do
        if user.identifier ~= userId then
            table.insert(updatedUsers, user)
        end
    end
    MySQL.update.await(
        "UPDATE ps_banking_accounts SET users = ? WHERE holder = ?",
        { json.encode(updatedUsers), accountName }
    )
    return true
end
exports("RemoveUserFromAccountByHolder", removeUserFromAccountByHolder)

-- Society Compat MRI

lib.callback.register("ps-banking:server:getHistory", function(source)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)
	local result = MySQL.query.await("SELECT * FROM ps_banking_transactions WHERE identifier = ?", { identifier })
	return result
end)

lib.callback.register("ps-banking:server:getInvestmentProducts", function()
	local economy = getEconomyExports()
	if not economy then
		return { available = false, products = {} }
	end
	return { available = true, products = InvestmentProducts }
end)

lib.callback.register("ps-banking:server:getInvestments", function(source)
	local economy = getEconomyExports()
	if not economy or not economy.GetInvestments then
		return { available = false, investments = {} }
	end

	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return { available = false, investments = {} }
	end
	local identifier = getPlayerIdentifier(xPlayer)
	local ok, investments = pcall(economy.GetInvestments, identifier)
	if not ok then
		return { available = false, investments = {} }
	end

	return { available = true, investments = investments or {} }
end)

lib.callback.register("ps-banking:server:invest", function(source, data)
	local economy = getEconomyExports()
	if not economy or not economy.Invest then
		return { success = false, message = "Sistema econômico indisponível." }
	end

	local ok, result = pcall(economy.Invest, source, data.productId, data.amount)
	if not ok or not result then
		return { success = false, message = "Não foi possível investir." }
	end
	return { success = true, message = "Investimento aplicado com sucesso." }
end)

lib.callback.register("ps-banking:server:redeemInvestment", function(source, data)
	local economy = getEconomyExports()
	if not economy or not economy.RedeemInvestment then
		return { success = false, message = "Sistema econômico indisponível." }
	end

	local ok, result = pcall(economy.RedeemInvestment, source, data.investmentId)
	if not ok or not result then
		return { success = false, message = "Não foi possível resgatar o investimento." }
	end

	return { success = true, message = "Resgate efetuado com sucesso." }
end)

lib.callback.register("ps-banking:server:getStockQuotes", function()
	local economy = getEconomyExports()
	if not economy or not economy.GetStockQuotes then
		return { available = false, quotes = {} }
	end

	local ok, quotes = pcall(economy.GetStockQuotes)
	if not ok then
		return { available = false, quotes = {} }
	end
	return { available = true, quotes = quotes or {} }
end)

lib.callback.register("ps-banking:server:getStockPortfolio", function(source)
	local economy = getEconomyExports()
	if not economy or not economy.GetPortfolio then
		return { available = false, portfolio = {} }
	end

	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return { available = false, portfolio = {} }
	end
	local identifier = getPlayerIdentifier(xPlayer)
	local ok, portfolio = pcall(economy.GetPortfolio, identifier)
	if not ok then
		return { available = false, portfolio = {} }
	end

	return { available = true, portfolio = portfolio or {} }
end)

lib.callback.register("ps-banking:server:buyStock", function(source, data)
	local economy = getEconomyExports()
	if not economy or not economy.BuyStock then
		return { success = false, message = "Sistema econômico indisponível." }
	end

	local ok, result = pcall(economy.BuyStock, source, data.ticker, data.quantity)
	if not ok or not result then
		return { success = false, message = "Não foi possível comprar ações." }
	end

	return { success = true, message = "Compra realizada com sucesso." }
end)

lib.callback.register("ps-banking:server:sellStock", function(source, data)
	local economy = getEconomyExports()
	if not economy or not economy.SellStock then
		return { success = false, message = "Sistema econômico indisponível." }
	end

	local ok, result = pcall(economy.SellStock, source, data.ticker, data.quantity)
	if not ok or not result then
		return { success = false, message = "Não foi possível vender ações." }
	end

	return { success = true, message = "Venda realizada com sucesso." }
end)

lib.callback.register("ps-banking:server:getEconomyIndicators", function()
	local economy = getEconomyExports()
	if not economy then
		return { available = false, indicators = {} }
	end

	local function safeCall(fn, ...)
		if not fn then return nil end
		local ok, result = pcall(fn, ...)
		if ok then return result end
		return nil
	end

	local indicators = {
		selic = safeCall(economy.GetSELIC) or 0,
		inflation = safeCall(economy.GetInflation) or 0,
		pib = safeCall(economy.GetPIB) or 0,
		circulation = safeCall(economy.GetMoneyCirculation) or 0,
		velocity = safeCall(economy.GetVelocity) or 0,
	}

	return { available = true, indicators = indicators }
end)

lib.callback.register("ps-banking:server:getDebts", function(source)
	local economy = getEconomyExports()
	if not economy or not economy.GetActiveDebtsByCitizen then
		return { available = false, debts = {} }
	end

	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return { available = false, debts = {} }
	end
	local identifier = getPlayerIdentifier(xPlayer)
	local ok, debts = pcall(economy.GetActiveDebtsByCitizen, identifier, 50)
	if not ok then
		return { available = false, debts = {} }
	end

	return { available = true, debts = debts or {} }
end)

lib.callback.register("ps-banking:server:payDebt", function(source, data)
	local economy = getEconomyExports()
	if not economy or not economy.PayDebt then
		return { success = false, message = "Sistema econômico indisponível." }
	end

	local ok, success, remaining = pcall(economy.PayDebt, source, data.debtId, data.amount)
	if not ok or not success then
		return { success = false, message = "Não foi possível quitar a dívida." }
	end

	return { success = true, remaining = remaining }
end)

lib.callback.register("ps-banking:server:deleteHistory", function(source)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)
	MySQL.query.await("DELETE FROM ps_banking_transactions WHERE identifier = ?", { identifier })
	return true
end)

lib.callback.register("ps-banking:server:payAllBills", function(source)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)
	local result = MySQL.query.await(
		"SELECT SUM(amount) as total FROM ps_banking_bills WHERE identifier = ? AND isPaid = 0",
		{ identifier }
	)
	local totalAmount = result[1].total or 0
	local bankBalance = getPlayerAccounts(xPlayer)
	if tonumber(bankBalance) >= tonumber(totalAmount) then
		if framework == "ESX" then
			xPlayer.removeAccountMoney("bank", tonumber(totalAmount))
		elseif framework == "QBCore" then
			xPlayer.Functions.RemoveMoney("bank", tonumber(totalAmount))
		end
		MySQL.query.await("DELETE FROM ps_banking_bills WHERE identifier = ?", { identifier })
		return true
	else
		return false
	end
end)

lib.callback.register("ps-banking:server:getWeeklySummary", function(source)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)
	local receivedResult = MySQL.query.await(
		"SELECT SUM(amount) as totalReceived FROM ps_banking_transactions WHERE identifier = ? AND isIncome = ? AND DATE(date) >= DATE(NOW() - INTERVAL 7 DAY)",
		{ identifier, true }
	)
	local totalReceived = receivedResult[1].totalReceived or 0
	local usedResult = MySQL.query.await(
		"SELECT SUM(amount) as totalUsed FROM ps_banking_transactions WHERE identifier = ? AND isIncome = ? AND DATE(date) >= DATE(NOW() - INTERVAL 7 DAY)",
		{ identifier, false }
	)
	local totalUsed = usedResult[1].totalUsed or 0
	return {
		totalReceived = totalReceived,
		totalUsed = totalUsed,
	}
end)

lib.callback.register("ps-banking:server:transferMoney", function(source, data)
	local xPlayer = getPlayerFromId(source)
	local targetPlayer = getPlayerFromId(data.id)
	local amount = tonumber(data.amount)

	if data.id == source and data.method == "id" then
		debugPrint("Transfer blocked: Player tried to send money to themselves")
		return false, locale("cannot_send_self_money")
	end

	if not xPlayer then
		return false, "Player not found"
	end

	if not targetPlayer then
		return false, locale("user_not_in_city")
	end

	-- Validate amount
	local valid, errorMsg = validateAmount(
		amount,
		Config.Security and Config.Security.MinTransferAmount or 1,
		Config.Security and Config.Security.MaxTransferAmount or 999999999
	)
	if not valid then
		debugPrint("Transfer blocked: " .. errorMsg)
		return false, errorMsg
	end

	-- Check daily limit
	local identifier = getPlayerIdentifier(xPlayer)
	local limitOk, limitMsg = checkDailyLimit(identifier, amount)
	if not limitOk then
		debugPrint("Transfer blocked: Daily limit exceeded for " .. identifier)
		return false, limitMsg or "Daily transfer limit exceeded"
	end

	-- Calculate fee
	local fee = calculateFee(amount, "transfer")
	local totalAmount = amount + fee

	local xPlayerBalance = getPlayerAccounts(xPlayer)
	if xPlayerBalance < totalAmount then
		return false, locale("no_money")
	end

	-- Process transfer
	if data.method == "id" then
		if framework == "ESX" then
			xPlayer.removeAccountMoney("bank", totalAmount)
			targetPlayer.addAccountMoney("bank", amount)
		elseif framework == "QBCore" then
			xPlayer.Functions.RemoveMoney("bank", totalAmount)
			targetPlayer.Functions.AddMoney("bank", amount)
		end

		-- Update daily limit
		updateDailyLimit(identifier, amount)

		-- Log audit
		logAudit("transfer", identifier, getPlayerIdentifier(targetPlayer), nil, amount, {
			method = "id",
			fee = fee,
			senderName = getName(xPlayer),
			recipientName = getName(targetPlayer)
		})

		-- Send webhook
		if Config.Webhooks and Config.Webhooks.TransferWebhook then
			sendWebhook(
				Config.Webhooks.TransferWebhook,
				"Transferência Realizada",
				string.format("**De:** %s (%s)\n**Para:** %s (%s)\n**Valor:** %s\n**Taxa:** %s",
					getName(xPlayer), identifier,
					getName(targetPlayer), getPlayerIdentifier(targetPlayer),
					amount, fee
				),
				3066993
			)
		end

		debugPrint(string.format("Transfer: %s sent %s to %s (Fee: %s)", identifier, amount, getPlayerIdentifier(targetPlayer), fee))
		return true, locale("money_sent", amount, getName(targetPlayer))

	elseif data.method == "phone" and Config.LBPhone then
		exports["lb-phone"]:AddTransaction(
			targetPlayer.identifier,
			amount,
			locale("received_money", getName(xPlayer), amount)
		)

		-- Update daily limit
		updateDailyLimit(identifier, amount)

		-- Log audit
		logAudit("transfer", identifier, getPlayerIdentifier(targetPlayer), nil, amount, {
			method = "phone",
			fee = fee
		})

		return true, locale("money_sent", amount, getName(targetPlayer))
	end

	return false, "Invalid transfer method"
end)

RegisterNetEvent("ps-banking:server:logClient", function(account, moneyData)
	if account.name ~= "bank" then
		return
	end

	local src = source
	local xPlayer = getPlayerFromId(src)
	local identifier = getPlayerIdentifier(xPlayer)

	local previousBankBalance = 0
	if moneyData then
		for _, data in ipairs(moneyData) do
			if data.name == "bank" then
				previousBankBalance = data.amount
				break
			end
		end
	end

	local currentBankBalance = getPlayerAccounts(xPlayer)
	local amountChange = currentBankBalance - previousBankBalance

	if amountChange ~= 0 then
		local isIncome = currentBankBalance >= previousBankBalance and true or false
		local description = locale("transaction_description")
		logTransaction(identifier, description, account.name, math.abs(amountChange), isIncome)
	end
end)

lib.callback.register("ps-banking:server:getTransactionStats", function(source)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)

	local result = MySQL.query.await(
		"SELECT COUNT(*) as totalCount, SUM(amount) as totalAmount FROM ps_banking_transactions WHERE identifier = ?",
		{ identifier }
	)
	local transactionData = MySQL.query.await(
		"SELECT amount, date FROM ps_banking_transactions WHERE identifier = ? ORDER BY date DESC LIMIT 50",
		{ identifier }
	)

	return {
		totalCount = result[1].totalCount,
		totalAmount = result[1].totalAmount,
		transactionData = transactionData,
	}
end)

lib.callback.register("ps-banking:server:createNewAccount", function(source, newAccount)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end

	local identifier = getPlayerIdentifier(xPlayer)

	-- Validate group name
	if not validateGroup(newAccount.holder) then
		debugPrint("Account creation blocked: Invalid group name")
		return false
	end

	-- Check if account with this holder already exists
	local existingAccount = getAccountByHolder(newAccount.holder)
	if existingAccount then
		debugPrint("Account creation blocked: Account already exists with this name")
		return false
	end

	-- Check maximum accounts per player
	if Config.Accounts and Config.Accounts.MaxAccountsPerPlayer then
		local playerAccounts = MySQL.query.await(
			"SELECT COUNT(*) as count FROM ps_banking_accounts WHERE JSON_EXTRACT(owner, '$.identifier') = ?",
			{ identifier }
		)
		if playerAccounts[1].count >= Config.Accounts.MaxAccountsPerPlayer then
			debugPrint("Account creation blocked: Maximum accounts limit reached")
			return false
		end
	end

	-- Set initial balance from config
	local initialBalance = Config.Accounts and Config.Accounts.InitialAccountBalance or 0
	if newAccount.balance then
		initialBalance = newAccount.balance
	end

	MySQL.insert.await(
		"INSERT INTO ps_banking_accounts (balance, holder, cardNumber, users, owner, status) VALUES (?, ?, ?, ?, ?, ?)",
		{
			initialBalance,
			newAccount.holder,
			newAccount.cardNumber,
			json.encode(newAccount.users),
			json.encode(newAccount.owner),
			'active'
		}
	)

	-- Log audit
	logAudit("account_created", identifier, nil, nil, initialBalance, {
		holder = newAccount.holder,
		cardNumber = newAccount.cardNumber
	})

	-- Send webhook
	if Config.Webhooks and Config.Webhooks.AccountWebhook then
		sendWebhook(
			Config.Webhooks.AccountWebhook,
			"Nova Conta Criada",
			string.format("**Titular:** %s\n**Criada por:** %s\n**Saldo Inicial:** %s",
				newAccount.holder, getName(xPlayer), initialBalance
			),
			3066993
		)
	end

	debugPrint(string.format("Account created: %s by %s", newAccount.holder, identifier))
	return true
end)

lib.callback.register("ps-banking:server:getUser", function(source)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end
	return {
		name = getName(xPlayer),
		identifier = getPlayerIdentifier(xPlayer),
	}
end)

lib.callback.register("ps-banking:server:getAccounts", function(source)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end
	
	local playerIdentifier = getPlayerIdentifier(xPlayer)
	local playerJob = xPlayer.PlayerData.job.name
	local playerGang = xPlayer.PlayerData.gang.name

	if Config.Debug then
		print(("[ps-banking] Buscando contas para jogador %s (Job: %s, Gang: %s)"):format(playerIdentifier, playerJob, playerGang))
	end

	local accounts = MySQL.query.await("SELECT * FROM ps_banking_accounts")
	local result = {}

	for _, account in ipairs(accounts) do
		local accountData = {
			id = account.id,
			balance = account.balance,
			holder = account.holder,
			cardNumber = account.cardNumber,
			users = json.decode(account.users),
			owner = json.decode(account.owner),
		}

		local isJobOrGangAccount = not validateGroup(accountData.holder)

		if Config.Debug then
			print(("[ps-banking] Conta ID %s pertence a %s - Conta de Job/Gang? %s"):format(accountData.id, accountData.holder, isJobOrGangAccount))
		end

		if accountData.owner and accountData.owner.identifier == playerIdentifier then
			if isJobOrGangAccount and accountData.holder ~= playerJob and accountData.holder ~= playerGang then
				if Config.Debug then
					print(("[ps-banking] REMOVENDO jogador %s como OWNER da conta %s (Job/Gang: %s)"):format(playerIdentifier, accountData.holder, accountData.holder))
				end

				accountData.owner = {}

				MySQL.update.await(
					"UPDATE ps_banking_accounts SET owner = ? WHERE id = ?",
					{ json.encode(accountData.owner), accountData.id }
				)
			else
				accountData.owner.state = true
				table.insert(result, accountData)
			end
		else
			local shouldRemove = false

			if isJobOrGangAccount and accountData.holder ~= playerJob and accountData.holder ~= playerGang then
				shouldRemove = true
			end

			for index, user in ipairs(accountData.users) do
				if user.identifier == playerIdentifier then
					if shouldRemove then
						if Config.Debug then
							print(("[ps-banking] REMOVENDO jogador %s da lista de usuários da conta %s (Job/Gang: %s)"):format(playerIdentifier, accountData.holder, accountData.holder))
						end

						table.remove(accountData.users, index)

						MySQL.update.await(
							"UPDATE ps_banking_accounts SET users = ? WHERE id = ?",
							{ json.encode(accountData.users), accountData.id }
						)
					else
						accountData.owner.state = false
						table.insert(result, accountData)
					end
					break
				end
			end
		end
	end

	if Config.Debug then
		print("[ps-banking] Contas processadas para o jogador:", json.encode(result, { indent = true }))
	end

	return result
end)


lib.callback.register("ps-banking:server:deleteAccount", function(source, accountId)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end

    local account = getAccountById(accountId)
    if not account then
        return false
    end

    if not validateGroup(account.holder) then
        return false
    end

	MySQL.query.await("DELETE FROM ps_banking_accounts WHERE id = ?", { accountId })
	return true
end)

lib.callback.register("ps-banking:server:withdrawFromAccount", function(source, accountId, amount)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end
	local account = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE id = ?", { accountId })
	if #account > 0 then
		local balance = account[1].balance
		if balance >= amount then
			local affectedRows = MySQL.update.await(
				"UPDATE ps_banking_accounts SET balance = balance - ? WHERE id = ?",
				{ amount, accountId }
			)
			if affectedRows > 0 then
				if framework == "ESX" then
					xPlayer.addAccountMoney("bank", amount)
				elseif framework == "QBCore" then
					xPlayer.Functions.AddMoney("bank", amount)
				end
				return true
			else
				return false
			end
		else
			return false
		end
	else
		return false
	end
end)

lib.callback.register("ps-banking:server:depositToAccount", function(source, accountId, amount)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end
    local bankBalance = getPlayerAccounts(xPlayer)
	if tonumber(bankBalance) >= tonumber(amount) then
		local affectedRows = MySQL.update.await(
			"UPDATE ps_banking_accounts SET balance = balance + ? WHERE id = ?",
			{ amount, accountId }
		)
		if affectedRows > 0 then
			if framework == "ESX" then
				xPlayer.removeAccountMoney("bank", amount)
			elseif framework == "QBCore" then
				xPlayer.Functions.RemoveMoney("bank", amount)
			end
			return true
		else
			return false
		end
	else
		return false
	end
end)

lib.callback.register("ps-banking:server:addUserToAccount", function(source, accountId, userId)
	local xPlayer = getPlayerFromId(source)
	local targetPlayer = getPlayerFromId(userId)
	local promise = promise.new()
	if source == userId then
		return {
			success = false,
			message = locale("cannot_add_self"),
		}
	end
	if not xPlayer then
		return {
			success = false,
			message = locale("player_not_found"),
		}
	end
	if not targetPlayer then
		return {
			success = false,
			message = locale("target_player_not_found"),
		}
	end
	local accounts = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE id = ?", { accountId })
	if #accounts > 0 then
		local account = accounts[1]
		local users = json.decode(account.users)
		for _, user in ipairs(users) do
			if user.identifier == userId then
				return {
					success = false,
					message = locale("user_already_in_account"),
				}
			end
		end
		table.insert(users, {
			name = getName(targetPlayer),
			identifier = getPlayerIdentifier(targetPlayer),
		})
		local affectedRows = MySQL.update.await(
			"UPDATE ps_banking_accounts SET users = ? WHERE id = ?",
			{ json.encode(users), accountId }
		)
		return {
			success = affectedRows > 0,
			userName = getName(targetPlayer),
		}
	else
		return {
			success = false,
			message = locale("account_not_found"),
		}
	end
end)

lib.callback.register("ps-banking:server:removeUserFromAccount", function(source, accountId, userId)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end
	local accounts = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE id = ?", { accountId })
	if #accounts > 0 then
		local account = accounts[1]
		local users = json.decode(account.users)
		local updatedUsers = {}
		for _, user in ipairs(users) do
			if user.identifier ~= userId then
				table.insert(updatedUsers, user)
			end
		end
		local affectedRows = MySQL.update.await(
			"UPDATE ps_banking_accounts SET users = ? WHERE id = ?",
			{ json.encode(updatedUsers), accountId }
		)
		return affectedRows > 0
	else
		return false
	end
end)

lib.callback.register("ps-banking:server:renameAccount", function(source, id, newName)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end
	local affectedRows = MySQL.update.await("UPDATE ps_banking_accounts SET holder = ? WHERE id = ?", { newName, id })
	return affectedRows > 0
end)

lib.callback.register("ps-banking:server:ATMwithdraw", function(source, amount)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end

	-- Validate amount
	local valid, errorMsg = validateAmount(
		amount,
		Config.Security and Config.Security.MinWithdrawAmount or 1,
		Config.Security and Config.Security.MaxWithdrawAmount or 100000
	)
	if not valid then
		debugPrint("ATM withdraw blocked: " .. errorMsg)
		return false
	end

	local fee = calculateFee(amount, "atm_withdraw")
	local totalAmount = amount + fee
	local bankBalance = getPlayerAccounts(xPlayer)

	if bankBalance >= totalAmount then
		if framework == "ESX" then
			xPlayer.removeAccountMoney("bank", totalAmount)
			xPlayer.addMoney(amount)
		elseif framework == "QBCore" then
			xPlayer.Functions.RemoveMoney("bank", totalAmount)
			xPlayer.Functions.AddMoney("cash", amount)
		end

		-- Log audit
		local identifier = getPlayerIdentifier(xPlayer)
		logAudit("atm_withdraw", identifier, nil, nil, amount, { fee = fee })

		debugPrint(string.format("ATM Withdraw: %s withdrew %s (Fee: %s)", identifier, amount, fee))
		return true
	else
		return false
	end
end)

lib.callback.register("ps-banking:server:ATMdeposit", function(source, amount)
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end

	-- Validate amount
	local valid, errorMsg = validateAmount(
		amount,
		Config.Security and Config.Security.MinDepositAmount or 1,
		Config.Security and Config.Security.MaxDepositAmount or 500000
	)
	if not valid then
		debugPrint("ATM deposit blocked: " .. errorMsg)
		return false
	end

	local cashBalance = nil
	if framework == "ESX" then
		cashBalance = xPlayer.getMoney()
	elseif framework == "QBCore" then
		cashBalance = xPlayer.PlayerData.money["cash"]
	end

	if cashBalance >= amount then
		if framework == "ESX" then
			xPlayer.removeMoney(amount)
			xPlayer.addAccountMoney("bank", amount)
		elseif framework == "QBCore" then
			xPlayer.Functions.RemoveMoney("cash", amount)
			xPlayer.Functions.AddMoney("bank", amount)
		end

		-- Log audit
		local identifier = getPlayerIdentifier(xPlayer)
		logAudit("atm_deposit", identifier, nil, nil, amount, {})

		debugPrint(string.format("ATM Deposit: %s deposited %s", identifier, amount))
		return true
	else
		return false
	end
end)

lib.callback.register("ps-banking:server:getBills", function(source)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)
	local result = MySQL.query.await("SELECT * FROM ps_banking_bills WHERE identifier = ?", { identifier })
	return result
end)

lib.callback.register("ps-banking:server:payBill", function(source, billId)
	local xPlayer = getPlayerFromId(source)
	local identifier = getPlayerIdentifier(xPlayer)
	local result = MySQL.query.await(
		"SELECT * FROM ps_banking_bills WHERE id = ? AND identifier = ? AND isPaid = 0",
		{ billId, identifier }
	)
	if #result == 0 then
		return false
	end
	local bill = result[1]
	local amount = bill.amount

	local xPlayerName = xPlayer.PlayerData.charinfo.firstname ..' '.. xPlayer.PlayerData.charinfo.lastname

	local identifier2 = bill.identifier2
	local senderPlayer = exports.qbx_core:GetOfflinePlayer(identifier2)
	local senderName = senderPlayer.PlayerData.charinfo.firstname ..' '.. senderPlayer.PlayerData.charinfo.lastname
	local senderLicense = senderPlayer.PlayerData.license

	if tonumber(getPlayerAccounts(xPlayer)) >= tonumber(amount) then
		if framework == "ESX" then
			xPlayer.removeAccountMoney("bank", tonumber(amount))
		elseif framework == "QBCore" then
			xPlayer.Functions.RemoveMoney("bank", tonumber(amount))
			-- senderPlayer.Functions.AddMoney("bank", tonumber(amount))
			exports.qbx_core:AddMoney(identifier2, "bank", amount, "Fatura recebida: ".. bill.description)

			logTransaction(identifier2, "Fatura recebida: ".. bill.description, xPlayerName, amount, true)
			logTransaction(identifier, "Fatura paga: ".. bill.description, xPlayerName, amount, false)

			local senderSource = exports.qbx_core:GetSource(senderLicense)
			print(xPlayerName .. " pagou uma fatura de R$" .. amount, "ID", senderSource)
			if senderSource > 0 then 
				exports["lb-phone"]:SendNotification(senderSource, {
					app = "Wallet",
					title = "Uma fatura foi paga",
					content = xPlayerName .. " pagou uma fatura de R$" .. amount .. ".",
				})
			end
		end
		MySQL.query.await("DELETE FROM ps_banking_bills WHERE id = ?", { billId })
		return true
	else
		return false
	end
end)

function createBill(data)
	local identifier = data.identifier
	local identifier2 = data.identifier2 or nil
	local description = data.description
	local type = data.type
	local amount = data.amount
	local dueDays = data.dueDays or (Config.Bills and Config.Bills.DefaultDueDays or 7)

	-- Validate amount
	local valid, errorMsg = validateAmount(
		amount,
		Config.Bills and Config.Bills.MinBillAmount or 1,
		Config.Bills and Config.Bills.MaxBillAmount or 1000000
	)
	if not valid then
		debugPrint("Bill creation blocked: " .. errorMsg)
		return false
	end

	-- Calculate due date
	local dueDate = nil
	if Config.Bills and Config.Bills.EnableDueDates then
		dueDate = os.date("%Y-%m-%d %H:%M:%S", os.time() + (dueDays * 24 * 60 * 60))
	end

	-- Calculate fee
	local fee = calculateFee(amount, "bill")

	MySQL.insert.await(
		"INSERT INTO ps_banking_bills (identifier, identifier2, description, type, amount, date, due_date, isPaid) VALUES (?, ?, ?, ?, ?, NOW(), ?, ?)",
		{ identifier, identifier2, description, type, amount + fee, dueDate, false }
	)

	-- Log audit
	logAudit("bill_created", identifier2 or "system", identifier, nil, amount, {
		description = description,
		type = type,
		fee = fee,
		dueDate = dueDate
	})

	-- Send webhook
	if Config.Webhooks and Config.Webhooks.BillWebhook then
		sendWebhook(
			Config.Webhooks.BillWebhook,
			"Nova Fatura Criada",
			string.format("**Para:** %s\n**De:** %s\n**Descrição:** %s\n**Valor:** %s\n**Taxa:** %s\n**Vencimento:** %s",
				identifier, identifier2 or "Sistema", description, amount, fee, dueDate or "N/A"
			),
			15158332
		)
	end

	debugPrint(string.format("Bill created: %s for %s, amount: %s", description, identifier, amount))
	return true
end
exports("createBill", createBill)

--[[ EXAMPLE
    exports["ps-banking"]:createBill({
        identifier = "char1:df6c12c50e2712c57b1386e7103d5a372fb960a0",
        description = "Utility Bill",
        type = "Expense",
        amount = 150.00,
    })
]]

-- Society Compat MRI
local function updateAccountOwner(accountName, newOwnerIdentifier, newOwnerName)
    local account = getAccountByHolder(accountName)
    if not account then return end

    local newOwnerData = {
        name = newOwnerName,
        state = true,
        identifier = newOwnerIdentifier
    }

    MySQL.update.await(
        "UPDATE ps_banking_accounts SET owner = ? WHERE holder = ?",
        { json.encode(newOwnerData), accountName }
    )

    if Config.Debug then
        print(("[ps-banking] Conta %s agora pertence a %s (%s)"):format(accountName, newOwnerName, newOwnerIdentifier))
    end
end


local function createSocietyAccountIfMissing(source, groupName, isJob)
    local xPlayer = getPlayerFromId(source)
    if not xPlayer then return end

    local isBoss = isJob and xPlayer.PlayerData.job.isboss or xPlayer.PlayerData.gang.isboss
    local playerIdentifier = getPlayerIdentifier(xPlayer)
    local playerName = getName(xPlayer)

    local accountExists = getAccountByHolder(groupName)

    if not accountExists and isBoss then
        if Config.Debug then
            print(("[ps-banking] Criando conta para o %s %s pois %s agora é chefe."):format(
                isJob and "Job" or "Gang", groupName, playerIdentifier))
        end
        createPlayerAccount(source, groupName, 0, {})
    elseif accountExists and isBoss then
        if Config.Debug then
            print(("[ps-banking] Atualizando conta para o %s %s pois %s agora é chefe."):format(
                isJob and "Job" or "Gang", groupName, playerIdentifier))
        end
        updateAccountOwner(groupName, playerIdentifier, playerName)
    end
end


lib.callback.register("ps-banking:server:createSocietyAccount", function(source)
    local xPlayer = getPlayerFromId(source)
    if not xPlayer then
        return false
    end

    createSocietyAccountIfMissing(source, xPlayer.PlayerData.job.name, true)
    
    createSocietyAccountIfMissing(source, xPlayer.PlayerData.gang.name, false)

    return true
end)


local function removePlayerFromAccount(playerIdentifier, account)
    local accountData = {
        id = account.id,
        holder = account.holder,
        users = json.decode(account.users),
        owner = json.decode(account.owner),
    }

    local isJobOrGangAccount = not validateGroup(accountData.holder)

    if isJobOrGangAccount then
        if accountData.owner and accountData.owner.identifier == playerIdentifier then
            if Config.Debug then
                print(("[ps-banking] Removendo jogador %s como OWNER da conta %s"):format(
                    playerIdentifier, accountData.holder))
            end
            accountData.owner = {}
            MySQL.update.await("UPDATE ps_banking_accounts SET owner = ? WHERE id = ?", 
                { json.encode(accountData.owner), accountData.id })
        end

        for index, user in ipairs(accountData.users) do
            if user.identifier == playerIdentifier then
                if Config.Debug then
                    print(("[ps-banking] Removendo jogador %s da lista de usuários da conta %s"):format(
                        playerIdentifier, accountData.holder))
                end
                table.remove(accountData.users, index)
                MySQL.update.await("UPDATE ps_banking_accounts SET users = ? WHERE id = ?", 
                    { json.encode(accountData.users), accountData.id })
                break
            end
        end
    end
end

local function addPlayerToAccount(playerIdentifier, jobName)
    if jobName == "unemployed" or jobName == "none" then
        return
    end

    local account = MySQL.query.await("SELECT * FROM ps_banking_accounts WHERE holder = ?", { jobName })
    if #account > 0 then
        local accountData = account[1]
        local users = json.decode(accountData.users)

        local isUserPresent = false
        for _, user in ipairs(users) do
            if user.identifier == playerIdentifier then
                isUserPresent = true
                break
            end
        end

        if not isUserPresent then
            if Config.Debug then
                print(("[ps-banking] Adicionando jogador %s à conta %s"):format(
                    playerIdentifier, jobName))
            end
            table.insert(users, { identifier = playerIdentifier })
            MySQL.update.await("UPDATE ps_banking_accounts SET users = ? WHERE holder = ?", 
                { json.encode(users), jobName })
        end
    end
end

lib.callback.register("ps-banking:server:playerGroupInfo", function(source, data, isJob)
    local xPlayer = getPlayerFromId(source)
    if not xPlayer or not data or not data.name then
        return
    end

    local playerIdentifier = getPlayerIdentifier(xPlayer)
    local playerJob = xPlayer.PlayerData.job.name
    local playerGang = xPlayer.PlayerData.gang.name

    if Config.Debug then
        print(("[ps-banking] Atualizando contas para jogador %s (Novo %s: %s)"):format(
            playerIdentifier, isJob and "Job" or "Gang", data.name))
    end

    local accounts = MySQL.query.await("SELECT * FROM ps_banking_accounts")
    for _, account in ipairs(accounts) do
        removePlayerFromAccount(playerIdentifier, account)
    end

    createSocietyAccountIfMissing(source, data.name, isJob)

    addPlayerToAccount(playerIdentifier, data.name)

    if isJob then
        PlayerJob = data
    else
        PlayerGang = data
    end
end)

-- =====================================================
-- Additional Exports
-- =====================================================

-- Get all accounts for a player
local function getPlayerAllAccounts(identifier)
	local accounts = MySQL.query.await(
		"SELECT * FROM ps_banking_accounts WHERE JSON_EXTRACT(owner, '$.identifier') = ? OR JSON_SEARCH(users, 'one', ?, NULL, '$[*].identifier') IS NOT NULL",
		{ identifier, identifier }
	)
	return accounts
end
exports("GetPlayerAllAccounts", getPlayerAllAccounts)

-- Freeze/Unfreeze account
local function setAccountStatus(accountId, status)
	if not accountId or not status then
		return false
	end

	if status ~= "active" and status ~= "frozen" and status ~= "closed" then
		return false
	end

	local affectedRows = MySQL.update.await(
		"UPDATE ps_banking_accounts SET status = ? WHERE id = ?",
		{ status, accountId }
	)

	-- Log audit
	logAudit("account_status_changed", "system", nil, accountId, nil, { newStatus = status })

	return affectedRows > 0
end
exports("SetAccountStatus", setAccountStatus)
exports("FreezeAccount", function(accountId) return setAccountStatus(accountId, "frozen") end)
exports("UnfreezeAccount", function(accountId) return setAccountStatus(accountId, "active") end)
exports("CloseAccount", function(accountId) return setAccountStatus(accountId, "closed") end)

-- Get account transactions
local function getAccountTransactions(accountId, limit)
	limit = limit or 50
	local account = getAccountById(accountId)
	if not account then
		return {}
	end

	local transactions = MySQL.query.await(
		"SELECT * FROM ps_banking_transactions WHERE type = ? ORDER BY date DESC LIMIT ?",
		{ account.holder, limit }
	)
	return transactions
end
exports("GetAccountTransactions", getAccountTransactions)

-- Get unpaid bills for player
local function getUnpaidBills(identifier)
	local bills = MySQL.query.await(
		"SELECT * FROM ps_banking_bills WHERE identifier = ? AND isPaid = 0 ORDER BY date DESC",
		{ identifier }
	)
	return bills
end
exports("GetUnpaidBills", getUnpaidBills)

-- Check if player has sufficient balance
local function hasSufficientBalance(source, amount, accountType)
	accountType = accountType or "bank"
	local xPlayer = getPlayerFromId(source)
	if not xPlayer then
		return false
	end

	if accountType == "bank" then
		local balance = getPlayerAccounts(xPlayer)
		return balance >= amount
	elseif accountType == "cash" then
		local balance
		if framework == "ESX" then
			balance = xPlayer.getMoney()
		elseif framework == "QBCore" then
			balance = xPlayer.PlayerData.money["cash"]
		end
		return balance >= amount
	end

	return false
end
exports("HasSufficientBalance", hasSufficientBalance)

-- Get account owner info
local function getAccountOwner(accountId)
	local account = getAccountById(accountId)
	if not account then
		return nil
	end

	local owner = json.decode(account.owner)
	return owner
end
exports("GetAccountOwner", getAccountOwner)

-- Transfer between accounts
local function transferBetweenAccounts(fromAccountId, toAccountId, amount, reason)
	local fromAccount = getAccountById(fromAccountId)
	local toAccount = getAccountById(toAccountId)

	if not fromAccount or not toAccount then
		return false, "Account not found"
	end

	if fromAccount.balance < amount then
		return false, "Insufficient balance"
	end

	-- Remove from source account
	MySQL.update.await(
		"UPDATE ps_banking_accounts SET balance = balance - ? WHERE id = ?",
		{ amount, fromAccountId }
	)

	-- Add to target account
	MySQL.update.await(
		"UPDATE ps_banking_accounts SET balance = balance + ? WHERE id = ?",
		{ amount, toAccountId }
	)

	-- Log transactions
	local fromOwner = json.decode(fromAccount.owner)
	local toOwner = json.decode(toAccount.owner)

	if fromOwner.identifier then
		logTransaction(fromOwner.identifier, reason or "Transfer between accounts", fromAccount.holder, amount, false)
	end

	if toOwner.identifier then
		logTransaction(toOwner.identifier, reason or "Transfer between accounts", toAccount.holder, amount, true)
	end

	-- Log audit
	logAudit("account_transfer", fromOwner.identifier or "system", toOwner.identifier or "system", fromAccountId, amount, {
		toAccountId = toAccountId,
		reason = reason
	})

	return true
end
exports("TransferBetweenAccounts", transferBetweenAccounts)

-- Society Compat MRI
