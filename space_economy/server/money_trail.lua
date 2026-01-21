--============================================================
-- space_economy - server/money_trail.lua
-- Rastreamento de trajeto do dinheiro (alta granularidade)
--============================================================
SE = SE or {}
SE.MoneyTrail = SE.MoneyTrail or {}

local U = SE.Util
local MT = SE.MoneyTrail
local cfg = Config and Config.MoneyTrail or {}

local function safeStr(v, fallback)
  if U and U.safeStr then return U.safeStr(v, fallback) end
  if v == nil then return fallback or '' end
  return tostring(v)
end

local function toInt(v, fallback)
  if U and U.toInt then return U.toInt(v, fallback) end
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return fallback or 0 end
  return math.floor(v)
end

local function getMinAmount()
  local base = toInt(cfg.MinAmount, 50000)
  local dyn = cfg.Dynamic or {}

  if dyn.Enabled and SE.EconomyMonitor and SE.EconomyMonitor.GetTotalCirculation then
    local circulation = toInt(SE.EconomyMonitor.GetTotalCirculation(), 0)
    if circulation > 0 then
      local pct = tonumber(dyn.PercentOfCirculation) or 0.001
      local calculated = math.floor(circulation * pct)
      local minClamp = toInt(dyn.Min, base)
      local maxClamp = toInt(dyn.Max, calculated)
      return math.max(minClamp, math.min(calculated, maxClamp))
    end
  end

  return base
end

local function reasonIgnored(reason)
  reason = safeStr(reason, '')
  local ignore = cfg.IgnoreReasons
  if type(ignore) ~= 'table' then return false end
  for _, item in ipairs(ignore) do
    if reason:find(tostring(item), 1, true) then
      return true
    end
  end
  return false
end

local function shouldLog(amount, account, reason)
  if not cfg.Enabled then return false end
  amount = toInt(amount, 0)
  if amount <= 0 then return false end

  local minAmount = getMinAmount()
  if amount < minAmount then return false end

  local accounts = cfg.LogAccounts or {}
  if account and accounts[account] == false then return false end

  if reasonIgnored(reason) then return false end

  return true
end

local function ensureTable()
  if not MySQL then return end
  pcall(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_money_trail (
        id BIGINT NOT NULL AUTO_INCREMENT,
        timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        amount BIGINT NOT NULL,
        account VARCHAR(16) NOT NULL,
        flow_type VARCHAR(16) NOT NULL,
        reason VARCHAR(128) NULL,
        from_type VARCHAR(32) NULL,
        from_id VARCHAR(64) NULL,
        to_type VARCHAR(32) NULL,
        to_id VARCHAR(64) NULL,
        metadata LONGTEXT NULL,
        PRIMARY KEY (id),
        INDEX idx_timestamp (timestamp),
        INDEX idx_from (from_type, from_id),
        INDEX idx_to (to_type, to_id),
        INDEX idx_amount (amount)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
  end)
end

local function cleanup()
  if not MySQL then return end
  local days = toInt(cfg.RetentionDays, 30)
  if days <= 0 then return end

  pcall(function()
    MySQL.query.await([[
      DELETE FROM space_economy_money_trail
      WHERE timestamp < DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { days })
  end)
end

function MT.Log(data)
  if not data then return false end
  local amount = toInt(data.amount, 0)
  local account = safeStr(data.account, 'bank')
  local reason = safeStr(data.reason, '')

  if not shouldLog(amount, account, reason) then return false end

  local payload = data.metadata or {}
  if U and U.safeJsonEncode then
    payload = U.safeJsonEncode(payload)
  else
    payload = json.encode(payload)
  end

  if not MySQL then return false end
  ensureTable()

  local ok = pcall(function()
    MySQL.insert.await([[
      INSERT INTO space_economy_money_trail
        (amount, account, flow_type, reason, from_type, from_id, to_type, to_id, metadata)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      amount,
      account,
      safeStr(data.flow_type, 'unknown'),
      reason ~= '' and reason or nil,
      data.from_type and tostring(data.from_type) or nil,
      data.from_id and tostring(data.from_id) or nil,
      data.to_type and tostring(data.to_type) or nil,
      data.to_id and tostring(data.to_id) or nil,
      payload,
    })
  end)

  return ok == true
end

function MT.LogDebit(src, amount, account, reason, meta)
  local cid = SE.Integrations and SE.Integrations.GetCitizenId and SE.Integrations.GetCitizenId(src) or nil
  return MT.Log({
    amount = amount,
    account = account,
    flow_type = 'debit',
    reason = reason,
    from_type = 'player',
    from_id = cid or tostring(src),
    to_type = 'system',
    to_id = 'economy',
    metadata = meta,
  })
end

function MT.LogCredit(src, amount, account, reason, meta)
  local cid = SE.Integrations and SE.Integrations.GetCitizenId and SE.Integrations.GetCitizenId(src) or nil
  return MT.Log({
    amount = amount,
    account = account,
    flow_type = 'credit',
    reason = reason,
    from_type = 'system',
    from_id = 'economy',
    to_type = 'player',
    to_id = cid or tostring(src),
    metadata = meta,
  })
end

function MT.LogTransfer(fromCid, toAccount, amount, reason, meta)
  return MT.Log({
    amount = amount,
    account = 'bank',
    flow_type = 'transfer',
    reason = reason,
    from_type = 'player',
    from_id = fromCid,
    to_type = 'society',
    to_id = toAccount,
    metadata = meta,
  })
end

function MT.LogTreasury(amount, reason, meta)
  meta = meta or {}
  local fromType = meta.from_type or (amount >= 0 and 'player' or 'treasury')
  local toType = meta.to_type or (amount >= 0 and 'treasury' or 'player')
  local fromId = meta and (meta.citizenid or meta.src or meta.from_id) or nil
  local toId = meta and (meta.citizenid or meta.src or meta.to_id) or nil

  if amount < 0 then
    amount = math.abs(amount)
  end

  return MT.Log({
    amount = amount,
    account = 'treasury',
    flow_type = 'treasury',
    reason = reason,
    from_type = fromType,
    from_id = fromId,
    to_type = toType,
    to_id = toId,
    metadata = meta,
  })
end

function MT.GetRecent(limit)
  if not MySQL then return {} end
  limit = toInt(limit, 50)
  local ok, rows = pcall(function()
    return MySQL.query.await([[
      SELECT id, timestamp, amount, account, flow_type, reason, from_type, from_id, to_type, to_id
      FROM space_economy_money_trail
      ORDER BY id DESC
      LIMIT ?
    ]], { limit })
  end)
  if not ok or not rows then return {} end
  return rows
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureTable()
  Wait(5000)
  cleanup()
  while true do
    Wait(86400000)
    cleanup()
  end
end)

exports('LogMoneyTrail', MT.Log)
exports('GetMoneyTrail', MT.GetRecent)
