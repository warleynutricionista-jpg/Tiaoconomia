-- =====================================================
-- PAINEL DE MONITORAMENTO DE INTEGRAÇÕES
-- Interface para visualizar e gerenciar todas as integrações
-- =====================================================

local SE = exports['space_economy']:GetCoreObject()

SE.IntegrationMonitor = {}
local IM = SE.IntegrationMonitor

-- =====================================================
-- COMANDOS DE ADMINISTRAÇÃO
-- =====================================================

---Comando principal do painel de monitoramento
RegisterCommand('se:monitor', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    -- Coleta todos os dados
    local data = IM.CollectMonitoringData()

    -- Envia para o cliente para exibir no NUI
    TriggerClientEvent('space_economy:openMonitor', source, data)
end, false)

---Comando para ver visão geral
RegisterCommand('se:overview', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    local stats = SE.ServiceRegistry.GetStats()
    local pricing = SE.DynamicPricing.GenerateReport()
    local intercept = SE.TransactionInterceptor.Statistics

    print('^2╔════════════════════════════════════════════════════════╗^7')
    print('^2║     VISÃO GERAL DO SISTEMA ECONÔMICO INTEGRADO        ║^7')
    print('^2╚════════════════════════════════════════════════════════╝^7')
    print('')
    print('^5📊 SERVIÇOS REGISTRADOS^7')
    print(('   Total: ^2%d^7 serviços'):format(stats.total_registered))
    for type, count in pairs(stats.by_type) do
        print(('   - %s: ^3%d^7'):format(type, count))
    end
    print('')
    print('^1⚠️  SERVIÇOS NÃO REGISTRADOS^7')
    print(('   Total: ^1%d^7 detectados'):format(stats.unregistered_count))
    print('')
    print('^5💰 PREÇOS DINÂMICOS^7')
    print(('   Itens rastreados: ^3%d^7'):format(pricing.total_items))
    print(('   Multiplicador global: ^3%.2fx^7'):format(pricing.global_multiplier))
    print('')
    print('^5🔍 INTERCEPTADOR DE TRANSAÇÕES^7')
    print(('   Total interceptado: ^3%d^7 transações'):format(intercept.total_intercepted))
    print(('   Volume total: ^2$%s^7'):format(SE.Format.Money(intercept.total_volume)))
    if intercept.blocked_count > 0 then
        print(('   ^1Bloqueados: %d ($%s)^7'):format(intercept.blocked_count, SE.Format.Money(intercept.blocked_volume)))
    end
    print('')
end, false)

---Comando para forçar integração de um serviço
RegisterCommand('se:integrate', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    if #args < 1 then
        print('^1Uso: se:integrate <resource_name>^7')
        return
    end

    local resourceName = args[1]
    local unregistered = SE.ServiceRegistry.GetUnregisteredServices()

    if not unregistered[resourceName] then
        print(('^1Erro: Serviço "%s" não foi detectado como não registrado^7'):format(resourceName))
        return
    end

    -- Usa os dados detectados para criar registro
    local detection = unregistered[resourceName]

    SE.ServiceRegistry.RegisterService(resourceName, {
        type = detection.suggested_type,
        description = 'Integrado manualmente via comando',
        resource = resourceName,
        status = SE.ServiceRegistry.IntegrationStatus.FULLY_INTEGRATED,
        uses_economy_api = true,
        logs_transactions = true
    })

    -- Remove da lista de não registrados
    MySQL.Async.execute('DELETE FROM space_economy_unregistered_services WHERE resource_name = ?', {
        resourceName
    })

    unregistered[resourceName] = nil

    print(('^2✓ Serviço "%s" integrado com sucesso!^7'):format(resourceName))
end, false)

---Comando para ignorar um serviço não registrado
RegisterCommand('se:ignore', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    if #args < 1 then
        print('^1Uso: se:ignore <resource_name>^7')
        return
    end

    local resourceName = args[1]

    MySQL.Async.execute('UPDATE space_economy_unregistered_services SET status = ? WHERE resource_name = ?', {
        'ignored',
        resourceName
    })

    local unregistered = SE.ServiceRegistry.GetUnregisteredServices()
    if unregistered[resourceName] then
        unregistered[resourceName] = nil
    end

    print(('^3Serviço "%s" marcado como ignorado^7'):format(resourceName))
end, false)

---Comando para atualizar todos os preços manualmente
RegisterCommand('se:updateprices', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    print('^3Forçando atualização de todos os preços...^7')
    SE.DynamicPricing.UpdateAllPrices()
end, false)

---Comando para ativar/desativar modo de bloqueio
RegisterCommand('se:toggleblock', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    local currentState = SE.TransactionInterceptor.Config.block_unregistered
    SE.TransactionInterceptor.Config.block_unregistered = not currentState

    local newState = SE.TransactionInterceptor.Config.block_unregistered and '^2ATIVADO^7' or '^1DESATIVADO^7'
    print(('^3Modo de bloqueio: %s^7'):format(newState))

    -- Salva configuração
    MySQL.Async.execute([[
        UPDATE space_economy_balance_config
        SET config_value = ?
        WHERE config_key = 'enforce_integration'
    ]], {
        SE.TransactionInterceptor.Config.block_unregistered and 'true' or 'false'
    })
end, false)

-- =====================================================
-- COLETA DE DADOS PARA O PAINEL
-- =====================================================

---Coleta todos os dados necessários para o painel de monitoramento
---@return table data
function IM.CollectMonitoringData()
    local data = {
        timestamp = os.time(),

        -- Serviços registrados
        registered_services = {},
        unregistered_services = {},

        -- Estatísticas gerais
        stats = {},

        -- Preços dinâmicos
        pricing = {},

        -- Interceptador
        interceptor = {},

        -- Configurações
        config = {}
    }

    -- Serviços registrados
    local services = SE.ServiceRegistry.GetAllServices()
    for name, service in pairs(services) do
        table.insert(data.registered_services, {
            name = name,
            type = service.type,
            description = service.description,
            resource = service.resource,
            status = service.status,
            total_transactions = service.stats.total_transactions,
            total_volume = service.stats.total_volume,
            last_transaction = service.stats.last_transaction,
            supports_dynamic_pricing = service.pricing.can_be_balanced
        })
    end

    -- Serviços não registrados
    local unregistered = SE.ServiceRegistry.GetUnregisteredServices()
    for resource, detection in pairs(unregistered) do
        table.insert(data.unregistered_services, {
            resource = resource,
            suggested_type = detection.suggested_type,
            first_detected = detection.first_detected,
            last_seen = detection.last_seen,
            transaction_count = detection.transaction_count,
            total_volume = detection.total_volume
        })
    end

    -- Estatísticas
    data.stats = SE.ServiceRegistry.GetStats()

    -- Preços
    data.pricing = SE.DynamicPricing.GenerateReport()

    -- Interceptador
    data.interceptor = SE.TransactionInterceptor.Statistics

    -- Configurações
    data.config = {
        enforce_integration = SE.TransactionInterceptor.Config.block_unregistered,
        auto_apply_taxes = SE.TransactionInterceptor.Config.auto_apply_taxes,
        alert_threshold = SE.TransactionInterceptor.Config.alert_threshold,
        price_update_interval = SE.DynamicPricing.UpdateInterval
    }

    return data
end

-- =====================================================
-- EVENTOS DO CLIENTE
-- =====================================================

---Cliente solicita dados do monitor
RegisterNetEvent('space_economy:server_requestMonitorData', function()
    local src = source

    if not SE.Permissions.IsAdmin(src) then
        return
    end

    local data = IM.CollectMonitoringData()
    TriggerClientEvent('space_economy:client_monitorData', src, data)
end)

---Cliente atualiza configuração
RegisterNetEvent('space_economy:server_updateConfig', function(configKey, configValue)
    local src = source

    if not SE.Permissions.IsAdmin(src) then
        return
    end

    -- Aplica configuração
    if configKey == 'enforce_integration' then
        SE.TransactionInterceptor.Config.block_unregistered = configValue
    elseif configKey == 'auto_apply_taxes' then
        SE.TransactionInterceptor.Config.auto_apply_taxes = configValue
    elseif configKey == 'alert_threshold' then
        SE.TransactionInterceptor.Config.alert_threshold = configValue
    elseif configKey == 'price_update_interval' then
        SE.DynamicPricing.UpdateInterval = configValue
    end

    -- Salva no banco
    MySQL.Async.execute([[
        UPDATE space_economy_balance_config
        SET config_value = ?, modified_by = ?, modified_at = ?
        WHERE config_key = ?
    ]], {
        tostring(configValue),
        GetPlayerIdentifiers(src)[1],
        os.time(),
        configKey
    })

    print(('^2[Monitor] Configuração atualizada: %s = %s^7'):format(configKey, tostring(configValue)))
end)

---Cliente solicita integração de um serviço
RegisterNetEvent('space_economy:server_integrateService', function(resourceName)
    local src = source

    if not SE.Permissions.IsAdmin(src) then
        return
    end

    local unregistered = SE.ServiceRegistry.GetUnregisteredServices()

    if not unregistered[resourceName] then
        TriggerClientEvent('space_economy:client_notify', src, {
            type = 'error',
            message = 'Serviço não encontrado'
        })
        return
    end

    local detection = unregistered[resourceName]

    SE.ServiceRegistry.RegisterService(resourceName, {
        type = detection.suggested_type,
        description = 'Integrado via painel de monitoramento',
        resource = resourceName,
        status = SE.ServiceRegistry.IntegrationStatus.FULLY_INTEGRATED,
        uses_economy_api = true,
        logs_transactions = true
    })

    MySQL.Async.execute('DELETE FROM space_economy_unregistered_services WHERE resource_name = ?', {
        resourceName
    })

    unregistered[resourceName] = nil

    TriggerClientEvent('space_economy:client_notify', src, {
        type = 'success',
        message = 'Serviço integrado com sucesso'
    })

    -- Atualiza dados do monitor
    local data = IM.CollectMonitoringData()
    TriggerClientEvent('space_economy:client_monitorData', src, data)
end)

-- =====================================================
-- RELATÓRIOS AUTOMATIZADOS
-- =====================================================

---Gera relatório diário de integração
function IM.GenerateDailyReport()
    local report = {
        date = os.date('%Y-%m-%d'),
        services = SE.ServiceRegistry.GetStats(),
        pricing = SE.DynamicPricing.GenerateReport(),
        interceptor = SE.TransactionInterceptor.Statistics,
        unregistered = {}
    }

    -- Top 10 serviços não registrados
    local unregistered = SE.ServiceRegistry.GetUnregisteredServices()
    local sorted = {}

    for resource, detection in pairs(unregistered) do
        table.insert(sorted, {
            resource = resource,
            volume = detection.total_volume,
            count = detection.transaction_count
        })
    end

    table.sort(sorted, function(a, b)
        return a.volume > b.volume
    end)

    for i = 1, math.min(10, #sorted) do
        table.insert(report.unregistered, sorted[i])
    end

    -- Salva no banco
    MySQL.Async.execute([[
        INSERT INTO space_economy_integration_reports
        (report_date, total_registered_services, total_unregistered_services,
         total_transactions, total_volume, blocked_transactions, blocked_volume, full_report)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        report.date,
        report.services.total_registered,
        report.services.unregistered_count,
        report.interceptor.total_intercepted,
        report.interceptor.total_volume,
        report.interceptor.blocked_count,
        report.interceptor.blocked_volume,
        json.encode(report)
    })

    print(('^2[Monitor] Relatório diário gerado: %s^7'):format(report.date))

    return report
end

-- Thread para gerar relatório diário
Citizen.CreateThread(function()
    while true do
        -- Aguarda até meia-noite
        local now = os.time()
        local tomorrow = os.time({
            year = os.date('%Y', now),
            month = os.date('%m', now),
            day = os.date('%d', now) + 1,
            hour = 0,
            min = 0,
            sec = 0
        })
        local waitTime = (tomorrow - now) * 1000

        Wait(waitTime)

        -- Gera relatório
        IM.GenerateDailyReport()
    end
end)

-- =====================================================
-- ALERTAS AUTOMÁTICOS
-- =====================================================

---Verifica condições de alerta
function IM.CheckAlerts()
    local alerts = {}

    -- Verifica serviços não registrados com alto volume
    local unregistered = SE.ServiceRegistry.GetUnregisteredServices()
    for resource, detection in pairs(unregistered) do
        if detection.total_volume > 100000 then -- Mais de 100k
            table.insert(alerts, {
                type = 'high_volume_unregistered',
                severity = 'high',
                resource = resource,
                volume = detection.total_volume,
                message = string.format(
                    'Serviço não registrado "%s" movimentou $%s',
                    resource,
                    SE.Format.Money(detection.total_volume)
                )
            })
        end
    end

    -- Verifica multiplicador de preços extremo
    local multiplier = SE.DynamicPricing.GetGlobalPriceMultiplier()
    if multiplier > 2.0 or multiplier < 0.7 then
        table.insert(alerts, {
            type = 'extreme_price_multiplier',
            severity = 'medium',
            multiplier = multiplier,
            message = string.format(
                'Multiplicador de preços extremo: %.2fx',
                multiplier
            )
        })
    end

    -- Verifica taxa de bloqueio alta
    local stats = SE.TransactionInterceptor.Statistics
    if stats.total_intercepted > 0 then
        local blockRate = stats.blocked_count / stats.total_intercepted
        if blockRate > 0.1 then -- Mais de 10% bloqueado
            table.insert(alerts, {
                type = 'high_block_rate',
                severity = 'high',
                rate = blockRate * 100,
                message = string.format(
                    'Taxa de bloqueio alta: %.1f%% (%d/%d)',
                    blockRate * 100,
                    stats.blocked_count,
                    stats.total_intercepted
                )
            })
        end
    end

    -- Envia alertas para admins
    if #alerts > 0 then
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            local src = tonumber(playerId)
            if SE.Permissions.IsAdmin(src) then
                TriggerClientEvent('space_economy:client_alerts', src, alerts)
            end
        end
    end

    return alerts
end

-- Thread para verificar alertas a cada 5 minutos
Citizen.CreateThread(function()
    while true do
        Wait(300000) -- 5 minutos
        IM.CheckAlerts()
    end
end)

-- =====================================================
-- INICIALIZAÇÃO
-- =====================================================

function IM.Initialize()
    print('^2[IntegrationMonitor] Inicializando painel de monitoramento...^7')

    -- Carrega configurações salvas do banco
    MySQL.Async.fetchAll('SELECT * FROM space_economy_balance_config', {}, function(results)
        if not results then return end

        for _, row in ipairs(results) do
            local key = row.config_key
            local value = row.config_value

            if key == 'enforce_integration' then
                SE.TransactionInterceptor.Config.block_unregistered = (value == 'true')
            elseif key == 'auto_apply_taxes' then
                SE.TransactionInterceptor.Config.auto_apply_taxes = (value == 'true')
            elseif key == 'alert_threshold' then
                SE.TransactionInterceptor.Config.alert_threshold = tonumber(value)
            elseif key == 'price_update_interval' then
                SE.DynamicPricing.UpdateInterval = tonumber(value)
            end
        end

        print('^2[IntegrationMonitor] Configurações carregadas do banco de dados^7')
    end)

    print('^2[IntegrationMonitor] Sistema inicializado!^7')
end

-- Inicializa
Citizen.CreateThread(function()
    Wait(6000) -- Aguarda outros sistemas
    IM.Initialize()
end)

-- Exporta
function GetMonitoringData()
    return IM.CollectMonitoringData()
end

function GenerateDailyReport()
    return IM.GenerateDailyReport()
end
