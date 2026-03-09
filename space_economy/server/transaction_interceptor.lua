-- =====================================================
-- INTERCEPTADOR DE TRANSAÇÕES
-- Detecta e intercepta todas as transações financeiras do servidor
-- Garante que tudo passe pelo sistema econômico centralizado
-- =====================================================

local SE = exports['space_economy']:GetCoreObject()

SE.TransactionInterceptor = {}
local TI = SE.TransactionInterceptor

-- Configurações
TI.Config = {
    enabled = true,
    enforce_integration = true,      -- Força integração ou apenas alerta
    auto_apply_taxes = true,          -- Aplica impostos automaticamente
    block_unregistered = false,       -- Bloqueia transações de serviços não registrados
    log_all_transactions = true,      -- Loga todas as transações
    alert_threshold = 10000           -- Alerta para admins em transações acima deste valor
}

-- Rastreamento de transações
TI.TransactionQueue = {}
TI.Initialized = false
TI.Statistics = {
    total_intercepted = 0,
    total_volume = 0,
    by_resource = {},
    by_type = {},
    blocked_count = 0,
    blocked_volume = 0
}

-- =====================================================
-- INTERCEPTAÇÃO DE EVENTOS NATIVOS
-- =====================================================

-- Lista de eventos conhecidos que lidam com dinheiro
TI.MoneyEvents = {
    -- QBCore
    'QBCore:Server:OnMoneyChange',
    'QBCore:Server:SetMoney',
    'QBCore:Server:AddMoney',
    'QBCore:Server:RemoveMoney',

    -- ESX
    'esx:addMoney',
    'esx:removeMoney',
    'esx:addAccountMoney',
    'esx:removeAccountMoney',

    -- QB-Banking
    'qb-banking:server:addMoney',
    'qb-banking:server:removeMoney',
    'qb-banking:server:depositMoney',
    'qb-banking:server:withdrawMoney',

    -- PS-Banking
    'ps-banking:server:addMoney',
    'ps-banking:server:removeMoney',
    'ps-banking:server:depositMoney',
    'ps-banking:server:withdrawMoney',
    'ps-banking:server:transfer',

    -- Genéricos
    'banking:server:depositMoney',
    'banking:server:withdrawMoney',
    'bank:deposit',
    'bank:withdraw'
}

---Intercepta um evento de dinheiro
---@param eventName string
---@param originalHandler function
---@return function wrappedHandler
function TI.WrapMoneyEvent(eventName, originalHandler)
    return function(...)
        local args = {...}
        local resource = GetInvokingResource() or 'unknown'

        -- Extrai informações da transação
        local transactionData = TI.ExtractTransactionData(eventName, args)
        local src = tonumber(transactionData.source or source) or 0

        -- Registra a interceptação
        TI.LogInterception(src, resource, eventName, transactionData)

        -- Verifica se o recurso está registrado
        local service = nil
        if SE.ServiceRegistry and SE.ServiceRegistry.GetService then
            service = SE.ServiceRegistry.GetService(resource)
        end

        if not service then
            -- Detecta serviço não registrado
            if SE.ServiceRegistry and SE.ServiceRegistry.DetectUnregisteredService then SE.ServiceRegistry.DetectUnregisteredService(resource, {
                timestamp = os.time(),
                source = src,
                amount = transactionData.amount or 0,
                type = transactionData.type or 'unknown',
                account = transactionData.account or 'unknown',
                reason = eventName
            }) end

            -- Se configurado para bloquear
            if TI.Config.block_unregistered then
                print(('^1[TransactionInterceptor] ❌ BLOQUEADO: %s de %s tentou %s sem registro!^7'):format(
                    resource, GetPlayerName(src), eventName
                ))

                TI.Statistics.blocked_count = TI.Statistics.blocked_count + 1
                TI.Statistics.blocked_volume = TI.Statistics.blocked_volume + (transactionData.amount or 0)

                -- Notifica admin
                TI.NotifyAdmins('blocked_transaction', {
                    resource = resource,
                    player = GetPlayerName(src),
                    event = eventName,
                    amount = transactionData.amount
                })

                return -- Bloqueia a transação
            end
        end

        -- Se configurado para aplicar impostos automaticamente
        if TI.Config.auto_apply_taxes and service and transactionData.amount and transactionData.amount > 0 then
            TI.ApplyTaxesToTransaction(src, transactionData, service)
        end

        -- Executa o handler original
        if originalHandler then
            return originalHandler(...)
        end
    end
end

---Extrai dados de uma transação de diferentes formatos de eventos
---@param eventName string
---@param args table
---@return table transactionData
local KNOWN_ACCOUNTS = {
    cash = true, bank = true, crypto = true, money = true, markedbills = true
}

local function normalizeText(v, fallback)
    local out = tostring(v or fallback or '')
    if out == '' then return tostring(fallback or '') end
    return out
end

local function normalizeAccount(v)
    local account = tostring(v or ''):lower()
    if KNOWN_ACCOUNTS[account] then return account end
    return nil
end

local function normalizeTxType(v)
    local op = tostring(v or ''):lower()
    if op == 'add' or op == 'remove' or op == 'set' or op == 'paycheck' or op == 'deposit' or op == 'withdraw' then
        if op == 'deposit' then return 'add' end
        if op == 'withdraw' then return 'remove' end
        return op
    end
    return nil
end

function TI.ExtractTransactionData(eventName, args)
    local data = {
        amount = 0,
        type = nil,
        account = nil,
        reason = nil,
        source = nil,
        raw_args = args
    }

    local lowerEvent = tostring(eventName or ''):lower()

    for i = 1, #args do
        local value = args[i]
        local t = type(value)

        if t == 'number' then
            if i == 1 and value > 0 and value < 65536 then
                data.source = data.source or math.floor(value)
            elseif data.amount == 0 then
                data.amount = tonumber(value) or 0
            end
        elseif t == 'string' then
            local acc = normalizeAccount(value)
            if acc and not data.account then
                data.account = acc
            else
                local op = normalizeTxType(value)
                if op and not data.type then
                    data.type = op
                elseif not data.reason and value ~= '' then
                    data.reason = value
                end
            end
        elseif t == 'table' then
            data.amount = tonumber(value.amount or value.value or value.money or data.amount) or data.amount
            data.account = normalizeAccount(value.account or value.moneyType or value.type) or data.account
            data.type = normalizeTxType(value.transaction_type or value.action or value.operation or value.type) or data.type
            data.reason = normalizeText(value.reason or value.description, data.reason)
            data.source = tonumber(value.source or value.src or value.playerId or data.source) or data.source
        end
    end

    if not data.type then
        if lowerEvent:match('add') or lowerEvent:match('deposit') then
            data.type = 'add'
        elseif lowerEvent:match('remove') or lowerEvent:match('withdraw') then
            data.type = 'remove'
        elseif lowerEvent:match('set') then
            data.type = 'set'
        elseif lowerEvent:match('paycheck') then
            data.type = 'paycheck'
        else
            data.type = 'unknown'
        end
    end

    data.account = data.account or 'cash'
    data.reason = normalizeText(data.reason, eventName)
    data.amount = tonumber(data.amount) or 0

    return data
end

-- =====================================================
-- HOOKS NO FRAMEWORK
-- =====================================================

---Cria hooks nos frameworks para interceptar AddMoney/RemoveMoney
function TI.HookFrameworkFunctions()
    -- Detecta framework
    local framework = nil

    if GetResourceState('qb-core') == 'started' or GetResourceState('qbx_core') == 'started' then
        framework = 'qbcore'
    elseif GetResourceState('es_extended') == 'started' then
        framework = 'esx'
    end

    if not framework then
        print('^3[TransactionInterceptor] Nenhum framework detectado, usando modo genérico^7')
        return
    end

    print(('^2[TransactionInterceptor] Framework detectado: %s^7'):format(framework))

    -- Hook específico para cada framework será feito via events
    -- pois não podemos modificar funções de objetos diretamente
end

-- =====================================================
-- INTERCEPTAÇÃO DE EXPORTS
-- =====================================================

-- Rastreia chamadas de exports relacionadas a dinheiro
local originalExport = exports

-- Monkey patch no sistema de exports (AVANÇADO)
_G.exports = setmetatable({}, {
    __index = function(_, resource)
        -- Se é um recurso relacionado a banco/dinheiro
        if resource == 'qb-banking' or resource == 'ps-banking' or
           resource == 'esx_society' or resource:match('bank') then
            return setmetatable({}, {
                __index = function(_, exportName)
                    local originalExportFunc = originalExport[resource] and originalExport[resource][exportName]
                    if type(originalExportFunc) ~= 'function' then
                        return function(...)
                            return originalExport[resource][exportName](...)
                        end
                    end

                    -- Wrappa a função de export
                    return function(...)
                        local invokingResource = GetInvokingResource() or 'unknown'

                        -- Loga a chamada
                        TI.LogExportCall(invokingResource, resource, exportName, {...})

                        -- Chama função original
                        return originalExportFunc(...)
                    end
                end
            })
        end

        -- Retorna export normal para outros recursos
        return originalExport[resource]
    end
})

-- =====================================================
-- LOGGING E RASTREAMENTO
-- =====================================================

---Registra uma interceptação
---@param source number
---@param resource string
---@param eventName string
---@param transactionData table
function TI.LogInterception(source, resource, eventName, transactionData)
    local amount = tonumber(transactionData.amount) or 0

    -- Estatísticas
    TI.Statistics.total_intercepted = TI.Statistics.total_intercepted + 1
    TI.Statistics.total_volume = TI.Statistics.total_volume + math.abs(amount)

    if not TI.Statistics.by_resource[resource] then
        TI.Statistics.by_resource[resource] = { count = 0, volume = 0 }
    end
    TI.Statistics.by_resource[resource].count = TI.Statistics.by_resource[resource].count + 1
    TI.Statistics.by_resource[resource].volume = TI.Statistics.by_resource[resource].volume + math.abs(amount)

    local txType = transactionData.type or 'unknown'
    if not TI.Statistics.by_type[txType] then
        TI.Statistics.by_type[txType] = { count = 0, volume = 0 }
    end
    TI.Statistics.by_type[txType].count = TI.Statistics.by_type[txType].count + 1
    TI.Statistics.by_type[txType].volume = TI.Statistics.by_type[txType].volume + math.abs(amount)

    -- Loga no banco de dados se configurado
    if TI.Config.log_all_transactions then
        local okDb, errDb = pcall(function()
            MySQL.Async.execute([[
            INSERT INTO space_economy_intercepted_transactions
            (timestamp, source, resource, event_name, amount, transaction_type, account, reason, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            os.time(),
            source,
            resource,
            eventName,
            amount,
            txType,
            transactionData.account or 'unknown',
            transactionData.reason or '',
            json.encode(transactionData)
        })
        end)
        if not okDb then
            print(('^1[TransactionInterceptor] Erro ao inserir transação interceptada: %s^7'):format(tostring(errDb)))
        end
    end

    -- Se o valor for alto, envia notificação para ServiceRegistry
    if math.abs(amount) >= TI.Config.alert_threshold then
        if SE.ServiceRegistry and SE.ServiceRegistry.LogTransaction then SE.ServiceRegistry.LogTransaction(
            source,
            amount,
            txType,
            transactionData.account or 'cash',
            transactionData.reason or eventName,
            { intercepted = true, event = eventName }
        ) end
    end
end

---Registra uma chamada de export
---@param invokingResource string
---@param targetResource string
---@param exportName string
---@param args table
function TI.LogExportCall(invokingResource, targetResource, exportName, args)
    -- Similar ao LogInterception, mas para exports
    if Config and Config.Debug then
        print(('^5[TransactionInterceptor] Export Call: %s -> %s:%s^7'):format(
            invokingResource,
            targetResource,
            exportName
        ))
    end
end

-- =====================================================
-- APLICAÇÃO AUTOMÁTICA DE IMPOSTOS
-- =====================================================

---Busca um imposto no catálogo pelo key
---@param key string
---@return table|nil tax
local function GetTaxFromCatalog(key)
    if not Config or not Config.TaxCatalog then return nil end

    for _, tax in ipairs(Config.TaxCatalog) do
        if tax.key == key then
            return tax
        end
    end

    return nil
end

---Aplica impostos a uma transação interceptada
---@param source number
---@param transactionData table
---@param service table
function TI.ApplyTaxesToTransaction(source, transactionData, service)
    -- Só aplica impostos em adições de dinheiro (ganhos)
    if transactionData.type ~= 'add' then
        return
    end

    local amount = transactionData.amount
    if not amount or amount <= 0 then
        return
    end

    -- Determina o tipo de imposto baseado no serviço
    local taxType = nil
    local taxRate = 0

    if service.type == SE.ServiceRegistry.ServiceTypes.LEGAL then
        taxType = 'ISS' -- Imposto sobre serviços
        local issTax = GetTaxFromCatalog('ISS')
        taxRate = issTax and (issTax.percent / 100) or 0.02 -- 2% padrão
    elseif service.type == SE.ServiceRegistry.ServiceTypes.ILLEGAL then
        taxType = 'ILLEGAL_TAX' -- Taxa sobre atividades ilegais
        taxRate = 0.05 -- 5% padrão
    elseif service.type == SE.ServiceRegistry.ServiceTypes.ORGANIZATIONS then
        taxType = 'ICMS' -- Imposto sobre mercadorias
        local icmsTax = GetTaxFromCatalog('ICMS')
        taxRate = icmsTax and (icmsTax.percent / 100) or 0.12 -- 12% padrão
    end

    if not taxType then
        return
    end

    local taxAmount = math.floor(amount * taxRate)

    if taxAmount > 0 then
        -- Cria uma dívida ou desconta direto
        local taxCollection = Config.TaxCollection or {}
        if taxCollection.CreateDebtInsteadOfDirectCharge then
            if SE.Debts and SE.Debts.Create then
                SE.Debts.Create(source, taxAmount, taxType, {
                    reason = 'Imposto sobre transação: ' .. (transactionData.reason or ''),
                    resource = service.resource,
                    auto_charged = true
                })
            end
        else
            -- Remove o imposto direto
            if SE.Integrations and SE.Integrations.RemoveMoney then
                SE.Integrations.RemoveMoney(source, taxAmount, 'bank', 'imposto_' .. taxType:lower())
            end

            -- Deposita no tesouro
            if SE.Treasury and SE.Treasury.Deposit then
                SE.Treasury.Deposit(taxAmount, 'imposto_' .. taxType:lower(), {
                    source = source,
                    service = service.name
                })
            end
        end

        print(('^3[TransactionInterceptor] Imposto aplicado: %s - $%s (%.1f%%)^7'):format(
            taxType,
            SE.Format.Money(taxAmount),
            taxRate * 100
        ))
    end
end

-- =====================================================
-- NOTIFICAÇÕES E ALERTAS
-- =====================================================

---Notifica admins sobre eventos importantes
---@param type string
---@param data table
function TI.NotifyAdmins(type, data)
    local players = GetPlayers()

    for _, playerId in ipairs(players) do
        local src = tonumber(playerId)
        if SE.Permissions.IsAdmin(src) then
            TriggerClientEvent('space_economy:client_notify', src, {
                type = 'transaction_interceptor',
                subtype = type,
                data = data
            }) end
        end
    end
end

-- =====================================================
-- COMANDOS DE ADMINISTRAÇÃO
-- =====================================================

---Comando para ver estatísticas de interceptação
RegisterCommand('se:intercept', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    local stats = TI.Statistics

    print('^2========================================^7')
    print('^2ESTATÍSTICAS DE INTERCEPTAÇÃO^7')
    print('^2========================================^7')
    print(('^3Total Interceptado: %d transações^7'):format(stats.total_intercepted))
    print(('^3Volume Total: $%s^7'):format(SE.Format.Money(stats.total_volume)))
    print(('^1Bloqueados: %d ($%s)^7'):format(stats.blocked_count, SE.Format.Money(stats.blocked_volume)))
    print('')
    print('^5Por Recurso:^7')

    for resource, data in pairs(stats.by_resource) do
        print(('  ^7%s: %d transações ($%s)'):format(
            resource,
            data.count,
            SE.Format.Money(data.volume)
        ))
    end

    print('')
    print('^5Por Tipo:^7')

    for txType, data in pairs(stats.by_type) do
        print(('  ^7%s: %d transações ($%s)'):format(
            txType,
            data.count,
            SE.Format.Money(data.volume)
        ))
    end
end, false)

---Comando para habilitar/desabilitar bloqueio
RegisterCommand('se:blockmode', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    TI.Config.block_unregistered = not TI.Config.block_unregistered

    local status = TI.Config.block_unregistered and '^2ATIVADO^7' or '^1DESATIVADO^7'
    print(('^3[TransactionInterceptor] Modo de bloqueio: %s^7'):format(status))
end, false)

-- =====================================================
-- MONITORAMENTO DE SQL DIRETO
-- =====================================================

-- Monitora queries SQL diretas que modificam dinheiro
-- ATENÇÃO: Isso é experimental e pode ter impacto na performance

TI.MonitoredTables = {
    'players',
    'character_accounts',
    'bank_accounts',
    'ps_banking_accounts'
}

---Monitora uma query SQL para detectar modificações de dinheiro
---@param query string
---@param params table
function TI.MonitorSQLQuery(query, params)
    local lowerQuery = query:lower()

    -- Detecta UPDATEs que modificam dinheiro
    if lowerQuery:match('update') and (lowerQuery:match('money') or lowerQuery:match('bank') or lowerQuery:match('cash')) then
        local resource = GetInvokingResource() or 'unknown'

        print(('^3[TransactionInterceptor] SQL Direto detectado de %s:^7'):format(resource))
        print(('  ^7Query: %s'):format(query))

        -- Registra no log
        local okDb, errDb = pcall(function()
            MySQL.Async.execute([[            INSERT INTO space_economy_sql_monitor
            (timestamp, resource, query_text, params)
            VALUES (?, ?, ?, ?)
        ]], {
                os.time(),
                resource,
                query,
                json.encode(params)
            })
        end)

        if not okDb then
            print(('^1[TransactionInterceptor] Erro no monitor SQL: %s^7'):format(tostring(errDb)))
        end

        -- Detecta como serviço não registrado se aplicável
        local service = (SE.ServiceRegistry and SE.ServiceRegistry.GetService) and SE.ServiceRegistry.GetService(resource) or nil
        if not service and resource ~= 'unknown' then
            if SE.ServiceRegistry and SE.ServiceRegistry.DetectUnregisteredService then
                SE.ServiceRegistry.DetectUnregisteredService(resource, {
                    timestamp = os.time(),
                    source = nil,
                    amount = 0,
                    type = 'sql_direct',
                    account = 'unknown',
                    reason = 'SQL direto: ' .. query
                })
            end
        end
    end
end

-- =====================================================
-- INICIALIZAÇÃO
-- =====================================================

function TI.Initialize()
    if TI.Initialized then
        return true
    end

    if not (SE.ServiceRegistry and SE.ServiceRegistry.IsReady and SE.ServiceRegistry.IsReady()) then
        return false
    end

    print('^2[TransactionInterceptor] Inicializando interceptador de transações...^7')

    -- Hook em frameworks
    TI.HookFrameworkFunctions()

    -- Registra interceptadores de eventos
    for _, eventName in ipairs(TI.MoneyEvents) do
        -- Tenta obter o handler original (não é possível no FiveM, então faremos diferente)
        -- Vamos adicionar nosso próprio handler que sempre executa
        AddEventHandler(eventName, function(...)
            local args = {...}
            TI.WrapMoneyEvent(eventName, nil)(table.unpack(args))
        end)
    end

    TI.Initialized = true

    print('^2[TransactionInterceptor] Sistema inicializado!^7')
    print(('^3[TransactionInterceptor] Modo de bloqueio: %s^7'):format(
        TI.Config.block_unregistered and '^2ATIVADO^7' or '^1DESATIVADO^7'
    ))

    return true
end

-- Exporta funções
function EnableBlocking(enable)
    TI.Config.block_unregistered = enable
end

function GetStatistics()
    return TI.Statistics
end

-- Inicializa
Citizen.CreateThread(function()
    local maxAttempts = 20
    local intervalMs = 2000
    print('^3[TransactionInterceptor] Aguardando ServiceRegistry para inicializar...^7')

    for _ = 1, maxAttempts do
        if TI.Initialize() then
            return
        end
        Wait(intervalMs)
    end

    print('^1[TransactionInterceptor] Inicialização adiada: ServiceRegistry não ficou pronto.^7')
end)

AddEventHandler('space_economy:serviceRegistryReady', function()
    if not TI.Initialized then
        TI.Initialize()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TI.Initialized = false
end)
