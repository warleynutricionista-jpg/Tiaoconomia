--============================================================
-- space_economy - server/wealth_tax.lua
-- Imposto sobre grandes fortunas + taxa de ociosidade
--============================================================
SE = SE or {}
SE.WealthTax = SE.WealthTax or {}

local WT = SE.WealthTax
local U = SE.Util or {}
local B = SE.Bridge or {}
local cfg = Config or {}

local function hasMySQL()
  return MySQL
    and MySQL.query and MySQL.query.await
    and MySQL.single and MySQL.single.await
    and MySQL.scalar and MySQL.scalar.await
    and MySQL.insert and MySQL.insert.await
    and MySQL.update and MySQL.update.await
end

local function tableExists(name)
  if not hasMySQL() then return false end
  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)
  return ok and rows and #rows > 0
end

local function columnsOf(tableName)
  if not hasMySQL() then return {} end
  local ok, cols = pcall(function()
    return MySQL.query.await(('SHOW COLUMNS FROM `%s`'):format(tableName))
  end)
  local out = {}
  if ok and cols then
    for _, c in ipairs(cols) do
      if c and c.Field then out[c.Field] = true end
    end
  end
  return out
end

local function pickColumn(cols, candidates)
  for _, name in ipairs(candidates) do
    if cols[name] then return name end
  end
  return nil
end

local function toInt(v, d)
  if U and U.toInt then return U.toInt(v, d or 0) end
  v = tonumber(v)
  if not v then return d or 0 end
  return math.floor(v)
end

local function toNumber(v, d)
  if U and U.toNumber then return U.toNumber(v, d) end
  v = tonumber(v)
  if not v then return d end
  return v
end

local function safeJsonDecode(v)
  if U and U.safeJsonDecode then return U.safeJsonDecode(v) end
  if json and json.decode then
    local ok, out = pcall(function() return json.decode(v or '{}') end)
    return ok and out or {}
  end
  return {}
end

local function safeJsonEncode(v)
  if U and U.safeJsonEncode then return U.safeJsonEncode(v) end
  if json and json.encode then
    local ok, out = pcall(function() return json.encode(v or {}) end)
    return ok and out or '{}'
  end
  return '{}'
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

local function getLastSeenTimestamp(row, columns)
  local candidates = {
    'last_login',
    'last_updated',
    'last_seen',
    'updated_at',
    'last_login_at',
  }

  local col = pickColumn(columns, candidates)
  if not col then return nil end
  return parseDateTime(row[col])
end

local function getPlayerMoney(row)
  local cash = 0
  local bank = 0

  if row.money then
    local decoded = safeJsonDecode(row.money)
    if type(decoded) == 'table' then
      cash = toInt(decoded.cash, 0)
      bank = toInt(decoded.bank, 0)
    end
  end

  if row.cash ~= nil then
    cash = toInt(row.cash, cash)
  end

  if row.bank ~= nil then
    bank = toInt(row.bank, bank)
  end

  return cash, bank
end

local function updatePlayerMoney(citizenid, columns, newCash, newBank, existingMoney)
  if not hasMySQL() then return false end
  if not citizenid or citizenid == '' then return false end

  local updates = {}
  local params = {}

  if columns.money then
    local money = existingMoney or {}
    money.cash = newCash
    money.bank = newBank
    updates[#updates + 1] = '`money` = ?'
    params[#params + 1] = safeJsonEncode(money)
  end

  if columns.cash then
    updates[#updates + 1] = '`cash` = ?'
    params[#params + 1] = newCash
  end

  if columns.bank then
    updates[#updates + 1] = '`bank` = ?'
    params[#params + 1] = newBank
  end

  if #updates == 0 then return false end

  params[#params + 1] = citizenid
  local sql = ('UPDATE players SET %s WHERE citizenid = ?'):format(table.concat(updates, ', '))
  local ok = pcall(function() MySQL.update.await(sql, params) end)
  return ok
end

local function countMoneyTables()
  local columns = columnsOf('players')
  return columns
end

local function getAllPlayers(columns)
  if not hasMySQL() or not tableExists('players') then return {}, columns end

  local selectCols = { 'citizenid' }
  if columns.money then selectCols[#selectCols + 1] = 'money' end
  if columns.cash then selectCols[#selectCols + 1] = 'cash' end
  if columns.bank then selectCols[#selectCols + 1] = 'bank' end

  local lastSeenCol = pickColumn(columns, {
    'last_login',
    'last_updated',
    'last_seen',
    'updated_at',
    'last_login_at',
  })
  if lastSeenCol then selectCols[#selectCols + 1] = lastSeenCol end

  local sql = ('SELECT %s FROM players'):format(table.concat(selectCols, ', '))
  local rows = MySQL.query.await(sql) or {}
  return rows, columns
end

local function getAssetTotals(tableName, priceColumnCandidates)
  if not tableExists(tableName) then return {} end

  -- Detecta dinamicamente qual coluna de preço existe na tabela
  local cols = columnsOf(tableName)
  local priceColumn = pickColumn(cols, priceColumnCandidates)

  -- Se não encontrar coluna de preço, retorna vazio
  if not priceColumn then
    print('^3[wealth_tax]^7 Aviso: Nenhuma coluna de preço encontrada em ' .. tableName)
    return {}
  end

  -- Verifica se tem coluna citizenid
  local citizenCol = pickColumn(cols, {'citizenid', 'owner', 'identifier'})
  if not citizenCol then
    print('^3[wealth_tax]^7 Aviso: Nenhuma coluna de cidadão encontrada em ' .. tableName)
    return {}
  end

  local sql = ('SELECT `%s` as citizenid, COALESCE(SUM(`%s`),0) as total, COUNT(*) as count FROM `%s` GROUP BY `%s`'):format(
    citizenCol,
    priceColumn,
    tableName,
    citizenCol
  )
  local rows = MySQL.query.await(sql) or {}
  local out = {}
  for _, row in ipairs(rows) do
    local cid = row.citizenid
    if cid then
      out[cid] = {
        total = toInt(row.total, 0),
        count = toInt(row.count, 0),
      }
    end
  end
  return out
end

local function logSys(category, message, meta)
  if type(SE.Log) == 'function' then
    pcall(SE.Log, category, message, meta)
  end
end

local function setSetting(key, value)
  if not SE.State then return end
  SE.State.settings = type(SE.State.settings) == 'table' and SE.State.settings or {}
  SE.State.settings.wealthTax = type(SE.State.settings.wealthTax) == 'table' and SE.State.settings.wealthTax or {}
  SE.State.settings.wealthTax[key] = value
  if SE.Server and SE.Server.MarkDirty then
    SE.Server.MarkDirty()
  end
end

local function getSetting(key)
  if not (SE.State and SE.State.settings and SE.State.settings.wealthTax) then return nil end
  return SE.State.settings.wealthTax[key]
end

local function ensureLogSchema()
  if not hasMySQL() then return end
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_wealth_tax_log (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      tax_type VARCHAR(32) NOT NULL,
      total_wealth BIGINT NOT NULL DEFAULT 0,
      tax_amount BIGINT NOT NULL DEFAULT 0,
      rank_position INT NULL,
      population INT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      meta LONGTEXT NULL,
      INDEX idx_citizen (citizenid),
      INDEX idx_type (tax_type),
      INDEX idx_created (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])
end

local function insertTaxLog(citizenid, taxType, totalWealth, taxAmount, rankPos, population, meta)
  if not hasMySQL() then return end
  MySQL.insert.await([[
    INSERT INTO space_economy_wealth_tax_log
      (citizenid, tax_type, total_wealth, tax_amount, rank_position, population, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], {
    citizenid,
    taxType,
    totalWealth,
    taxAmount,
    rankPos,
    population,
    meta and safeJsonEncode(meta) or nil
  })
end

function WT.BuildWealthSnapshot()
  if not hasMySQL() then return {} end
  if not tableExists('players') then return {} end

  local columns = countMoneyTables()
  local rows = getAllPlayers(columns)

  local vehicleTotals = getAssetTotals('player_vehicles', {'price', 'buy_price', 'value'})
  local propertyTotals = getAssetTotals('player_houses', {'price', 'value', 'buy_price'})

  local list = {}
  for _, row in ipairs(rows) do
    local citizenid = row.citizenid
    if citizenid then
      local cash, bank = getPlayerMoney(row)
      local vehicles = vehicleTotals[citizenid] or { total = 0, count = 0 }
      local properties = propertyTotals[citizenid] or { total = 0, count = 0 }
      local total = cash + bank + vehicles.total + properties.total

      list[#list + 1] = {
        citizenid = citizenid,
        cash = cash,
        bank = bank,
        vehicles = vehicles.total,
        properties = properties.total,
        total = total,
        lastSeen = getLastSeenTimestamp(row, columns),
        rawMoney = row.money and safeJsonDecode(row.money) or nil,
      }
    end
  end

  return list
end

function WT.RunCycle()
  if not hasMySQL() then return false end
  if not (cfg.WealthTax and cfg.WealthTax.Enabled) then return false end
  if not (SE.Debts and SE.Debts.Upsert) then return false end

  ensureLogSchema()

  local snapshot = WT.BuildWealthSnapshot()
  if #snapshot == 0 then return false end

  table.sort(snapshot, function(a, b) return (a.total or 0) > (b.total or 0) end)

  local totalPlayers = #snapshot
  local richCount = math.max(1, math.ceil(totalPlayers * toNumber(cfg.WealthTax.TopPercentile, 0.05)))

  for i = 1, richCount do
    local entry = snapshot[i]
    local totalWealth = toInt(entry.total, 0)
    if totalWealth > 0 then
      local rankFactor = 1 + ((richCount - i) / richCount) * toNumber(cfg.WealthTax.ProgressiveMultiplier, 1.5)
      local taxRate = toNumber(cfg.WealthTax.BaseRate, 0.02) * rankFactor
      local taxAmount = math.floor(totalWealth * taxRate)

      if taxAmount > 0 then
        local dueDays = toInt(cfg.WealthTax.DueDays, 7)
        SE.Debts.Upsert(entry.citizenid, taxAmount, 'IGF - Imposto sobre Grandes Fortunas', os.time() + (dueDays * 86400), {
          total_wealth = totalWealth,
          rank = i,
          population = totalPlayers,
          rate = taxRate
        })

        logSys('tax', ('IGF aplicado em %s: $%d (Rank %d/%d)'):format(entry.citizenid, taxAmount, i, totalPlayers), {
          total_wealth = totalWealth,
          rate = taxRate,
        })

        insertTaxLog(entry.citizenid, 'igf', totalWealth, taxAmount, i, totalPlayers, {
          rate = taxRate
        })
      end
    end
  end

  setSetting('lastCycleAt', os.time())
  return true
end

function WT.RunIdleTax()
  if not hasMySQL() then return false end
  if not (cfg.WealthDecay and cfg.WealthDecay.Enabled) then return false end
  if not tableExists('players') then return false end

  ensureLogSchema()

  local columns = countMoneyTables()
  local rows = getAllPlayers(columns)

  local cutoffDays = toInt(cfg.WealthDecay.InactiveDays, 30)
  local cutoffTs = os.time() - (cutoffDays * 86400)
  local minWealth = toInt(cfg.WealthDecay.MinWealth, 1000000)

  for _, row in ipairs(rows) do
    local citizenid = row.citizenid
    if citizenid then
      local lastSeen = getLastSeenTimestamp(row, columns)
      if lastSeen and lastSeen < cutoffTs then
        local cash, bank = getPlayerMoney(row)
        local total = cash + bank
        if total >= minWealth then
          local rate = toNumber(cfg.WealthDecay.DailyRate, 0.05)
          local maxRate = toNumber(cfg.WealthDecay.MaxDailyRate, 0.10)
          rate = math.min(rate, maxRate)

          local taxAmount = math.floor(total * rate)
          if taxAmount > 0 then
            local remaining = taxAmount
            local bankPay = math.min(bank, remaining)
            bank = bank - bankPay
            remaining = remaining - bankPay
            local cashPay = math.min(cash, remaining)
            cash = cash - cashPay
            remaining = remaining - cashPay

            local paid = taxAmount - remaining
            if paid > 0 then
              updatePlayerMoney(citizenid, columns, cash, bank, row.money and safeJsonDecode(row.money) or {})
              if SE.Treasury and type(SE.Treasury.Deposit) == 'function' then
                pcall(SE.Treasury.Deposit, paid, 'taxa_ociosidade', { citizenid = citizenid })
              end

              logSys('tax', ('Taxa de ociosidade aplicada: %s $%d'):format(citizenid, paid), {
                total_wealth = total,
                rate = rate
              })

              insertTaxLog(citizenid, 'idle', total, paid, nil, #rows, {
                rate = rate,
                inactive_days = cutoffDays
              })
            end
          end
        end
      end
    end
  end

  setSetting('lastIdleAt', os.time())
  return true
end

CreateThread(function()
  while not hasMySQL() do Wait(1000) end
  ensureLogSchema()

  local cycleHours = toInt(cfg.WealthTax and cfg.WealthTax.CycleHours, 168)
  local idleHours = 24

  while true do
    local now = os.time()

    if cfg.WealthTax and cfg.WealthTax.Enabled then
      local lastRun = toInt(getSetting('lastCycleAt'), 0)
      if lastRun == 0 or (now - lastRun) >= (cycleHours * 3600) then
        WT.RunCycle()
      end
    end

    if cfg.WealthDecay and cfg.WealthDecay.Enabled then
      local lastIdle = toInt(getSetting('lastIdleAt'), 0)
      if lastIdle == 0 or (now - lastIdle) >= (idleHours * 3600) then
        WT.RunIdleTax()
      end
    end

    Wait(60 * 60 * 1000)
  end
end)
