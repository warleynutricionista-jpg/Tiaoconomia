--============================================================
-- space_economy - server/loans.lua (REESCRITO / QBOX Hardened)
-- Sistema de empréstimos governamentais com juros (PRICE), cobrança e inadimplência
-- Integra com SE.Integrations (ps-banking) e SE.Debts (bill/boletos)
--============================================================
SE = SE or {}
SE.Loans = SE.Loans or {}

local Loans = SE.Loans
local U = SE.Util or {}
local B = SE.Bridge or {}
local cfg = Config or {}

local RES = GetCurrentResourceName()

--============================================================
-- Fallback Utils (anti-nil)
--============================================================
local function _safeStr(v, fb)
  if v == nil then return fb or '' end
  local s = tostring(v)
  if s == '' then return fb or '' end
  return s
end

local function _trim(s)
  s = _safeStr(s, '')
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function _toInt(v, d)
  local n = tonumber(v)
  if not n then return d or 0 end
  if n >= 0 then return math.floor(n + 0.0) end
  return math.ceil(n - 0.0)
end

local function _toNumber(v, d)
  local n = tonumber(v)
  if not n then return d end
  return n
end

local function _jsonEncode(tbl)
  if type(U.safeJsonEncode) == 'function' then
    return U.safeJsonEncode(tbl)
  end
  if json and json.encode then
    local ok, out = pcall(function()
      return json.encode(tbl or {})
    end)
    return ok and out or '{}'
  end
  return '{}'
end

local function dbg(...)
  if type(U.dbg) == 'function' then
    U.dbg(...)
  else
    print('^3[space_economy:loans]^7', ...)
  end
end

local function notify(src, msg, typ)
  if src and src > 0 and type(B.Notify) == 'function' then
    B.Notify(src, msg, typ or 'inform')
  end
end

local function hasMySQL()
  return MySQL
    and MySQL.query and MySQL.query.await
    and MySQL.single and MySQL.single.await
    and MySQL.scalar and MySQL.scalar.await
    and MySQL.insert and MySQL.insert.await
    and MySQL.update and MySQL.update.await
end

local function tableExists(name)
  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)
  return ok and rows and #rows > 0
end

--============================================================
-- Logs
--============================================================
local function logSys(category, message, meta)
  category = _safeStr(category, 'emprestimos')
  message = _safeStr(message, '')
  if message == '' or not hasMySQL() then return end

  if type(SE.Log) == 'function' then
    pcall(SE.Log, category, message, meta)
  end

  pcall(function()
    MySQL.insert.await([[
      INSERT INTO space_economy_logs (category, message, metadata, created_at)
      VALUES (?, ?, ?, NOW())
    ]], { category, message, meta and _jsonEncode(meta) or nil })
  end)
end

--============================================================
-- Configuração (com defaults seguros)
--============================================================
cfg.LoanSystem = cfg.LoanSystem or {}
local LC = cfg.LoanSystem

-- Limites por score (ordem: maior score primeiro)
LC.Limits = LC.Limits or {
  { minScore = 850, maxAmount = 500000, interestRate = 0.05 }, -- 5% a.m.
  { minScore = 740, maxAmount = 300000, interestRate = 0.08 }, -- 8% a.m.
  { minScore = 670, maxAmount = 150000, interestRate = 0.12 }, -- 12% a.m.
  { minScore = 580, maxAmount = 75000,  interestRate = 0.15 }, -- 15% a.m.
  { minScore = 0,   maxAmount = 25000,  interestRate = 0.20 }, -- 20% a.m.
}

LC.Enabled = (LC.Enabled ~= false)
LC.MaxActiveLoans = _toInt(LC.MaxActiveLoans or 3, 3)
LC.MinLoanAmount = _toInt(LC.MinLoanAmount or 1000, 1000)
LC.MaxTermMonths = _toInt(LC.MaxTermMonths or 24, 24)
LC.OriginationFee = _toNumber(LC.OriginationFee or 0.02, 0.02) -- 2%
LC.DueEveryDays = _toInt(LC.DueEveryDays or 30, 30) -- parcelas a cada 30 dias
LC.WarnBeforeDays = _toInt(LC.WarnBeforeDays or 3, 3)
LC.DefaultAfterDays = _toInt(LC.DefaultAfterDays or 30, 30) -- inadimplente após 30 dias do vencimento
LC.DefaultToDebt = (LC.DefaultToDebt ~= false) -- ao inadimplir, vira dívida no SE.Debts

--============================================================
-- Schema (sem information_schema)
--============================================================
local schemaReady = false
local cache = { hasCharCache = nil }

local function ensureSchema()
  if schemaReady or not hasMySQL() then return end
  schemaReady = true

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_loans (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      amount BIGINT NOT NULL,
      disbursed_amount BIGINT NOT NULL,
      balance BIGINT NOT NULL,
      interest_rate DECIMAL(10,4) NOT NULL,
      term_months INT NOT NULL,
      monthly_payment BIGINT NOT NULL,
      paid_installments INT NOT NULL DEFAULT 0,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      credit_score_at_approval INT NOT NULL DEFAULT 0,
      purpose VARCHAR(200) NULL,
      approved_by VARCHAR(64) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      disbursed_at TIMESTAMP NULL,
      completed_at TIMESTAMP NULL,
      defaulted_at TIMESTAMP NULL,
      next_due_at TIMESTAMP NULL,
      meta LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_status (status),
      INDEX idx_next_due (next_due_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_loan_payments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      loan_id INT NOT NULL,
      installment_number INT NOT NULL,
      amount BIGINT NOT NULL,
      principal BIGINT NOT NULL,
      interest BIGINT NOT NULL,
      balance_after BIGINT NOT NULL,
      paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      meta LONGTEXT NULL,
      INDEX idx_loan (loan_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  -- garante tabela de logs (caso não exista)
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_logs (
      id INT AUTO_INCREMENT PRIMARY KEY,
      category VARCHAR(64) NOT NULL DEFAULT 'sistema',
      message VARCHAR(255) NOT NULL,
      metadata LONGTEXT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_created (created_at),
      INDEX idx_cat (category)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])

  cache.hasCharCache = tableExists('space_economy_charcache')

  dbg('Schema de empréstimos garantido.')
  logSys('sistema', ('[%s] Schema loans/payments OK.'):format(RES))
end

CreateThread(function()
  while not hasMySQL() do Wait(250) end
  ensureSchema()
end)

--============================================================
-- Helpers de Integração (ps-banking via SE.Integrations)
--============================================================
local function addMoney(src, amount)
  amount = _toInt(amount, 0)
  if amount <= 0 or not src or src <= 0 then return false end
  if SE.Integrations and type(SE.Integrations.AddMoney) == 'function' then
    return SE.Integrations.AddMoney(src, amount, 'bank') == true
  end
  return false
end

local function removeMoney(src, amount)
  amount = _toInt(amount, 0)
  if amount <= 0 or not src or src <= 0 then return false end
  if SE.Integrations and type(SE.Integrations.RemoveMoney) == 'function' then
    return SE.Integrations.RemoveMoney(src, amount, 'bank') == true
  end
  return false
end

local function treasuryBalance()
  if SE.Treasury and type(SE.Treasury.GetBalance) == 'function' then
    return _toInt(SE.Treasury.GetBalance(), 0)
  end
  return 0
end

local function treasuryWithdraw(amount, reason, meta)
  if SE.Treasury and type(SE.Treasury.Withdraw) == 'function' then
    pcall(SE.Treasury.Withdraw, _toInt(amount, 0), reason or 'emprestimo', meta or {})
    return true
  end
  return false
end

local function treasuryDeposit(amount, reason, meta)
  if SE.Treasury and type(SE.Treasury.Deposit) == 'function' then
    pcall(SE.Treasury.Deposit, _toInt(amount, 0), reason or 'pagamento_emprestimo', meta or {})
    return true
  end
  return false
end

local function getCitizenId(src)
  if type(B.GetCitizenId) == 'function' then
    return B.GetCitizenId(src)
  end
  return nil
end

--============================================================
-- Cálculo (PRICE)
-- interestRate é taxa mensal (ex.: 0.05 = 5% a.m.)
--============================================================
local function getLoanTier(score)
  score = _toInt(score, 0)
  for _, t in ipairs(LC.Limits) do
    if score >= _toInt(t.minScore, 0) then
      return t
    end
  end
  return LC.Limits[#LC.Limits]
end

local function calculateMonthlyPayment(principal, monthlyRate, months)
  principal = _toNumber(principal, 0)
  monthlyRate = _toNumber(monthlyRate, 0)
  months = _toInt(months, 1)

  if months <= 0 then return 0 end
  if monthlyRate <= 0 then
    return math.ceil(principal / months)
  end

  local r = monthlyRate
  local p = principal
  local pow = math.pow(1 + r, months)
  local payment = p * (r * pow) / (pow - 1)

  payment = math.ceil(payment)
  if payment < 1 then payment = 1 end
  return payment
end

--============================================================
-- API: Simulação
--============================================================
function Loans.Simulate(citizenid, amount, months, purpose)
  ensureSchema()
  if not LC.Enabled then return nil, 'sistema_desabilitado' end

  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return nil, 'citizenid_invalido' end

  amount = _toInt(amount, 0)
  if amount < LC.MinLoanAmount then
    return nil, 'valor_minimo'
  end

  months = _toInt(months, 12)
  if months < 1 or months > LC.MaxTermMonths then
    return nil, 'prazo_invalido'
  end

  -- score
  local scoreValue = 500
  local rating = 'Regular'
  if SE.CreditScore and type(SE.CreditScore.Get) == 'function' then
    local score = SE.CreditScore.Get(citizenid)
    if score then
      scoreValue = _toInt(score.score, scoreValue)
      rating = _safeStr(score.rating, rating)
    end
  end

  local tier = getLoanTier(scoreValue)
  if amount > _toInt(tier.maxAmount, 0) then
    return nil, ('limite_excedido:%d'):format(_toInt(tier.maxAmount, 0))
  end

  -- limite de empréstimos ativos
  local row = MySQL.single.await([[
    SELECT COALESCE(COUNT(*),0) as cnt
    FROM space_economy_loans
    WHERE citizenid = ? AND status = 'active'
  ]], { citizenid })
  local activeCnt = _toInt(row and row.cnt, 0)
  if activeCnt >= LC.MaxActiveLoans then
    return nil, 'maximo_emprestimos_ativos'
  end

  local origFee = math.floor(amount * _toNumber(LC.OriginationFee, 0.02))
  if origFee < 0 then origFee = 0 end

  local disbursed = amount - origFee
  if disbursed < 0 then disbursed = 0 end

  local monthlyRate = _toNumber(tier.interestRate, 0.10)
  local monthlyPayment = calculateMonthlyPayment(amount, monthlyRate, months)

  local totalPayment = monthlyPayment * months
  local totalInterest = totalPayment - amount

  return {
    amount = amount,
    disbursedAmount = disbursed,
    originationFee = origFee,
    interestRate = monthlyRate,
    interestRatePercent = monthlyRate * 100.0,
    termMonths = months,
    monthlyPayment = monthlyPayment,
    totalPayment = totalPayment,
    totalInterest = totalInterest,
    creditScore = scoreValue,
    rating = rating,
    purpose = _safeStr(purpose, 'Uso pessoal'),
    approved = (scoreValue >= 580),
    maxAllowed = _toInt(tier.maxAmount, 0)
  }
end

--============================================================
-- API: Solicitação (player)
--============================================================
function Loans.Request(src, amount, months, purpose)
  ensureSchema()
  if not LC.Enabled then return false, 'sistema_desabilitado' end

  src = tonumber(src) or 0
  if src <= 0 then return false, 'source_invalida' end

  local cid = getCitizenId(src)
  if not cid then return false, 'cid_invalido' end

  local sim, err = Loans.Simulate(cid, amount, months, purpose)
  if not sim then
    return false, err
  end

  if not sim.approved then
    return false, 'score_insuficiente'
  end

  -- tesouro
  local bal = treasuryBalance()
  if bal < sim.disbursedAmount then
    return false, 'tesouro_insuficiente'
  end

  local nextDue = ('%s'):format(os.date('%Y-%m-%d %H:%M:%S', os.time() + (LC.DueEveryDays * 24 * 60 * 60)))

  local loanId = MySQL.insert.await([[
    INSERT INTO space_economy_loans
      (citizenid, amount, disbursed_amount, balance, interest_rate,
       term_months, monthly_payment, credit_score_at_approval, purpose,
       approved_by, disbursed_at, next_due_at, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?)
  ]], {
    cid,
    sim.amount,
    sim.disbursedAmount,
    sim.amount, -- balance = principal inicial
    sim.interestRate,
    sim.termMonths,
    sim.monthlyPayment,
    sim.creditScore,
    sim.purpose,
    'auto',
    nextDue,
    _jsonEncode({ resource = RES, origination_fee = sim.originationFee })
  })

  if not loanId then
    logSys('erro', 'Falha ao criar empréstimo no banco.', { citizenid = cid })
    return false, 'falha_criar_emprestimo'
  end

  -- debita tesouro (somente valor liberado ao player)
  treasuryWithdraw(sim.disbursedAmount, 'emprestimo_concedido', {
    loan_id = loanId,
    citizenid = cid,
    disbursed = sim.disbursedAmount,
    fee = sim.originationFee
  })

  -- credita player (banco)
  local okAdd = addMoney(src, sim.disbursedAmount)
  if not okAdd then
    -- reversão: marca emprestimo cancelado e devolve tesouro
    MySQL.update.await([[
      UPDATE space_economy_loans
      SET status='cancelled', completed_at=NOW(), meta = ?
      WHERE id = ?
    ]], { _jsonEncode({ cancelled_reason = 'falha_creditar_banco', resource = RES }), loanId })

    treasuryDeposit(sim.disbursedAmount, 'reversao_emprestimo', { loan_id = loanId, citizenid = cid })
    logSys('erro', 'Falha ao creditar banco do jogador. Empréstimo revertido.', { loan_id = loanId, citizenid = cid })
    return false, 'falha_credito_banco'
  end

  -- score
  if SE.CreditScore and type(SE.CreditScore.RecordEvent) == 'function' then
    pcall(SE.CreditScore.RecordEvent, cid, 'loan_approved', { amount = sim.amount, loan_id = loanId })
  end

  logSys('emprestimos', ('Empréstimo aprovado #%d: %d meses x $%d'):format(loanId, sim.termMonths, sim.monthlyPayment), {
    loan_id = loanId, citizenid = cid, amount = sim.amount, disbursed = sim.disbursedAmount
  })

  dbg(('Empréstimo concedido: %s | $%d em %d meses (#%d)'):format(cid, sim.amount, sim.termMonths, loanId))
  return true, loanId, sim
end

--============================================================
-- API: Pagamento de parcela
--============================================================
function Loans.PayInstallment(loanId, src)
  ensureSchema()
  if not LC.Enabled then return false, 'sistema_desabilitado' end

  loanId = _toInt(loanId, 0)
  if loanId <= 0 then return false, 'loan_id_invalido' end

  src = tonumber(src) or 0
  if src <= 0 then return false, 'source_invalida' end

  -- lock
  local lockKey = ('loan:%d'):format(loanId)
  local owner = ('src_%d'):format(src)

  if SE.Locks and type(SE.Locks.AcquireBlocking) == 'function' then
    local okLock = SE.Locks.AcquireBlocking(lockKey, owner, 30000, 5000, 50)
    if not okLock then return false, 'lock_timeout' end
  end

  local loan = MySQL.single.await([[
    SELECT * FROM space_economy_loans
    WHERE id = ? AND status = 'active'
    LIMIT 1
  ]], { loanId })

  if not loan then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'emprestimo_nao_encontrado'
  end

  -- valida dono (somente o dono paga pelo painel do player)
  local cid = getCitizenId(src)
  if cid and _safeStr(loan.citizenid, '') ~= cid then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'nao_autorizado'
  end

  local monthlyPayment = _toInt(loan.monthly_payment, 0)
  local balance = _toInt(loan.balance, 0)
  local rate = _toNumber(loan.interest_rate, 0)

  if monthlyPayment <= 0 or balance <= 0 then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'emprestimo_invalido'
  end

  -- juros da parcela (sobre saldo atual)
  local interest = math.floor((balance * rate) + 0.5)
  if interest < 0 then interest = 0 end

  local principal = monthlyPayment - interest
  if principal < 0 then principal = 0 end
  if principal > balance then principal = balance end

  -- remove dinheiro
  local okRemove = removeMoney(src, monthlyPayment)
  if not okRemove then
    if SE.Locks and type(SE.Locks.Release) == 'function' then SE.Locks.Release(lockKey, owner, true) end
    return false, 'saldo_insuficiente'
  end

  local paidCount = _toInt(loan.paid_installments, 0) + 1
  local totalInstallments = _toInt(loan.term_months, 0)
  local newBalance = balance - principal
  if newBalance < 0 then newBalance = 0 end

  local completed = (newBalance <= 0) or (paidCount >= totalInstallments)

  if completed then
    MySQL.update.await([[
      UPDATE space_economy_loans
      SET balance = 0,
          paid_installments = ?,
          status = 'completed',
          completed_at = NOW(),
          next_due_at = NULL
      WHERE id = ?
    ]], { paidCount, loanId })

    if SE.CreditScore and type(SE.CreditScore.RecordEvent) == 'function' then
      pcall(SE.CreditScore.RecordEvent, loan.citizenid, 'loan_completed', { loan_id = loanId })
    end
  else
    local nextDue = ('%s'):format(os.date('%Y-%m-%d %H:%M:%S', os.time() + (LC.DueEveryDays * 24 * 60 * 60)))
    MySQL.update.await([[
      UPDATE space_economy_loans
      SET balance = ?,
          paid_installments = ?,
          next_due_at = ?
      WHERE id = ?
    ]], { newBalance, paidCount, nextDue, loanId })
  end

  MySQL.insert.await([[
    INSERT INTO space_economy_loan_payments
      (loan_id, installment_number, amount, principal, interest, balance_after, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], {
    loanId,
    paidCount,
    monthlyPayment,
    principal,
    interest,
    newBalance,
    _jsonEncode({ src = src, citizenid = loan.citizenid })
  })

  -- vai pro tesouro
  treasuryDeposit(monthlyPayment, 'pagamento_emprestimo', { loan_id = loanId, citizenid = loan.citizenid })

  if SE.Locks and type(SE.Locks.Release) == 'function' then
    SE.Locks.Release(lockKey, owner, true)
  end

  logSys('emprestimos', ('Parcela paga #%d: %d/%d | principal=%d | juros=%d | saldo=%d'):format(
    loanId, paidCount, totalInstallments, principal, interest, newBalance
  ), { loan_id = loanId, citizenid = loan.citizenid })

  return true, {
    paid = paidCount,
    total = totalInstallments,
    remaining = math.max(totalInstallments - paidCount, 0),
    payment = monthlyPayment,
    principal = principal,
    interest = interest,
    balance = newBalance,
    completed = completed
  }
end

--============================================================
-- API: Listagens
--============================================================
function Loans.GetActiveLoans(citizenid, limit)
  ensureSchema()
  citizenid = _trim(_safeStr(citizenid, ''))
  if citizenid == '' then return {} end

  limit = _toInt(limit or 50, 50)
  if limit < 1 then limit = 1 end
  if limit > 200 then limit = 200 end

  local rows
  if cache.hasCharCache then
    rows = MySQL.query.await([[
      SELECT l.*,
             COALESCE(c.name,'Desconhecido') as playerName
      FROM space_economy_loans l
      LEFT JOIN space_economy_charcache c ON c.citizenid = l.citizenid
      WHERE l.citizenid = ? AND l.status = 'active'
      ORDER BY l.created_at DESC
      LIMIT ?
    ]], { citizenid, limit }) or {}
  else
    rows = MySQL.query.await([[
      SELECT l.*, 'Desconhecido' as playerName
      FROM space_economy_loans l
      WHERE l.citizenid = ? AND l.status = 'active'
      ORDER BY l.created_at DESC
      LIMIT ?
    ]], { citizenid, limit }) or {}
  end

  return rows
end

function Loans.GetDetails(loanId)
  ensureSchema()
  loanId = _toInt(loanId, 0)
  if loanId <= 0 then return nil end

  local loan
  if cache.hasCharCache then
    loan = MySQL.single.await([[
      SELECT l.*,
             COALESCE(c.name,'Desconhecido') as playerName
      FROM space_economy_loans l
      LEFT JOIN space_economy_charcache c ON c.citizenid = l.citizenid
      WHERE l.id = ?
      LIMIT 1
    ]], { loanId })
  else
    loan = MySQL.single.await([[
      SELECT l.*, 'Desconhecido' as playerName
      FROM space_economy_loans l
      WHERE l.id = ?
      LIMIT 1
    ]], { loanId })
  end

  if not loan then return nil end

  local payments = MySQL.query.await([[
    SELECT *
    FROM space_economy_loan_payments
    WHERE loan_id = ?
    ORDER BY installment_number ASC
  ]], { loanId }) or {}

  loan.payments = payments
  return loan
end

--============================================================
-- Thread: Avisos de vencimento + inadimplência
--============================================================
CreateThread(function()
  while not hasMySQL() do Wait(1000) end
  ensureSchema()

  local checkIntervalMs = 60 * 60 * 1000 -- 1h

  while true do
    Wait(checkIntervalMs)
    if not (LC.Enabled) then
      -- skip
    else
      -- avisos: vence em até WarnBeforeDays
      local upcoming = MySQL.query.await([[
        SELECT id, citizenid, monthly_payment, next_due_at
        FROM space_economy_loans
        WHERE status = 'active'
          AND next_due_at IS NOT NULL
          AND next_due_at BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL ? DAY)
      ]], { LC.WarnBeforeDays }) or {}

      for _, l in ipairs(upcoming) do
        local src = (type(B.GetSourceByCitizenId) == 'function') and B.GetSourceByCitizenId(l.citizenid) or nil
        if src then
          notify(src, ('Parcela do empréstimo vence em breve. Valor: $%d'):format(_toInt(l.monthly_payment, 0)), 'warn')
        end
        Wait(0)
      end

      -- inadimplência: passou DefaultAfterDays do vencimento
      local def = MySQL.query.await([[
        SELECT *
        FROM space_economy_loans
        WHERE status = 'active'
          AND next_due_at IS NOT NULL
          AND next_due_at < DATE_SUB(NOW(), INTERVAL ? DAY)
      ]], { LC.DefaultAfterDays }) or {}

      for _, l in ipairs(def) do
        MySQL.update.await([[
          UPDATE space_economy_loans
          SET status='defaulted', defaulted_at=NOW()
          WHERE id = ?
        ]], { l.id })

        -- penaliza score
        if SE.CreditScore and type(SE.CreditScore.RecordEvent) == 'function' then
          pcall(SE.CreditScore.RecordEvent, l.citizenid, 'loan_defaulted', {
            loan_id = l.id,
            balance = _toInt(l.balance, 0)
          })
        end

        -- vira dívida (isso cria BILL no ps-banking via seu debts.lua melhorado)
        if LC.DefaultToDebt and SE.Debts and type(SE.Debts.Upsert) == 'function' then
          local bal = _toInt(l.balance, 0)
          if bal > 0 then
            local reason = ('Empréstimo inadimplente #%d'):format(_toInt(l.id, 0))
            local dueTs = os.time() + (7 * 24 * 60 * 60)
            SE.Debts.Upsert(l.citizenid, bal, reason, dueTs, {
              source = 'loan_default',
              loan_id = l.id,
              auto_generated = true,
              resource = RES,
              forceNew = true
            })
          end
        end

        logSys('emprestimos', ('Empréstimo inadimplente #%d (saldo: %d)'):format(_toInt(l.id, 0), _toInt(l.balance, 0)), {
          loan_id = l.id, citizenid = l.citizenid
        })

        Wait(0)
      end
    end
  end
end)

--============================================================
-- Eventos de rede (mantém compat do seu NUI/Router)
--============================================================
RegisterNetEvent('space_economy:server_simulateLoan', function(amount, months, purpose)
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  local sim, err = Loans.Simulate(cid, amount, months, purpose)
  if sim then
    TriggerClientEvent('space_economy:client_loanSimulation', src, sim)
  else
    notify(src, ('Falha na simulação: %s'):format(_safeStr(err, 'erro')), 'error')
  end
end)

RegisterNetEvent('space_economy:server_requestLoan', function(amount, months, purpose)
  local src = source
  local ok, a, b = Loans.Request(src, amount, months, purpose)

  if ok then
    local loanId = a
    local sim = b
    notify(src, ('Empréstimo aprovado! $%d creditados em sua conta bancária.'):format(_toInt(sim.disbursedAmount, 0)), 'success')
    TriggerClientEvent('space_economy:client_loanApproved', src, loanId, sim)
  else
    notify(src, ('Empréstimo negado: %s'):format(_safeStr(a, 'erro')), 'error')
  end
end)

RegisterNetEvent('space_economy:server_payLoanInstallment', function(loanId)
  local src = source
  local ok, result = Loans.PayInstallment(loanId, src)

  if ok then
    if result.completed then
      notify(src, 'Empréstimo quitado com sucesso!', 'success')
    else
      notify(src, ('Parcela paga! Restam %d de %d. Saldo: $%d'):format(
        _toInt(result.remaining, 0), _toInt(result.total, 0), _toInt(result.balance, 0)
      ), 'success')
    end
    TriggerClientEvent('space_economy:client_loanPaymentMade', src, loanId, result)
  else
    notify(src, ('Falha ao pagar parcela: %s'):format(_safeStr(result, 'erro')), 'error')
  end
end)

RegisterNetEvent('space_economy:server_getMyLoans', function()
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  local loans = Loans.GetActiveLoans(cid, 50)
  TriggerClientEvent('space_economy:client_receiveLoans', src, loans)
end)

RegisterNetEvent('space_economy:server_getLoanDetails', function(loanId)
  local src = source
  local cid = getCitizenId(src)
  if not cid then return end

  local loan = Loans.GetDetails(loanId)
  if not loan then
    notify(src, 'Empréstimo não encontrado.', 'error')
    return
  end

  -- segurança: somente o dono (para painel do jogador)
  if _safeStr(loan.citizenid, '') ~= cid then
    notify(src, 'Acesso negado.', 'error')
    return
  end

  TriggerClientEvent('space_economy:client_receiveLoanDetails', src, loan)
end)

dbg('loans.lua carregado (QBOX Hardened).')
