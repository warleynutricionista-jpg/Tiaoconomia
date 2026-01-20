--============================================================
-- space_economy - server/banking_system.lua
-- Sistema Bancário Completo
-- Poupança, CDB, LCI/LCA, Tesouro SELIC
--============================================================
SE = SE or {}
SE.BankingSystem = SE.BankingSystem or {}

local U = SE.Util
local BS = SE.BankingSystem

--============================================================
-- Produtos Bancários
--============================================================
local Products = {
  -- Poupança
  poupanca = {
    id = 'poupanca',
    name = 'Poupança',
    description = 'Rendimento mensal baseado na SELIC',
    minInvestment = 100,
    liquidity = 'imediata',
    taxFree = true,
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      local yield = selic * 0.70  -- 70% da SELIC
      return amount * yield * (days / 30)
    end,
  },

  -- CDB 30 dias
  cdb_30 = {
    id = 'cdb_30',
    name = 'CDB 30 dias',
    description = '90% do CDI - Liquidez em 30 dias',
    minInvestment = 5000,
    term = 30,
    liquidity = '30 dias',
    taxRate = 0.225,  -- IR 22.5%
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      local cdi = selic * 0.99  -- CDI ≈ 99% SELIC
      local yield = cdi * 0.90  -- 90% CDI
      return amount * yield * (days / 30)
    end,
  },

  -- CDB 60 dias
  cdb_60 = {
    id = 'cdb_60',
    name = 'CDB 60 dias',
    description = '100% do CDI - Liquidez em 60 dias',
    minInvestment = 5000,
    term = 60,
    liquidity = '60 dias',
    taxRate = 0.20,  -- IR 20%
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      local cdi = selic * 0.99
      local yield = cdi * 1.00  -- 100% CDI
      return amount * yield * (days / 30)
    end,
  },

  -- CDB 90 dias
  cdb_90 = {
    id = 'cdb_90',
    name = 'CDB 90 dias',
    description = '110% do CDI - Liquidez em 90 dias',
    minInvestment = 10000,
    term = 90,
    liquidity = '90 dias',
    taxRate = 0.175,  -- IR 17.5%
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      local cdi = selic * 0.99
      local yield = cdi * 1.10  -- 110% CDI
      return amount * yield * (days / 30)
    end,
  },

  -- CDB 180 dias
  cdb_180 = {
    id = 'cdb_180',
    name = 'CDB 180 dias',
    description = '120% do CDI - Liquidez em 180 dias',
    minInvestment = 10000,
    term = 180,
    liquidity = '180 dias',
    taxRate = 0.175,  -- IR 17.5%
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      local cdi = selic * 0.99
      local yield = cdi * 1.20  -- 120% CDI
      return amount * yield * (days / 30)
    end,
  },

  -- LCI/LCA (Isento de IR)
  lci = {
    id = 'lci',
    name = 'LCI/LCA',
    description = '85% do CDI - ISENTO de IR',
    minInvestment = 20000,
    term = 90,
    liquidity = '90 dias',
    taxFree = true,
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      local cdi = selic * 0.99
      local yield = cdi * 0.85  -- 85% CDI
      return amount * yield * (days / 30)
    end,
  },

  -- Tesouro SELIC
  tesouro = {
    id = 'tesouro',
    name = 'Tesouro SELIC',
    description = '100% da SELIC - Liquidez imediata',
    minInvestment = 1000,
    liquidity = 'imediata',
    taxRate = 0.15,  -- IR 15%
    calculateYield = function(amount, days)
      local selic = exports.tiao_economia:GetSELIC() or 0.005
      return amount * selic * (days / 30)
    end,
  },
}

--============================================================
-- Investir
--============================================================
function BS.Invest(src, productId, amount)
  src = tonumber(src)
  amount = U.toInt(amount, 0)

  if not src or amount <= 0 then return false end

  -- Produto existe?
  local product = Products[productId]
  if not product then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Produto inválido'
    })
    return false
  end

  -- Valor mínimo?
  if amount < product.minInvestment then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = string.format('Investimento mínimo: $%s', U.formatNumber(product.minInvestment))
    })
    return false
  end

  local citizenid = SE.Integrations.GetCitizenId(src)
  if not citizenid then return false end

  -- Tem dinheiro?
  local hasMoney = SE.Integrations.GetMoney(src, 'bank') >= amount
  if not hasMoney then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Saldo insuficiente'
    })
    return false
  end

  -- Remover dinheiro
  SE.Integrations.RemoveMoney(src, 'bank', amount, 'Investimento ' .. product.name)

  -- Criar investimento
  if not MySQL then return false end

  local maturityDate = product.term and os.time() + (product.term * 86400) or nil

  MySQL.insert.await([[
    INSERT INTO space_economy_investments (
      citizenid, product_id, amount, created_at, maturity_date
    ) VALUES (?, ?, ?, NOW(), ?)
  ]], {
    citizenid,
    productId,
    amount,
    maturityDate and os.date('%Y-%m-%d %H:%M:%S', maturityDate) or nil
  })

  TriggerClientEvent('ox_lib:notify', src, {
    type = 'success',
    title = 'Investimento Realizado',
    description = string.format('%s - $%s\n%s',
      product.name,
      U.formatNumber(amount),
      product.description
    ),
    duration = 8000,
  })

  U.dbg(('[Banking] %s invested $%d in %s'):format(citizenid, amount, productId))

  return true
end

--============================================================
-- Resgatar Investimento
--============================================================
function BS.Redeem(src, investmentId)
  src = tonumber(src)
  investmentId = U.toInt(investmentId, 0)

  if not src or investmentId <= 0 or not MySQL then return false end

  local citizenid = SE.Integrations.GetCitizenId(src)
  if not citizenid then return false end

  -- Buscar investimento
  local investment = MySQL.single.await([[
    SELECT id, product_id, amount, created_at, maturity_date
    FROM space_economy_investments
    WHERE id = ? AND citizenid = ? AND redeemed_at IS NULL
    LIMIT 1
  ]], { investmentId, citizenid })

  if not investment then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'error',
      description = 'Investimento não encontrado'
    })
    return false
  end

  local product = Products[investment.product_id]
  if not product then return false end

  -- Calcular rendimento
  local investedAt = investment.created_at
  local now = os.time()
  local investedTimestamp = 0

  -- Parse timestamp
  local year, month, day, hour, min, sec = investedAt:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
  if year then
    investedTimestamp = os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec)
    })
  end

  local daysInvested = math.max(0, (now - investedTimestamp) / 86400)

  -- Verificar se pode resgatar (se tiver prazo)
  if investment.maturity_date then
    local matYear, matMonth, matDay = investment.maturity_date:match('(%d+)-(%d+)-(%d+)')
    if matYear then
      local maturityTimestamp = os.time({
        year = tonumber(matYear),
        month = tonumber(matMonth),
        day = tonumber(matDay),
        hour = 0,
        min = 0,
        sec = 0
      })

      if now < maturityTimestamp then
        TriggerClientEvent('ox_lib:notify', src, {
          type = 'error',
          description = string.format('Resgate disponível apenas em %s', investment.maturity_date)
        })
        return false
      end
    end
  end

  -- Calcular rendimento bruto
  local grossYield = product.calculateYield(investment.amount, daysInvested)

  -- Calcular IR
  local tax = 0
  if not product.taxFree and product.taxRate then
    tax = grossYield * product.taxRate
  end

  local netYield = grossYield - tax
  local totalAmount = investment.amount + netYield

  -- Marcar como resgatado
  MySQL.execute.await([[
    UPDATE space_economy_investments
    SET redeemed_at = NOW(), yield = ?, tax = ?
    WHERE id = ?
  ]], { netYield, tax, investmentId })

  -- Devolver dinheiro
  SE.Integrations.AddMoney(src, 'bank', totalAmount, 'Resgate de investimento')

  TriggerClientEvent('ox_lib:notify', src, {
    type = 'success',
    title = 'Resgate Realizado',
    description = string.format('%s\nPrincipal: $%s\nRendimento: $%s\nIR: $%s\nTotal: $%s',
      product.name,
      U.formatNumber(investment.amount),
      U.formatNumber(grossYield),
      U.formatNumber(tax),
      U.formatNumber(totalAmount)
    ),
    duration = 12000,
  })

  U.dbg(('[Banking] %s redeemed investment #%d - Yield: $%.2f (Tax: $%.2f)'):format(
    citizenid,
    investmentId,
    netYield,
    tax
  ))

  return true
end

--============================================================
-- Listar Investimentos do Player
--============================================================
function BS.GetInvestments(citizenid)
  if not MySQL or not citizenid then return {} end

  local investments = MySQL.query.await([[
    SELECT id, product_id, amount, created_at, maturity_date, redeemed_at, yield, tax
    FROM space_economy_investments
    WHERE citizenid = ?
    ORDER BY created_at DESC
  ]], { citizenid })

  if not investments then return {} end

  local result = {}

  for _, inv in ipairs(investments) do
    local product = Products[inv.product_id]
    if product then
      -- Calcular rendimento atual (se ainda não resgatado)
      local currentYield = 0
      local currentTax = 0

      if not inv.redeemed_at then
        local investedTimestamp = 0
        local year, month, day, hour, min, sec = inv.created_at:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
        if year then
          investedTimestamp = os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
          })
        end

        local daysInvested = math.max(0, (os.time() - investedTimestamp) / 86400)
        local grossYield = product.calculateYield(inv.amount, daysInvested)

        if not product.taxFree and product.taxRate then
          currentTax = grossYield * product.taxRate
        end

        currentYield = grossYield - currentTax
      end

      table.insert(result, {
        id = inv.id,
        productId = inv.product_id,
        productName = product.name,
        amount = inv.amount,
        createdAt = inv.created_at,
        maturityDate = inv.maturity_date,
        redeemedAt = inv.redeemed_at,
        yield = inv.yield or currentYield,
        tax = inv.tax or currentTax,
        canRedeem = inv.redeemed_at == nil,
      })
    end
  end

  return result
end

--============================================================
-- Comando: Investir
--============================================================
RegisterCommand('banco_investir', function(source, args)
  local src = tonumber(source)

  if not args[1] or not args[2] then
    print('Uso: /banco_investir <produto> <valor>')
    print('Produtos disponíveis:')
    for id, product in pairs(Products) do
      print(string.format('  %s - %s (Mín: $%s)',
        id,
        product.name,
        U.formatNumber(product.minInvestment)
      ))
    end
    return
  end

  local productId = args[1]
  local amount = tonumber(args[2]) or 0

  BS.Invest(src, productId, amount)
end, false)

--============================================================
-- Comando: Resgatar
--============================================================
RegisterCommand('banco_resgatar', function(source, args)
  local src = tonumber(source)

  if not args[1] then
    print('Uso: /banco_resgatar <id>')
    return
  end

  local investmentId = tonumber(args[1]) or 0

  BS.Redeem(src, investmentId)
end, false)

--============================================================
-- Comando: Extrato
--============================================================
RegisterCommand('banco_extrato', function(source, args)
  local src = tonumber(source)

  local citizenid = SE.Integrations.GetCitizenId(src)
  if not citizenid then return end

  local investments = BS.GetInvestments(citizenid)

  print('\n========================================')
  print('EXTRATO DE INVESTIMENTOS')
  print('========================================')

  if #investments == 0 then
    print('Nenhum investimento encontrado')
  else
    local totalInvested = 0
    local totalYield = 0

    for _, inv in ipairs(investments) do
      totalInvested = totalInvested + inv.amount
      totalYield = totalYield + (inv.yield or 0)

      print(string.format('#%d | %s | $%s → $%s | %s',
        inv.id,
        inv.productName,
        U.formatNumber(inv.amount),
        U.formatNumber(inv.amount + (inv.yield or 0)),
        inv.redeemedAt and 'RESGATADO' or 'ATIVO'
      ))
    end

    print('')
    print(string.format('Total Investido: $%s', U.formatNumber(totalInvested)))
    print(string.format('Rendimento Total: $%s', U.formatNumber(totalYield)))
  end

  print('========================================\n')

  if src ~= 0 then
    TriggerClientEvent('ox_lib:notify', src, {
      type = 'success',
      description = 'Extrato gerado no console'
    })
  end
end, false)

--============================================================
-- Thread de Rendimento Automático (Poupança)
--============================================================
CreateThread(function()
  -- Aguardar inicialização
  Wait(30000)

  while true do
    -- A cada 2 horas (em produção seria mensal)
    Wait(7200000)

    if not MySQL then
      Wait(60000)
      goto continue
    end

    U.dbg('[Banking] Processing automatic yields for poupanca...')

    -- Buscar todos os investimentos em poupança ativos
    local investments = MySQL.query.await([[
      SELECT id, citizenid, amount, created_at
      FROM space_economy_investments
      WHERE product_id = 'poupanca' AND redeemed_at IS NULL
    ]], {})

    if investments then
      for _, inv in ipairs(investments) do
        local product = Products.poupanca

        -- Calcular rendimento do período
        local daysInvested = 60  -- Período de 2h = aproximadamente 2 meses simulados

        local grossYield = product.calculateYield(inv.amount, daysInvested)

        -- Atualizar saldo
        MySQL.execute.await([[
          UPDATE space_economy_investments
          SET amount = amount + ?
          WHERE id = ?
        ]], { grossYield, inv.id })

        U.dbg(('[Banking] Poupanca #%d - Yield: $%.2f'):format(inv.id, grossYield))
      end

      U.dbg(('[Banking] Processed %d poupanca investments'):format(#investments))
    end

    ::continue::
  end
end)

--============================================================
-- Garantir Tabelas
--============================================================
CreateThread(function()
  if not MySQL then return end

  Wait(2000)

  pcall(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS space_economy_investments (
        id INT AUTO_INCREMENT PRIMARY KEY,
        citizenid VARCHAR(50) NOT NULL,
        product_id VARCHAR(32) NOT NULL,
        amount BIGINT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        maturity_date DATE NULL,
        redeemed_at TIMESTAMP NULL,
        yield BIGINT DEFAULT 0,
        tax BIGINT DEFAULT 0,
        INDEX idx_citizenid (citizenid),
        INDEX idx_product (product_id),
        INDEX idx_redeemed (redeemed_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
  end)

  U.dbg('[Banking System] Tables ensured')
end)

--============================================================
-- Exports
--============================================================
exports('Invest', BS.Invest)
exports('RedeemInvestment', BS.Redeem)
exports('GetInvestments', BS.GetInvestments)

print('^2[space_economy]^7 Banking System loaded - ' .. U.tableCount(Products) .. ' products available')
