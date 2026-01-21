--============================================================
-- space_economy - server/external_integrations.lua (REESCRITO)
-- Integrações com recursos externos (ps-banking, ox_inventory, ps-housing, ps-mdt, etc.)
-- Foco: robustez, compatibilidade e segurança (sem travar o resource)
--============================================================

SE = SE or {}
SE.External = SE.External or {}

local External = SE.External
local U = SE.Util
local B = SE.Bridge

--============================================================
-- Fallback utils (caso SE.Util não tenha algo)
--============================================================
local function _str(v, d) v = v == nil and d or v; v = tostring(v); if v == '' then return d or '' end; return v end
local function _num(v, d) local n = tonumber(v); if not n then return d or 0 end; return n end
local function _int(v, d) return math.floor(_num(v, d) + 0.000001) end

local function _jsonEncode(t)
  if U and U.safeJsonEncode then return U.safeJsonEncode(t or {}) end
  if json and json.encode then
    local ok, out = pcall(function() return json.encode(t or {}) end)
    return ok and out or '{}'
  end
  return '{}'
end

local function dbg(...)
  if U and U.dbg then
    U.dbg(...)
  else
    print('^5[space_economy:external]^7', ...)
  end
end

local function errlog(...)
  print('^1[space_economy:external:ERROR]^7', ...)
end

local function log(kind, msg, meta)
  if SE and SE.Log then
    pcall(SE.Log, kind, msg, meta or {})
  end
  if (Config and Config.Debug) then
    print(('[space_economy][%s] %s'):format(tostring(kind), tostring(msg)))
  end
end

--============================================================
-- Config (merge seguro)
-- Suporta:
--   Config.ExternalIntegrations
--   Config.Integrations.ExternalIntegrations
--   Config.Integrations (antigo)
--============================================================
local function deepMerge(dst, src)
  if type(dst) ~= 'table' then dst = {} end
  if type(src) ~= 'table' then return dst end
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      dst[k] = deepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

local DEFAULT_CFG = {
  General = {
    Enabled = true,
    Debug = false,
    StartDelayMs = 2000,
    DefaultDueDays = 7,
    DedupeWindowSec = 6, -- evita duplicar dívida quando um recurso dispara 2 eventos parecidos
  },

  Banking = {
    Enabled = true,
    Mode = 'debt',            -- 'debt' (gera dívida) | 'charge' (cobra na hora se conseguir)
    DueDays = 7,

    TaxTransfers = true,
    TransferTaxRate = 0.5,    -- %
    TransferMinTax = 10,      -- mínimo
    TransferMinBase = 100,    -- só taxa transferências >= isso

    TaxWithdrawals = false,
    WithdrawalMinBase = 5000,
    WithdrawalFixedTax = 50,  -- taxa fixa
    WithdrawalTaxRate = 0.0,  -- se quiser %, use >0 e FixedTax=0
  },

  Inventory = {
    Enabled = false,
    Mode = 'debt',
    DueDays = 30,

    TaxPurchases = true,
    TaxRate = 12.0,           -- %
    MinBase = 1,
    ExemptItems = {},
  },

  Vehicles = {
    Enabled = false,
    Mode = 'debt',
    DueDays = 30,

    TaxOnPurchase = true,
    TaxRate = 1.5,
    MinVehiclePrice = 1000,
  },

  Housing = {
    Enabled = false,
    Mode = 'debt',
    DueDays = 30,

    TaxOnPurchase = true,
    TaxRate = 0.3,
    MinPropertyPrice = 5000,
  },

  Management = {
    Enabled = false,
    Mode = 'debt',
    DueDays = 15,

    TaxServices = true,
    ServiceTaxRate = 2.0,
    MinServiceValue = 100,
  },

  Police = {
    Enabled = false,
    Mode = 'debt',
    DueDays = 15,

    AutoCreateDebt = true,
    FineMultiplier = 1.0,
  }
}

local function loadCfg()
  local cfg = deepMerge({}, DEFAULT_CFG)

  local user = nil
  if Config then
    user = Config.ExternalIntegrations
      or (Config.Integrations and Config.Integrations.ExternalIntegrations)
      or Config.Integrations
  end

  cfg = deepMerge(cfg, user or {})
  cfg.General.Debug = cfg.General.Debug or (Config and Config.DebugMode) or false
  return cfg
end

local CFG = loadCfg()

--============================================================
-- Dedupe simples em memória (anti-evento duplicado)
--============================================================
local _dedupe = {} -- key -> lastTs

local function dedupeKey(kind, citizenid, amount, extra)
  return ('%s|%s|%s|%s'):format(tostring(kind), tostring(citizenid), tostring(amount), tostring(extra or ''))
end

local function isDuplicate(key)
  local now = os.time()
  local last = _dedupe[key]
  local win = _int(CFG.General.DedupeWindowSec, 6)
  if last and (now - last) <= win then return true end
  _dedupe[key] = now
  return false
end

CreateThread(function()
  while true do
    Wait(60000)
    local now = os.time()
    for k, ts in pairs(_dedupe) do
      if (now - ts) > 120 then _dedupe[k] = nil end
    end
  end
end)

--============================================================
-- Helpers de cobrança / dívida
--============================================================
local function getSrcFromEvent(firstArg)
  -- Se veio via net event, source global é o player
  if source and tonumber(source) and tonumber(source) > 0 then
    return tonumber(source)
  end
  local s = tonumber(firstArg)
  if s and s > 0 then return s end
  return 0
end

local function getCitizenIdSafe(src, fallbackCid)
  if fallbackCid and tostring(fallbackCid) ~= '' then return tostring(fallbackCid) end
  if B and B.GetCitizenId then
    local ok, cid = pcall(B.GetCitizenId, src)
    if ok and cid and cid ~= '' then return tostring(cid) end
  end
  if SE and SE.Integrations and SE.Integrations.GetCitizenId then
    local ok, cid = pcall(SE.Integrations.GetCitizenId, src)
    if ok and cid and cid ~= '' then return tostring(cid) end
  end
  return nil
end

local function notify(src, msg, typ)
  if B and B.Notify then
    pcall(B.Notify, src, msg, typ or 'inform', 'Economia')
  else
    TriggerClientEvent('space_economy:client_notify', src, msg, typ or 'inform')
  end
end

local function treasuryDeposit(amount, reason, meta)
  amount = _int(amount, 0)
  if amount <= 0 then return false end
  if SE and SE.Treasury and SE.Treasury.Deposit then
    pcall(SE.Treasury.Deposit, amount, reason or 'external', meta or {})
    return true
  end
  if SE and SE.Treasury and SE.Treasury.Modify then
    pcall(SE.Treasury.Modify, amount, reason or 'external', meta or {})
    return true
  end
  return false
end

local function tryChargeNow(src, amount, reason)
  amount = _int(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  -- prioridade: SE.Integrations (porque ela já faz fallback para qbx/qbcore/bridge)
  if SE and SE.Integrations and SE.Integrations.RemoveMoney then
    local ok, res = pcall(SE.Integrations.RemoveMoney, src, amount, 'bank')
    if ok and res == true then
      return true
    end
  end

  -- fallback bridge “bancário”
  if B and B.RemoveBankMoney then
    local ok, res = pcall(B.RemoveBankMoney, src, amount, reason or 'Taxa')
    if ok and res then return true end
  end

  return false, 'could_not_charge'
end

local function createDebt(cid, amount, reason, dueDays, meta)
  if not (SE and SE.Debts and SE.Debts.Upsert) then
    return false, 'debt_module_missing'
  end

  amount = _int(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  dueDays = _int(dueDays, _int(CFG.General.DefaultDueDays, 7))
  local dueTs = os.time() + (dueDays * 24 * 60 * 60)

  local ok, resA, resB = pcall(SE.Debts.Upsert, cid, amount, reason, dueTs, meta or {})
  if not ok then return false, tostring(resA) end

  -- sua Upsert (melhorada) retorna (true, id) ou (false, err)
  if resA == true then return true, resB end
  return false, resB or 'upsert_failed'
end

local function chargeOrDebt(src, cid, amount, reason, mode, dueDays, meta)
  mode = tostring(mode or 'debt'):lower()
  amount = _int(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  -- modo charge: tenta cobrar agora; se não der, vira dívida
  if mode == 'charge' then
    local okCharge = false
    local ok, err2 = tryChargeNow(src, amount, reason)
    if ok == true then
      okCharge = true
      treasuryDeposit(amount, 'tax_charge', { citizenid = cid, amount = amount, reason = reason, meta = meta })
      log('external', ('Cobrança imediata: $%d | %s'):format(amount, reason), { citizenid = cid, src = src, amount = amount })
      return true, { charged = true, amount = amount }
    end

    -- fallback para dívida
    local okDebt, debtId = createDebt(cid, amount, reason, dueDays, meta)
    if okDebt then
      return true, { charged = false, debt = true, debt_id = debtId, amount = amount, fallback = err2 }
    end
    return false, 'charge_failed_and_debt_failed'
  end

  -- modo debt
  local okDebt, debtId = createDebt(cid, amount, reason, dueDays, meta)
  if okDebt then
    return true, { debt = true, debt_id = debtId, amount = amount }
  end
  return false, 'debt_failed'
end

--============================================================
-- Hook helper (não quebrar servidor)
--============================================================
local function listen(eventName, handler)
  if type(eventName) ~= 'string' or eventName == '' then return end

  -- RegisterNetEvent não faz mal mesmo se for server-only
  pcall(RegisterNetEvent, eventName)

  AddEventHandler(eventName, function(...)
    local ok, e = pcall(handler, ...)
    if not ok then
      errlog(('Handler falhou (%s): %s'):format(eventName, tostring(e)))
      log('external_error', 'handler_failed', { event = eventName, error = tostring(e) })
    end
  end)

  if CFG.General.Debug then dbg('Hook registrado:', eventName) end
end

--============================================================
-- 1) PS-BANKING
--============================================================
External.Banking = External.Banking or { Enabled = false }

local function calcPercentTax(base, ratePercent, minTax)
  base = _num(base, 0)
  local rate = _num(ratePercent, 0)
  local tax = math.floor(base * (rate / 100.0) + 0.00001)
  tax = math.max(tax, _int(minTax, 0))
  return _int(tax, 0)
end

local function initPsBanking()
  if not CFG.Banking.Enabled then
    dbg('ps-banking: integração desativada no config')
    return false
  end

  if GetResourceState('ps-banking') ~= 'started' then
    dbg('ps-banking não está started')
    return false
  end

  External.Banking.Enabled = true
  dbg('✓ ps-banking detectado: habilitando hooks...')

  local function handleTransferEvent(...)
    local args = { ... }
    local src = getSrcFromEvent(args[1])
    if src <= 0 then return end

    -- data pode vir em vários formatos
    local data = nil
    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    local amount =
      (data and _num(data.amount, 0))
      or _num(args[2], 0)
      or _num(args[3], 0)

    if amount <= 0 then return end

    if not CFG.Banking.TaxTransfers then return end
    if amount < _num(CFG.Banking.TransferMinBase, 100) then return end

    local cid = getCitizenIdSafe(src, data and (data.citizenid or data.identifier))
    if not cid then return end

    local taxAmount = calcPercentTax(amount, CFG.Banking.TransferTaxRate, CFG.Banking.TransferMinTax)
    if taxAmount <= 0 then return end

    local target = (data and (data.target or data.to or data.account)) or args[2] or 'unknown'
    local txId = (data and (data.id or data.transactionId)) or nil

    local key = dedupeKey('bank_transfer_tax', cid, taxAmount, txId or target)
    if isDuplicate(key) then return end

    local reason = 'IOF - Transferência Bancária'
    local meta = {
      source = 'ps-banking',
      kind = 'transfer',
      base_amount = amount,
      tax_rate = _num(CFG.Banking.TransferTaxRate, 0.5),
      target = target,
      tx_id = txId,
    }

    local ok, res = chargeOrDebt(src, cid, taxAmount, reason, CFG.Banking.Mode, CFG.Banking.DueDays, meta)
    if ok then
      notify(src, ('Taxa IOF gerada: $%d (sobre $%d)'):format(taxAmount, _int(amount, 0)), 'inform')
      log('external_banking', ('IOF: $%d sobre transferência $%d'):format(taxAmount, _int(amount, 0)), { citizenid = cid, src = src, meta = meta, result = res })
    end
  end

  local function handleWithdrawEvent(...)
    local args = { ... }
    local src = getSrcFromEvent(args[1])
    if src <= 0 then return end

    local data = nil
    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    local amount =
      (data and _num(data.amount, 0))
      or _num(args[2], 0)
      or _num(args[3], 0)

    if amount <= 0 then return end
    if not CFG.Banking.TaxWithdrawals then return end
    if amount < _num(CFG.Banking.WithdrawalMinBase, 5000) then return end

    local cid = getCitizenIdSafe(src, data and (data.citizenid or data.identifier))
    if not cid then return end

    local taxAmount = 0
    if _num(CFG.Banking.WithdrawalFixedTax, 0) > 0 then
      taxAmount = _int(CFG.Banking.WithdrawalFixedTax, 0)
    else
      taxAmount = math.floor(amount * (_num(CFG.Banking.WithdrawalTaxRate, 0) / 100.0) + 0.00001)
    end

    if taxAmount <= 0 then return end

    local txId = (data and (data.id or data.transactionId)) or nil
    local key = dedupeKey('bank_withdraw_tax', cid, taxAmount, txId or amount)
    if isDuplicate(key) then return end

    local reason = 'Taxa de Saque ATM'
    local meta = {
      source = 'ps-banking',
      kind = 'withdraw',
      base_amount = amount,
      tax_fixed = _int(CFG.Banking.WithdrawalFixedTax, 0),
      tax_rate = _num(CFG.Banking.WithdrawalTaxRate, 0),
      tx_id = txId,
    }

    local ok, res = chargeOrDebt(src, cid, taxAmount, reason, CFG.Banking.Mode, CFG.Banking.DueDays, meta)
    if ok then
      notify(src, ('Taxa de saque gerada: $%d'):format(taxAmount), 'inform')
      log('external_banking', ('Taxa saque: $%d sobre $%d'):format(taxAmount, _int(amount, 0)), { citizenid = cid, src = src, meta = meta, result = res })
    end
  end

  -- ps-banking: variações comuns
  local transferEvents = {
    'ps-banking:server:transfer',
    'ps-banking:server:Transfer',
    'ps-banking:server:TransferMoney',
    'ps-banking:server:doTransfer',
    'ps-banking:transfer',
  }

  local withdrawEvents = {
    'ps-banking:server:withdraw',
    'ps-banking:server:Withdraw',
    'ps-banking:withdraw',
    'ps-banking:server:atmWithdraw',
  }

  for _, ev in ipairs(transferEvents) do
    listen(ev, handleTransferEvent)
  end

  for _, ev in ipairs(withdrawEvents) do
    listen(ev, handleWithdrawEvent)
  end

  return true
end

--============================================================
-- 2) OX_INVENTORY (compras)
--============================================================
External.Inventory = External.Inventory or { Enabled = false }

local function isExemptItem(itemName)
  itemName = tostring(itemName or '')
  for _, ex in ipairs(CFG.Inventory.ExemptItems or {}) do
    if itemName == tostring(ex) then return true end
  end
  return false
end

local function initOxInventory()
  if not CFG.Inventory.Enabled then
    dbg('ox_inventory: integração desativada no config')
    return false
  end

  if GetResourceState('ox_inventory') ~= 'started' then
    dbg('ox_inventory não está started')
    return false
  end

  External.Inventory.Enabled = true
  dbg('✓ ox_inventory detectado: habilitando hooks...')

  local function handlePurchaseEvent(...)
    local args = { ... }
    local src = getSrcFromEvent(args[1])
    if src <= 0 then return end
    if not CFG.Inventory.TaxPurchases then return end

    local item, count, price, shop = nil, 1, 0, nil
    local data = nil

    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    if data then
      item  = data.name or data.item or data.itemName
      count = _int(data.count or data.amount or data.quantity, 1)
      price = _num(data.price or data.unitPrice or data.cost, 0)
      shop  = data.shop or data.shopName or data.store
      -- alguns eventos já trazem total:
      if data.total and _num(data.total, 0) > 0 and price <= 0 then
        price = _num(data.total, 0) / math.max(count, 1)
      end
    else
      -- formato: (src, item, count, price, shopName)
      item  = args[2]
      count = _int(args[3], 1)
      price = _num(args[4], 0)
      shop  = args[5]
    end

    item = tostring(item or '')
    if item == '' then return end
    if isExemptItem(item) then return end
    if count < 1 then count = 1 end

    local total = price * count
    if total < _num(CFG.Inventory.MinBase, 1) then return end

    local tax = math.floor(total * (_num(CFG.Inventory.TaxRate, 12.0) / 100.0) + 0.00001)
    if tax <= 0 then return end

    local cid = getCitizenIdSafe(src, data and (data.citizenid or data.identifier))
    if not cid then return end

    local key = dedupeKey('inv_purchase_tax', cid, tax, item .. '|' .. tostring(shop or ''))
    if isDuplicate(key) then return end

    local reason = ('ICMS - Compra: %s'):format(item)
    local meta = {
      source = 'ox_inventory',
      kind = 'purchase',
      item = item,
      quantity = count,
      base_total = total,
      tax_rate = _num(CFG.Inventory.TaxRate, 12.0),
      shop = shop,
    }

    local ok, res = chargeOrDebt(src, cid, tax, reason, CFG.Inventory.Mode, CFG.Inventory.DueDays, meta)
    if ok and CFG.General.Debug then
      dbg(('ICMS gerado: cid=%s item=%s total=%d tax=%d'):format(cid, item, _int(total, 0), tax))
    end
    log('external_inventory', ('ICMS: $%d sobre compra $%d (%s)'):format(tax, _int(total, 0), item), { citizenid = cid, src = src, meta = meta, result = res })
  end

  local purchaseEvents = {
    'ox_inventory:server:buyItem',
    'ox_inventory:shopPurchase',
    'ox_inventory:server:shopPurchase',
    'ox_inventory:buyItem',
  }

  for _, ev in ipairs(purchaseEvents) do
    listen(ev, handlePurchaseEvent)
  end

  return true
end

--============================================================
-- 3) VEÍCULOS (compra) - hooks “best-effort”
--============================================================
External.Vehicles = External.Vehicles or { Enabled = false }

local function calcIPVA(price)
  price = _num(price, 0)
  if price < _num(CFG.Vehicles.MinVehiclePrice, 1000) then return 0 end
  return math.floor(price * (_num(CFG.Vehicles.TaxRate, 1.5) / 100.0) + 0.00001)
end

local function initVehicleSystems()
  if not CFG.Vehicles.Enabled then
    dbg('vehicles: integração desativada no config')
    return false
  end

  local hasAny =
    (GetResourceState('rhd_garage') == 'started')
    or (GetResourceState('rm-dealership') == 'started')
    or (GetResourceState('qb-vehicleshop') == 'started')
    or (GetResourceState('qbx-vehicleshop') == 'started')

  if not hasAny then
    dbg('vehicles: nenhum sistema detectado (rhd_garage/rm-dealership/qb-vehicleshop/qbx-vehicleshop)')
    return false
  end

  External.Vehicles.Enabled = true
  dbg('✓ vehicle systems detectados: habilitando hooks...')

  local function handleVehiclePurchase(...)
    if not CFG.Vehicles.TaxOnPurchase then return end

    local args = { ... }
    local src = getSrcFromEvent(args[1])
    if src <= 0 then return end

    local data = nil
    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    local price = _num((data and (data.price or data.value or data.cost)) or args[3] or args[2], 0)
    local model = (data and (data.model or data.vehicle or data.spawncode)) or args[2] or 'vehicle'
    local plate = (data and (data.plate or data.plateText)) or nil

    local ipva = calcIPVA(price)
    if ipva <= 0 then return end

    local cid = getCitizenIdSafe(src, data and (data.citizenid or data.owner))
    if not cid then return end

    local key = dedupeKey('vehicle_ipva_purchase', cid, ipva, tostring(plate or model))
    if isDuplicate(key) then return end

    local reason = ('IPVA - %s'):format(tostring(model))
    local meta = {
      source = 'vehicle_purchase',
      kind = 'ipva_purchase',
      vehicle_model = tostring(model),
      vehicle_plate = plate,
      vehicle_price = _int(price, 0),
      tax_rate = _num(CFG.Vehicles.TaxRate, 1.5),
    }

    local ok, res = chargeOrDebt(src, cid, ipva, reason, CFG.Vehicles.Mode, CFG.Vehicles.DueDays, meta)
    if ok then
      notify(src, ('IPVA gerado: $%d'):format(ipva), 'inform')
      log('external_vehicles', ('IPVA: $%d (modelo=%s placa=%s)'):format(ipva, tostring(model), tostring(plate)), { citizenid = cid, src = src, meta = meta, result = res })
    end
  end

  local evs = {
    -- rhd_garage (varia por fork)
    'rhd_garage:server:vehiclePurchased',
    'rhd_garage:server:buyVehicle',

    -- rm-dealership
    'rm-dealership:server:buyVehicle',
    'rm-dealership:server:vehiclePurchased',

    -- qb/qbx vehicleshop (variações)
    'qb-vehicleshop:server:buyVehicle',
    'qbx-vehicleshop:server:buyVehicle',
  }

  for _, ev in ipairs(evs) do
    listen(ev, handleVehiclePurchase)
  end

  -- Export manual
  External.Vehicles.ChargeIPVA = function(src, plate, vehiclePrice, model)
    local s = tonumber(src) or 0
    if s <= 0 then return false, 'invalid_src' end

    local cid = getCitizenIdSafe(s, nil)
    if not cid then return false, 'no_citizenid' end

    local ipva = calcIPVA(vehiclePrice)
    if ipva <= 0 then return false, 'no_tax' end

    local reason = ('IPVA - %s'):format(tostring(model or plate or 'Veículo'))
    local meta = {
      source = 'manual',
      kind = 'ipva_manual',
      vehicle_plate = plate,
      vehicle_model = model,
      vehicle_price = _int(vehiclePrice, 0),
      tax_rate = _num(CFG.Vehicles.TaxRate, 1.5),
    }

    local ok, res = chargeOrDebt(s, cid, ipva, reason, CFG.Vehicles.Mode, CFG.Vehicles.DueDays, meta)
    return ok, ipva, res
  end

  return true
end

--============================================================
-- 4) HOUSING (ps-housing) - compra
--============================================================
External.Housing = External.Housing or { Enabled = false }

local function calcIPTU(price)
  price = _num(price, 0)
  if price < _num(CFG.Housing.MinPropertyPrice, 5000) then return 0 end
  return math.floor(price * (_num(CFG.Housing.TaxRate, 0.3) / 100.0) + 0.00001)
end

local function initPsHousing()
  if not CFG.Housing.Enabled then
    dbg('ps-housing: integração desativada no config')
    return false
  end

  if GetResourceState('ps-housing') ~= 'started' then
    dbg('ps-housing não está started')
    return false
  end

  External.Housing.Enabled = true
  dbg('✓ ps-housing detectado: habilitando hooks...')

  local function handlePropertyPurchase(...)
    if not CFG.Housing.TaxOnPurchase then return end

    local args = { ... }
    local src = getSrcFromEvent(args[1])
    if src <= 0 then return end

    local data = nil
    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    local price = _num((data and (data.price or data.value)) or args[2] or 0, 0)
    local label = (data and (data.address or data.street or data.label or data.name)) or 'Propriedade'
    local propId = (data and (data.property_id or data.propertyId or data.property)) or nil

    local iptu = calcIPTU(price)
    if iptu <= 0 then return end

    local cid = getCitizenIdSafe(src, data and (data.citizenid or data.owner_citizenid or data.owner))
    if not cid then return end

    local key = dedupeKey('housing_iptu_purchase', cid, iptu, tostring(propId or label))
    if isDuplicate(key) then return end

    local reason = ('IPTU - %s'):format(tostring(label))
    local meta = {
      source = 'ps-housing',
      kind = 'iptu_purchase',
      property_id = propId,
      property_label = tostring(label),
      property_price = _int(price, 0),
      tax_rate = _num(CFG.Housing.TaxRate, 0.3),
    }

    local ok, res = chargeOrDebt(src, cid, iptu, reason, CFG.Housing.Mode, CFG.Housing.DueDays, meta)
    if ok then
      notify(src, ('IPTU gerado: $%d'):format(iptu), 'inform')
      log('external_housing', ('IPTU: $%d (%s)'):format(iptu, tostring(label)), { citizenid = cid, src = src, meta = meta, result = res })
    end
  end

  local evs = {
    'ps-housing:server:purchaseProperty',
    'ps-housing:buyProperty',
    'ps-housing:server:buyProperty',
  }

  for _, ev in ipairs(evs) do
    listen(ev, handlePropertyPurchase)
  end

  -- Export manual
  External.Housing.ChargeIPTU = function(src, propertyId, propertyPrice, label)
    local s = tonumber(src) or 0
    if s <= 0 then return false, 'invalid_src' end

    local cid = getCitizenIdSafe(s, nil)
    if not cid then return false, 'no_citizenid' end

    local iptu = calcIPTU(propertyPrice)
    if iptu <= 0 then return false, 'no_tax' end

    local reason = ('IPTU - %s'):format(tostring(label or propertyId or 'Propriedade'))
    local meta = {
      source = 'manual',
      kind = 'iptu_manual',
      property_id = propertyId,
      property_label = label,
      property_price = _int(propertyPrice, 0),
      tax_rate = _num(CFG.Housing.TaxRate, 0.3),
    }

    local ok, res = chargeOrDebt(s, cid, iptu, reason, CFG.Housing.Mode, CFG.Housing.DueDays, meta)
    return ok, iptu, res
  end

  return true
end

--============================================================
-- 5) MANAGEMENT (klb-management) - serviços e folha
--============================================================
External.Management = External.Management or { Enabled = false }

local function initKlbManagement()
  if not CFG.Management.Enabled then
    dbg('klb-management: integração desativada no config')
    return false
  end

  if GetResourceState('klb-management') ~= 'started' then
    dbg('klb-management não está started')
    return false
  end

  External.Management.Enabled = true
  dbg('✓ klb-management detectado: habilitando hooks...')

  local function handleServicePay(...)
    if not CFG.Management.TaxServices then return end

    local args = { ... }
    local src = getSrcFromEvent(args[1])
    if src <= 0 then return end

    local data = nil
    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    local amount = _num((data and (data.amount or data.value)) or args[2] or 0, 0)
    if amount < _num(CFG.Management.MinServiceValue, 100) then return end

    local rate = _num(CFG.Management.ServiceTaxRate, 2.0)
    local iss = math.floor(amount * (rate / 100.0) + 0.00001)
    if iss <= 0 then return end

    local cid = getCitizenIdSafe(src, data and (data.citizenid or data.identifier))
    if not cid then return end

    local svc = (data and (data.service or data.type or data.label)) or 'Serviço'
    local key = dedupeKey('mgmt_iss', cid, iss, tostring(svc))
    if isDuplicate(key) then return end

    local reason = ('ISS - Serviço: %s'):format(tostring(svc))
    local meta = {
      source = 'klb-management',
      kind = 'service_tax',
      service = tostring(svc),
      base_amount = _int(amount, 0),
      tax_rate = rate,
      company = data and (data.company or data.business) or nil,
    }

    local ok, res = chargeOrDebt(src, cid, iss, reason, CFG.Management.Mode, CFG.Management.DueDays, meta)
    if ok then
      notify(src, ('ISS gerado: $%d'):format(iss), 'inform')
      log('external_management', ('ISS: $%d sobre serviço $%d'):format(iss, _int(amount, 0)), { citizenid = cid, src = src, meta = meta, result = res })
    end
  end

  local evs = {
    'klb-management:server:payService',
    'klb-management:server:servicePaid',
  }

  for _, ev in ipairs(evs) do
    listen(ev, handleServicePay)
  end

  return true
end

--============================================================
-- 6) PS-MDT (multas)
--============================================================
External.Police = External.Police or { Enabled = false }

local function initPsMdt()
  if not CFG.Police.Enabled then
    dbg('ps-mdt: integração desativada no config')
    return false
  end

  if GetResourceState('ps-mdt') ~= 'started' then
    dbg('ps-mdt não está started')
    return false
  end

  External.Police.Enabled = true
  dbg('✓ ps-mdt detectado: habilitando hooks...')

  local function handleFineCreate(...)
    if not CFG.Police.AutoCreateDebt then return end

    local args = { ... }
    local src = getSrcFromEvent(args[1]) -- policial (pode ser 0 se server)
    local data = nil

    for i = 1, #args do
      if type(args[i]) == 'table' then data = args[i]; break end
    end

    local targetCid =
      (data and (data.targetCid or data.citizenid or data.cid))
      or (args[2] and type(args[2]) == 'table' and (args[2].citizenid or args[2].cid))
      or nil

    local fineData =
      (args[3] and type(args[3]) == 'table' and args[3])
      or (data and data.fineData)
      or data

    local amount = _num(fineData and (fineData.amount or fineData.fine), 0)
    if amount <= 0 then return end

    amount = math.floor(amount * _num(CFG.Police.FineMultiplier, 1.0) + 0.00001)
    if amount <= 0 then return end

    if not targetCid or tostring(targetCid) == '' then return end
    targetCid = tostring(targetCid)

    local reason = (fineData and (fineData.reason or fineData.description or fineData.label)) or 'Multa'
    local key = dedupeKey('mdt_fine', targetCid, amount, tostring(reason))
    if isDuplicate(key) then return end

    local officerCid = (src > 0) and getCitizenIdSafe(src, nil) or 'SYSTEM'

    local meta = {
      source = 'ps-mdt',
      kind = 'fine',
      officer = officerCid,
      base_amount = _int(amount, 0),
      reason = tostring(reason),
    }

    -- aqui src pode ser 0 (policial offline/server), então usamos modo "debt" direto
    local okDebt, debtId = createDebt(targetCid, amount, ('Multa: %s'):format(tostring(reason)), CFG.Police.DueDays, meta)
    if okDebt then
      log('external_police', ('Multa gerada: $%d (%s)'):format(amount, tostring(reason)), { target = targetCid, officer = officerCid, debt_id = debtId, meta = meta })
    end
  end

  local evs = {
    'ps-mdt:server:createFine',
    'ps-mdt:server:addFine',
    'ps-mdt:server:addCharge',
  }

  for _, ev in ipairs(evs) do
    listen(ev, handleFineCreate)
  end

  return true
end

--============================================================
-- EXPORTS (uso manual / scripts externos)
--============================================================
function External.TaxTransfer(src, amount, targetAccount)
  if not External.Banking.Enabled then return false, 'banking_not_enabled' end

  local s = tonumber(src) or 0
  if s <= 0 then return false, 'invalid_src' end

  amount = _num(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  if amount < _num(CFG.Banking.TransferMinBase, 100) then return false, 'below_min_base' end

  local tax = calcPercentTax(amount, CFG.Banking.TransferTaxRate, CFG.Banking.TransferMinTax)
  if tax <= 0 then return false, 'no_tax' end

  local cid = getCitizenIdSafe(s, nil)
  if not cid then return false, 'no_citizenid' end

  local meta = { source = 'manual', kind = 'transfer_tax', base_amount = amount, tax_rate = CFG.Banking.TransferTaxRate, target = targetAccount }
  local ok, res = chargeOrDebt(s, cid, tax, 'IOF - Transferência Bancária', CFG.Banking.Mode, CFG.Banking.DueDays, meta)
  return ok, tax, res
end

function External.TaxPurchase(src, itemName, price, quantity)
  if not External.Inventory.Enabled then return false, 'inventory_not_enabled' end

  local s = tonumber(src) or 0
  if s <= 0 then return false, 'invalid_src' end

  itemName = tostring(itemName or '')
  if itemName == '' then return false, 'invalid_item' end
  if isExemptItem(itemName) then return false, 'exempt' end

  local qty = _int(quantity, 1)
  local unit = _num(price, 0)
  local total = unit * math.max(qty, 1)
  if total <= 0 then return false, 'invalid_price' end

  local tax = math.floor(total * (_num(CFG.Inventory.TaxRate, 12.0) / 100.0) + 0.00001)
  if tax <= 0 then return false, 'no_tax' end

  local cid = getCitizenIdSafe(s, nil)
  if not cid then return false, 'no_citizenid' end

  local meta = { source = 'manual', kind = 'purchase_tax', item = itemName, quantity = qty, base_total = total, tax_rate = CFG.Inventory.TaxRate }
  local ok, res = chargeOrDebt(s, cid, tax, ('ICMS - %s'):format(itemName), CFG.Inventory.Mode, CFG.Inventory.DueDays, meta)
  return ok, tax, res
end

function External.ChargeIPVA(src, plate, vehiclePrice, model)
  if not External.Vehicles.Enabled or not External.Vehicles.ChargeIPVA then return false, 'vehicles_not_enabled' end
  return External.Vehicles.ChargeIPVA(src, plate, vehiclePrice, model)
end

function External.ChargeIPTU(src, propertyId, propertyPrice, label)
  if not External.Housing.Enabled or not External.Housing.ChargeIPTU then return false, 'housing_not_enabled' end
  return External.Housing.ChargeIPTU(src, propertyId, propertyPrice, label)
end

function External.CreateFine(targetCid, amount, reason, officerSrc)
  if not External.Police.Enabled then return false, 'police_not_enabled' end

  targetCid = tostring(targetCid or '')
  if targetCid == '' then return false, 'invalid_target' end

  amount = _num(amount, 0)
  if amount <= 0 then return false, 'invalid_amount' end

  amount = math.floor(amount * _num(CFG.Police.FineMultiplier, 1.0) + 0.00001)
  if amount <= 0 then return false, 'invalid_amount' end

  local officerCid = (officerSrc and tonumber(officerSrc) and tonumber(officerSrc) > 0)
    and (getCitizenIdSafe(tonumber(officerSrc), nil) or 'OFFICER')
    or 'SYSTEM'

  local meta = { source = 'manual', kind = 'fine_manual', officer = officerCid, reason = reason }
  local okDebt, debtId = createDebt(targetCid, amount, ('Multa: %s'):format(tostring(reason or 'Administrativa')), CFG.Police.DueDays, meta)
  return okDebt, amount, debtId
end

exports('TaxTransfer', External.TaxTransfer)
exports('TaxPurchase', External.TaxPurchase)
exports('ChargeIPVA', External.ChargeIPVA)
exports('ChargeIPTU', External.ChargeIPTU)
exports('CreateFine', External.CreateFine)

exports('GetIntegrationStatus', function()
  return {
    banking = External.Banking.Enabled == true,
    inventory = External.Inventory.Enabled == true,
    vehicles = External.Vehicles.Enabled == true,
    housing = External.Housing.Enabled == true,
    management = External.Management.Enabled == true,
    police = External.Police.Enabled == true,
  }
end)

--============================================================
-- Inicialização
--============================================================
CreateThread(function()
  Wait(_int(CFG.General.StartDelayMs, 2000))

  if not CFG.General.Enabled then
    dbg('Integrações externas: DESABILITADAS (CFG.General.Enabled=false)')
    return
  end

  dbg('==========================================================')
  dbg('Inicializando Integrações Externas (REESCRITO)...')
  dbg('Debug:', CFG.General.Debug == true and 'ON' or 'OFF')
  dbg('==========================================================')

  local list = {
    { name = 'ps-banking', fn = initPsBanking },
    { name = 'ox_inventory', fn = initOxInventory },
    { name = 'vehicle systems', fn = initVehicleSystems },
    { name = 'ps-housing', fn = initPsHousing },
    { name = 'klb-management', fn = initKlbManagement },
    { name = 'ps-mdt', fn = initPsMdt },
  }

  local okCount = 0
  for _, it in ipairs(list) do
    local ok, res = pcall(it.fn)
    if ok and res then
      okCount = okCount + 1
    end
  end

  dbg('==========================================================')
  dbg(('%d/%d integrações ativas'):format(okCount, #list))
  dbg('==========================================================')
end)

dbg('[space_economy] external_integrations.lua carregado (REESCRITO)')
