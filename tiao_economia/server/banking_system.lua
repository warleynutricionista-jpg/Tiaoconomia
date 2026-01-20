--============================================================
-- space_economy - server/banking_system.lua
-- Sistema Bancário Ultra-Realista
-- FASE 3.3 - Poupança, CDB, Investimentos
--============================================================
SE = SE or {}
SE.Banking = SE.Banking or {}

local U = SE.Util
local BK = SE.Banking

--============================================================
-- Tipos de Contas e Produtos
--============================================================
BK.Products = {
  -- Contas
  poupanca = {
    nome = 'Poupança',
    rendimento_base = 0.007,  -- 70% da SELIC
    isento_ir = true,
    liquidez = 'imediata',
    valor_minimo = 100,
  },

  conta_corrente = {
    nome = 'Conta Corrente',
    rendimento = 0,
    taxa_manutencao = 50,  -- Por mês
    isento_ir = true,
    liquidez = 'imediata',
  },

  -- Investimentos
  cdb_30 = {
    nome = 'CDB 30 Dias',
    rendimento_base = 0.90,  -- 90% do CDI (SELIC)
    prazo_dias = 30,
    liquidez = 'vencimento',
    valor_minimo = 5000,
    imposto_ir = 0.225,  -- 22.5%
  },

  cdb_60 = {
    nome = 'CDB 60 Dias',
    rendimento_base = 1.00,  -- 100% do CDI
    prazo_dias = 60,
    liquidez = 'vencimento',
    valor_minimo = 5000,
    imposto_ir = 0.20,  -- 20%
  },

  cdb_90 = {
    nome = 'CDB 90 Dias',
    rendimento_base = 1.10,  -- 110% do CDI
    prazo_dias = 90,
    liquidez = 'vencimento',
    valor_minimo = 10000,
    imposto_ir = 0.175,  -- 17.5%
  },

  cdb_180 = {
    nome = 'CDB 180 Dias',
    rendimento_base = 1.20,  -- 120% do CDI
    prazo_dias = 180,
    liquidez = 'vencimento',
    valor_minimo = 10000,
    imposto_ir = 0.175,  -- 17.5%
  },

  lci = {
    nome = 'LCI (Imobiliário)',
    rendimento_base = 0.85,  -- 85% do CDI
    prazo_dias = 90,
    liquidez = 'vencimento',
    valor_minimo = 20000,
    imposto_ir = 0,  -- ISENTO
  },

  lca = {
    nome = 'LCA (Agronegócio)',
    rendimento_base = 0.85,  -- 85% do CDI
    prazo_dias = 90,
    liquidez = 'vencimento',
    valor_minimo = 20000,
    imposto_ir = 0,  -- ISENTO
  },

  tesouro_selic = {
    nome = 'Tesouro SELIC',
    rendimento_base = 1.00,  -- 100% da SELIC
    prazo_dias = 365,
    liquidez = 'imediata',  -- Pode resgatar a qualquer momento
    valor_minimo = 1000,
    imposto_ir = 0.15,  -- 15% (aplicação > 2 anos)
  },
}

--============================================================
-- Estado
--============================================================
BK.State = {
  contas = {},  -- [citizenid] = { tipo, saldo, ... }
  investimentos = {},  -- [id] = { produto, valor, vencimento, ... }
  ultima_manutencao = 0,
  ultimo_rendimento = 0,
}

--============================================================
-- Schema
--============================================================
local schemaReady = false

local function ensureSchema()
  if schemaReady or not MySQL then return end
  schemaReady = true

  -- Contas bancárias
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_bank_accounts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      tipo VARCHAR(50) NOT NULL,
      saldo BIGINT NOT NULL DEFAULT 0,
      rendimento_acumulado BIGINT NOT NULL DEFAULT 0,
      taxa_manutencao_proxima BIGINT NOT NULL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY unique_account (citizenid, tipo),
      INDEX idx_citizen (citizenid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Investimentos
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_investments (
      id INT AUTO_INCREMENT PRIMARY KEY,
      citizenid VARCHAR(64) NOT NULL,
      produto VARCHAR(50) NOT NULL,
      valor_aplicado BIGINT NOT NULL,
      valor_bruto BIGINT NOT NULL DEFAULT 0,
      valor_liquido BIGINT NOT NULL DEFAULT 0,
      rendimento BIGINT NOT NULL DEFAULT 0,
      imposto_ir BIGINT NOT NULL DEFAULT 0,
      taxa_rendimento DECIMAL(10,4) NOT NULL,
      data_aplicacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      data_vencimento TIMESTAMP NULL,
      data_resgate TIMESTAMP NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'ativo',
      metadata LONGTEXT NULL,
      INDEX idx_citizen_status (citizenid, status),
      INDEX idx_vencimento (data_vencimento),
      INDEX idx_produto (produto)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Histórico de rendimentos
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_bank_yields (
      id INT AUTO_INCREMENT PRIMARY KEY,
      account_id INT NULL,
      investment_id INT NULL,
      citizenid VARCHAR(64) NOT NULL,
      tipo VARCHAR(50) NOT NULL,
      valor BIGINT NOT NULL,
      taxa DECIMAL(10,4) NOT NULL,
      selic_periodo DECIMAL(10,4) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_citizen (citizenid),
      INDEX idx_created (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  U.dbg('[Banking] Schema garantido')
end

CreateThread(function()
  while not MySQL do Wait(250) end
  ensureSchema()
end)

--============================================================
-- Abrir Conta
--============================================================
function BK.OpenAccount(citizenid, tipo)
  tipo = U.safeStr(tipo, 'poupanca')

  if not BK.Products[tipo] or tipo:find('cdb') or tipo:find('lci') or tipo:find('lca') or tipo:find('tesouro') then
    return false, 'Tipo de conta inválido'
  end

  -- Verificar se já existe
  local exists = MySQL.scalar.await([[
    SELECT id FROM space_economy_bank_accounts
    WHERE citizenid = ? AND tipo = ?
  ]], { citizenid, tipo })

  if exists then
    return false, 'Conta já existe'
  end

  -- Criar conta
  local inserted = MySQL.insert.await([[
    INSERT INTO space_economy_bank_accounts (citizenid, tipo, saldo)
    VALUES (?, ?, 0)
  ]], { citizenid, tipo })

  U.dbg(('[Banking] Conta aberta: %s - %s (#%d)'):format(citizenid, tipo, inserted))

  return true, inserted
end

--============================================================
-- Depositar em Conta
--============================================================
function BK.Deposit(citizenid, tipo, valor)
  tipo = U.safeStr(tipo, 'poupanca')
  valor = U.toInt(valor, 0)

  if valor <= 0 then return false, 'Valor inválido' end

  local account = MySQL.single.await([[
    SELECT * FROM space_economy_bank_accounts
    WHERE citizenid = ? AND tipo = ?
  ]], { citizenid, tipo })

  if not account then
    -- Criar automaticamente
    local ok, accountId = BK.OpenAccount(citizenid, tipo)
    if not ok then return false, accountId end
  end

  -- Depositar
  MySQL.update.await([[
    UPDATE space_economy_bank_accounts
    SET saldo = saldo + ?
    WHERE citizenid = ? AND tipo = ?
  ]], { valor, citizenid, tipo })

  U.dbg(('[Banking] Depósito: %s +$%d em %s'):format(citizenid, valor, tipo))

  return true
end

--============================================================
-- Sacar de Conta
--============================================================
function BK.Withdraw(citizenid, tipo, valor)
  tipo = U.safeStr(tipo, 'poupanca')
  valor = U.toInt(valor, 0)

  if valor <= 0 then return false, 'Valor inválido' end

  local account = MySQL.single.await([[
    SELECT * FROM space_economy_bank_accounts
    WHERE citizenid = ? AND tipo = ?
  ]], { citizenid, tipo })

  if not account then return false, 'Conta não encontrada' end

  local saldo = U.toInt(account.saldo, 0)
  if saldo < valor then return false, 'Saldo insuficiente' end

  -- Sacar
  MySQL.update.await([[
    UPDATE space_economy_bank_accounts
    SET saldo = saldo - ?
    WHERE citizenid = ? AND tipo = ?
  ]], { valor, citizenid, tipo })

  U.dbg(('[Banking] Saque: %s -$%d de %s'):format(citizenid, valor, tipo))

  return true
end

--============================================================
-- Aplicar em Investimento
--============================================================
function BK.Invest(citizenid, produto, valor)
  produto = U.safeStr(produto, '')
  valor = U.toInt(valor, 0)

  local produtoInfo = BK.Products[produto]
  if not produtoInfo then return false, 'Produto não encontrado' end

  if valor < produtoInfo.valor_minimo then
    return false, string.format('Valor mínimo: $%d', produtoInfo.valor_minimo)
  end

  -- Obter SELIC atual
  local selic = 0.0075  -- Padrão
  if SE.MonetaryPolicy and SE.MonetaryPolicy.State then
    selic = SE.MonetaryPolicy.State.selic_atual or 0.0075
  end

  -- Calcular taxa de rendimento
  local taxa = selic * produtoInfo.rendimento_base

  -- Calcular vencimento
  local vencimento = os.time() + (produtoInfo.prazo_dias * 24 * 60 * 60)

  -- Inserir investimento
  local investmentId = MySQL.insert.await([[
    INSERT INTO space_economy_investments (
      citizenid, produto, valor_aplicado, taxa_rendimento,
      data_vencimento, status
    ) VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), 'ativo')
  ]], { citizenid, produto, valor, taxa, vencimento })

  U.dbg(('[Banking] Investimento: %s aplicou $%d em %s (taxa: %.2f%%)'):format(
    citizenid, valor, produto, taxa * 100
  ))

  return true, {
    id = investmentId,
    produto = produtoInfo.nome,
    valor_aplicado = valor,
    taxa_rendimento = taxa,
    vencimento = vencimento,
    prazo_dias = produtoInfo.prazo_dias,
  }
end

--============================================================
-- Resgatar Investimento
--============================================================
function BK.Redeem(investmentId, citizenid)
  investmentId = U.toInt(investmentId, 0)

  local investment = MySQL.single.await([[
    SELECT * FROM space_economy_investments
    WHERE id = ? AND citizenid = ? AND status = 'ativo'
  ]], { investmentId, citizenid })

  if not investment then
    return false, 'Investimento não encontrado'
  end

  local produto = investment.produto
  local produtoInfo = BK.Products[produto]

  if not produtoInfo then
    return false, 'Produto inválido'
  end

  -- Verificar liquidez
  local vencimento = investment.data_vencimento and
    os.time(investment.data_vencimento) or os.time()

  local pode_resgatar = (produtoInfo.liquidez == 'imediata') or
    (os.time() >= vencimento)

  if not pode_resgatar then
    return false, 'Investimento ainda não venceu (sem liquidez)'
  end

  -- Calcular rendimento
  local valor_aplicado = U.toInt(investment.valor_aplicado, 0)
  local taxa = U.toNumber(investment.taxa_rendimento, 0)

  -- Rendimento proporcional aos dias
  local dias_aplicado = math.floor((os.time() - os.time(investment.data_aplicacao)) / (24 * 60 * 60))
  local dias_totais = produtoInfo.prazo_dias

  local rendimento_bruto = math.floor(valor_aplicado * taxa * (dias_aplicado / dias_totais))
  local valor_bruto = valor_aplicado + rendimento_bruto

  -- Calcular IR
  local imposto_ir = math.floor(rendimento_bruto * produtoInfo.imposto_ir)
  local valor_liquido = valor_bruto - imposto_ir

  -- Atualizar investimento
  MySQL.update.await([[
    UPDATE space_economy_investments
    SET status = 'resgatado',
        valor_bruto = ?,
        valor_liquido = ?,
        rendimento = ?,
        imposto_ir = ?,
        data_resgate = NOW()
    WHERE id = ?
  ]], { valor_bruto, valor_liquido, rendimento_bruto, imposto_ir, investmentId })

  -- IR vai para tesouro
  if imposto_ir > 0 and SE.Treasury then
    SE.Treasury.Deposit(imposto_ir, 'imposto_renda_investimento', {
      citizenid = citizenid,
      investment_id = investmentId,
    })
  end

  U.dbg(('[Banking] Resgate: %s resgatou inv #%d - $%d (rend: $%d, IR: $%d)'):format(
    citizenid, investmentId, valor_liquido, rendimento_bruto, imposto_ir
  ))

  return true, {
    valor_aplicado = valor_aplicado,
    rendimento_bruto = rendimento_bruto,
    imposto_ir = imposto_ir,
    valor_liquido = valor_liquido,
    rentabilidade = valor_aplicado > 0 and ((valor_bruto / valor_aplicado) - 1) or 0,
    dias_aplicado = dias_aplicado,
  }
end

--============================================================
-- Pagar Rendimento de Poupança
--============================================================
function BK.PaySavingsYield()
  -- Obter SELIC
  local selic = 0.0075
  if SE.MonetaryPolicy and SE.MonetaryPolicy.State then
    selic = SE.MonetaryPolicy.State.selic_atual or 0.0075
  end

  local taxa_poupanca = selic * 0.70  -- 70% da SELIC

  -- Buscar todas as poupanças
  local accounts = MySQL.query.await([[
    SELECT * FROM space_economy_bank_accounts
    WHERE tipo = 'poupanca' AND saldo > 0
  ]]) or {}

  for _, account in ipairs(accounts) do
    local saldo = U.toInt(account.saldo, 0)
    local rendimento = math.floor(saldo * taxa_poupanca)

    if rendimento > 0 then
      MySQL.update.await([[
        UPDATE space_economy_bank_accounts
        SET saldo = saldo + ?,
            rendimento_acumulado = rendimento_acumulado + ?
        WHERE id = ?
      ]], { rendimento, rendimento, account.id })

      -- Registrar histórico
      MySQL.insert.await([[
        INSERT INTO space_economy_bank_yields
          (account_id, citizenid, tipo, valor, taxa, selic_periodo)
        VALUES (?, ?, 'poupanca', ?, ?, ?)
      ]], { account.id, account.citizenid, rendimento, taxa_poupanca, selic })

      U.dbg(('[Banking] Rendimento poupança: %s +$%d (taxa: %.2f%%)'):format(
        account.citizenid, rendimento, taxa_poupanca * 100
      ))
    end
  end
end

--============================================================
-- Cobrar Taxa de Manutenção
--============================================================
function BK.ChargeMaintenanceFee()
  local fee = BK.Products.conta_corrente.taxa_manutencao

  local accounts = MySQL.query.await([[
    SELECT * FROM space_economy_bank_accounts
    WHERE tipo = 'conta_corrente'
  ]]) or {}

  for _, account in ipairs(accounts) do
    local saldo = U.toInt(account.saldo, 0)

    if saldo >= fee then
      MySQL.update.await([[
        UPDATE space_economy_bank_accounts
        SET saldo = saldo - ?,
            taxa_manutencao_proxima = ?
        WHERE id = ?
      ]], { fee, fee, account.id })

      -- Taxa vai para tesouro
      if SE.Treasury then
        SE.Treasury.Deposit(fee, 'taxa_manutencao_bancaria', {
          citizenid = account.citizenid,
        })
      end

      U.dbg(('[Banking] Taxa manutenção: %s -$%d'):format(account.citizenid, fee))
    end
  end
end

--============================================================
-- Obter Extrato
--============================================================
function BK.GetStatement(citizenid)
  -- Contas
  local accounts = MySQL.query.await([[
    SELECT * FROM space_economy_bank_accounts
    WHERE citizenid = ?
  ]], { citizenid }) or {}

  -- Investimentos
  local investments = MySQL.query.await([[
    SELECT * FROM space_economy_investments
    WHERE citizenid = ?
    ORDER BY data_aplicacao DESC
    LIMIT 20
  ]], { citizenid }) or {}

  -- Processar investimentos
  for _, inv in ipairs(investments) do
    local produtoInfo = BK.Products[inv.produto]
    if produtoInfo then
      inv.produto_nome = produtoInfo.nome
      inv.pode_resgatar = (inv.status == 'ativo') and
        ((produtoInfo.liquidez == 'imediata') or
         (inv.data_vencimento and os.time() >= os.time(inv.data_vencimento)))
    end
  end

  return {
    contas = accounts,
    investimentos = investments,
  }
end

--============================================================
-- Thread - Rendimento Poupança (Mensal)
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end
  ensureSchema()

  -- Intervalo: 2 horas (em prod seria mensal)
  local intervalMs = 7200000

  while true do
    Wait(intervalMs)
    BK.PaySavingsYield()
  end
end)

--============================================================
-- Thread - Taxa Manutenção (Mensal)
--============================================================
CreateThread(function()
  while not MySQL do Wait(1000) end

  -- Intervalo: 2 horas (em prod seria mensal)
  local intervalMs = 7200000

  Wait(intervalMs / 2)  -- Offset para não rodar junto com rendimento

  while true do
    Wait(intervalMs)
    BK.ChargeMaintenanceFee()
  end
end)

--============================================================
-- Comandos
--============================================================
RegisterCommand('banco_investir', function(source, args)
  local src = tonumber(source)
  if src == 0 then return end

  local produto = args[1]
  local valor = tonumber(args[2])

  if not produto or not valor then
    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', 'Uso: /banco_investir <produto> <valor>' }
    })
    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', 'Produtos: cdb_30, cdb_60, cdb_90, cdb_180, lci, lca, tesouro_selic' }
    })
    return
  end

  local citizenid = SE.Bridge.GetCitizenId(src)
  if not citizenid then return end

  -- Remover dinheiro primeiro
  if SE.Integrations and SE.Integrations.RemoveMoney then
    local removed = SE.Integrations.RemoveMoney(src, valor, 'bank')
    if not removed then
      TriggerClientEvent('chat:addMessage', src, {
        args = { '[BANCO]', 'Saldo insuficiente' }
      })
      return
    end
  end

  local ok, result = BK.Invest(citizenid, produto, valor)

  if ok then
    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', string.format('Investimento realizado: %s - $%d (taxa: %.2f%%)',
        result.produto, result.valor_aplicado, result.taxa_rendimento * 100) }
    })
  else
    -- Devolver dinheiro
    if SE.Integrations and SE.Integrations.AddMoney then
      SE.Integrations.AddMoney(src, valor, 'bank')
    end

    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', 'Erro: ' .. result }
    })
  end
end, false)

RegisterCommand('banco_resgatar', function(source, args)
  local src = tonumber(source)
  if src == 0 then return end

  local investmentId = tonumber(args[1])

  if not investmentId then
    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', 'Uso: /banco_resgatar <id>' }
    })
    return
  end

  local citizenid = SE.Bridge.GetCitizenId(src)
  if not citizenid then return end

  local ok, result = BK.Redeem(investmentId, citizenid)

  if ok then
    -- Adicionar dinheiro
    if SE.Integrations and SE.Integrations.AddMoney then
      SE.Integrations.AddMoney(src, result.valor_liquido, 'bank')
    end

    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', string.format('Resgate efetuado: $%d (rendimento: $%d | IR: $%d | rentabilidade: %.2f%%)',
        result.valor_liquido, result.rendimento_bruto, result.imposto_ir, result.rentabilidade * 100) }
    })
  else
    TriggerClientEvent('chat:addMessage', src, {
      args = { '[BANCO]', 'Erro: ' .. result }
    })
  end
end, false)

RegisterCommand('banco_extrato', function(source, args)
  local src = tonumber(source)
  if src == 0 then return end

  local citizenid = SE.Bridge.GetCitizenId(src)
  if not citizenid then return end

  local statement = BK.GetStatement(citizenid)

  print('\n========================================')
  print('EXTRATO BANCÁRIO')
  print('========================================')

  print('CONTAS:')
  for _, acc in ipairs(statement.contas) do
    print(string.format('  %s: $%d (rendimento acumulado: $%d)',
      acc.tipo:upper(), acc.saldo, acc.rendimento_acumulado))
  end

  print('\nINVESTIMENTOS:')
  for _, inv in ipairs(statement.investimentos) do
    local status_txt = inv.status == 'ativo' and '🟢 ATIVO' or '⚪ RESGATADO'
    print(string.format('  #%d %s - %s', inv.id, status_txt, inv.produto_nome or inv.produto))
    print(string.format('    Aplicado: $%d | Taxa: %.2f%% | Vencimento: %s',
      inv.valor_aplicado,
      inv.taxa_rendimento * 100,
      inv.data_vencimento and os.date('%Y-%m-%d', os.time(inv.data_vencimento)) or 'N/A'
    ))

    if inv.status == 'resgatado' then
      print(string.format('    Resgatado: $%d (rendimento: $%d | IR: $%d)',
        inv.valor_liquido, inv.rendimento, inv.imposto_ir))
    end
  end

  print('========================================\n')
end, false)

--============================================================
-- Exports
--============================================================
exports('BankOpenAccount', BK.OpenAccount)
exports('BankDeposit', BK.Deposit)
exports('BankWithdraw', BK.Withdraw)
exports('BankInvest', BK.Invest)
exports('BankRedeem', BK.Redeem)
exports('BankGetStatement', BK.GetStatement)

print('^2[space_economy]^7 Banking System loaded - Savings, CDB, LCI/LCA and Tesouro active')
