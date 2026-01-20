--============================================================
-- space_economy - server/hooks.lua
-- Hooks universais para capturar transações econômicas
--============================================================
SE = SE or {}
SE.Hooks = SE.Hooks or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config or {}

local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^3[hooks]^7', ...) end
end

local function normalize(text)
  return tostring(text or ''):lower()
end

local function containsAny(text, list)
  text = normalize(text)
  for _, entry in ipairs(list or {}) do
    if text:find(normalize(entry), 1, true) then
      return true
    end
  end
  return false
end

local function isIllegalReason(reason)
  if not (cfg.IllegalMoney and cfg.IllegalMoney.Enabled) then return false end
  return containsAny(reason, cfg.IllegalMoney.Reasons)
end

local function classifyCategory(resourceName, reason)
  local res = normalize(resourceName)
  local rea = normalize(reason)

  if res:find('vehicleshop') or res:find('vehshop') then
    return 'compra_veiculo'
  end
  if res:find('housing') or res:find('realestate') or res:find('property') then
    return 'compra_imovel'
  end
  if res:find('mechanic') or res:find('repair') then
    return 'servico_mecanico'
  end
  if res:find('ambulance') or res:find('hospital') then
    return 'servico_hospital'
  end
  if res:find('fuel') or res:find('gas') or rea:find('combustivel') then
    return 'combustivel'
  end
  if res:find('food') or res:find('restaurant') or rea:find('aliment') then
    return 'alimentacao'
  end
  if res:find('mining') or rea:find('minerio') or rea:find('mining') then
    return 'mineracao'
  end
  if rea:find('servico') then
    return 'servico_geral'
  end
  if rea:find('imposto') or rea:find('tax') then
    return 'imposto'
  end

  return 'compra_item'
end

local function shouldTrack(reason)
  local rea = normalize(reason)
  return rea:find('compra') or rea:find('imposto') or rea:find('servico')
end

local function registerTransaction(src, amount, reason, resourceName, extra)
  if not (SE.EconomyMonitor and SE.EconomyMonitor.RegisterTransaction) then return end

  amount = math.abs(U.toInt(amount, 0))
  if amount <= 0 then return end

  if not shouldTrack(reason) then return end

  local category = classifyCategory(resourceName, reason)
  local meta = {
    reason = reason,
    resource = resourceName,
    citizenid = B and B.GetCitizenId and B.GetCitizenId(src) or nil,
  }

  if type(extra) == 'table' then
    for k, v in pairs(extra) do meta[k] = v end
  end

  SE.EconomyMonitor.RegisterTransaction(category, amount, meta)
end

local function handleIllegalMoney(src, amount, reason, resourceName)
  if not isIllegalReason(reason) then return end

  TriggerEvent('space_economy:server_illegalMoneyAlert', {
    source = src,
    amount = amount,
    reason = reason,
    resource = resourceName,
    citizenid = B and B.GetCitizenId and B.GetCitizenId(src) or nil,
  })
end

local function handleMoneyChange(src, account, amount, action, reason)
  if not src or not amount then return end
  local res = GetInvokingResource() or 'unknown'
  local normalizedAction = normalize(action)

  if amount < 0 or normalizedAction == 'remove' then
    registerTransaction(src, amount, reason, res, { account = account })
    handleIllegalMoney(src, amount, reason, res)
  end
end

--============================================================
-- Hooks QBCore / QBX
--============================================================
AddEventHandler('QBCore:Server:OnMoneyChange', function(src, account, amount, action, reason)
  handleMoneyChange(src, account, amount, action, reason)
end)

--============================================================
-- Hooks ESX
--============================================================
AddEventHandler('esx:removeAccountMoney', function(src, account, amount, reason)
  handleMoneyChange(src, account, -math.abs(amount or 0), 'remove', reason)
end)

AddEventHandler('esx:removeMoney', function(src, amount, reason)
  handleMoneyChange(src, 'cash', -math.abs(amount or 0), 'remove', reason)
end)

--============================================================
-- Hooks ox_inventory (troca de dinheiro por item em lojas NPC)
--============================================================
AddEventHandler('ox_inventory:swapItems', function(data)
  if not data then return end

  local fromSlot = data.fromSlot or {}
  if normalize(fromSlot.name) ~= 'money' then return end

  local amount = tonumber(fromSlot.count or data.count or data.fromCount) or 0
  if amount <= 0 then return end

  local res = tostring(data.fromInventory or data.toInventory or data.inventory or 'ox_inventory')
  registerTransaction(data.source or 0, amount, 'compra', res, {
    item = (data.toSlot and data.toSlot.name) or data.toSlotName or 'item',
    shop = data.shop or data.shopType or nil,
  })
end)

--============================================================
-- Log inicial
--============================================================
dbg(('Hooks ativos (%s)'):format(B and B.GetFrameworkName and B.GetFrameworkName() or 'unknown'))
