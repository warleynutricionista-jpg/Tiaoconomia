--============================================================
-- space_economy - server/organizations.lua
-- Sistema de organizações/empresas administradas por players
--============================================================
SE = SE or {}
SE.Organizations = SE.Organizations or {}

local Org = SE.Organizations
local U = SE.Util
local B = SE.Bridge

local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^3[organizations]^7', ...) end
end

local function notify(src, ntype, msg)
  if not src or src == 0 then return end
  TriggerClientEvent('ox_lib:notify', src, {
    type = ntype or 'info',
    description = msg
  })
end

local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_organizations (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(64) NOT NULL UNIQUE,
      tag VARCHAR(8) NOT NULL UNIQUE,
      owner_citizenid VARCHAR(64) NOT NULL,
      balance BIGINT NOT NULL DEFAULT 0,
      settings JSON NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_org_members (
      id INT AUTO_INCREMENT PRIMARY KEY,
      org_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      role VARCHAR(32) NOT NULL DEFAULT 'staff',
      permissions JSON NULL,
      joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY unique_member (org_id, citizenid),
      INDEX idx_org_id (org_id),
      INDEX idx_citizenid (citizenid)
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_org_products (
      id INT AUTO_INCREMENT PRIMARY KEY,
      org_id INT NOT NULL,
      item VARCHAR(64) NOT NULL,
      label VARCHAR(64) NULL,
      base_cost BIGINT NOT NULL DEFAULT 0,
      price BIGINT NOT NULL DEFAULT 0,
      stock INT NOT NULL DEFAULT 0,
      metadata JSON NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY unique_product (org_id, item),
      INDEX idx_org_id (org_id),
      INDEX idx_item (item)
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_org_transactions (
      id INT AUTO_INCREMENT PRIMARY KEY,
      org_id INT NOT NULL,
      citizenid VARCHAR(64) NOT NULL,
      item VARCHAR(64) NOT NULL,
      quantity INT NOT NULL,
      unit_price BIGINT NOT NULL,
      logistics_fee BIGINT NOT NULL DEFAULT 0,
      tax_amount BIGINT NOT NULL DEFAULT 0,
      total BIGINT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_org_id (org_id),
      INDEX idx_citizenid (citizenid)
    )
  ]])
end

local function getConfig()
  return (Config and Config.Organizations) or {}
end

local function getRolePermissions(role)
  local cfg = getConfig()
  local roles = cfg.Roles or {}
  return roles[role] or {}
end

local function getDefaultSettings()
  local cfg = getConfig()
  local settings = cfg.DefaultSettings or {}
  return {
    logistics = settings.logistics or { deliveryFeePercent = 0, storageFeePercent = 0, taxPercent = 0 },
    pricing = settings.pricing or { minMarkupPercent = 0 },
    governance = settings.governance or { allowMemberPricing = false },
  }
end

local function getInflationAdjustedCost(baseCost)
  baseCost = U.toInt(baseCost, 0)
  if baseCost <= 0 then baseCost = 1 end

  if SE.MonetaryPolicy and SE.MonetaryPolicy.AdjustPriceForInflation then
    return math.max(1, U.toInt(SE.MonetaryPolicy.AdjustPriceForInflation(baseCost), baseCost))
  end

  local inflation = 1.0
  if SE.Server and SE.Server.GetInflationRate then
    inflation = SE.Server.GetInflationRate() or 1.0
  elseif SE.State and SE.State.inflationRate then
    inflation = SE.State.inflationRate
  end

  return math.max(1, U.toInt(baseCost * inflation, baseCost))
end

local function getBaseCost(item)
  local cfg = getConfig()
  local baseCosts = cfg.BaseCosts or {}
  local base = baseCosts[item] or cfg.DefaultBaseCost or 0
  if base <= 0 then base = 1 end
  return getInflationAdjustedCost(base)
end

local function parseSettings(raw)
  local settings = U.safeJsonDecode(raw) or {}
  local defaults = getDefaultSettings()

  settings.logistics = settings.logistics or defaults.logistics
  settings.pricing = settings.pricing or defaults.pricing
  settings.governance = settings.governance or defaults.governance

  return settings
end

local function encodeSettings(settings)
  return U.safeJsonEncode(settings or getDefaultSettings())
end

local function getOrg(orgId)
  ensureSchema()
  if not MySQL then return nil end
  return MySQL.single.await('SELECT * FROM space_economy_organizations WHERE id = ? LIMIT 1', { orgId })
end

local function getOrgByName(name)
  ensureSchema()
  if not MySQL then return nil end
  return MySQL.single.await('SELECT * FROM space_economy_organizations WHERE name = ? LIMIT 1', { name })
end

local function getOrgByTag(tag)
  ensureSchema()
  if not MySQL then return nil end
  return MySQL.single.await('SELECT * FROM space_economy_organizations WHERE tag = ? LIMIT 1', { tag })
end

local function getMember(orgId, citizenid)
  ensureSchema()
  if not MySQL then return nil end
  return MySQL.single.await(
    'SELECT * FROM space_economy_org_members WHERE org_id = ? AND citizenid = ? LIMIT 1',
    { orgId, citizenid }
  )
end

local function hasPermission(orgId, citizenid, permission)
  local member = getMember(orgId, citizenid)
  if not member then return false end
  if member.role == 'owner' then return true end

  local rolePerms = getRolePermissions(member.role)
  if rolePerms[permission] == true then return true end

  local extra = U.safeJsonDecode(member.permissions) or {}
  return extra[permission] == true
end

local function ensureOwner(orgId, citizenid)
  local member = getMember(orgId, citizenid)
  return member and member.role == 'owner'
end

local function orgBalance(orgId)
  ensureSchema()
  if not MySQL then return 0 end
  local row = MySQL.single.await('SELECT balance FROM space_economy_organizations WHERE id = ? LIMIT 1', { orgId })
  return row and U.toInt(row.balance, 0) or 0
end

local function updateBalance(orgId, delta)
  if not MySQL then return false end
  MySQL.update.await(
    'UPDATE space_economy_organizations SET balance = balance + ? WHERE id = ?',
    { delta, orgId }
  )
  return true
end

function Org.CreateOrganization(src, name, tag, ownerCitizenId)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  local cfg = getConfig()
  if cfg.Enabled == false then return false, 'disabled' end

  name = U.trim(name or '')
  tag = U.trim(tag or '')

  if name == '' or #name < (cfg.MinNameLength or 3) or #name > (cfg.MaxNameLength or 32) then
    return false, 'invalid_name'
  end

  if tag == '' or #tag < (cfg.MinTagLength or 2) or #tag > (cfg.MaxTagLength or 6) then
    return false, 'invalid_tag'
  end

  if getOrgByName(name) then return false, 'name_exists' end
  if getOrgByTag(tag) then return false, 'tag_exists' end

  local citizenid = ownerCitizenId or (B and B.GetCitizenId and B.GetCitizenId(src))
  if not citizenid or citizenid == '' then return false, 'invalid_citizenid' end

  local creationCost = U.toInt(cfg.CreateCost, 0)
  if creationCost > 0 and src and src ~= 0 and not ownerCitizenId then
    if SE.Integrations and SE.Integrations.RemoveMoney then
      local ok, err = SE.Integrations.RemoveMoney(src, creationCost, cfg.PurchaseAccount or 'bank', 'org_create')
      if not ok then return false, err or 'insufficient_funds' end
    end
    if SE.Treasury and SE.Treasury.Deposit then
      SE.Treasury.Deposit(creationCost, 'org_create', { citizenid = citizenid, org = name })
    end
  end

  local settings = encodeSettings(getDefaultSettings())

  local insertId = MySQL.insert.await(
    'INSERT INTO space_economy_organizations (name, tag, owner_citizenid, settings) VALUES (?, ?, ?, ?)',
    { name, tag, citizenid, settings }
  )

  if not insertId then return false, 'db_error' end

  MySQL.insert.await(
    'INSERT INTO space_economy_org_members (org_id, citizenid, role) VALUES (?, ?, ?)',
    { insertId, citizenid, 'owner' }
  )

  return true, insertId
end

function Org.AddMember(orgId, citizenid, role)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  local cfg = getConfig()
  if not getOrg(orgId) then return false, 'org_not_found' end
  role = role or 'staff'

  local roles = cfg.Roles or {}
  if not roles[role] then
    role = 'staff'
  end

  local count = MySQL.scalar.await('SELECT COUNT(*) FROM space_economy_org_members WHERE org_id = ?', { orgId })
  if count and cfg.MaxMembers and count >= cfg.MaxMembers then
    return false, 'max_members'
  end

  local ok, err = pcall(function()
    MySQL.insert.await(
      'INSERT INTO space_economy_org_members (org_id, citizenid, role) VALUES (?, ?, ?)',
      { orgId, citizenid, role }
    )
  end)

  if not ok then return false, err or 'db_error' end
  return true
end

function Org.RemoveMember(orgId, citizenid)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  MySQL.update.await(
    'DELETE FROM space_economy_org_members WHERE org_id = ? AND citizenid = ?',
    { orgId, citizenid }
  )
  return true
end

function Org.UpdateLogistics(orgId, settings)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  local org = getOrg(orgId)
  if not org then return false, 'not_found' end

  local current = parseSettings(org.settings)
  current.logistics = settings

  MySQL.update.await(
    'UPDATE space_economy_organizations SET settings = ? WHERE id = ?',
    { encodeSettings(current), orgId }
  )

  return true
end

function Org.UpdatePricing(orgId, settings)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  local org = getOrg(orgId)
  if not org then return false, 'not_found' end

  local current = parseSettings(org.settings)
  current.pricing = settings

  MySQL.update.await(
    'UPDATE space_economy_organizations SET settings = ? WHERE id = ?',
    { encodeSettings(current), orgId }
  )

  return true
end

function Org.AddProduct(orgId, item, quantity, price, label, metadata)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  item = U.trim(item or '')
  if item == '' then return false, 'invalid_item' end

  quantity = U.toInt(quantity, 0)
  if quantity <= 0 then return false, 'invalid_quantity' end

  local baseCost = getBaseCost(item)
  price = U.toInt(price, baseCost)
  if price < baseCost then return false, 'price_below_cost' end

  local existing = MySQL.single.await(
    'SELECT id, base_cost, price, stock FROM space_economy_org_products WHERE org_id = ? AND item = ? LIMIT 1',
    { orgId, item }
  )

  if existing then
    local newBase = math.max(baseCost, U.toInt(existing.base_cost, baseCost))
    local newPrice = math.max(price, newBase, U.toInt(existing.price, price))
    MySQL.update.await(
      'UPDATE space_economy_org_products SET base_cost = ?, price = ?, stock = stock + ?, label = COALESCE(?, label), metadata = COALESCE(?, metadata) WHERE id = ?',
      { newBase, newPrice, quantity, label, metadata, existing.id }
    )
    return true, { base_cost = newBase, price = newPrice }
  end

  MySQL.insert.await(
    [[
      INSERT INTO space_economy_org_products (org_id, item, label, base_cost, price, stock, metadata)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ]],
    { orgId, item, label, baseCost, price, quantity, metadata }
  )

  return true, { base_cost = baseCost, price = price }
end

function Org.RestockProduct(orgId, item, quantity)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  item = U.trim(item or '')
  if item == '' then return false, 'invalid_item' end

  quantity = U.toInt(quantity, 0)
  if quantity <= 0 then return false, 'invalid_quantity' end

  local existing = MySQL.single.await(
    'SELECT id, base_cost, price FROM space_economy_org_products WHERE org_id = ? AND item = ? LIMIT 1',
    { orgId, item }
  )

  if not existing then return false, 'product_not_found' end

  local baseCost = getBaseCost(item)
  local newBase = math.max(baseCost, U.toInt(existing.base_cost, baseCost))
  local newPrice = math.max(U.toInt(existing.price, newBase), newBase)

  MySQL.update.await(
    'UPDATE space_economy_org_products SET base_cost = ?, price = ?, stock = stock + ? WHERE id = ?',
    { newBase, newPrice, quantity, existing.id }
  )

  return true, { base_cost = newBase, price = newPrice }
end

function Org.UpdatePrice(orgId, item, price)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  item = U.trim(item or '')
  if item == '' then return false, 'invalid_item' end

  price = U.toInt(price, 0)
  if price <= 0 then return false, 'invalid_price' end

  local existing = MySQL.single.await(
    'SELECT id, base_cost FROM space_economy_org_products WHERE org_id = ? AND item = ? LIMIT 1',
    { orgId, item }
  )

  if not existing then return false, 'product_not_found' end

  local baseCost = U.toInt(existing.base_cost, 0)
  if price < baseCost then return false, 'price_below_cost' end

  MySQL.update.await(
    'UPDATE space_economy_org_products SET price = ? WHERE id = ?',
    { price, existing.id }
  )

  return true
end

function Org.BuyProduct(src, orgId, item, quantity)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  local cfg = getConfig()
  if cfg.Enabled == false then return false, 'disabled' end

  item = U.trim(item or '')
  if item == '' then return false, 'invalid_item' end

  quantity = U.toInt(quantity, 0)
  if quantity <= 0 then return false, 'invalid_quantity' end

  local org = getOrg(orgId)
  if not org then return false, 'org_not_found' end

  local product = MySQL.single.await(
    'SELECT id, price, stock FROM space_economy_org_products WHERE org_id = ? AND item = ? LIMIT 1',
    { orgId, item }
  )

  if not product then return false, 'product_not_found' end
  if U.toInt(product.stock, 0) < quantity then return false, 'insufficient_stock' end

  local settings = parseSettings(org.settings)
  local unitPrice = U.toInt(product.price, 0)
  if unitPrice <= 0 then return false, 'invalid_price' end

  local subtotal = unitPrice * quantity
  local logisticsFee = math.floor(subtotal * (U.toNumber(settings.logistics.deliveryFeePercent, 0) / 100))
  local taxPercent = U.toNumber(settings.logistics.taxPercent, cfg.SalesTaxPercent or 0)
  local taxAmount = math.floor(subtotal * (taxPercent / 100))
  local total = subtotal + logisticsFee + taxAmount

  if SE.Integrations and SE.Integrations.RemoveMoney then
    local ok, err = SE.Integrations.RemoveMoney(src, total, cfg.PurchaseAccount or 'bank', 'org_purchase')
    if not ok then return false, err or 'insufficient_funds' end
  end

  if SE.Integrations and SE.Integrations.InventoryAddItem then
    local ok, err = SE.Integrations.InventoryAddItem(src, item, quantity)
    if not ok then
      if SE.Integrations and SE.Integrations.AddMoney then
        SE.Integrations.AddMoney(src, total, cfg.PurchaseAccount or 'bank', 'org_purchase_refund')
      end
      return false, err or 'inventory_failed'
    end
  end

  MySQL.update.await(
    'UPDATE space_economy_org_products SET stock = stock - ? WHERE id = ?',
    { quantity, product.id }
  )

  updateBalance(orgId, subtotal + logisticsFee - taxAmount)

  MySQL.insert.await(
    [[
      INSERT INTO space_economy_org_transactions
      (org_id, citizenid, item, quantity, unit_price, logistics_fee, tax_amount, total)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]],
    { orgId, B.GetCitizenId(src), item, quantity, unitPrice, logisticsFee, taxAmount, total }
  )

  if taxAmount > 0 and SE.Treasury and SE.Treasury.Deposit then
    SE.Treasury.Deposit(taxAmount, 'org_sale_tax', { org_id = orgId, item = item })
  end

  if SE.EconomyMonitor and SE.EconomyMonitor.RegisterTransaction then
    SE.EconomyMonitor.RegisterTransaction('organizacao_venda', subtotal, {
      org_id = orgId,
      item = item,
      quantity = quantity
    })
  end

  return true, total
end

function Org.GetOrganization(orgId)
  local org = getOrg(orgId)
  if not org then return nil end
  org.settings = parseSettings(org.settings)
  return org
end

function Org.GetProducts(orgId)
  ensureSchema()
  if not MySQL then return {} end
  local rows = MySQL.query.await(
    'SELECT item, label, base_cost, price, stock FROM space_economy_org_products WHERE org_id = ? ORDER BY item ASC',
    { orgId }
  )
  return rows or {}
end

--============================================================
-- Commands
--============================================================
RegisterCommand('org_create', function(source, args)
  local src = tonumber(source)
  if not src or src == 0 then return end

  local name = args[1]
  local tag = args[2]

  local ok, res = Org.CreateOrganization(src, name, tag)
  if not ok then
    notify(src, 'error', ('Falha ao criar organização (%s)'):format(res or 'erro'))
    return
  end

  notify(src, 'success', ('Organização criada! ID %d'):format(res))
end)

RegisterCommand('org_admin_create', function(source, args)
  local src = tonumber(source)
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed and not SE.Admin.IsAllowed(src) then
    notify(src, 'error', 'Sem permissão')
    return
  end

  local citizenid = args[1]
  local name = args[2]
  local tag = args[3]

  local ok, res = Org.CreateOrganization(src, name, tag, citizenid)
  if not ok then
    notify(src, 'error', ('Falha ao criar organização (%s)'):format(res or 'erro'))
    return
  end

  notify(src, 'success', ('Organização criada! ID %d'):format(res))
end)

RegisterCommand('org_addmember', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local citizenid = args[2]
  local role = args[3] or 'staff'

  if orgId <= 0 or not citizenid then
    notify(src, 'error', 'Uso: /org_addmember <org_id> <citizenid> [role]')
    return
  end

  local callerCid = B.GetCitizenId(src)
  if src ~= 0 and not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) then
    if not hasPermission(orgId, callerCid, 'members') then
      notify(src, 'error', 'Sem permissão para adicionar membros')
      return
    end
  end

  local ok, err = Org.AddMember(orgId, citizenid, role)
  if not ok then
    notify(src, 'error', ('Falha ao adicionar membro (%s)'):format(err or 'erro'))
    return
  end

  notify(src, 'success', 'Membro adicionado com sucesso')
end)

RegisterCommand('org_removemember', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local citizenid = args[2]

  if orgId <= 0 or not citizenid then
    notify(src, 'error', 'Uso: /org_removemember <org_id> <citizenid>')
    return
  end

  local callerCid = B.GetCitizenId(src)
  if src ~= 0 and not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) then
    if not hasPermission(orgId, callerCid, 'members') then
      notify(src, 'error', 'Sem permissão para remover membros')
      return
    end
  end

  if ensureOwner(orgId, citizenid) then
    notify(src, 'error', 'Não é possível remover o dono')
    return
  end

  Org.RemoveMember(orgId, citizenid)
  notify(src, 'success', 'Membro removido com sucesso')
end)

RegisterCommand('org_setlogistica', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local delivery = U.toNumber(args[2], 0)
  local storage = U.toNumber(args[3], 0)
  local tax = U.toNumber(args[4], 0)

  if orgId <= 0 then
    notify(src, 'error', 'Uso: /org_setlogistica <org_id> <entrega%> <armazenagem%> <taxa%>')
    return
  end

  local callerCid = B.GetCitizenId(src)
  if src ~= 0 and not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) then
    if not hasPermission(orgId, callerCid, 'logistics') then
      notify(src, 'error', 'Sem permissão para ajustar logística')
      return
    end
  end

  local settings = {
    deliveryFeePercent = U.clamp(delivery, 0, 50),
    storageFeePercent = U.clamp(storage, 0, 50),
    taxPercent = U.clamp(tax, 0, 50),
  }

  Org.UpdateLogistics(orgId, settings)
  notify(src, 'success', 'Logística atualizada')
end)

RegisterCommand('org_addproduct', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local item = args[2]
  local quantity = U.toInt(args[3], 0)
  local price = U.toInt(args[4], 0)
  local label = args[5]

  if orgId <= 0 or not item or quantity <= 0 then
    notify(src, 'error', 'Uso: /org_addproduct <org_id> <item> <quantidade> <preco> [label]')
    return
  end

  local callerCid = B.GetCitizenId(src)
  if src ~= 0 and not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) then
    if not hasPermission(orgId, callerCid, 'products') then
      notify(src, 'error', 'Sem permissão para cadastrar produtos')
      return
    end
  end

  if SE.Integrations and SE.Integrations.InventoryHasItem then
    if not SE.Integrations.InventoryHasItem(src, item, quantity) then
      notify(src, 'error', 'Itens insuficientes no inventário')
      return
    end
  end

  if SE.Integrations and SE.Integrations.InventoryRemoveItem then
    local ok, err = SE.Integrations.InventoryRemoveItem(src, item, quantity)
    if not ok then
      notify(src, 'error', ('Falha ao remover itens (%s)'):format(err or 'erro'))
      return
    end
  end

  local ok, res = Org.AddProduct(orgId, item, quantity, price, label)
  if not ok then
    notify(src, 'error', ('Falha ao adicionar produto (%s)'):format(res or 'erro'))
    return
  end

  notify(src, 'success', 'Produto adicionado ao catálogo')
end)

RegisterCommand('org_restock', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local item = args[2]
  local quantity = U.toInt(args[3], 0)

  if orgId <= 0 or not item or quantity <= 0 then
    notify(src, 'error', 'Uso: /org_restock <org_id> <item> <quantidade>')
    return
  end

  local callerCid = B.GetCitizenId(src)
  if src ~= 0 and not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) then
    if not hasPermission(orgId, callerCid, 'products') then
      notify(src, 'error', 'Sem permissão para repor estoque')
      return
    end
  end

  if SE.Integrations and SE.Integrations.InventoryHasItem then
    if not SE.Integrations.InventoryHasItem(src, item, quantity) then
      notify(src, 'error', 'Itens insuficientes no inventário')
      return
    end
  end

  if SE.Integrations and SE.Integrations.InventoryRemoveItem then
    local ok, err = SE.Integrations.InventoryRemoveItem(src, item, quantity)
    if not ok then
      notify(src, 'error', ('Falha ao remover itens (%s)'):format(err or 'erro'))
      return
    end
  end

  local ok, res = Org.RestockProduct(orgId, item, quantity)
  if not ok then
    notify(src, 'error', ('Falha ao repor estoque (%s)'):format(res or 'erro'))
    return
  end

  notify(src, 'success', 'Estoque atualizado')
end)

RegisterCommand('org_setprice', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local item = args[2]
  local price = U.toInt(args[3], 0)

  if orgId <= 0 or not item or price <= 0 then
    notify(src, 'error', 'Uso: /org_setprice <org_id> <item> <preco>')
    return
  end

  local callerCid = B.GetCitizenId(src)
  if src ~= 0 and not (SE.Admin and SE.Admin.IsAllowed and SE.Admin.IsAllowed(src)) then
    if not hasPermission(orgId, callerCid, 'products') then
      notify(src, 'error', 'Sem permissão para alterar preços')
      return
    end
  end

  local ok, err = Org.UpdatePrice(orgId, item, price)
  if not ok then
    notify(src, 'error', ('Falha ao atualizar preço (%s)'):format(err or 'erro'))
    return
  end

  notify(src, 'success', 'Preço atualizado')
end)

RegisterCommand('org_buy', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)
  local item = args[2]
  local quantity = U.toInt(args[3], 1)

  if orgId <= 0 or not item then
    notify(src, 'error', 'Uso: /org_buy <org_id> <item> [quantidade]')
    return
  end

  local ok, total = Org.BuyProduct(src, orgId, item, quantity)
  if not ok then
    notify(src, 'error', ('Compra não realizada (%s)'):format(total or 'erro'))
    return
  end

  notify(src, 'success', ('Compra realizada! Total: $%d'):format(total))
end)

RegisterCommand('org_info', function(source, args)
  local src = tonumber(source)
  local orgId = U.toInt(args[1], 0)

  if orgId <= 0 then
    notify(src, 'error', 'Uso: /org_info <org_id>')
    return
  end

  local org = Org.GetOrganization(orgId)
  if not org then
    notify(src, 'error', 'Organização não encontrada')
    return
  end

  local bal = orgBalance(orgId)
  notify(src, 'info', ('%s [%s] | Saldo: $%d'):format(org.name, org.tag, bal))
end)

--============================================================
-- Exports
--============================================================
exports('CreateOrganization', Org.CreateOrganization)
exports('GetOrganization', Org.GetOrganization)
exports('GetOrganizationProducts', Org.GetProducts)
exports('AddOrganizationProduct', Org.AddProduct)
exports('BuyOrganizationProduct', Org.BuyProduct)
exports('GetOrganizationBalance', orgBalance)
