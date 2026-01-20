--============================================================
-- space_economy - server/social_programs.lua
-- Programas sociais: UBI / redistribuição automática
--============================================================
SE = SE or {}
SE.SocialPrograms = SE.SocialPrograms or {}

local SP = SE.SocialPrograms
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

local function toInt(v, d)
  if U and U.toInt then return U.toInt(v, d or 0) end
  v = tonumber(v)
  if not v then return d or 0 end
  return math.floor(v)
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
  if row.cash ~= nil then cash = toInt(row.cash, cash) end
  if row.bank ~= nil then bank = toInt(row.bank, bank) end
  return cash, bank, row.money and safeJsonDecode(row.money) or {}
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

local function getEligiblePlayers()
  if not hasMySQL() or not tableExists('players') then return {} end

  local columns = columnsOf('players')
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

  local maxWealth = toInt(cfg.UBI and cfg.UBI.MaxWealth, 20000)
  local maxInactiveHours = toInt(cfg.UBI and cfg.UBI.MaxInactiveHours, 48)
  local cutoffTs = os.time() - (maxInactiveHours * 3600)

  local eligible = {}
  for _, row in ipairs(rows) do
    local cid = row.citizenid
    if cid then
      local lastSeen = getLastSeenTimestamp(row, columns)
      if not lastSeen or lastSeen >= cutoffTs then
        local cash, bank, moneyTable = getPlayerMoney(row)
        local total = cash + bank
        if total <= maxWealth then
          eligible[#eligible + 1] = {
            citizenid = cid,
            cash = cash,
            bank = bank,
            money = moneyTable,
            columns = columns,
          }
        end
      end
    end
  end

  return eligible
end

local function addMoneyToCitizen(entry, amount)
  if amount <= 0 then return false end

  local src = nil
  if B and type(B.GetSourceByCitizenId) == 'function' then
    src = B.GetSourceByCitizenId(entry.citizenid)
  end

  if src and src > 0 and SE.Integrations and type(SE.Integrations.AddMoney) == 'function' then
    local ok = SE.Integrations.AddMoney(src, amount, 'bank', cfg.UBI and cfg.UBI.Reason or 'UBI')
    if ok then return true end
  end

  local newBank = entry.bank + amount
  return updatePlayerMoney(entry.citizenid, entry.columns, entry.cash, newBank, entry.money)
end

function SP.DistributeUBI()
  if not (cfg.UBI and cfg.UBI.Enabled) then return false end
  if not (SE.Treasury and SE.Treasury.GetBalance and SE.Treasury.Withdraw) then return false end

  local treasuryBalance = SE.Treasury.GetBalance()
  local maxReserves = toInt(cfg.Treasury and cfg.Treasury.MaxReserves, 5000000)
  if treasuryBalance <= maxReserves then return false end

  local eligible = getEligiblePlayers()
  local minPlayers = toInt(cfg.UBI and cfg.UBI.MinPlayers, 3)
  if #eligible < minPlayers then return false end

  local surplus = treasuryBalance - maxReserves
  local amountPerPerson = math.floor(surplus / #eligible)
  if amountPerPerson <= 0 then return false end

  local paidCount = 0
  for _, entry in ipairs(eligible) do
    local ok = addMoneyToCitizen(entry, amountPerPerson)
    if ok then paidCount = paidCount + 1 end
  end

  if paidCount <= 0 then return false end

  local totalDistributed = amountPerPerson * paidCount
  SE.Treasury.Withdraw(totalDistributed, 'distribuicao_ubi', {
    recipients = paidCount,
    amount_each = amountPerPerson
  })

  if type(SE.Log) == 'function' then
    SE.Log('system', ('UBI distribuído: %d pessoas x $%d'):format(paidCount, amountPerPerson), {
      total = totalDistributed
    })
  end

  return true
end

CreateThread(function()
  while not hasMySQL() do Wait(1000) end

  local intervalHours = toInt(cfg.UBI and cfg.UBI.CheckIntervalHours, 12)
  local intervalMs = intervalHours * 60 * 60 * 1000

  while true do
    if cfg.UBI and cfg.UBI.Enabled then
      SP.DistributeUBI()
    end
    Wait(intervalMs)
  end
end)
