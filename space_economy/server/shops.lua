--============================================================
-- space_economy - server/shops.lua
-- Sistema de lojas para players venderem itens
--============================================================

SE = SE or {}
SE.Shops = SE.Shops or {}

local U = SE.Util or {}
local B = SE.Bridge or {}

local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^3[shops]^7', ...) end
end

local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_shops (
      id INT AUTO_INCREMENT PRIMARY KEY,
      owner_citizenid VARCHAR(64) NOT NULL,
      name VARCHAR(64) NOT NULL,
      location JSON NULL,
      settings JSON NULL,
      balance BIGINT NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_owner (owner_citizenid)
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_shop_products (
      id INT AUTO_INCREMENT PRIMARY KEY,
      shop_id INT NOT NULL,
      item VARCHAR(64) NOT NULL,
      label VARCHAR(64) NULL,
      price BIGINT NOT NULL,
      stock INT NOT NULL DEFAULT 0,
      metadata JSON NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY unique_shop_product (shop_id, item),
      INDEX idx_shop_id (shop_id)
    )
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_shop_sales (
      id INT AUTO_INCREMENT PRIMARY KEY,
      shop_id INT NOT NULL,
      buyer_citizenid VARCHAR(64) NOT NULL,
      item VARCHAR(64) NOT NULL,
      quantity INT NOT NULL,
      price BIGINT NOT NULL,
      total BIGINT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_shop_id (shop_id),
      INDEX idx_buyer (buyer_citizenid),
      INDEX idx_date (created_at)
    )
  ]])

  dbg('Shop schema ensured')
end

function SE.Shops.CreateShop(src, name)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  name = U.trim and U.trim(name) or name
  if not name or name == '' then return false, 'invalid_name' end

  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  if not citizenid then return false, 'invalid_citizenid' end

  -- Check if player already has a shop
  local existing = MySQL.scalar.await(
    'SELECT COUNT(*) FROM space_economy_shops WHERE owner_citizenid = ?',
    { citizenid }
  )

  if existing and existing >= 3 then
    return false, 'max_shops_reached'
  end

  local shopId = MySQL.insert.await(
    'INSERT INTO space_economy_shops (owner_citizenid, name) VALUES (?, ?)',
    { citizenid, name }
  )

  if not shopId then return false, 'db_error' end

  dbg(('Shop created: %s for %s'):format(name, citizenid))
  return true, shopId
end

function SE.Shops.GetPlayerShops(citizenid)
  ensureSchema()
  if not MySQL then return {} end

  local shops = MySQL.query.await([[
    SELECT s.*,
      (SELECT COUNT(*) FROM space_economy_shop_products WHERE shop_id = s.id) as productsCount,
      (SELECT COALESCE(SUM(total), 0) FROM space_economy_shop_sales WHERE shop_id = s.id AND DATE(created_at) = CURDATE()) as salesToday
    FROM space_economy_shops s
    WHERE s.owner_citizenid = ?
    ORDER BY s.id DESC
  ]], { citizenid })

  return shops or {}
end

function SE.Shops.GetShop(shopId)
  ensureSchema()
  if not MySQL then return nil end

  local shop = MySQL.single.await(
    'SELECT * FROM space_economy_shops WHERE id = ? LIMIT 1',
    { shopId }
  )

  return shop
end

function SE.Shops.AddProduct(shopId, item, price, stock, label, metadata)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  item = U.trim and U.trim(item) or item
  if not item or item == '' then return false, 'invalid_item' end

  price = U.toInt and U.toInt(price, 0) or tonumber(price) or 0
  if price <= 0 then return false, 'invalid_price' end

  stock = U.toInt and U.toInt(stock, 0) or tonumber(stock) or 0
  if stock <= 0 then return false, 'invalid_stock' end

  -- Check if product already exists
  local existing = MySQL.single.await(
    'SELECT id, stock FROM space_economy_shop_products WHERE shop_id = ? AND item = ? LIMIT 1',
    { shopId, item }
  )

  if existing then
    -- Update stock
    MySQL.update.await(
      'UPDATE space_economy_shop_products SET stock = stock + ?, price = ? WHERE id = ?',
      { stock, price, existing.id }
    )
    return true
  end

  -- Insert new product
  MySQL.insert.await(
    'INSERT INTO space_economy_shop_products (shop_id, item, label, price, stock, metadata) VALUES (?, ?, ?, ?, ?, ?)',
    { shopId, item, label, price, stock, metadata }
  )

  return true
end

function SE.Shops.GetProducts(shopId)
  ensureSchema()
  if not MySQL then return {} end

  local products = MySQL.query.await(
    'SELECT * FROM space_economy_shop_products WHERE shop_id = ? ORDER BY item ASC',
    { shopId }
  )

  return products or {}
end

function SE.Shops.BuyProduct(src, shopId, item, quantity)
  ensureSchema()
  if not MySQL then return false, 'no_database' end

  quantity = U.toInt and U.toInt(quantity, 1) or tonumber(quantity) or 1
  if quantity <= 0 then return false, 'invalid_quantity' end

  local product = MySQL.single.await(
    'SELECT * FROM space_economy_shop_products WHERE shop_id = ? AND item = ? LIMIT 1',
    { shopId, item }
  )

  if not product then return false, 'product_not_found' end
  if product.stock < quantity then return false, 'insufficient_stock' end

  local total = product.price * quantity

  -- Remove money from buyer
  if SE.Integrations and SE.Integrations.RemoveMoney then
    local ok, err = SE.Integrations.RemoveMoney(src, total, 'bank', 'shop_purchase')
    if not ok then return false, err or 'insufficient_funds' end
  end

  -- Add item to buyer
  if SE.Integrations and SE.Integrations.InventoryAddItem then
    local ok, err = SE.Integrations.InventoryAddItem(src, item, quantity)
    if not ok then
      -- Refund
      if SE.Integrations and SE.Integrations.AddMoney then
        SE.Integrations.AddMoney(src, total, 'bank', 'shop_purchase_refund')
      end
      return false, err or 'inventory_failed'
    end
  end

  -- Update stock
  MySQL.update.await(
    'UPDATE space_economy_shop_products SET stock = stock - ? WHERE id = ?',
    { quantity, product.id }
  )

  -- Add to shop balance
  MySQL.update.await(
    'UPDATE space_economy_shops SET balance = balance + ? WHERE id = ?',
    { total, shopId }
  )

  -- Record sale
  local citizenid = B and B.GetCitizenId and B.GetCitizenId(src)
  MySQL.insert.await(
    'INSERT INTO space_economy_shop_sales (shop_id, buyer_citizenid, item, quantity, price, total) VALUES (?, ?, ?, ?, ?, ?)',
    { shopId, citizenid, item, quantity, product.price, total }
  )

  return true, total
end

-- Export functions
exports('CreateShop', SE.Shops.CreateShop)
exports('GetPlayerShops', SE.Shops.GetPlayerShops)
exports('GetShop', SE.Shops.GetShop)
exports('AddProduct', SE.Shops.AddProduct)
exports('GetProducts', SE.Shops.GetProducts)
exports('BuyProduct', SE.Shops.BuyProduct)

dbg('shops.lua loaded')
