-- =====================================================
-- REGISTRO CENTRAL DE SERVIÇOS ECONÔMICOS
-- Sistema de gerenciamento centralizado de todos os serviços
-- que realizam transações financeiras no servidor
-- =====================================================

local SE = exports['space_economy']:GetCoreObject()

SE.ServiceRegistry = {}
local SR = SE.ServiceRegistry

-- Registro de todos os serviços conhecidos
SR.RegisteredServices = {}
SR.TransactionLog = {}
SR.UnregisteredDetections = {}

-- Tipos de serviços
SR.ServiceTypes = {
    LEGAL = 'legal',           -- Lojas legais, empregos oficiais
    ILLEGAL = 'illegal',        -- Drogas, armas, lavagem
    BANKING = 'banking',        -- Sistema bancário
    HOUSING = 'housing',        -- Propriedades e imóveis
    VEHICLES = 'vehicles',      -- Concessionárias e veículos
    JOBS = 'jobs',             -- Empregos/salários
    ORGANIZATIONS = 'organizations', -- Empresas de players
    GOVERNMENT = 'government',  -- Serviços governamentais
    OTHER = 'other'            -- Outros serviços
}

-- Status de integração
SR.IntegrationStatus = {
    FULLY_INTEGRATED = 'fully_integrated',     -- Totalmente integrado
    PARTIALLY_INTEGRATED = 'partially_integrated', -- Parcialmente integrado
    NOT_INTEGRATED = 'not_integrated',         -- Não integrado
    PENDING = 'pending',                       -- Pendente de integração
    DISABLED = 'disabled'                      -- Desabilitado
}

-- =====================================================
-- FUNÇÕES DE REGISTRO
-- =====================================================

---Registra um novo serviço no sistema econômico
---@param serviceName string Nome único do serviço
---@param serviceData table Dados do serviço
---@return boolean success
function SR.RegisterService(serviceName, serviceData)
    if not serviceName or serviceName == '' then
        print('^1[ServiceRegistry] Nome do serviço inválido^7')
        return false
    end

    local resourceName = serviceData.resource or GetInvokingResource() or SE.Resource or GetCurrentResourceName() or 'unknown'
    local service = {
        name = serviceName,
        type = serviceData.type or SR.ServiceTypes.OTHER,
        description = serviceData.description or '',
        resource = resourceName,
        status = serviceData.status or SR.IntegrationStatus.FULLY_INTEGRATED,

        -- Configurações de integração
        integration = {
            uses_economy_api = serviceData.uses_economy_api or false,
            bypasses_economy = serviceData.bypasses_economy or false,
            has_own_prices = serviceData.has_own_prices or false,
            supports_dynamic_pricing = serviceData.supports_dynamic_pricing or false,
            applies_taxes = serviceData.applies_taxes or false,
            logs_transactions = serviceData.logs_transactions or false
        },

        -- Preços e configurações econômicas
        pricing = {
            items = serviceData.items or {},
            services = serviceData.services or {},
            base_multiplier = serviceData.base_multiplier or 1.0,
            can_be_balanced = serviceData.can_be_balanced or true
        },

        -- Estatísticas
        stats = {
            total_transactions = 0,
            total_volume = 0,
            last_transaction = nil,
            registered_at = os.time()
        },

        -- Callbacks para integração
        callbacks = {
            get_prices = serviceData.get_prices_callback,
            set_prices = serviceData.set_prices_callback,
            on_transaction = serviceData.on_transaction_callback,
            on_balance_update = serviceData.on_balance_update_callback
        },

        -- Metadados adicionais
        metadata = serviceData.metadata or {}
    }

    SR.RegisteredServices[serviceName] = service

    -- Salva no banco de dados
    SR.SaveServiceToDB(serviceName, service)

    print(('^2[ServiceRegistry] Serviço registrado: %s [%s] - Status: %s^7'):format(
        serviceName, service.type, service.status
    ))

    -- Dispara evento para outros sistemas
    TriggerEvent('space_economy:serviceRegistered', serviceName, service)

    return true
end

---Remove o registro de um serviço
---@param serviceName string
---@return boolean
function SR.UnregisterService(serviceName)
    if not SR.RegisteredServices[serviceName] then
        return false
    end

    SR.RegisteredServices[serviceName] = nil

    -- Remove do BD
    MySQL.Async.execute('DELETE FROM space_economy_services WHERE service_name = ?', {
        serviceName
    })

    print(('^3[ServiceRegistry] Serviço removido: %s^7'):format(serviceName))
    TriggerEvent('space_economy:serviceUnregistered', serviceName)

    return true
end

---Atualiza o status de integração de um serviço
---@param serviceName string
---@param status string
function SR.UpdateServiceStatus(serviceName, status)
    if not SR.RegisteredServices[serviceName] then
        return false
    end

    SR.RegisteredServices[serviceName].status = status
    SR.SaveServiceToDB(serviceName, SR.RegisteredServices[serviceName])

    TriggerEvent('space_economy:serviceStatusUpdated', serviceName, status)
end

-- =====================================================
-- DETECÇÃO AUTOMÁTICA DE SERVIÇOS NÃO REGISTRADOS
-- =====================================================

---Registra uma transação e verifica se o serviço está registrado
---@param source number Player source
---@param amount number Valor da transação
---@param type string Tipo (add/remove)
---@param account string Conta (bank/cash)
---@param reason string Motivo da transação
---@param metadata table Metadados adicionais
function SR.LogTransaction(source, amount, type, account, reason, metadata)
    local invokingResource = GetInvokingResource() or 'unknown'

    -- Registra a transação
    local transaction = {
        timestamp = os.time(),
        source = source,
        amount = amount,
        type = type,
        account = account,
        reason = reason,
        resource = invokingResource,
        metadata = metadata or {}
    }

    table.insert(SR.TransactionLog, transaction)

    -- Verifica se o recurso está registrado
    local isRegistered = false
    for serviceName, service in pairs(SR.RegisteredServices) do
        if service.resource == invokingResource then
            isRegistered = true

            -- Atualiza estatísticas
            service.stats.total_transactions = service.stats.total_transactions + 1
            service.stats.total_volume = service.stats.total_volume + math.abs(amount)
            service.stats.last_transaction = os.time()

            -- Callback de transação
            if service.callbacks.on_transaction then
                service.callbacks.on_transaction(transaction)
            end

            break
        end
    end

    -- Se não está registrado, marca como não registrado
    if not isRegistered and invokingResource ~= 'unknown' and invokingResource ~= 'space_economy' then
        SR.DetectUnregisteredService(invokingResource, transaction)
    end

    -- Limita o log a 10000 transações para não ocupar muita memória
    if #SR.TransactionLog > 10000 then
        table.remove(SR.TransactionLog, 1)
    end
end

---Detecta e registra um serviço não integrado
---@param resourceName string
---@param transaction table
function SR.DetectUnregisteredService(resourceName, transaction)
    -- Se já foi detectado recentemente, apenas atualiza
    if SR.UnregisteredDetections[resourceName] then
        local detection = SR.UnregisteredDetections[resourceName]
        detection.transaction_count = detection.transaction_count + 1
        detection.total_volume = detection.total_volume + math.abs(transaction.amount)
        detection.last_seen = os.time()

        -- Adiciona exemplo de transação se não tiver muitos
        if #detection.sample_transactions < 10 then
            table.insert(detection.sample_transactions, transaction)
        end
    else
        -- Primeira detecção
        SR.UnregisteredDetections[resourceName] = {
            resource_name = resourceName,
            first_detected = os.time(),
            last_seen = os.time(),
            transaction_count = 1,
            total_volume = math.abs(transaction.amount),
            sample_transactions = { transaction },
            suggested_type = SR.GuessServiceType(resourceName, transaction)
        }

        -- Alerta no console
        print(('^3[ServiceRegistry] ⚠️  SERVIÇO NÃO REGISTRADO DETECTADO: %s^7'):format(resourceName))
        print(('^3[ServiceRegistry] Tipo sugerido: %s | Valor: $%s^7'):format(
            SR.UnregisteredDetections[resourceName].suggested_type,
            SE.Format.Money(transaction.amount)
        ))

        -- Salva no banco de dados
        MySQL.Async.execute([[
            INSERT INTO space_economy_unregistered_services
            (resource_name, first_detected, last_seen, transaction_count, total_volume, suggested_type, sample_data)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                last_seen = VALUES(last_seen),
                transaction_count = transaction_count + 1,
                total_volume = total_volume + VALUES(total_volume),
                sample_data = VALUES(sample_data)
        ]], {
            resourceName,
            os.time(),
            os.time(),
            1,
            math.abs(transaction.amount),
            SR.UnregisteredDetections[resourceName].suggested_type,
            json.encode({ transaction })
        })

        -- Envia notificação para admins online
        SR.NotifyAdmins('unregistered_service', {
            resource = resourceName,
            type = SR.UnregisteredDetections[resourceName].suggested_type,
            amount = transaction.amount
        })
    end
end

---Tenta adivinhar o tipo de serviço baseado no nome e transação
---@param resourceName string
---@param transaction table
---@return string type
function SR.GuessServiceType(resourceName, transaction)
    local name = resourceName:lower()
    local reason = (transaction.reason or ''):lower()

    -- Legal
    if name:match('shop') or name:match('store') or name:match('loja') or name:match('24') then
        return SR.ServiceTypes.LEGAL
    end

    -- Ilegal
    if name:match('drug') or name:match('weed') or name:match('droga') or name:match('meth') or
       name:match('weapon') or name:match('illegal') or reason:match('laund') or reason:match('lava') then
        return SR.ServiceTypes.ILLEGAL
    end

    -- Banking
    if name:match('bank') or name:match('atm') or name:match('banco') then
        return SR.ServiceTypes.BANKING
    end

    -- Housing
    if name:match('house') or name:match('housing') or name:match('property') or
       name:match('casa') or name:match('apto') or name:match('apartment') then
        return SR.ServiceTypes.HOUSING
    end

    -- Vehicles
    if name:match('vehicle') or name:match('car') or name:match('dealership') or
       name:match('garage') or name:match('veiculo') or name:match('carro') then
        return SR.ServiceTypes.VEHICLES
    end

    -- Jobs
    if name:match('job') or name:match('emprego') or name:match('salary') or name:match('salario') then
        return SR.ServiceTypes.JOBS
    end

    return SR.ServiceTypes.OTHER
end

-- =====================================================
-- FUNÇÕES DE CONSULTA
-- =====================================================

---Retorna todos os serviços registrados
---@return table services
function SR.GetAllServices()
    return SR.RegisteredServices
end

---Retorna um serviço específico
---@param serviceName string
---@return table|nil service
function SR.GetService(serviceName)
    return SR.RegisteredServices[serviceName]
end

---Retorna serviços por tipo
---@param serviceType string
---@return table services
function SR.GetServicesByType(serviceType)
    local services = {}
    for name, service in pairs(SR.RegisteredServices) do
        if service.type == serviceType then
            services[name] = service
        end
    end
    return services
end

---Retorna serviços por status de integração
---@param status string
---@return table services
function SR.GetServicesByStatus(status)
    local services = {}
    for name, service in pairs(SR.RegisteredServices) do
        if service.status == status then
            services[name] = service
        end
    end
    return services
end

---Retorna todos os serviços não registrados detectados
---@return table unregistered
function SR.GetUnregisteredServices()
    return SR.UnregisteredDetections
end

---Retorna estatísticas gerais do registro
---@return table stats
function SR.GetStats()
    local stats = {
        total_registered = 0,
        by_type = {},
        by_status = {},
        total_transactions = 0,
        total_volume = 0,
        unregistered_count = 0
    }

    for _, service in pairs(SR.RegisteredServices) do
        stats.total_registered = stats.total_registered + 1
        stats.by_type[service.type] = (stats.by_type[service.type] or 0) + 1
        stats.by_status[service.status] = (stats.by_status[service.status] or 0) + 1
        stats.total_transactions = stats.total_transactions + service.stats.total_transactions
        stats.total_volume = stats.total_volume + service.stats.total_volume
    end

    for _ in pairs(SR.UnregisteredDetections) do
        stats.unregistered_count = stats.unregistered_count + 1
    end

    return stats
end

-- =====================================================
-- PERSISTÊNCIA NO BANCO DE DADOS
-- =====================================================

---Salva um serviço no banco de dados
---@param serviceName string
---@param service table
function SR.SaveServiceToDB(serviceName, service)
    MySQL.Async.execute([[
        INSERT INTO space_economy_services
        (service_name, service_type, description, resource, status, integration_config, pricing_config, stats, callbacks, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            service_type = VALUES(service_type),
            description = VALUES(description),
            resource = VALUES(resource),
            status = VALUES(status),
            integration_config = VALUES(integration_config),
            pricing_config = VALUES(pricing_config),
            stats = VALUES(stats),
            callbacks = VALUES(callbacks),
            metadata = VALUES(metadata)
    ]], {
        serviceName,
        service.type,
        service.description,
        service.resource,
        service.status,
        json.encode(service.integration),
        json.encode(service.pricing),
        json.encode(service.stats),
        json.encode({
            has_get_prices = service.callbacks.get_prices ~= nil,
            has_set_prices = service.callbacks.set_prices ~= nil,
            has_on_transaction = service.callbacks.on_transaction ~= nil,
            has_on_balance = service.callbacks.on_balance_update ~= nil
        }),
        json.encode(service.metadata)
    })
end

---Carrega todos os serviços do banco de dados
function SR.LoadServicesFromDB()
    MySQL.Async.fetchAll('SELECT * FROM space_economy_services', {}, function(results)
        if not results then return end

        for _, row in ipairs(results) do
            local service = {
                name = row.service_name,
                type = row.service_type,
                description = row.description,
                resource = row.resource,
                status = row.status,
                integration = json.decode(row.integration_config or '{}'),
                pricing = json.decode(row.pricing_config or '{}'),
                stats = json.decode(row.stats or '{}'),
                callbacks = {},
                metadata = json.decode(row.metadata or '{}')
            }

            SR.RegisteredServices[row.service_name] = service
        end

        print(('^2[ServiceRegistry] Carregados %d serviços do banco de dados^7'):format(#results))
    end)
end

-- =====================================================
-- NOTIFICAÇÕES E ALERTAS
-- =====================================================

---Envia notificação para administradores online
---@param type string Tipo de notificação
---@param data table Dados da notificação
function SR.NotifyAdmins(type, data)
    local players = GetPlayers()

    for _, playerId in ipairs(players) do
        local src = tonumber(playerId)
        if SE.Permissions.IsAdmin(src) then
            TriggerClientEvent('space_economy:client_notify', src, {
                type = 'service_registry',
                subtype = type,
                data = data
            })
        end
    end
end

-- =====================================================
-- COMANDOS DE ADMINISTRAÇÃO
-- =====================================================

---Comando para listar todos os serviços registrados
RegisterCommand('se:services', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    local services = SR.GetAllServices()
    local stats = SR.GetStats()

    print('^2========================================^7')
    print('^2SERVIÇOS REGISTRADOS NO SISTEMA ECONÔMICO^7')
    print('^2========================================^7')
    print(('^3Total: %d serviços^7'):format(stats.total_registered))
    print('')

    for name, service in pairs(services) do
        print(('^5%s^7 [%s]'):format(name, service.type))
        print(('^7  Status: %s | Transações: %d | Volume: $%s'):format(
            service.status,
            service.stats.total_transactions,
            SE.Format.Money(service.stats.total_volume)
        ))
    end

    print('')
    print(('^1⚠️  Serviços não registrados: %d^7'):format(stats.unregistered_count))
end, false)

---Comando para listar serviços não registrados
RegisterCommand('se:unregistered', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    local unregistered = SR.GetUnregisteredServices()

    print('^3========================================^7')
    print('^3SERVIÇOS NÃO REGISTRADOS DETECTADOS^7')
    print('^3========================================^7')

    for resourceName, detection in pairs(unregistered) do
        print(('^1%s^7 [%s]'):format(resourceName, detection.suggested_type))
        print(('^7  Primeira detecção: %s'):format(os.date('%d/%m/%Y %H:%M', detection.first_detected)))
        print(('^7  Transações: %d | Volume: $%s'):format(
            detection.transaction_count,
            SE.Format.Money(detection.total_volume)
        ))
        print('')
    end
end, false)

-- =====================================================
-- INICIALIZAÇÃO
-- =====================================================

-- Cria tabelas necessárias se não existirem
local function EnsureTables()
    -- Tabela de serviços registrados
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `space_economy_services` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `service_name` VARCHAR(100) NOT NULL UNIQUE,
            `service_type` VARCHAR(50) NOT NULL,
            `description` TEXT,
            `resource` VARCHAR(100) NOT NULL,
            `status` VARCHAR(50) NOT NULL DEFAULT 'pending',
            `integration_config` TEXT,
            `pricing_config` TEXT,
            `stats` TEXT,
            `callbacks` TEXT,
            `metadata` TEXT,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_service_name` (`service_name`),
            INDEX `idx_service_type` (`service_type`),
            INDEX `idx_status` (`status`),
            INDEX `idx_resource` (`resource`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Tabela de preços dinâmicos
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `space_economy_prices` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `item_id` VARCHAR(200) NOT NULL UNIQUE,
            `base_price` DECIMAL(20, 2) NOT NULL,
            `current_price` DECIMAL(20, 2) NOT NULL,
            `category` VARCHAR(50) DEFAULT 'GENERAL',
            `multiplier` DECIMAL(10, 4) DEFAULT 1.0000,
            `last_update` INT NOT NULL,
            `price_history` LONGTEXT,
            `metadata` TEXT,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_item_id` (`item_id`),
            INDEX `idx_category` (`category`),
            INDEX `idx_last_update` (`last_update`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Tabela de configurações de balanceamento
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `space_economy_balance_config` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `config_key` VARCHAR(100) NOT NULL UNIQUE,
            `config_value` TEXT NOT NULL,
            `config_type` VARCHAR(50) DEFAULT 'json',
            `description` TEXT,
            `modified_by` VARCHAR(50),
            `modified_at` INT,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_config_key` (`config_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Insere configurações padrão se não existirem
    MySQL.Sync.execute([[
        INSERT IGNORE INTO `space_economy_balance_config` (`config_key`, `config_value`, `config_type`, `description`) VALUES
        ('global_price_multiplier', '1.0', 'number', 'Multiplicador global manual de preços'),
        ('auto_balance_enabled', 'true', 'boolean', 'Habilita balanceamento automático de preços'),
        ('enforce_integration', 'false', 'boolean', 'Força integração bloqueando serviços não registrados'),
        ('auto_apply_taxes', 'true', 'boolean', 'Aplica impostos automaticamente em transações interceptadas'),
        ('alert_threshold', '10000', 'number', 'Valor mínimo para alertar admins sobre transações'),
        ('price_update_interval', '300000', 'number', 'Intervalo de atualização de preços em ms (5 minutos padrão)')
    ]])

    print('^2[ServiceRegistry] Tabelas criadas/verificadas com sucesso!^7')
end

function SR.Initialize()
    print('^2[ServiceRegistry] Inicializando sistema de registro de serviços...^7')

    -- Garante que as tabelas existam
    EnsureTables()

    -- Carrega serviços do banco de dados
    SR.LoadServicesFromDB()

    -- Registra serviços internos do space_economy
    Citizen.CreateThread(function()
        Wait(2000) -- Aguarda outros sistemas carregarem

        SR.RegisterService('space_economy:treasury', {
            type = SR.ServiceTypes.GOVERNMENT,
            description = 'Sistema de tesouro público',
            uses_economy_api = true,
            applies_taxes = true,
            logs_transactions = true
        })

        SR.RegisterService('space_economy:debts', {
            type = SR.ServiceTypes.GOVERNMENT,
            description = 'Sistema de dívidas e cobrança',
            uses_economy_api = true,
            applies_taxes = false,
            logs_transactions = true
        })

        SR.RegisterService('space_economy:organizations', {
            type = SR.ServiceTypes.ORGANIZATIONS,
            description = 'Sistema de empresas de players',
            uses_economy_api = true,
            applies_taxes = true,
            logs_transactions = true,
            supports_dynamic_pricing = true
        })

        SR.RegisterService('space_economy:money_laundering', {
            type = SR.ServiceTypes.ILLEGAL,
            description = 'Sistema oficial de lavagem de dinheiro',
            uses_economy_api = true,
            applies_taxes = true,
            logs_transactions = true
        })

        SR.RegisterService('space_economy:banking_system', {
            type = SR.ServiceTypes.BANKING,
            description = 'Sistema de produtos bancários (CDB, Poupança)',
            uses_economy_api = true,
            applies_taxes = false,
            logs_transactions = true
        })

        print('^2[ServiceRegistry] Serviços internos registrados^7')
    end)

    print('^2[ServiceRegistry] Sistema inicializado com sucesso!^7')
end

-- Exporta para outros recursos
exports('RegisterService', function(serviceName, serviceData)
    return SR.RegisterService(serviceName, serviceData)
end)

exports('GetService', function(serviceName)
    return SR.GetService(serviceName)
end)

exports('GetAllServices', function()
    return SR.GetAllServices()
end)

exports('GetUnregisteredServices', function()
    return SR.GetUnregisteredServices()
end)

-- Inicializa quando o resource começar
Citizen.CreateThread(function()
    SR.Initialize()
end)
