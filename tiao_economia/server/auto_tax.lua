--============================================================
-- space_economy - server/auto_tax.lua (NOVO)
-- Integração automática para taxar compras, veículos e propriedades
--============================================================
SE = SE or {}
SE.AutoTax = SE.AutoTax or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config.Integrations or {}
local dbCfg = Config.Database or {}

local function dbg(...) 
  if U and U.dbg then U.dbg(...) else print('^3[auto_tax]^7', ...) end 
end

local function registerTransaction(category, amount, meta)
  if SE
    and SE.EconomyMonitor
    and type(SE.EconomyMonitor.RegisterTransaction) == 'function' then
    SE.EconomyMonitor.RegisterTransaction(category, amount, meta)
  end
end

local function countAssets(tableName, ownerColumn, citizenid)
  if not MySQL or not citizenid or citizenid == '' or not tableName then return 0 end
  local col = ownerColumn or 'citizenid'
  local ok, result = pcall(function()
    return MySQL.scalar.await(('SELECT COUNT(*) FROM `%s` WHERE `%s` = ?'):format(tableName, col), { citizenid })
  end)
  if not ok then return 0 end
  return U.toInt(result, 0)
end

local function applyAssetMultiplier(baseTax, count, multiplierCfg)
  baseTax = U.toInt(baseTax, 0)
  if not (Config.AssetTax and Config.AssetTax.Enabled) then return baseTax end
  local mult = U.toNumber(multiplierCfg, 0)
  if mult <= 0 then return baseTax end

  local extra = math.max(count - 1, 0)
  local factor = 1 + (extra * mult)
  local maxFactor = U.toNumber(Config.AssetTax.MaxMultiplier, 0)
  if maxFactor > 0 then
    factor = math.min(factor, maxFactor)
  end

  return math.floor(baseTax * factor)
end

local function parseDateTime(value)
  if type(value) == 'number' then return value end
  if type(value) ~= 'string' then return nil end
  local year, month, day, hour, min, sec = value:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
  if year then
    return os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
    })
  end
  return nil
end

local function getVehicleConfig()
  return dbCfg.Vehicles or {}
end

local function getPropertyConfig()
  return dbCfg.Properties or {}
end

local function getVehicleFallbackPrice()
  return U.toInt((Config.DBIntegrations and Config.DBIntegrations.IPVA and Config.DBIntegrations.IPVA.fallbackPrice), 50000)
end

local vehicleIdleColumn = nil
local function getVehicleIdleColumn()
  if vehicleIdleColumn ~= nil then return vehicleIdleColumn or nil end
  if not MySQL then
    vehicleIdleColumn = false
    return nil
  end

  local ok, cols = pcall(function()
    local vehiclesCfg = getVehicleConfig()
    local tableName = vehiclesCfg.table or 'player_vehicles'
    return MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName))
  end)

  if not ok or not cols then
    vehicleIdleColumn = false
    return nil
  end

  local names = {}
  for _, c in ipairs(cols) do
    if c and c.Field then
      names[c.Field] = true
    end
  end

  local candidates = {
    'last_parked',
    'last_parked_at',
    'last_garage',
    'last_garage_at',
    'last_driven',
    'last_drive',
    'last_used',
    'last_used_at',
    'last_updated',
    'updated_at',
  }

  for _, name in ipairs(candidates) do
    if names[name] then
      vehicleIdleColumn = name
      return name
    end
  end

  vehicleIdleColumn = false
  return nil
end

--============================================================
-- HOOKS PARA SHOPS (qb-shops, ox_inventory, etc)
--============================================================

-- Hook genérico para compras
local function hookShopPurchase(src, item, price, quantity)
  quantity = quantity or 1
  price = U.toInt(price, 0) * quantity
  
  if price <= 0 then return true end
  
  -- Calcula imposto (ICMS)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'ICMS' then return t end
      end
      return nil
    end)()
  
  if not taxCfg or not cfg.Shops or not cfg.Shops.TaxPurchases then
    return true -- Sem taxação
  end
  
  local taxRate = taxCfg.percent or 12
  local taxAmount = math.floor(price * (taxRate / 100))
  
  if taxAmount <= 0 then return true end
  
  -- Cria dívida de imposto
  local cid = B.GetCitizenId(src)
  if not cid then return true end
  
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, taxAmount, 'ICMS - Compra', os.time() + (30 * 24 * 60 * 60), {
      item = item,
      base_price = price,
      tax_rate = taxRate,
      quantity = quantity
    })
  end

  registerTransaction('compra_item', price, {
    citizenid = cid,
    item = item,
    quantity = quantity,
    total_price = price
  })
  
  dbg(('ICMS sobre compra: %s | $%d (base: $%d)'):format(cid, taxAmount, price))
  
  return true
end

-- Integração com qb-shops / qbx-shops
if GetResourceState('qb-shops') == 'started' or GetResourceState('qbx-shops') == 'started' then
  -- Hook no evento de compra
  AddEventHandler('qb-shops:server:purchaseItem', function(src, data)
    hookShopPurchase(src, data.item, data.price, data.amount)
  end)
  
  dbg('Hooked: qb-shops')
end

-- Integração com ox_inventory shops
if GetResourceState('ox_inventory') == 'started' then
  AddEventHandler('ox_inventory:server:shopPurchase', function(src, data)
    hookShopPurchase(src, data.name, data.price, data.count)
  end)
  
  dbg('Hooked: ox_inventory')
end

--============================================================
-- IPVA AUTOMÁTICO (Garages)
--============================================================

-- Calcula IPVA baseado no valor do veículo
local function calculateIPVA(vehiclePrice)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'IPVA' then return t end
      end
      return nil
    end)()
  
  if not taxCfg then return 0 end
  
  local rate = taxCfg.percent or 1.5
  local inflationMultiplier = 1.0

  if SE.MonetaryPolicy and SE.MonetaryPolicy.GetReport then
    local report = SE.MonetaryPolicy.GetReport()
    if report and report.inflation then
      inflationMultiplier = 1 + U.toNumber(report.inflation.accumulated, 0)
    end
  elseif SE.State and SE.State.inflationRate then
    inflationMultiplier = U.toNumber(SE.State.inflationRate, 1.0)
  elseif Config.Inflation and Config.Inflation.DefaultRate then
    inflationMultiplier = U.toNumber(Config.Inflation.DefaultRate, 1.0)
  end

  return math.floor(vehiclePrice * (rate / 100) * inflationMultiplier)
end

-- Hook para quando player compra veículo
function SE.AutoTax.OnVehiclePurchase(src, vehicleData)
  if not (cfg.Garages and cfg.Garages.AutoIPVA) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local price = U.toInt(vehicleData.price, 0)
  if price <= 0 and SE.DB and SE.DB.GetPlayerVehicles then
    local vehicles = SE.DB.GetPlayerVehicles(cid)
    for _, v in ipairs(vehicles) do
      if v.plate and vehicleData.plate and v.plate == vehicleData.plate then
        price = U.toInt(v.price, 0)
        break
      end
    end
  end
  if price <= 0 then return end
  
  local ipva = calculateIPVA(price)
  if ipva <= 0 then return end

  local vehicleCfg = getVehicleConfig()
  local vehicleTable = vehicleCfg.table or 'player_vehicles'
  local vehicleOwner = vehicleCfg.ownerColumn or 'citizenid'
  local vehicleCount = countAssets(vehicleTable, vehicleOwner, cid)
  ipva = applyAssetMultiplier(ipva, vehicleCount + 1, Config.AssetTax and Config.AssetTax.VehicleMultiplier)
  
  -- Cria dívida de IPVA (vence em 30 dias)
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, ipva, 'IPVA - ' .. (vehicleData.model or 'Veículo'), 
      os.time() + (30 * 24 * 60 * 60), {
      vehicle_model = vehicleData.model,
      vehicle_plate = vehicleData.plate,
      base_price = price,
      ipva_rate = 1.5
    })
    
    B.Notify(src, ('IPVA lançado: $%d (vence em 30 dias)'):format(ipva), 'inform')
  end

  registerTransaction('compra_veiculo', price, {
    citizenid = cid,
    vehicle_model = vehicleData.model,
    vehicle_plate = vehicleData.plate,
    total_price = price
  })
  
  dbg(('IPVA lançado: %s | $%d (veículo: %s)'):format(cid, ipva, vehicleData.plate or '?'))
end

-- Integração com qb-vehicleshop / qbx-vehicleshop
if GetResourceState('qb-vehicleshop') == 'started' or GetResourceState('qbx-vehicleshop') == 'started' then
  AddEventHandler('qb-vehicleshop:server:buyVehicle', function(src, data)
    SE.AutoTax.OnVehiclePurchase(src, data)
  end)
  
  dbg('Hooked: qb-vehicleshop (IPVA)')
end

-- Thread: IPVA anual recorrente
if cfg.Garages and cfg.Garages.AutoIPVA then
  CreateThread(function()
    while not MySQL do Wait(1000) end
    
    local intervalMs = 24 * 60 * 60 * 1000 -- Diário
    
    while true do
      Wait(intervalMs)
      
      -- Busca veículos que precisam renovar IPVA
      -- Requer tabela player_vehicles com colunas: citizenid, vehicle, plate, price, last_ipva_at
      
      local idleCol = getVehicleIdleColumn()
      local vehicleCfg = getVehicleConfig()
      local tableName = vehicleCfg.table or 'player_vehicles'
      local ownerColumn = vehicleCfg.ownerColumn or 'citizenid'
      local modelColumn = vehicleCfg.modelColumn or 'vehicle'
      local plateColumn = vehicleCfg.plateColumn or 'plate'
      local valueColumn = vehicleCfg.valueColumn or 'depotprice'
      local fallbackPrice = getVehicleFallbackPrice()

      local selectCols = ('`%s` as citizenid, `%s` as vehicle, `%s` as plate, COALESCE(NULLIF(`%s`, 0), %d) as price'):format(
        ownerColumn,
        modelColumn,
        plateColumn,
        valueColumn,
        fallbackPrice
      )
      if idleCol then
        selectCols = ('%s, `%s` as last_idle_at'):format(selectCols, idleCol)
      end

      local vehicles = MySQL.query.await(([[
        SELECT %s
        FROM `%s`
        WHERE (last_ipva_at IS NULL OR last_ipva_at < DATE_SUB(NOW(), INTERVAL 365 DAY))
        LIMIT 100
      ]]):format(selectCols, tableName))
      
      if vehicles then
        for _, v in ipairs(vehicles) do
          local ipva = calculateIPVA(U.toInt(v.price, fallbackPrice))
          local vehicleCount = countAssets(tableName, ownerColumn, v.citizenid)
          ipva = applyAssetMultiplier(ipva, vehicleCount, Config.AssetTax and Config.AssetTax.VehicleMultiplier)

          local idleApplied = false
          local idleDaysCount = nil

          if idleCol and Config.AssetTax then
            local idleDaysLimit = U.toInt(Config.AssetTax.IdleVehicleDays, 0)
            local idleMult = U.toNumber(Config.AssetTax.IdleVehicleMultiplier, 1.0)
            local lastIdle = parseDateTime(v.last_idle_at)
            if idleDaysLimit > 0 and idleMult > 1.0 and lastIdle then
              local daysIdle = math.floor((os.time() - lastIdle) / 86400)
              if daysIdle >= idleDaysLimit then
                ipva = math.floor(ipva * idleMult)
                idleApplied = true
                idleDaysCount = daysIdle
              end
            end
          end
          
          if ipva > 0 and SE.Debts and SE.Debts.Upsert then
            SE.Debts.Upsert(v.citizenid, ipva, 'IPVA - ' .. (v.vehicle or 'Veículo'),
              os.time() + (30 * 24 * 60 * 60), {
                vehicle_plate = v.plate,
                base_price = v.price,
                ipva_rate = 1.5,
                annual = true,
                idle_check = idleCol and true or false,
                idle_applied = idleApplied,
                idle_days = idleDaysCount,
              })
            
            -- Atualiza última cobrança
            MySQL.update.await(([[
              UPDATE `%s`
              SET last_ipva_at = NOW()
              WHERE `%s` = ?
            ]]):format(tableName, plateColumn), { v.plate })
            
            dbg(('IPVA anual: %s | $%d (placa: %s)'):format(v.citizenid, ipva, v.plate))
          end
        end
      end
    end
  end)
end

--============================================================
-- IPTU AUTOMÁTICO (Real Estate)
--============================================================

-- Calcula IPTU baseado no valor da propriedade
local function calculateIPTU(propertyPrice)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'IPTU' then return t end
      end
      return nil
    end)()
  
  if not taxCfg then return 0 end
  
  local rate = taxCfg.percent or 0.3
  return math.floor(propertyPrice * (rate / 100))
end

-- Hook para quando player compra propriedade
function SE.AutoTax.OnPropertyPurchase(src, propertyData)
  if not (cfg.RealEstate and cfg.RealEstate.AutoIPTU) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local price = U.toInt(propertyData.price, 0)
  if price <= 0 and SE.DB and SE.DB.GetPlayerProperties then
    local properties = SE.DB.GetPlayerProperties(cid)
    for _, property in ipairs(properties) do
      if property.id and propertyData.id and tostring(property.id) == tostring(propertyData.id) then
        price = U.toInt(property.price, 0)
        break
      end
    end
  end
  if price <= 0 then return end
  
  local iptu = calculateIPTU(price)
  if iptu <= 0 then return end

  local propertyCfg = getPropertyConfig()
  local propertyTable = propertyCfg.table or 'player_houses'
  local propertyOwner = propertyCfg.ownerColumn or 'citizenid'
  local propertyCount = countAssets(propertyTable, propertyOwner, cid)
  iptu = applyAssetMultiplier(iptu, propertyCount + 1, Config.AssetTax and Config.AssetTax.PropertyMultiplier)
  
  -- Cria dívida de IPTU (vence em 30 dias)
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, iptu, 'IPTU - ' .. (propertyData.label or 'Propriedade'),
      os.time() + (30 * 24 * 60 * 60), {
      property_id = propertyData.id,
      property_label = propertyData.label,
      base_price = price,
      iptu_rate = 0.3
    })
    
    B.Notify(src, ('IPTU lançado: $%d (vence em 30 dias)'):format(iptu), 'inform')
  end

  registerTransaction('compra_imovel', price, {
    citizenid = cid,
    property_id = propertyData.id,
    property_label = propertyData.label,
    total_price = price
  })
  
  dbg(('IPTU lançado: %s | $%d (propriedade: %s)'):format(cid, iptu, propertyData.label or '?'))
end

-- Integração com qb-houses / ps-housing
if GetResourceState('qb-houses') == 'started' or GetResourceState('ps-housing') == 'started' then
  AddEventHandler('qb-houses:server:buyProperty', function(src, data)
    SE.AutoTax.OnPropertyPurchase(src, data)
  end)
  
  AddEventHandler('ps-housing:server:buyProperty', function(src, data)
    SE.AutoTax.OnPropertyPurchase(src, data)
  end)
  
  dbg('Hooked: housing (IPTU)')
end

-- Thread: IPTU mensal recorrente
if cfg.RealEstate and cfg.RealEstate.AutoIPTU then
  CreateThread(function()
    while not MySQL do Wait(1000) end
    
    local intervalMs = 24 * 60 * 60 * 1000 -- Diário
    
    while true do
      Wait(intervalMs)
      
      -- Busca propriedades que precisam pagar IPTU
      -- Requer tabela player_houses/properties com: citizenid, label, price, last_iptu_at
      local propertyCfg = getPropertyConfig()
      local propertyTable = propertyCfg.table or 'player_houses'
      local ownerColumn = propertyCfg.ownerColumn or 'citizenid'
      local priceColumn = propertyCfg.priceColumn or 'price'
      local nameColumn = propertyCfg.nameColumn or 'label'

      local properties = MySQL.query.await(([[
        SELECT `%s` AS citizenid, `%s` AS label,
               COALESCE(`%s`, 100000) as price
        FROM `%s`
        WHERE (last_iptu_at IS NULL OR last_iptu_at < DATE_SUB(NOW(), INTERVAL 30 DAY))
        LIMIT 100
      ]]):format(ownerColumn, nameColumn, priceColumn, propertyTable))
      
      if properties then
        for _, p in ipairs(properties) do
          local iptu = calculateIPTU(U.toInt(p.price, 100000))
          local propertyCount = countAssets(propertyTable, ownerColumn, p.citizenid)
          iptu = applyAssetMultiplier(iptu, propertyCount, Config.AssetTax and Config.AssetTax.PropertyMultiplier)
          
          if iptu > 0 and SE.Debts and SE.Debts.Upsert then
            SE.Debts.Upsert(p.citizenid, iptu, 'IPTU - ' .. (p.label or 'Propriedade'),
              os.time() + (30 * 24 * 60 * 60), {
              property_label = p.label,
              base_price = p.price,
              iptu_rate = 0.3,
              monthly = true
            })
            
            -- Atualiza última cobrança
            MySQL.update.await(([[
              UPDATE `%s`
              SET last_iptu_at = NOW()
              WHERE `%s` = ?
            ]]):format(propertyTable, nameColumn), { p.label })
            
            dbg(('IPTU mensal: %s | $%d (propriedade: %s)'):format(p.citizenid, iptu, p.label))
          end
        end
      end
    end
  end)
end

--============================================================
-- ISS (Imposto sobre Serviços)
--============================================================

-- Hook para prestação de serviços
function SE.AutoTax.OnServiceProvided(src, serviceData)
  if not (cfg.Shops and cfg.Shops.TaxPurchases) then return end
  
  local cid = B.GetCitizenId(src)
  if not cid then return end
  
  local amount = U.toInt(serviceData.amount, 0)
  if amount <= 0 then return end
  
  -- Calcula ISS (2%)
  local taxCfg = Config.TaxCatalog and 
    (function()
      for _, t in ipairs(Config.TaxCatalog) do
        if t.key == 'ISS' then return t end
      end
      return nil
    end)()
  
  if not taxCfg then return end
  
  local rate = taxCfg.percent or 2
  local taxAmount = math.floor(amount * (rate / 100))
  
  if taxAmount <= 0 then return end
  
  -- Cria dívida de ISS
  if SE.Debts and SE.Debts.Upsert then
    SE.Debts.Upsert(cid, taxAmount, 'ISS - ' .. (serviceData.service or 'Serviço'),
      os.time() + (30 * 24 * 60 * 60), {
      service = serviceData.service,
      base_amount = amount,
      tax_rate = rate
    })
  end
  
  dbg(('ISS sobre serviço: %s | $%d (base: $%d)'):format(cid, taxAmount, amount))
end

-- Exports para outros recursos
exports('TaxVehiclePurchase', SE.AutoTax.OnVehiclePurchase)
exports('TaxPropertyPurchase', SE.AutoTax.OnPropertyPurchase)
exports('TaxService', SE.AutoTax.OnServiceProvided)
exports('TaxShopPurchase', hookShopPurchase)

--============================================================
-- COMANDOS ADMIN
--============================================================
RegisterCommand('eco_tax_vehicle', function(source, args)
  if not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(source)) then return end
  
  local targetId = tonumber(args[1])
  local price = tonumber(args[2]) or 50000
  
  if not targetId then
    TriggerClientEvent('chat:addMessage', source, {
      args = {'[Economia]', 'Uso: /eco_tax_vehicle [id] [preço]'}
    })
    return
  end
  
  SE.AutoTax.OnVehiclePurchase(targetId, {
    price = price,
    model = 'Admin',
    plate = 'ADMIN'
  })
  
  TriggerClientEvent('chat:addMessage', source, {
    args = {'[Economia]', ('IPVA de $%d lançado para ID %d'):format(calculateIPVA(price), targetId)}
  })
end, false)

RegisterCommand('eco_tax_property', function(source, args)
  if not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(source)) then return end
  
  local targetId = tonumber(args[1])
  local price = tonumber(args[2]) or 100000
  
  if not targetId then
    TriggerClientEvent('chat:addMessage', source, {
      args = {'[Economia]', 'Uso: /eco_tax_property [id] [preço]'}
    })
    return
  end
  
  SE.AutoTax.OnPropertyPurchase(targetId, {
    price = price,
    label = 'Propriedade Admin',
    id = 'admin_property'
  })
  
  TriggerClientEvent('chat:addMessage', source, {
    args = {'[Economia]', ('IPTU de $%d lançado para ID %d'):format(calculateIPTU(price), targetId)}
  })
end, false) 

