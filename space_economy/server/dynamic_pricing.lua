-- =====================================================
-- SISTEMA DE BALANCEAMENTO DINÂMICO DE PREÇOS
-- Controla todos os preços do servidor baseado em fatores econômicos
-- =====================================================

local SE = exports['space_economy']:GetCoreObject()

SE.DynamicPricing = {}
local DP = SE.DynamicPricing

-- Cache de preços
DP.PriceCache = {}
DP.LastUpdate = 0
DP.UpdateInterval = 300000 -- 5 minutos
DP.Running = false
DP.Ready = false
DP.Boot = { waitingLogged = false, failedLogged = false }

-- =====================================================
-- FATORES QUE AFETAM PREÇOS
-- =====================================================

DP.PriceFactors = {
    -- Fator de inflação (baseado no sistema monetário)
    inflation = {
        weight = 0.30,  -- 30% de peso
        getValue = function()
            if not SE.State or not SE.State.Get then return 0.02 end

            local state = SE.State.Get('economy')
            if not state then return 0.02 end

            return state.inflation or 0.02
        end
    },

    -- Fator de PIB (demanda geral)
    gdp = {
        weight = 0.25,  -- 25% de peso
        getValue = function()
            if not SE.EconomyMonitor or not SE.EconomyMonitor.GetReport then
                return 1.0
            end

            local report = SE.EconomyMonitor.GetReport()
            if not report or not report.pib then return 1.0 end

            -- PIB alto = preços altos (demanda)
            -- Usa variação percentual do PIB total
            local gdpGrowth = report.pib.growth or 0
            return 1.0 + (gdpGrowth / 100)
        end
    },

    -- Fator de circulação monetária
    money_circulation = {
        weight = 0.20,  -- 20% de peso
        getValue = function()
            if not SE.State or not SE.State.Get then return 1.0 end

            local state = SE.State.Get('economy')
            if not state then return 1.0 end

            local circulation = state.total_circulation or 1000000
            local target = (Config.Economy and Config.Economy.TargetCirculation) or 10000000

            -- Quanto mais dinheiro circulando, mais inflação
            local ratio = circulation / target
            return math.max(0.5, math.min(2.0, ratio))
        end
    },

    -- Fator de SELIC (custo de capital)
    selic = {
        weight = 0.15,  -- 15% de peso
        getValue = function()
            if not SE.State or not SE.State.Get then return 1.0 + (0.05 * 0.5) end

            local state = SE.State.Get('economy')
            local selic = (state and state.selic) or 0.05

            -- SELIC alta = preços altos (custo de produção)
            return 1.0 + (selic * 0.5)
        end
    },

    -- Fator de eventos econômicos
    economic_events = {
        weight = 0.10,  -- 10% de peso
        getValue = function()
            if not SE.EconomicEvents or not SE.EconomicEvents.GetCurrentEvent then
                return 1.0
            end

            local currentEvent = SE.EconomicEvents.GetCurrentEvent()
            if not currentEvent then return 1.0 end

            return currentEvent.price_multiplier or 1.0
        end
    }
}

-- =====================================================
-- CATEGORIAS DE PREÇOS
-- =====================================================

DP.PriceCategories = {
    -- Alimentos e bebidas
    FOOD = {
        base_multiplier = 1.0,
        volatility = 0.15,  -- 15% de variação máxima
        min_price = 1,
        max_price = 1000
    },

    -- Armas e munição
    WEAPONS = {
        base_multiplier = 1.5,
        volatility = 0.25,
        min_price = 100,
        max_price = 100000
    },

    -- Drogas
    DRUGS = {
        base_multiplier = 2.0,
        volatility = 0.40,  -- Alta volatilidade
        min_price = 50,
        max_price = 50000
    },

    -- Veículos
    VEHICLES = {
        base_multiplier = 1.2,
        volatility = 0.10,  -- Baixa volatilidade
        min_price = 5000,
        max_price = 10000000
    },

    -- Propriedades
    PROPERTIES = {
        base_multiplier = 1.3,
        volatility = 0.05,  -- Muito baixa volatilidade
        min_price = 10000,
        max_price = 50000000
    },

    -- Serviços
    SERVICES = {
        base_multiplier = 1.1,
        volatility = 0.20,
        min_price = 10,
        max_price = 10000
    },

    -- Itens gerais
    GENERAL = {
        base_multiplier = 1.0,
        volatility = 0.20,
        min_price = 1,
        max_price = 10000
    }
}

-- =====================================================
-- CÁLCULO DE PREÇOS DINÂMICOS
-- =====================================================

---Calcula o multiplicador global de preços baseado em todos os fatores
---@return number multiplier
function DP.GetGlobalPriceMultiplier()
    local multiplier = 1.0

    for factorName, factor in pairs(DP.PriceFactors) do
        local value = factor.getValue()
        local weight = factor.weight

        -- Aplica o peso do fator
        multiplier = multiplier + ((value - 1.0) * weight)
    end

    -- Limita entre 0.5 e 3.0 para evitar extremos
    return math.max(0.5, math.min(3.0, multiplier))
end

---Calcula o preço final de um item/serviço
---@param basePrice number Preço base
---@param category string Categoria do item
---@param itemData table Dados adicionais do item
---@return number finalPrice
function DP.CalcPrice(basePrice, category, itemData)
    if not basePrice or basePrice <= 0 then
        return 0
    end

    -- Pega a configuração da categoria
    local catConfig = DP.PriceCategories[category] or DP.PriceCategories.GENERAL

    -- Multiplicador global
    local globalMult = DP.GetGlobalPriceMultiplier()

    -- Multiplicador da categoria
    local categoryMult = catConfig.base_multiplier

    -- Volatilidade (adiciona randomização baseada em oferta/demanda)
    local volatility = catConfig.volatility
    local randomFactor = 1.0 + (math.random(-100, 100) / 100) * volatility

    -- Multiplicador customizado do item (se houver)
    local itemMult = 1.0
    if itemData and itemData.custom_multiplier then
        itemMult = itemData.custom_multiplier
    end

    -- Calcula preço final
    local finalPrice = basePrice * globalMult * categoryMult * randomFactor * itemMult

    -- Aplica limites da categoria
    finalPrice = math.max(catConfig.min_price, math.min(catConfig.max_price, finalPrice))

    -- Arredonda para inteiro
    return math.floor(finalPrice)
end

---Atualiza o preço de um item específico no cache
---@param itemId string ID do item
---@param basePrice number Preço base
---@param category string Categoria
---@param itemData table Dados do item
function DP.UpdatePrice(itemId, basePrice, category, itemData)
    local price = DP.CalcPrice(basePrice, category, itemData)

    DP.PriceCache[itemId] = {
        base_price = basePrice,
        current_price = price,
        category = category,
        last_update = os.time(),
        multiplier = price / basePrice
    }

    -- Salva no banco de dados
    MySQL.Async.execute([[
        INSERT INTO space_economy_prices
        (item_id, base_price, current_price, category, multiplier, last_update)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            current_price = VALUES(current_price),
            multiplier = VALUES(multiplier),
            last_update = VALUES(last_update)
    ]], {
        itemId,
        basePrice,
        price,
        category,
        price / basePrice,
        os.time()
    })

    return price
end

---Retorna o preço atual de um item
---@param itemId string
---@return number|nil price
function DP.GetPrice(itemId)
    local cached = DP.PriceCache[itemId]
    if cached then
        return cached.current_price
    end
    return nil
end

---Retorna informações completas do preço
---@param itemId string
---@return table|nil priceInfo
function DP.GetPriceInfo(itemId)
    return DP.PriceCache[itemId]
end

-- =====================================================
-- ATUALIZAÇÃO AUTOMÁTICA DE PREÇOS
-- =====================================================

---Atualiza todos os preços do sistema
function DP.UpdateAllPrices()
    local startTime = GetGameTimer()
    local updatedCount = 0

    print('^3[DynamicPricing] Iniciando atualização global de preços...^7')

    -- Atualiza preços do cache
    for itemId, priceData in pairs(DP.PriceCache) do
        DP.UpdatePrice(itemId, priceData.base_price, priceData.category, {})
        updatedCount = updatedCount + 1
    end

    -- Busca preços de serviços registrados e atualiza
    if not (SE.ServiceRegistry and SE.ServiceRegistry.IsReady and SE.ServiceRegistry.IsReady()) then
        return
    end

    if SE.ServiceRegistry and SE.ServiceRegistry.GetAllServices then
        local services = SE.ServiceRegistry.GetAllServices()
        for serviceName, service in pairs(services) do
            if service.pricing and service.pricing.can_be_balanced then
                -- Se o serviço tem callback para obter preços
                if service.callbacks.get_prices then
                    local prices = service.callbacks.get_prices()

                    if prices then
                        for itemId, itemPrice in pairs(prices) do
                            if type(itemPrice) == 'table' then
                                DP.UpdatePrice(
                                    serviceName .. ':' .. itemId,
                                    itemPrice.base or itemPrice.price,
                                    itemPrice.category or 'GENERAL',
                                    itemPrice
                                )
                            else
                                DP.UpdatePrice(
                                    serviceName .. ':' .. itemId,
                                    itemPrice,
                                    'GENERAL',
                                    {}
                                )
                            end
                            updatedCount = updatedCount + 1
                        end
                    end

                    -- Se o serviço tem callback para definir preços, notifica
                    if service.callbacks.set_prices then
                        local newPrices = {}
                        for itemId, priceData in pairs(DP.PriceCache) do
                            if itemId:match('^' .. serviceName .. ':') then
                                local realItemId = itemId:gsub('^' .. serviceName .. ':', '')
                                newPrices[realItemId] = priceData.current_price
                            end
                        end

                        if next(newPrices) then
                            service.callbacks.set_prices(newPrices)
                        end
                    end
                end
            end
        end
    end

    local elapsed = GetGameTimer() - startTime
    DP.LastUpdate = os.time()

    print(('^2[DynamicPricing] Atualização concluída: %d preços em %dms^7'):format(
        updatedCount, elapsed
    ))

    -- Notifica clientes
    TriggerClientEvent('space_economy:pricesUpdated', -1, {
        timestamp = DP.LastUpdate,
        count = updatedCount,
        multiplier = DP.GetGlobalPriceMultiplier()
    })

    -- Dispara evento para outros sistemas
    TriggerEvent('space_economy:pricesUpdated', DP.PriceCache)
end

---Thread de atualização automática
function DP.StartScheduler()
    if DP.Running then
        print('^3[DynamicPricing] Scheduler já ativo; pulando start duplicado.^7')
        return
    end

    DP.Running = true
    print('^2[DynamicPricing] Scheduler iniciado.^7')

    CreateThread(function()
        while DP.Running do
            Wait(DP.UpdateInterval)
            if DP.Running and DP.Ready then
                DP.UpdateAllPrices()
            end
        end
    end)
end

function DP.StopScheduler()
    if not DP.Running then return end
    DP.Running = false
    print('^3[DynamicPricing] Scheduler finalizado.^7')
end

-- =====================================================
-- INTEGRAÇÃO COM SERVIÇOS EXTERNOS
-- =====================================================

---Registra preços de um serviço externo no sistema
---@param serviceName string Nome do serviço
---@param prices table Tabela de preços {itemId = price}
---@param category string Categoria padrão
function DP.RegisterServicePrices(serviceName, prices, category)
    category = category or 'GENERAL'

    for itemId, price in pairs(prices) do
        local fullItemId = serviceName .. ':' .. itemId

        if type(price) == 'table' then
            DP.UpdatePrice(
                fullItemId,
                price.base or price.price or 0,
                price.category or category,
                price
            )
        else
            DP.UpdatePrice(
                fullItemId,
                price,
                category,
                {}
            )
        end
    end

    print(('^2[DynamicPricing] Registrados %d preços do serviço: %s^7'):format(
        #prices, serviceName
    ))
end

---Retorna todos os preços de um serviço
---@param serviceName string
---@return table prices
function DP.GetServicePrices(serviceName)
    local prices = {}

    for itemId, priceData in pairs(DP.PriceCache) do
        if itemId:match('^' .. serviceName .. ':') then
            local realItemId = itemId:gsub('^' .. serviceName .. ':', '')
            prices[realItemId] = {
                base_price = priceData.base_price,
                current_price = priceData.current_price,
                multiplier = priceData.multiplier,
                category = priceData.category
            }
        end
    end

    return prices
end

-- =====================================================
-- API PARA DESENVOLVEDORES
-- =====================================================

---Evento para serviços externos solicitarem preço atualizado
RegisterNetEvent('space_economy:server_requestPrice', function(itemId, basePrice, category)
    local src = source

    local price = DP.CalcPrice(basePrice, category or 'GENERAL', {})

    TriggerClientEvent('space_economy:client_priceResponse', src, {
        item_id = itemId,
        price = price
    })
end)

---Evento para serviços externos registrarem seus preços
RegisterNetEvent('space_economy:server_registerPrices', function(serviceName, prices, category)
    local resource = GetInvokingResource()

    if not resource then
        return
    end

    DP.RegisterServicePrices(serviceName or resource, prices, category)
end)

-- =====================================================
-- RELATÓRIOS E ESTATÍSTICAS
-- =====================================================

---Gera relatório de preços
---@return table report
function DP.GenerateReport()
    local report = {
        timestamp = os.time(),
        global_multiplier = DP.GetGlobalPriceMultiplier(),
        total_items = 0,
        by_category = {},
        factors = {}
    }

    -- Fatores econômicos
    for factorName, factor in pairs(DP.PriceFactors) do
        report.factors[factorName] = {
            value = factor.getValue(),
            weight = factor.weight
        }
    end

    -- Estatísticas por categoria
    for itemId, priceData in pairs(DP.PriceCache) do
        report.total_items = report.total_items + 1

        local cat = priceData.category
        if not report.by_category[cat] then
            report.by_category[cat] = {
                count = 0,
                avg_multiplier = 0,
                total_base = 0,
                total_current = 0
            }
        end

        local catData = report.by_category[cat]
        catData.count = catData.count + 1
        catData.total_base = catData.total_base + priceData.base_price
        catData.total_current = catData.total_current + priceData.current_price
        catData.avg_multiplier = catData.total_current / catData.total_base
    end

    return report
end

---Comando para visualizar relatório de preços
RegisterCommand('se:prices', function(source, args, raw)
    if not SE.Permissions.IsAdmin(source) then
        return
    end

    local report = DP.GenerateReport()

    print('^2========================================^7')
    print('^2RELATÓRIO DE PREÇOS DINÂMICOS^7')
    print('^2========================================^7')
    print(('^3Multiplicador Global: %.2fx^7'):format(report.global_multiplier))
    print(('^3Total de Itens: %d^7'):format(report.total_items))
    print('')
    print('^5Fatores Econômicos:^7')

    for factorName, factorData in pairs(report.factors) do
        print(('  ^7%s: %.2f (peso: %.0f%%)'):format(
            factorName,
            factorData.value,
            factorData.weight * 100
        ))
    end

    print('')
    print('^5Preços por Categoria:^7')

    for category, catData in pairs(report.by_category) do
        print(('  ^7%s: %d itens | Mult. Médio: %.2fx'):format(
            category,
            catData.count,
            catData.avg_multiplier
        ))
    end
end, false)

-- =====================================================
-- PERSISTÊNCIA NO BANCO DE DADOS
-- =====================================================

---Carrega preços do banco de dados
function DP.LoadPricesFromDB()
    MySQL.Async.fetchAll('SELECT * FROM space_economy_prices', {}, function(results)
        if not results then return end

        for _, row in ipairs(results) do
            DP.PriceCache[row.item_id] = {
                base_price = row.base_price,
                current_price = row.current_price,
                category = row.category,
                last_update = row.last_update,
                multiplier = row.multiplier
            }
        end

        print(('^2[DynamicPricing] Carregados %d preços do banco de dados^7'):format(#results))

        -- Força atualização após carregar
        Citizen.SetTimeout(5000, function()
            DP.UpdateAllPrices()
        end)
    end)
end

-- =====================================================
-- INICIALIZAÇÃO
-- =====================================================

function DP.Initialize()
    if DP.Ready then
        return true
    end

    if not (SE.ServiceRegistry and SE.ServiceRegistry.IsReady and SE.ServiceRegistry.IsReady()) then
        return false
    end

    print('^2[DynamicPricing] Inicializando sistema de preços dinâmicos...^7')

    DP.LoadPricesFromDB()
    DP.Ready = true
    DP.Boot.waitingLogged = false
    DP.Boot.failedLogged = false
    DP.StartScheduler()

    print('^2[DynamicPricing] Sistema inicializado com sucesso!^7')
    return true
end

-- Exporta para outros recursos
exports('GetPrice', function(itemId)
    return DP.GetPrice(itemId)
end)

exports('CalcPrice', function(basePrice, category, itemData)
    return DP.CalcPrice(basePrice, category, itemData)
end)

exports('RegisterServicePrices', function(serviceName, prices, category)
    return DP.RegisterServicePrices(serviceName, prices, category)
end)

exports('GetServicePrices', function(serviceName)
    return DP.GetServicePrices(serviceName)
end)

exports('GetGlobalPriceMultiplier', function()
    return DP.GetGlobalPriceMultiplier()
end)

-- Inicializa quando o resource começar
Citizen.CreateThread(function()
    local maxAttempts = 12
    local intervalMs = 5000

    if not DP.Boot.waitingLogged then
        DP.Boot.waitingLogged = true
        print('^3[DynamicPricing] Aguardando ServiceRegistry para bootstrap...^7')
    end

    for _ = 1, maxAttempts do
        if DP.Initialize() then
            return
        end
        Wait(intervalMs)
    end

    if not DP.Boot.failedLogged then
        DP.Boot.failedLogged = true
        print('^1[DynamicPricing] Bootstrap adiado: ServiceRegistry indisponível.^7')
    end
end)

AddEventHandler('space_economy:serviceRegistryReady', function()
    if DP.Initialize() then
        print('^2[DynamicPricing] Bootstrap liberado por ServiceRegistryReady.^7')
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    DP.StopScheduler()
    DP.Ready = false
    DP.Boot.waitingLogged = false
    DP.Boot.failedLogged = false
end)
