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
        local src = source
        local resource = GetInvokingResource() or 'unknown'

        -- Extrai informações da transação
        local transactionData = TI.ExtractTransactionData(eventName, args)

        -- Registra a interceptação
        TI.LogInterception(src, resource, eventName, transactionData)

        -- Verifica se o recurso está registrado
        local service = SE.ServiceRegistry.GetService(resource)

        if not service then
            -- Detecta serviço não registrado
            SE.ServiceRegistry.DetectUnregisteredService(resource, {
                timestamp = os.time(),
                source = src,
                amount = transactionData.amount or 0,
                type = transactionData.type or 'unknown',
                account = transactionData.account or 'unknown',
                reason = eventName
            })

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
function TI.ExtractTransactionData(eventName, args)
    local data = {
        amount = nil,
        type = nil,
        account = nil,
        reason = nil
    }

    -- Tenta diferentes formatos de argumentos
    if #args >= 1 then
        -- Formato 1: source, amount, account, reason (mais comum)
        if type(args[1]) == 'number' and #args >= 2 then
            data.amount = args[2]
            data.account = args[3] or 'cash'
            data.reason = args[4] or eventName
        -- Formato 2: amount, account, reason (source implícito)
        elseif type(args[1]) == 'number' then
            data.amount = args[1]
            data.account = args[2] or 'cash'
            data.reason = args[3] or eventName
        -- Formato 3: table com dados
        elseif type(args[1]) == 'table' then
            data.amount = args[1].amount or args[1].value or args[1].money
            data.account = args[1].account or args[1].type or 'cash'
            data.reason = args[1].reason or args[1].description or eventName
        end
    end

    -- Determina tipo (add/remove)
    if eventName:lower():match('add') or eventName:lower():match('deposit') then
        data.type = 'add'
    elseif eventName:lower():match('remove') or eventName:lower():match('withdraw') then
        data.type = 'remove'
    end

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
    __index = function(t, resource)
        -- Se é um recurso relacionado a banco/dinheiro
        if resource == 'qb-banking' or resource == 'ps-banking' or
           resource == 'esx_society' or resource:match('bank') then

            return setmetatable({}, {
                __index = function(t2, exportName)
                    local originalExportFunc = originalExport[resource][exportName]

                    -- Wrappa a função de export
                    return function(...)
                        local invokingResource = GetInvokingResource()

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
    local amount = transactionData.amount or 0

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
    end

    -- Se o valor for alto, envia notificação para ServiceRegistry
    if math.abs(amount) >= TI.Config.alert_threshold then
        SE.ServiceRegistry.LogTransaction(
            source,
            amount,
            txType,
            transactionData.account or 'cash',
            transactionData.reason or eventName,
            { intercepted = true, event = eventName }
        )
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
            })
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
        MySQL.Async.execute([[
            INSERT INTO space_economy_sql_monitor
            (timestamp, resource, query_text, params)
            VALUES (?, ?, ?, ?)
        ]], {
            os.time(),
            resource,
            query,
            json.encode(params)
        })

        -- Detecta como serviço não registrado se aplicável
        local service = SE.ServiceRegistry.GetService(resource)
        if not service and resource ~= 'unknown' then
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

-- =====================================================
-- INICIALIZAÇÃO
-- =====================================================

function TI.Initialize()
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

    print('^2[TransactionInterceptor] Sistema inicializado!^7')
    print(('^3[TransactionInterceptor] Modo de bloqueio: %s^7'):format(
        TI.Config.block_unregistered and '^2ATIVADO^7' or '^1DESATIVADO^7'
    ))
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
    Wait(5000) -- Aguarda outros sistemas
    TI.Initialize()
end)
