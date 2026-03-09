-- ============================================
-- SPACE ECONOMY - DATABASE DIRECT INTEGRATIONS (QBOX Hardened)
-- Versão: 3.1.0-DB (sem goto / sem hitch)
-- ============================================

SE = SE or {}
SE.DBIntegrations = SE.DBIntegrations or {}
local DBInt = SE.DBIntegrations
local RES = GetCurrentResourceName()

DBInt.Config = {
  Enabled = true,
  BatchSize = 100,
  DebugMode = true,
  DueDays = 7,

  IOF  = { rate = 0.5, minTax = 10, minAmount = 100 },
  IPVA = { rate = 1.5, fallbackPrice = 50000 },
  IPTU = { rate = 0.3 },

  Systems = {
    ['ps-banking'] = { enabled = true, table = 'ps_banking_transactions', interval = 60000,  processor = 'ProcessBankingTransactions' },
    ['dealership'] = { enabled = true, table = 'player_vehicles',         interval = 120000, processor = 'ProcessVehicleIPVA' },
    ['properties'] = { enabled = true, table = 'properties',              interval = 120000, processor = 'ProcessPropertyIPTU' }
  }
}

local function DeepMerge(dst, src)
  if type(dst) ~= 'table' then dst = {} end
  if type(src) ~= 'table' then return dst end
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      dst[k] = DeepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

if Config then
  local overrides = Config.DBIntegrations or (Config.Integrations and Config.Integrations.DBIntegrations)
  if overrides then
    DBInt.Config = DeepMerge(DBInt.Config, overrides)
  end
end

DBInt.State = {
  active = true,
  initialized = false,
  running = {},
  lastCheck = {},
  stats = { totalProcessed = 0, totalErrors = 0, bySystem = {} },
  schema = { tables = {}, columns = {}, loaded = false },
  cache = { vehiclePrice = {} }
}

-- ===== utils anti-nil
local function SafeStr(v, fb) if v == nil then return fb or '' end v=tostring(v) if v=='' then return fb or '' end return v end
local function SafeNum(v, fb) v=tonumber(v) if not v then return fb or 0 end return v end
local function NowStr() return os.date('%Y-%m-%d %H:%M:%S') end
local function PeriodMonth() return os.date('%Y%m') end
local function PeriodYear() return os.date('%Y') end
local function JsonEncodeSafe(t)
  if not json or not json.encode then return '{}' end
  local ok, out = pcall(function() return json.encode(t or {}) end)
  return ok and out or '{}'
end

local function TrimKey(s, maxLen)
  s = SafeStr(s, '')
  s = s:gsub('%s+', ' '):gsub('[\r\n\t]', ' ')
  s = s:gsub('[^%w%-%_:%|%.,#@ ]', '')
  s = s:gsub(' ', '_')
  if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
  return s
end

local function Hash32(str)
  str = SafeStr(str, '')
  local hash = 2166136261
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    hash = (hash * 16777619) % 4294967296
  end
  return string.format('%08x', hash)
end

function DBInt.Debug(msg, data)
  if not DBInt.Config.DebugMode then return end
  print(('[^3SPACE ECONOMY DB-INT^7] %s'):format(msg))
  if data ~= nil then print(JsonEncodeSafe(data)) end
end

function DBInt.Error(msg, err)
  print(('[^1SPACE ECONOMY DB-INT ERRO^7] %s'):format(msg))
  if err ~= nil then
    print(('[^1SPACE ECONOMY DB-INT ERRO^7] Detalhe: %s'):format(SafeStr(err, 'desconhecido')))
  end
end

local function HasMySQL()
  return MySQL and MySQL.query and MySQL.query.await and MySQL.scalar and MySQL.scalar.await and MySQL.update and MySQL.update.await and MySQL.insert and MySQL.insert.await
end

-- ===== camada de dados unificada
SE.DB = SE.DB or {}
local DB = SE.DB

DB.State = {
  tables = {},
  columns = {},
}

local function GetDatabaseConfig()
  return (Config and Config.Database) or {}
end

local function TableExists(tableName)
  if DB.State.tables[tableName] ~= nil then
    return DB.State.tables[tableName]
  end

  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { tableName })
  end)

  local exists = ok and rows and #rows > 0
  DB.State.tables[tableName] = exists and true or false
  return DB.State.tables[tableName]
end

local function LoadColumns(tableName)
  if DB.State.columns[tableName] then
    return DB.State.columns[tableName]
  end

  if not TableExists(tableName) then
    DB.State.columns[tableName] = false
    return nil
  end

  local ok, cols = pcall(function()
    return MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName))
  end)

  if not ok or not cols then
    DB.State.columns[tableName] = false
    return nil
  end

  local map = {}
  for _, row in ipairs(cols) do
    if row and row.Field then
      map[row.Field] = true
    end
  end

  DB.State.columns[tableName] = map
  return map
end

local function GetPlayersMoneyTotal(playersTable)
  if not HasMySQL() then return 0 end
  if not TableExists(playersTable) then return 0 end

  local columns = LoadColumns(playersTable)
  if not columns or columns == false then return 0 end

  local selectCols = {}
  if columns.money then selectCols[#selectCols + 1] = 'money' end
  if columns.cash then selectCols[#selectCols + 1] = 'cash' end
  if columns.bank then selectCols[#selectCols + 1] = 'bank' end

  if #selectCols == 0 then return 0 end

  local sql = ('SELECT %s FROM `%s`'):format(table.concat(selectCols, ', '), playersTable)
  local ok, rows = pcall(function() return MySQL.query.await(sql) end)
  if not ok or not rows then return 0 end

  local total = 0
  for _, row in ipairs(rows) do
    local cash = 0
    local bank = 0
    local crypto = 0

    if columns.money and row.money then
      local okDecode, decoded = pcall(function() return json.decode(row.money) end)
      if okDecode and type(decoded) == 'table' then
        cash = SafeNum(decoded.cash, cash)
        bank = SafeNum(decoded.bank, bank)
        crypto = SafeNum(decoded.crypto, crypto)
      end
    end

    if columns.cash then
      cash = SafeNum(row.cash, cash)
    end

    if columns.bank then
      bank = SafeNum(row.bank, bank)
    end

    total = total + cash + bank + crypto
  end

  return total
end

function DB.GetPlayerVehicles(citizenid)
  if not HasMySQL() then return {} end
  if not citizenid or citizenid == '' then return {} end

  local dbCfg = GetDatabaseConfig()
  local vehiclesCfg = dbCfg.Vehicles or {}

  local tableName = vehiclesCfg.table or 'player_vehicles'
  local ownerColumn = vehiclesCfg.ownerColumn or 'citizenid'
  local plateColumn = vehiclesCfg.plateColumn or 'plate'
  local modelColumn = vehiclesCfg.modelColumn or 'vehicle'
  local valueColumn = vehiclesCfg.valueColumn or 'depotprice'

  if not TableExists(tableName) then return {} end

  local fallbackPrice = SafeNum(DBInt.Config and DBInt.Config.IPVA and DBInt.Config.IPVA.fallbackPrice, 50000)
  local sql = ('SELECT `%s` AS plate, `%s` AS model, COALESCE(NULLIF(`%s`, 0), ?) AS price FROM `%s` WHERE `%s` = ?'):format(
    plateColumn,
    modelColumn,
    valueColumn,
    tableName,
    ownerColumn
  )

  local ok, rows = pcall(function()
    return MySQL.query.await(sql, { fallbackPrice, citizenid })
  end)

  if not ok or not rows then return {} end

  for _, row in ipairs(rows) do
    row.price = SafeNum(row.price, fallbackPrice)
  end

  return rows
end

function DB.GetPlayerProperties(citizenid)
  if not HasMySQL() then return {} end
  if not citizenid or citizenid == '' then return {} end

  local dbCfg = GetDatabaseConfig()
  local propertiesCfg = dbCfg.Properties or {}

  local tableName = propertiesCfg.table or 'properties'
  local ownerColumn = propertiesCfg.ownerColumn or 'owner_citizenid'
  local priceColumn = propertiesCfg.priceColumn or 'price'
  local nameColumn = propertiesCfg.nameColumn or 'label'

  if not TableExists(tableName) then return {} end

  local columns = LoadColumns(tableName)
  local idColumn = (columns and columns.property_id) and 'property_id' or nil

  local selectCols = {
    ('`%s` AS label'):format(nameColumn),
    ('COALESCE(`%s`, 0) AS price'):format(priceColumn),
  }
  if idColumn then
    selectCols[#selectCols + 1] = ('`%s` AS id'):format(idColumn)
  end

  local sql = ('SELECT %s FROM `%s` WHERE `%s` = ?'):format(
    table.concat(selectCols, ', '),
    tableName,
    ownerColumn
  )

  local ok, rows = pcall(function()
    return MySQL.query.await(sql, { citizenid })
  end)

  if not ok or not rows then return {} end

  for _, row in ipairs(rows) do
    row.price = SafeNum(row.price, 0)
  end

  return rows
end

function DB.GetAllCompanies()
  if not HasMySQL() then return {} end

  local dbCfg = GetDatabaseConfig()
  local sources = dbCfg.Societies or { 'management_funds', 'ps_banking_accounts' }
  local companies = {}

  for _, source in ipairs(sources) do
    if source == 'management_funds' and TableExists('management_funds') then
      local ok, rows = pcall(function()
        return MySQL.query.await([[
          SELECT job_name AS name, COALESCE(amount, 0) AS balance, type
          FROM management_funds
        ]])
      end)

      if ok and rows then
        for _, row in ipairs(rows) do
          if row and row.name then
            companies[#companies + 1] = {
              name = SafeStr(row.name, ''),
              balance = SafeNum(row.balance, 0),
              source = 'management_funds',
              type = SafeStr(row.type, ''),
            }
          end
        end
      end
    elseif source == 'ps_banking_accounts' and TableExists('ps_banking_accounts') then
      local ok, rows = pcall(function()
        return MySQL.query.await([[
          SELECT holder AS name, COALESCE(balance, 0) AS balance
          FROM ps_banking_accounts
        ]])
      end)

      if ok and rows then
        for _, row in ipairs(rows) do
          if row and row.name then
            companies[#companies + 1] = {
              name = SafeStr(row.name, ''),
              balance = SafeNum(row.balance, 0),
              source = 'ps_banking_accounts',
            }
          end
        end
      end
    end
  end

  return companies
end

function DB.GetTotalMoneySupply()
  if not HasMySQL() then
    return {
      playerMoney = 0,
      managementFunds = 0,
      bankingFunds = 0,
      companyMoney = 0,
      total = 0,
    }
  end

  local dbCfg = GetDatabaseConfig()
  local playersTable = dbCfg.Players or 'players'

  local playerMoney = GetPlayersMoneyTotal(playersTable)
  local companies = DB.GetAllCompanies()

  local managementFunds = 0
  local bankingFunds = 0

  for _, company in ipairs(companies) do
    if company.source == 'management_funds' then
      managementFunds = managementFunds + SafeNum(company.balance, 0)
    elseif company.source == 'ps_banking_accounts' then
      bankingFunds = bankingFunds + SafeNum(company.balance, 0)
    end
  end

  local companyMoney = managementFunds + bankingFunds

  return {
    playerMoney = playerMoney,
    managementFunds = managementFunds,
    bankingFunds = bankingFunds,
    companyMoney = companyMoney,
    total = playerMoney + companyMoney,
  }
end

function DB.GetPlayerBankBalance(citizenid)
  if not HasMySQL() then return 0 end
  citizenid = SafeStr(citizenid, '')
  if citizenid == '' then return 0 end

  local dbCfg = GetDatabaseConfig()
  local playersTable = dbCfg.Players or 'players'

  if not TableExists(playersTable) then return 0 end

  local columns = LoadColumns(playersTable)
  if not columns or columns == false then return 0 end

  local selectCols = {}
  if columns.money then selectCols[#selectCols + 1] = 'money' end
  if columns.bank then selectCols[#selectCols + 1] = 'bank' end

  if #selectCols == 0 then return 0 end

  local sql = ('SELECT %s FROM `%s` WHERE citizenid = ? LIMIT 1'):format(
    table.concat(selectCols, ', '),
    playersTable
  )

  local ok, row = pcall(function()
    return MySQL.single.await(sql, { citizenid })
  end)
  if not ok or not row then return 0 end

  local bank = 0
  if columns.money and row.money then
    local okDecode, decoded = pcall(function() return json.decode(row.money) end)
    if okDecode and type(decoded) == 'table' then
      bank = SafeNum(decoded.bank, bank)
    end
  end

  if columns.bank then
    bank = SafeNum(row.bank, bank)
  end

  return bank
end

function DB.GetExternalDebts(citizenid)
  if not HasMySQL() then return 0 end
  citizenid = SafeStr(citizenid, '')
  if citizenid == '' then return 0 end
  if not TableExists('ps_banking_bills') then return 0 end

  local total = MySQL.scalar.await([[
    SELECT COALESCE(SUM(amount), 0)
    FROM ps_banking_bills
    WHERE identifier = ? AND isPaid = 0
  ]], { citizenid })

  return SafeNum(total, 0)
end

function DB.GetFinancingDebt(citizenid)
  if not HasMySQL() then return 0 end
  citizenid = SafeStr(citizenid, '')
  if citizenid == '' then return 0 end
  if not TableExists('vehicle_financing') or not TableExists('player_vehicles') then return 0 end

  local total = MySQL.scalar.await([[
    SELECT COALESCE(SUM(vf.balance), 0)
    FROM vehicle_financing vf
    INNER JOIN player_vehicles pv ON vf.vehicleId = pv.id
    WHERE pv.citizenid = ?
  ]], { citizenid })

  return SafeNum(total, 0)
end

function DB.GetTotalExternalDebts()
  if not HasMySQL() then return 0 end
  if not TableExists('ps_banking_bills') then return 0 end

  local total = MySQL.scalar.await([[
    SELECT COALESCE(SUM(amount), 0)
    FROM ps_banking_bills
    WHERE isPaid = 0
  ]])

  return SafeNum(total, 0)
end

function DB.GetTotalFinancingDebt()
  if not HasMySQL() then return 0 end
  if not TableExists('vehicle_financing') then return 0 end

  local total = MySQL.scalar.await([[
    SELECT COALESCE(SUM(balance), 0)
    FROM vehicle_financing
  ]])

  return SafeNum(total, 0)
end

-- ===== schema (sem information_schema)
function DBInt.TableExists(tableName)
  if DBInt.State.schema.tables[tableName] ~= nil then
    return DBInt.State.schema.tables[tableName]
  end

  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { tableName })
  end)

  local exists = ok and rows and #rows > 0
  DBInt.State.schema.tables[tableName] = exists and true or false
  return DBInt.State.schema.tables[tableName]
end

function DBInt.LoadColumns(tableName)
  DBInt.State.schema.columns[tableName] = DBInt.State.schema.columns[tableName] or {}

  local ok, cols = pcall(function()
    return MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName))
  end)

  if not ok or not cols then
    DBInt.Error(('Falha ao ler colunas de `%s` (permissão/ausência?)'):format(tableName), cols)
    DBInt.State.schema.tables[tableName] = false
    return false
  end

  DBInt.State.schema.tables[tableName] = true
  for _, row in ipairs(cols) do
    if row and row.Field then
      DBInt.State.schema.columns[tableName][row.Field] = true
    end
  end
  return true
end

local function HasColumn(tableName, col)
  local t = DBInt.State.schema.columns[tableName]
  return t and t[col] == true
end

local function PickColumn(tableName, candidates)
  for _, c in ipairs(candidates) do
    if HasColumn(tableName, c) then return c end
  end
  return nil
end

function DBInt.RefreshSchema()
  DBInt.TableExists('space_economy_processed_transactions')
  DBInt.TableExists('space_economy_integration_config')

  for _, sys in pairs(DBInt.Config.Systems) do
    if DBInt.TableExists(sys.table) then
      DBInt.LoadColumns(sys.table)
    end
  end

  if DBInt.TableExists('vehicles_data') then DBInt.LoadColumns('vehicles_data') end
  if DBInt.TableExists('dealership_vehicles') then DBInt.LoadColumns('dealership_vehicles') end

  DBInt.State.schema.loaded = true
end

-- ===== control tables
function DBInt.EnsureConfigRow(systemName)
  MySQL.insert.await([[
    INSERT IGNORE INTO space_economy_integration_config (source_system, enabled, last_check, total_processed, total_errors)
    VALUES (?, 1, NOW(), 0, 0)
  ]], { systemName })
end

function DBInt.IsProcessed(sourceSystem, transactionId)
  local v = MySQL.scalar.await([[
    SELECT 1 FROM space_economy_processed_transactions
     WHERE source_system = ? AND transaction_id = ?
     LIMIT 1
  ]], { sourceSystem, transactionId })
  return v ~= nil
end

function DBInt.MarkAsProcessed(data)
  local ok, err = pcall(function()
    MySQL.insert.await([[
      INSERT IGNORE INTO space_economy_processed_transactions
        (source_system, transaction_id, transaction_type, citizenid, amount, tax_amount, tax_type, debt_id, transaction_date, metadata)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      SafeStr(data.source_system, 'unknown'),
      SafeStr(data.transaction_id, 'unknown'),
      SafeStr(data.transaction_type, 'unknown'),
      SafeStr(data.citizenid, 'unknown'),
      SafeNum(data.amount, 0),
      SafeNum(data.tax_amount, 0),
      SafeStr(data.tax_type, 'NA'),
      data.debt_id,
      data.transaction_date or NowStr(),
      JsonEncodeSafe(data.metadata or {})
    })
  end)

  if not ok then
    DBInt.Error('Falha ao salvar transação processada', err)
    return false
  end
  return true
end

function DBInt.UpdateStats(systemName, processedDelta, errorsDelta, lastTxDate)
  processedDelta = SafeNum(processedDelta, 0)
  errorsDelta = SafeNum(errorsDelta, 0)

  DBInt.EnsureConfigRow(systemName)

  MySQL.update.await([[
    UPDATE space_economy_integration_config
       SET last_check = NOW(),
           total_processed = total_processed + ?,
           total_errors = total_errors + ?,
           last_transaction_date = COALESCE(?, last_transaction_date)
     WHERE source_system = ?
  ]], { processedDelta, errorsDelta, lastTxDate, systemName })
end

function DBInt.GetLastTransactionDate(systemName)
  DBInt.EnsureConfigRow(systemName)
  return MySQL.scalar.await([[
    SELECT COALESCE(last_transaction_date, DATE_SUB(NOW(), INTERVAL 30 DAY))
      FROM space_economy_integration_config
     WHERE source_system = ?
  ]], { systemName })
end

-- ===== debts
function DBInt.CreateDebt(citizenid, amount, reason, taxType, metadata)
  citizenid = SafeStr(citizenid, '')
  amount = SafeNum(amount, 0)

  if citizenid == '' or amount <= 0 then
    DBInt.Error('CreateDebt: citizenid/valor inválido', JsonEncodeSafe({ citizenid = citizenid, amount = amount }))
    return nil
  end

  if not SE.Debts or not SE.Debts.Upsert then
    DBInt.Error('SE.Debts.Upsert não está disponível (Space Economy não carregou?)')
    return nil
  end

  local dueTimestamp = os.time() + (DBInt.Config.DueDays * 24 * 60 * 60)

  metadata = metadata or {}
  metadata.tax_type = taxType
  metadata.auto_generated = true
  metadata.source = 'db_integration'
  metadata.resource = RES

  local debtId = SE.Debts.Upsert(citizenid, amount, reason, dueTimestamp, metadata)
  if debtId then
    DBInt.Debug(('Dívida criada: ID=%s | Cidadão=%s | Valor=$%d | Tipo=%s'):format(
      SafeStr(debtId, '?'), citizenid, amount, SafeStr(taxType, 'NA')
    ))
  end
  return debtId
end

-- ===== price lookup
function DBInt.GetVehiclePrice(model)
  model = SafeStr(model, '')
  if model == '' then return nil end
  if DBInt.State.cache.vehiclePrice[model] ~= nil then
    return DBInt.State.cache.vehiclePrice[model]
  end

  local price

  if DBInt.State.schema.tables['vehicles_data'] then
    local colModel = PickColumn('vehicles_data', { 'model' })
    local colPrice = PickColumn('vehicles_data', { 'price' })
    if colModel and colPrice then
      price = MySQL.scalar.await(
        ('SELECT `%s` FROM vehicles_data WHERE `%s` = ? LIMIT 1'):format(colPrice, colModel),
        { model }
      )
    end
  end

  if (not price) and DBInt.State.schema.tables['dealership_vehicles'] then
    local colModel = PickColumn('dealership_vehicles', { 'model', 'vehicle', 'spawncode' })
    local colPrice = PickColumn('dealership_vehicles', { 'price', 'cost', 'value' })
    if colModel and colPrice then
      price = MySQL.scalar.await(
        ('SELECT `%s` FROM dealership_vehicles WHERE `%s` = ? LIMIT 1'):format(colPrice, colModel),
        { model }
      )
    end
  end

  price = price and SafeNum(price, nil) or nil
  DBInt.State.cache.vehiclePrice[model] = price
  return price
end

-- ============================================
-- PROCESSORS (sem goto)
-- ============================================

function DBInt.ProcessBankingTransactions()
  local systemName = 'ps-banking'
  DBInt.Debug('Iniciando processamento de transações bancárias (IOF)...')

  local processed, errors = 0, 0
  local lastCheck = DBInt.GetLastTransactionDate(systemName)

  local txs = MySQL.query.await([[
    SELECT id,
           identifier as citizenid,
           type,
           amount,
           date as transaction_date,
           description,
           isIncome
      FROM ps_banking_transactions
     WHERE date > ?
       AND amount > 0
       AND type = 'bank'
       AND isIncome = 0
     ORDER BY date ASC
     LIMIT ?
  ]], { lastCheck, DBInt.Config.BatchSize })

  if not txs or #txs == 0 then
    DBInt.Debug('Nenhuma transação bancária nova encontrada')
    return 0, 0, nil
  end

  DBInt.Debug(('Encontradas %d transações bancárias para processar'):format(#txs))

  local newestDate = nil

  for i, tx in ipairs(txs) do
    repeat
      local txId = SafeStr(tx.id, '')
      local citizenid = SafeStr(tx.citizenid, '')
      local amount = SafeNum(tx.amount, 0)
      local txDate = SafeStr(tx.transaction_date, NowStr())
      newestDate = txDate

      if txId == '' or citizenid == '' then
        errors = errors + 1
        break
      end

      local transactionId = ('iof:%s'):format(txId)
      if DBInt.IsProcessed(systemName, transactionId) then break end

      local taxRate = DBInt.Config.IOF.rate
      local minTax = DBInt.Config.IOF.minTax
      local minAmount = DBInt.Config.IOF.minAmount

      local taxAmount = math.max(math.floor(amount * (taxRate / 100)), minTax)

      if amount >= minAmount and taxAmount > 0 then
        local reason = 'IOF - Transação bancária'
        local metadata = {
          original_amount = amount,
          description = SafeStr(tx.description, ''),
          tax_rate = taxRate,
          transaction_date = txDate
        }

        local debtId = DBInt.CreateDebt(citizenid, taxAmount, reason, 'IOF', metadata)
        if debtId then
          DBInt.MarkAsProcessed({
            source_system = systemName,
            transaction_id = transactionId,
            transaction_type = SafeStr(tx.type, 'bank'),
            citizenid = citizenid,
            amount = amount,
            tax_amount = taxAmount,
            tax_type = 'IOF',
            debt_id = debtId,
            transaction_date = txDate,
            metadata = metadata
          })
          processed = processed + 1
        else
          errors = errors + 1
        end
      else
        DBInt.MarkAsProcessed({
          source_system = systemName,
          transaction_id = transactionId,
          transaction_type = SafeStr(tx.type, 'bank'),
          citizenid = citizenid,
          amount = amount,
          tax_amount = 0,
          tax_type = 'IOF',
          debt_id = nil,
          transaction_date = txDate,
          metadata = { note = 'Valor abaixo do mínimo para cobrança de IOF' }
        })
      end
    until true

    if i % 25 == 0 then Wait(0) end
  end

  return processed, errors, newestDate
end

function DBInt.ProcessVehicleIPVA()
  local systemName = 'dealership'
  DBInt.Debug('Iniciando processamento de veículos (IPVA anual)...')

  local processed, errors = 0, 0
  local year = PeriodYear()

  if not DBInt.State.schema.loaded then DBInt.RefreshSchema() end
  if not DBInt.State.schema.tables['player_vehicles'] then
    DBInt.Error('Tabela player_vehicles não encontrada; IPVA ignorado.')
    return 0, 1, nil
  end

  local t = 'player_vehicles'
  local colId      = PickColumn(t, { 'id', 'vehicleid' })
  local colCitizen = PickColumn(t, { 'citizenid', 'owner', 'identifier' })
  local colVehicle = PickColumn(t, { 'vehicle', 'model' })
  local colPlate   = PickColumn(t, { 'plate', 'plateText' })
  local colLast    = PickColumn(t, { 'last_ipva_at' })
  local colPrice   = PickColumn(t, { 'price', 'buy_price', 'value' })

  if not colCitizen or not colVehicle then
    DBInt.Error('player_vehicles sem citizenid/vehicle (colunas não encontradas).')
    return 0, 1, nil
  end

  local whereExtra = ''
  if colLast then
    whereExtra = (' AND (`%s` IS NULL OR `%s` < DATE_SUB(NOW(), INTERVAL 30 DAY)) '):format(colLast, colLast)
  end

  local sql = ([[
    SELECT %s AS row_id,
           `%s` AS citizenid,
           `%s` AS vehicle,
           %s AS plate,
           %s AS last_ipva_at,
           %s AS stored_price
      FROM player_vehicles
     WHERE `%s` IS NOT NULL AND `%s` != ''
       %s
     LIMIT ?
  ]]):format(
    colId and ('`'..colId..'`') or 'NULL',
    colCitizen,
    colVehicle,
    colPlate and ('`'..colPlate..'`') or 'NULL',
    colLast and ('`'..colLast..'`') or 'NULL',
    colPrice and ('`'..colPrice..'`') or 'NULL',
    colCitizen, colCitizen,
    whereExtra
  )

  local vehicles = MySQL.query.await(sql, { DBInt.Config.BatchSize })
  if not vehicles or #vehicles == 0 then
    DBInt.Debug('Nenhum veículo pendente de IPVA encontrado')
    return 0, 0, nil
  end

  DBInt.Debug(('Encontrados %d veículos para IPVA'):format(#vehicles))

  for i, veh in ipairs(vehicles) do
    repeat
      local citizenid = SafeStr(veh.citizenid, '')
      local model = SafeStr(veh.vehicle, '')
      local plate = SafeStr(veh.plate, '')
      local rowId = SafeStr(veh.row_id, '')

      if citizenid == '' or model == '' then
        errors = errors + 1
        break
      end

      local key = (plate ~= '' and plate) or (rowId ~= '' and ('id'..rowId)) or ('idx'..i)
      key = TrimKey(key, 64)

      local transactionId = ('ipva:%s:%s'):format(year, key)
      if DBInt.IsProcessed(systemName, transactionId) then break end

      local basePrice = SafeNum(veh.stored_price, 0)
      if basePrice <= 0 then
        basePrice = DBInt.GetVehiclePrice(model) or DBInt.Config.IPVA.fallbackPrice
      end
      basePrice = SafeNum(basePrice, DBInt.Config.IPVA.fallbackPrice)

      local taxRate = DBInt.Config.IPVA.rate
      local taxAmount = math.floor(basePrice * (taxRate / 100))

      if taxAmount <= 0 then
        DBInt.MarkAsProcessed({
          source_system = systemName,
          transaction_id = transactionId,
          transaction_type = 'ipva_anual',
          citizenid = citizenid,
          amount = basePrice,
          tax_amount = 0,
          tax_type = 'IPVA',
          debt_id = nil,
          transaction_date = NowStr(),
          metadata = { note = 'IPVA zerado (base inválida)', model = model, plate = plate, year = year }
        })
        break
      end

      local reason = ('IPVA anual (%s) - Veículo %s (%s)'):format(year, model, plate ~= '' and plate or key)
      local metadata = { vehicle = model, plate = plate, base_price = basePrice, tax_rate = taxRate, year = year }

      local debtId = DBInt.CreateDebt(citizenid, taxAmount, reason, 'IPVA', metadata)
      if debtId then
        if colLast and colId and rowId ~= '' then
          MySQL.update.await(
            ('UPDATE player_vehicles SET `%s` = NOW() WHERE `%s` = ?'):format(colLast, colId),
            { rowId }
          )
        end

        DBInt.MarkAsProcessed({
          source_system = systemName,
          transaction_id = transactionId,
          transaction_type = 'ipva_anual',
          citizenid = citizenid,
          amount = basePrice,
          tax_amount = taxAmount,
          tax_type = 'IPVA',
          debt_id = debtId,
          transaction_date = NowStr(),
          metadata = metadata
        })

        processed = processed + 1
      else
        errors = errors + 1
      end
    until true

    if i % 25 == 0 then Wait(0) end
  end

  return processed, errors, nil
end

function DBInt.ProcessPropertyIPTU()
  local systemName = 'properties'
  DBInt.Debug('Iniciando processamento de propriedades (IPTU mensal)...')

  local processed, errors = 0, 0
  local period = PeriodMonth()

  if not DBInt.State.schema.loaded then DBInt.RefreshSchema() end
  if not DBInt.State.schema.tables['properties'] then
    DBInt.Error('Tabela properties não encontrada; IPTU ignorado.')
    return 0, 1, nil
  end

  local props = MySQL.query.await([[
    SELECT property_id,
           owner_citizenid as citizenid,
           street,
           region,
           apartment,
           description,
           price
      FROM properties
     WHERE owner_citizenid IS NOT NULL
       AND owner_citizenid != ''
       AND price IS NOT NULL
       AND price > 0
     LIMIT ?
  ]], { DBInt.Config.BatchSize })

  if not props or #props == 0 then
    DBInt.Debug('Nenhuma propriedade encontrada para IPTU')
    return 0, 0, nil
  end

  DBInt.Debug(('Encontradas %d propriedades para IPTU'):format(#props))

  for i, prop in ipairs(props) do
    repeat
      local citizenid = SafeStr(prop.citizenid, '')
      local price = SafeNum(prop.price, 0)
      local propertyId = SafeStr(prop.property_id, '')

      if citizenid == '' or price <= 0 then
        errors = errors + 1
        break
      end

      local display = SafeStr(prop.apartment, '')
      if display == '' then display = SafeStr(prop.street, '') end
      if display == '' then display = SafeStr(prop.region, '') end
      if display == '' then display = ('ID %s'):format(propertyId ~= '' and propertyId or 'desconhecido') end

      local key = (propertyId ~= '' and ('id'..propertyId)) or ('h'..Hash32(citizenid..'|'..display..'|'..price))
      key = TrimKey(key, 72)

      local transactionId = ('iptu:%s:%s'):format(period, key)
      if DBInt.IsProcessed(systemName, transactionId) then break end

      local taxRate = DBInt.Config.IPTU.rate
      local taxAmount = math.floor(price * (taxRate / 100))

      if taxAmount <= 0 then
        DBInt.MarkAsProcessed({
          source_system = systemName,
          transaction_id = transactionId,
          transaction_type = 'iptu_mensal',
          citizenid = citizenid,
          amount = price,
          tax_amount = 0,
          tax_type = 'IPTU',
          debt_id = nil,
          transaction_date = NowStr(),
          metadata = { note = 'IPTU zerado (base inválida)', period = period, price = price }
        })
        break
      end

      local reason = ('IPTU mensal (%s/%s) - Imóvel %s'):format(os.date('%m'), os.date('%Y'), display)
      local metadata = {
        property_id = prop.property_id,
        street = prop.street,
        region = prop.region,
        apartment = prop.apartment,
        description = prop.description,
        price = price,
        tax_rate = taxRate,
        period = period
      }

      local debtId = DBInt.CreateDebt(citizenid, taxAmount, reason, 'IPTU', metadata)
      if debtId then
        DBInt.MarkAsProcessed({
          source_system = systemName,
          transaction_id = transactionId,
          transaction_type = 'iptu_mensal',
          citizenid = citizenid,
          amount = price,
          tax_amount = taxAmount,
          tax_type = 'IPTU',
          debt_id = debtId,
          transaction_date = NowStr(),
          metadata = metadata
        })
        processed = processed + 1
      else
        errors = errors + 1
      end
    until true

    if i % 25 == 0 then Wait(0) end
  end

  return processed, errors, nil
end

-- ============================================
-- Scheduler
-- ============================================
function DBInt.CheckSystem(systemName)
  local sys = DBInt.Config.Systems[systemName]
  if not sys or not sys.enabled then return end

  if DBInt.State.running[systemName] then
    DBInt.Debug(('Sistema %s já está em execução; pulando.'):format(systemName))
    return
  end

  DBInt.State.running[systemName] = true

  local ok, processed, errors, lastTxDate = pcall(function()
    if not DBInt[sys.processor] then
      error(('Processador não encontrado: %s'):format(sys.processor))
    end
    return DBInt[sys.processor]()
  end)

  if ok then
    processed = SafeNum(processed, 0)
    errors = SafeNum(errors, 0)

    DBInt.UpdateStats(systemName, processed, errors, lastTxDate)

    DBInt.State.stats.totalProcessed = DBInt.State.stats.totalProcessed + processed
    DBInt.State.stats.totalErrors = DBInt.State.stats.totalErrors + errors
    DBInt.State.stats.bySystem[systemName] = (DBInt.State.stats.bySystem[systemName] or 0) + processed

    DBInt.Debug(('Finalizado %s: processados=%d | erros=%d'):format(systemName, processed, errors))
  else
    DBInt.Error(('Erro ao processar %s'):format(systemName), processed)
    DBInt.UpdateStats(systemName, 0, 1, nil)
    DBInt.State.stats.totalErrors = DBInt.State.stats.totalErrors + 1
  end

  DBInt.State.running[systemName] = false
  DBInt.State.lastCheck[systemName] = os.time()
end

function DBInt.StartSchedulers()
  if not DBInt.Config.Enabled then
    print('[^3SPACE ECONOMY DB-INT^7] Integração DB: DESABILITADA')
    return
  end

  if DBInt.State.schedulersStarted then
    DBInt.Debug('Schedulers já iniciados; evitando duplicação.')
    return
  end

  DBInt.State.schedulersStarted = true
  DBInt.State.active = true
  print('[^2SPACE ECONOMY DB-INT^7] Iniciando schedulers de integração...')

  for systemName, sys in pairs(DBInt.Config.Systems) do
    if sys.enabled then
      CreateThread(function()
        Wait(10000)
        DBInt.Debug(('Scheduler ativo: %s (intervalo %dms)'):format(systemName, sys.interval))
        while DBInt.State.active do
          DBInt.CheckSystem(systemName)
          Wait(sys.interval)
        end
        DBInt.Debug(('Scheduler encerrado: %s'):format(systemName))
      end)
    end
  end
end

function DBInt.StopSchedulers()
  if not DBInt.State.schedulersStarted then return end
  DBInt.State.active = false
  DBInt.State.schedulersStarted = false
  print('[^3SPACE ECONOMY DB-INT^7] Schedulers finalizados.')
end

function DBInt.Initialize()
  if DBInt.State.initialized then return end

  if not HasMySQL() then
    DBInt.Error('MySQL não disponível. Verifique oxmysql e fxmanifest.')
    return
  end

  print('[^2SPACE ECONOMY DB-INT^7] Inicializando integração com banco de dados...')

  CreateThread(function()
    Wait(3000)

    if not DBInt.TableExists('space_economy_processed_transactions') then
      DBInt.Error('Tabela space_economy_processed_transactions não encontrada! Execute sql/db_integrations.sql')
      return
    end

    if not DBInt.TableExists('space_economy_integration_config') then
      DBInt.Error('Tabela space_economy_integration_config não encontrada! Execute sql/db_integrations.sql')
      return
    end

    DBInt.RefreshSchema()

    for systemName, _ in pairs(DBInt.Config.Systems) do
      DBInt.EnsureConfigRow(systemName)
    end

    DBInt.State.initialized = true
    DBInt.StartSchedulers()

    print('[^2SPACE ECONOMY DB-INT^7] Integração inicializada com sucesso!')
  end)
end

RegisterCommand('se:checkintegrations', function(source)
  if source ~= 0 then return end
  print('[^2SPACE ECONOMY DB-INT^7] Forçando verificação manual...')
  for systemName, _ in pairs(DBInt.Config.Systems) do
    DBInt.CheckSystem(systemName)
  end
  print('[^2SPACE ECONOMY DB-INT^7] Verificação manual concluída!')
end, true)

CreateThread(function()
  Wait(1000)
  DBInt.Initialize()
end)

exports('GetDBIntegrationStats', function()
  return DBInt.State.stats
end)

exports('ForceCheckSystem', function(systemName)
  if DBInt.Config.Systems[systemName] then
    DBInt.CheckSystem(systemName)
    return true
  end
  return false
end)


AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  DBInt.StopSchedulers()
end)

print('[^2SPACE ECONOMY^7] db_integrations.lua carregado (QBOX Hardened / sem goto)')
