--============================================================
-- space_economy - server/events.lua (REESCRITO / UNIFICADO)
-- Roteador server -> módulos | NUI/admin_requestData | legacy
-- Corrige: "Ação não suportada: addVault" (apenas 1 router!)
--============================================================
SE = SE or {}
SE.Server = SE.Server or {}

local U = SE.Util
local B = SE.Bridge
local cfg = Config or {}

--============================================================
-- Logs (compat: metadata/meta)
--============================================================
local logsReady = false
local logsMetaCol = 'metadata'

local function ensureLogs()
  if logsReady or not MySQL then return end
  logsReady = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_logs (
      id BIGINT NOT NULL AUTO_INCREMENT,
      timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      category VARCHAR(50) NOT NULL,
      message TEXT NOT NULL,
      actor_citizenid VARCHAR(50) NULL,
      target_citizenid VARCHAR(50) NULL,
      amount BIGINT NULL,
      metadata LONGTEXT NULL,
      meta LONGTEXT NULL,
      PRIMARY KEY (id),
      INDEX idx_timestamp (timestamp),
      INDEX idx_category (category)
    )
  ]])

  local cols = MySQL.query.await('SHOW COLUMNS FROM space_economy_logs') or {}
  local has = {}
  for _, c in ipairs(cols) do
    if c and c.Field then has[c.Field] = true end
  end

  if has.metadata then logsMetaCol = 'metadata'
  elseif has.meta then logsMetaCol = 'meta'
  else logsMetaCol = nil end
end

SE.Log = SE.Log or function(kind, msg, meta)
  kind = tostring(kind or 'system')
  msg  = tostring(msg or '')

  if MySQL then
    ensureLogs()
    local payload = (U and U.safeJsonEncode and U.safeJsonEncode(meta or {})) or json.encode(meta or {})

    if logsMetaCol then
      MySQL.insert.await(
        ('INSERT INTO space_economy_logs (category, message, %s) VALUES (?, ?, ?)'):format(logsMetaCol),
        { kind, msg, payload }
      )
    else
      MySQL.insert.await('INSERT INTO space_economy_logs (category, message) VALUES (?, ?)', { kind, msg })
    end
  end

  if cfg.Debug then
    print(('[space_economy][%s] %s'):format(kind, msg))
  end
end

CreateThread(function()
  while not MySQL do Wait(200) end
  ensureLogs()
end)

--============================================================
-- Helpers
--============================================================
local function dbg(...)
  if U and U.dbg then U.dbg(...) else print('^3[events]^7', ...) end
end

local function HasMySQL()
  return MySQL and MySQL.query and MySQL.query.await and MySQL.single and MySQL.single.await
end

local function AdminAllowed(src)
  if (SE.Admin and SE.Admin.IsAllowed) then
    return SE.Admin.IsAllowed(src) == true
  end
  local ace = (cfg.Permissions and cfg.Permissions.Ace) or 'space_economy.admin'
  return ace and IsPlayerAceAllowed(src, ace) or false
end

local function Notify(src, msg, typ)
  if B and B.Notify then
    B.Notify(src, msg, typ or 'inform', 'Economia')
  else
    TriggerClientEvent('space_economy:client_notify', src, msg, typ or 'inform')
  end
end

local function SendAdminPacket(src, dataType, payload, ok)
  payload = payload or {}
  local msg = { type = dataType, ok = (ok ~= false), data = payload }

  -- compat: alguns UIs leem no root
  for k, v in pairs(payload) do
    if msg[k] == nil then msg[k] = v end
  end

  -- compat dupla (tem UIs que escutam nomes diferentes)
  TriggerClientEvent('space_economy:client_receiveAdminData', src, msg)
  TriggerClientEvent('space_economy:client_adminData', src, dataType, payload)
end

local function TreasuryDeposit(amount, reason, meta)
  if SE.Treasury and SE.Treasury.Deposit then
    return SE.Treasury.Deposit(amount, reason, meta)
  end
  if SE.Treasury and SE.Treasury.Modify then
    return SE.Treasury.Modify(amount, reason, meta)
  end
  return 0
end

local function TreasuryWithdraw(amount, reason, meta)
  amount = (U and U.toInt and U.toInt(amount, 0)) or (tonumber(amount) or 0)
  if amount <= 0 then return 0 end

  if SE.Treasury and SE.Treasury.Withdraw then
    return SE.Treasury.Withdraw(amount, reason, meta)
  end
  if SE.Treasury and SE.Treasury.Modify then
    return SE.Treasury.Modify(-amount, reason, meta)
  end
  return 0
end

local function TreasuryBalance()
  if SE.Treasury and SE.Treasury.GetBalance then
    return SE.Treasury.GetBalance() or 0
  end
  if SE.Treasury and SE.Treasury.Get then
    return SE.Treasury.Get() or 0
  end
  return 0
end

local function Num(v, d)
  v = tonumber(v)
  if not v then return d or 0 end
  return v
end

--============================================================
-- Abertura de painéis
--============================================================
RegisterNetEvent('space_economy:server_openTaxPanel', function()
  local src = source
  TriggerClientEvent('space_economy:client_open', src, 'tax', {})
end)

RegisterNetEvent('space_economy:server_openAdminPanel', function()
  local src = source

  if not AdminAllowed(src) then
    SE.Log('admin', 'Acesso negado (permissão)', { src = src })
    Notify(src, 'Acesso negado.', 'error')
    return
  end

  local st = (SE.Admin and SE.Admin.GetStatePayload and SE.Admin.GetStatePayload()) or {}
  TriggerClientEvent('space_economy:client_open', src, 'admin', st)
end)

--============================================================
-- Admin Data Router (ÚNICO!)
--============================================================
local function getDebtsStats()
  if SE.Debts and SE.Debts.Stats then
    local ok, st = pcall(SE.Debts.Stats)
    if ok and type(st) == 'table' then return st end
  end

  if not HasMySQL() then return { totalActive = 0, count = 0 } end

  local row = MySQL.single.await([[
    SELECT COALESCE(SUM(amount),0) AS totalActive,
           COALESCE(COUNT(*),0) AS count
    FROM space_economy_debts
    WHERE status IN ('active','installment')
  ]])

  return { totalActive = Num(row and row.totalActive, 0), count = Num(row and row.count, 0) }
end

local function getLoansStats()
  if SE.Loans and SE.Loans.GetStats then
    local ok, st = pcall(SE.Loans.GetStats)
    if ok and type(st) == 'table' then return st end
  end

  if not HasMySQL() then return { totalActive = 0, count = 0, avgRate = 0 } end

  local row = MySQL.single.await([[
    SELECT COALESCE(SUM(balance),0) AS totalActive,
           COALESCE(COUNT(*),0) AS count,
           COALESCE(AVG(interest_rate),0) AS avgRate
    FROM space_economy_loans
    WHERE status = 'active'
  ]])

  return {
    totalActive = Num(row and row.totalActive, 0),
    count = Num(row and row.count, 0),
    avgRate = Num(row and row.avgRate, 0),
  }
end

local function getInstallmentsStats()
  if SE.Installments and SE.Installments.GetStats then
    local ok, st = pcall(SE.Installments.GetStats)
    if ok and type(st) == 'table' then return st end
  end

  if not HasMySQL() then return { totalActive = 0, count = 0 } end

  local row = MySQL.single.await([[
    SELECT COALESCE(SUM(total_amount),0) AS totalActive,
           COALESCE(COUNT(*),0) AS count
    FROM space_economy_installment_plans
    WHERE status = 'active'
  ]])

  return { totalActive = Num(row and row.totalActive, 0), count = Num(row and row.count, 0) }
end

local function fetchLogs(limit)
  limit = math.min(math.max(Num(limit, 80), 1), 200)
  if SE.Admin and SE.Admin.FetchLogs then
    local ok, logs = pcall(SE.Admin.FetchLogs, limit)
    if ok and type(logs) == 'table' then return logs end
  end

  if not HasMySQL() then return {} end

  local rows = MySQL.query.await([[
    SELECT id, timestamp, category, message, actor_citizenid, target_citizenid, amount,
           COALESCE(metadata, meta) AS meta
    FROM space_economy_logs
    ORDER BY id DESC
    LIMIT ?
  ]], { limit }) or {}

  return rows
end

RegisterNetEvent('space_economy:server_requestAdminData', function(dataType, payload)
  local src = source
  dataType = tostring(dataType or '')
  payload = payload or {}

  if not AdminAllowed(src) then
    return SendAdminPacket(src, 'error', { message = 'Acesso negado.' }, false)
  end

  local ok, err = pcall(function()
    --========================
    -- State / Settings
    --========================
    if dataType == 'admin_state' then
      local out = (SE.Admin and SE.Admin.GetStatePayload and SE.Admin.GetStatePayload()) or {}
      return SendAdminPacket(src, dataType, out, true)

    elseif dataType == 'admin_dashboard' then
      local dashboard = (SE.Metrics and SE.Metrics.GetAdminDashboardData and SE.Metrics.GetAdminDashboardData()) or {}
      return SendAdminPacket(src, dataType, { dashboard = dashboard }, true)

    elseif dataType == 'admin_saveSettings' then
      if SE.Admin and SE.Admin.ApplySettings then
        SE.Admin.ApplySettings(payload.settings or payload)
      end
      local out = (SE.Admin and SE.Admin.GetStatePayload and SE.Admin.GetStatePayload()) or {}
      return SendAdminPacket(src, 'admin_state', out, true)

    --========================
    -- Vault / Treasury
    --========================
    elseif dataType == 'viewVault' then
      return SendAdminPacket(src, dataType, { balance = TreasuryBalance() }, true)

    elseif dataType == 'addVault' then
      local amount = (U and U.toInt and U.toInt(payload.amount or payload.value, 0)) or Num(payload.amount or payload.value, 0)
      local reason = tostring(payload.reason or 'Depósito no Tesouro')

      if amount <= 0 then
        return SendAdminPacket(src, 'error', { message = 'Valor inválido.' }, false)
      end

      -- por padrão: debita do admin (bank) e deposita no tesouro
      local debitPlayer = (payload.debitPlayer ~= false)

      if debitPlayer and SE.Integrations and SE.Integrations.RemoveMoney then
        local okDeb = SE.Integrations.RemoveMoney(src, amount, 'bank')
        if not okDeb then
          return SendAdminPacket(src, 'error', { message = 'Saldo insuficiente ou falha ao debitar.' }, false)
        end
      end

      TreasuryDeposit(amount, 'admin_deposit', { src = src, reason = reason })
      SE.Log('treasury', ('Admin depositou $%d no tesouro'):format(amount), { src = src, reason = reason, amount = amount })

      return SendAdminPacket(src, 'viewVault', { balance = TreasuryBalance() }, true)

    elseif dataType == 'withdrawVault' then
      local amount = (U and U.toInt and U.toInt(payload.amount or payload.value, 0)) or Num(payload.amount or payload.value, 0)
      local reason = tostring(payload.reason or 'Saque do Tesouro')

      if amount <= 0 then
        return SendAdminPacket(src, 'error', { message = 'Valor inválido.' }, false)
      end

      local bal = TreasuryBalance()
      if bal < amount then
        return SendAdminPacket(src, 'error', { message = 'Tesouro sem saldo suficiente.' }, false)
      end

      local okW = TreasuryWithdraw(amount, 'admin_withdraw', { src = src, reason = reason })
      if not okW then
        return SendAdminPacket(src, 'error', { message = 'Falha ao sacar do tesouro.' }, false)
      end

      local credited = true
      if SE.Integrations and SE.Integrations.AddMoney then
        local okAdd = SE.Integrations.AddMoney(src, amount, 'bank', reason or 'admin_withdraw')
        credited = (okAdd == true)
      end

      if not credited then
        -- rollback
        TreasuryDeposit(amount, 'admin_withdraw_rollback', { src = src, reason = reason })
        return SendAdminPacket(src, 'error', { message = 'Falha ao creditar no player (rollback aplicado).' }, false)
      end

      SE.Log('treasury', ('Admin sacou $%d do tesouro'):format(amount), { src = src, reason = reason, amount = amount })
      return SendAdminPacket(src, 'viewVault', { balance = TreasuryBalance() }, true)

    --========================
    -- Debts
    --========================
    elseif dataType == 'debts_stats' then
      return SendAdminPacket(src, dataType, { stats = getDebtsStats() }, true)

    elseif dataType == 'debts_active' then
      local limit = Num(payload.limit, 150)
      local offset = Num(payload.offset, 0)
      local debts = (SE.Debts and SE.Debts.ListActive and SE.Debts.ListActive(limit, offset)) or {}
      return SendAdminPacket(src, dataType, { debts = debts }, true)

    elseif dataType == 'specific_debt' then
      local id = tonumber(payload.id or payload.debt_id)
      local debt = id and (SE.Debts and SE.Debts.GetById and SE.Debts.GetById(id)) or nil
      return SendAdminPacket(src, dataType, { debt = debt }, true)

    elseif dataType == 'collect_debt' then
      local id = tonumber(payload.id or payload.debt_id)
      if not id then
        return SendAdminPacket(src, 'error', { message = 'ID da dívida inválido.' }, false)
      end

      local success, msg = false, 'Ação indisponível no módulo de dívidas.'
      if SE.Debts then
        for _, fn in ipairs({ 'ForceCollect', 'CollectDebt', 'Collect', 'PayDebt', 'Pay' }) do
          if type(SE.Debts[fn]) == 'function' then
            local ok2, a, b = pcall(SE.Debts[fn], id, src, payload)
            if ok2 then
              if a == true then success = true; msg = b or 'Cobrança executada.'; break end
              if type(a) == 'table' then success = true; msg = a.message or 'Cobrança executada.'; break end
            end
          end
        end
      end

      if not success then
        return SendAdminPacket(src, 'error', { message = msg }, false)
      end

      return SendAdminPacket(src, dataType, { message = msg }, true)

    --========================
    -- Loans
    --========================
    elseif dataType == 'loans_stats' then
      return SendAdminPacket(src, dataType, { stats = getLoansStats() }, true)

    elseif dataType == 'loans_list' then
      local limit = math.min(math.max(Num(payload.limit, 50), 1), 200)
      local rows = {}
      if SE.Loans and SE.Loans.ListActive then
        local ok2, res = pcall(SE.Loans.ListActive, limit)
        if ok2 and type(res) == 'table' then rows = res end
      end
      if #rows == 0 and HasMySQL() then
        rows = MySQL.query.await([[
          SELECT l.*,
                 COALESCE(c.name, 'Desconhecido') as playerName
          FROM space_economy_loans l
          LEFT JOIN space_economy_charcache c ON c.citizenid = l.citizenid
          WHERE l.status = 'active'
          ORDER BY l.created_at DESC
          LIMIT ?
        ]], { limit }) or {}
      end
      return SendAdminPacket(src, dataType, { loans = rows }, true)

    --========================
    -- Installments
    --========================
    elseif dataType == 'installments_stats' then
      return SendAdminPacket(src, dataType, { stats = getInstallmentsStats() }, true)

    elseif dataType == 'installments_list' then
      local limit = math.min(math.max(Num(payload.limit, 50), 1), 200)
      local rows = {}
      if SE.Installments and SE.Installments.ListActive then
        local ok2, res = pcall(SE.Installments.ListActive, limit)
        if ok2 and type(res) == 'table' then rows = res end
      end
      if #rows == 0 and HasMySQL() then
        rows = MySQL.query.await([[
          SELECT p.*,
                 COALESCE(c.name, 'Desconhecido') as playerName
          FROM space_economy_installment_plans p
          LEFT JOIN space_economy_charcache c ON c.citizenid = p.citizenid
          WHERE p.status = 'active'
          ORDER BY p.created_at DESC
          LIMIT ?
        ]], { limit }) or {}
      end
      return SendAdminPacket(src, dataType, { installments = rows }, true)

    elseif dataType == 'search_installment' then
      local citizenid = tostring(payload.citizenid or ''):gsub('%s+', '')
      local limit = math.min(math.max(Num(payload.limit, 50), 1), 200)
      if citizenid == '' then
        return SendAdminPacket(src, dataType, { citizenid = citizenid, results = {} }, true)
      end

      local rows = {}
      if SE.Installments and SE.Installments.GetActivePlans then
        rows = SE.Installments.GetActivePlans(citizenid) or {}
      elseif HasMySQL() then
        rows = MySQL.query.await([[
          SELECT * FROM space_economy_installment_plans
          WHERE citizenid = ? AND status = 'active'
          ORDER BY created_at DESC
          LIMIT ?
        ]], { citizenid, limit }) or {}
      end

      return SendAdminPacket(src, dataType, { citizenid = citizenid, results = rows }, true)

    --========================
    -- Logs
    --========================
    elseif dataType == 'admin_logs' then
      local limit = Num(payload.limit, 80)
      return SendAdminPacket(src, dataType, { logs = fetchLogs(limit) }, true)

    --========================
    -- COPOM Manual (Admin Dashboard)
    --========================
    elseif dataType == 'admin_copom_action' then
      local action = tostring(payload.action or '')
      if not (SE.MonetaryPolicy and SE.MonetaryPolicy.ManualCopomAction) then
        return SendAdminPacket(src, 'error', { message = 'Política monetária indisponível.' }, false)
      end

      local result = SE.MonetaryPolicy.ManualCopomAction(action)
      if SE.Discord and SE.Discord.AdminAction then
        SE.Discord.AdminAction(src, 'COPOM Manual', {
          action = action,
          selic = result and result.selic,
        })
      end

      return SendAdminPacket(src, dataType, { result = result }, true)

    --========================
    -- Issue Tax Debt
    --========================
    elseif dataType == 'admin_issueTaxDebt' then
      if not (SE.Admin and SE.Admin.IssueTaxDebt) then
        return SendAdminPacket(src, 'error', { message = 'Função de tributos indisponível.' }, false)
      end

      local success, message = SE.Admin.IssueTaxDebt(src, payload)
      if not success then
        return SendAdminPacket(src, 'error', { message = message or 'Falha ao lançar tributo.' }, false)
      end

      if SE.Discord and SE.Discord.AdminAction then
        SE.Discord.AdminAction(src, 'Lançar Tributo', {
          targetMode = payload.targetMode,
          citizenid = payload.citizenid,
          type = payload.type,
          amount = payload.amount,
          reason = payload.reason,
        })
      end

      return SendAdminPacket(src, dataType, { message = message or 'Tributo lançado com sucesso!' }, true)

    else
      return SendAdminPacket(src, 'error', { message = ('Ação não suportada: %s'):format(dataType) }, false)
    end
  end)

  if not ok then
    return SendAdminPacket(src, 'error', { message = 'Falha interna no servidor.', detail = tostring(err), action = dataType }, false)
  end
end)

--============================================================
-- Player endpoints (NUI / legacy)
--============================================================
RegisterNetEvent('space_economy:server_payOnlyTax', function(amount, reason)
  local src = source
  amount = (U and U.toNumber and U.toNumber(amount, 0)) or Num(amount, 0)

  local tax = (SE.Tax and SE.Tax.Calculate and SE.Tax.Calculate(amount)) or 0
  tax = (U and U.toInt and U.toInt(tax, 0)) or Num(tax, 0)

  if tax <= 0 then
    Notify(src, 'Nenhum imposto calculado.', 'inform')
    return
  end

  local bal = 0
  if SE.Integrations and SE.Integrations.GetBalance then
    bal = SE.Integrations.GetBalance(src, 'bank') or 0
  elseif B and B.GetBankBalance then
    bal = B.GetBankBalance(src) or 0
  end

  if bal < tax then
    Notify(src, 'Saldo bancário insuficiente.', 'error')
    return
  end

  local okPay = false
  if SE.Integrations and SE.Integrations.RemoveMoney then
    okPay = SE.Integrations.RemoveMoney(src, tax, 'bank') == true
  elseif B and B.RemoveBankMoney then
    okPay = B.RemoveBankMoney(src, tax, reason or 'Pagamento de imposto') == true
  end

  if not okPay then
    Notify(src, 'Falha ao debitar.', 'error')
    return
  end

  TreasuryDeposit(tax, 'imposto', { src = src, base = amount, reason = reason })
  Notify(src, ('Imposto pago: $%d'):format(tax), 'success')
end)

RegisterNetEvent('space_economy:server_payTax', function(tax, reason)
  local src = source
  tax = (U and U.toInt and U.toInt(tax, 0)) or Num(tax, 0)
  reason = tostring(reason or 'Imposto')

  if tax <= 0 then
    Notify(src, 'Nenhum valor para pagar.', 'error')
    return
  end

  local okPay = (SE.Integrations and SE.Integrations.RemoveMoney and SE.Integrations.RemoveMoney(src, tax, 'bank') == true)
  if not okPay and B and B.RemoveBankMoney then
    okPay = B.RemoveBankMoney(src, tax, ('Pagamento: %s'):format(reason)) == true
  end

  if not okPay then
    Notify(src, 'Saldo insuficiente ou falha ao debitar.', 'error')
    return
  end

  TreasuryDeposit(tax, 'imposto_pagamento_ui', { src = src, reason = reason })
  Notify(src, ('Imposto pago: $%d'):format(tax), 'success')
end)

RegisterNetEvent('space_economy:server_refuseTax', function()
  local src = source
  SE.Log('tax', 'Imposto recusado', { src = src })
end)

RegisterNetEvent('space_economy:server_calculateTax', function(amount)
  local src = source
  amount = (U and U.toNumber and U.toNumber(amount, 0)) or Num(amount, 0)
  local tax = (SE.Tax and SE.Tax.Calculate and SE.Tax.Calculate(amount)) or 0
  Notify(src, ('Simulação: Base $%d → Imposto $%d'):format(Num(amount, 0), Num(tax, 0)), 'inform')
end)

RegisterNetEvent('space_economy:server_washMoney', function(businessId, amount, feePercent)
  local src = source
  if SE.Integrations and SE.Integrations.WashMoney then
    return SE.Integrations.WashMoney(src, businessId, amount, feePercent)
  end
  Notify(src, 'Lavagem não configurada neste servidor.', 'error')
end)

--============================================================
-- Intervenções Econômicas (Game Master)
--============================================================
SE.Events = SE.Events or {}

local function ensureEventSettings()
  SE.State.settings = type(SE.State.settings) == 'table' and SE.State.settings or {}
  SE.State.settings.economicEvents = type(SE.State.settings.economicEvents) == 'table'
    and SE.State.settings.economicEvents or {}
  return SE.State.settings.economicEvents
end

local function setEconomicEvent(key, data)
  local settings = ensureEventSettings()
  settings[key] = data
  if SE.Server and SE.Server.MarkDirty then
    SE.Server.MarkDirty()
  end
end

function SE.Events.GetActiveEvent(key)
  local settings = ensureEventSettings()
  local event = settings[key]
  if not event then return nil end
  if event.expiresAt and os.time() > event.expiresAt then
    settings[key] = nil
    return nil
  end
  return event
end

RegisterNetEvent('space_economy:server_triggerEconomicEvent', function(eventKey)
  local src = source
  if not AdminAllowed(src) then
    return Notify(src, 'Acesso negado.', 'error')
  end

  eventKey = tostring(eventKey or '')
  local now = os.time()
  local twoHours = 2 * 60 * 60

  if eventKey == 'mining_boom' then
    setEconomicEvent('mining_boom', {
      multiplier = 0.5,
      expiresAt = now + twoHours,
      label = 'Boom da Mineração',
      description = 'Impostos sobre minérios reduzidos em 50% por 2h.',
    })

    TriggerClientEvent('ox_lib:notify', -1, {
      title = 'Boom da Mineração',
      description = 'Impostos sobre minérios reduzidos em 50% por 2 horas.',
      type = 'success',
      duration = 10000,
    })

  elseif eventKey == 'oil_crisis' then
    setEconomicEvent('oil_crisis', {
      multiplier = 3.0,
      expiresAt = now + twoHours,
      label = 'Crise do Petróleo',
      description = 'Imposto sobre combustível aumentado em 200% por 2h.',
    })

    TriggerClientEvent('ox_lib:notify', -1, {
      title = 'Crise do Petróleo',
      description = 'Impostos sobre combustível aumentados em 200% por 2 horas.',
      type = 'warning',
      duration = 10000,
    })

  elseif eventKey == 'gov_stimulus' then
    local payout = 500
    local paid = 0
    for _, playerId in ipairs(GetPlayers()) do
      local pid = tonumber(playerId)
      if pid and SE.Integrations and SE.Integrations.AddMoney then
        local okPay = SE.Integrations.AddMoney(pid, payout, 'bank', 'estímulo_governamental')
        if okPay then paid = paid + 1 end
      end
    end

    TriggerClientEvent('ox_lib:notify', -1, {
      title = 'Estímulo Governamental',
      description = ('Governo distribuiu $%d para cidadãos online.'):format(payout),
      type = 'success',
      duration = 10000,
    })

    SE.Log('admin', ('Estímulo Governamental distribuído para %d cidadãos'):format(paid), {
      amount = payout,
      recipients = paid,
    })

  elseif eventKey == 'tax_audit' then
    local fined = 0
    if SE.WealthTax and SE.WealthTax.BuildWealthSnapshot and MySQL and SE.Debts and SE.Debts.Upsert then
      local snapshot = SE.WealthTax.BuildWealthSnapshot()
      table.sort(snapshot, function(a, b) return (a.total or 0) > (b.total or 0) end)
      for i = 1, math.min(#snapshot, 10) do
        local entry = snapshot[i]
        local totalDebt = MySQL.scalar.await([[
          SELECT COALESCE(SUM(amount),0)
          FROM space_economy_debts
          WHERE citizenid = ?
            AND status IN ('active','installment')
        ]], { entry.citizenid }) or 0

        totalDebt = Num(totalDebt, 0)
        if totalDebt > 0 then
          local fine = math.floor(totalDebt * 0.10)
          if fine > 0 then
            SE.Debts.Upsert(entry.citizenid, fine, 'Multa Auditoria Fiscal', os.time() + (7 * 24 * 60 * 60), {
              base_debt = totalDebt,
              rank = i,
            })
            fined = fined + 1
          end
        end
      end
    end

    TriggerClientEvent('ox_lib:notify', -1, {
      title = 'Auditoria Fiscal',
      description = 'Auditoria aplicada nos 10 mais ricos. Multas emitidas para devedores.',
      type = 'info',
      duration = 10000,
    })

    SE.Log('admin', ('Auditoria fiscal concluída. Multas emitidas: %d'):format(fined))

  else
    return Notify(src, 'Evento econômico inválido.', 'error')
  end

  if SE.Discord and SE.Discord.AdminAction then
    SE.Discord.AdminAction(src, 'Intervenção Econômica', { evento = eventKey })
  end
end)

--============================================================
-- Alertas de Dinheiro Ilegal (RP)
--============================================================
local function sendIllegalDispatch(payload)
  local icfg = Config and Config.IllegalMoney and Config.IllegalMoney.Dispatch or {}
  if not icfg.Enabled then return end
  local resource = icfg.Resource or 'ps-dispatch'
  if GetResourceState(resource) ~= 'started' then return end

  local coords = payload.coords or { x = 0.0, y = 0.0, z = 0.0 }
  pcall(function()
    exports[resource]:CustomAlert({
      dispatchcodename = 'spaceeconomy_illegal',
      dispatchCode = icfg.Code or '10-75',
      firstStreet = icfg.Title or 'Investigação Financeira',
      priority = 2,
      origin = { x = coords.x, y = coords.y, z = coords.z },
      dispatchMessage = icfg.Message or 'Movimentação suspeita detectada.',
      description = payload.description,
      job = { 'police' },
      blipSprite = 500,
      blipColour = 1,
      blipScale = 1.0,
      blipLength = 3,
    })
  end)
end

local function sendIllegalMDT(payload)
  local mcfg = Config and Config.IllegalMoney and Config.IllegalMoney.MDT or {}
  if not mcfg.Enabled then return end
  local resource = mcfg.Resource or 'ps-mdt'
  if GetResourceState(resource) ~= 'started' then return end

  pcall(function()
    exports[resource]:NewReport({
      author = 'Economia',
      title = mcfg.Title or 'Investigação Financeira',
      description = payload.description,
      tags = mcfg.Tags or { 'financeiro' },
      officers = {},
    })
  end)
end

RegisterNetEvent('space_economy:server_illegalMoneyAlert', function(payload)
  payload = payload or {}
  local src = payload.source or source
  local amount = Num(payload.amount, 0)
  local reason = tostring(payload.reason or 'desconhecido')
  local citizenid = payload.citizenid or (B and B.GetCitizenId and B.GetCitizenId(src))

  local coords = { x = 0.0, y = 0.0, z = 0.0 }
  if src and src > 0 then
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
      local vec = GetEntityCoords(ped)
      coords = { x = vec.x, y = vec.y, z = vec.z }
    end
  end

  local description = ('Movimentação ilegal: $%d | CID: %s | Motivo: %s'):format(amount, tostring(citizenid or 'N/A'), reason)

  SE.Log('admin', 'Alerta de dinheiro ilegal', {
    citizenid = citizenid,
    amount = amount,
    reason = reason,
    resource = payload.resource,
  })

  if SE.Discord and SE.Discord.Alert then
    SE.Discord.Alert('Dinheiro Ilegal Detectado', description)
  end

  sendIllegalDispatch({
    coords = coords,
    description = description,
  })

  sendIllegalMDT({
    description = description,
  })
end)
