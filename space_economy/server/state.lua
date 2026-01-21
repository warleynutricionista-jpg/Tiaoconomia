--============================================================
-- space_economy - server/state.lua
-- Sistema de persistência de estado (REESCRITO - SEM information_schema)
-- Otimizado para evitar erros de permissão no MySQL
--============================================================
SE = SE or {}
SE.Server = SE.Server or {}
SE.State = SE.State or {}

local U = SE.Util
local S = SE.State

-- Inicialização de estado
S.dirty = S.dirty == true
S.vaultBalance = U.toInt(S.vaultBalance, (Config.Treasury and Config.Treasury.StartBalance) or 0)
S.inflationRate = U.toNumber(S.inflationRate, (Config.Inflation and Config.Inflation.DefaultRate) or 1.0)
S.taxMultiplier = U.toNumber(S.taxMultiplier, Config.TaxMultiplierDefault or 1.0)
S.settings = type(S.settings) == 'table' and S.settings or {}

local ensured = false
local saving = false

--============================================================
-- Helpers de Schema (SEM information_schema)
--============================================================
local function tableExists(name)
  if not MySQL then return false end

  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)

  return ok and rows and #rows > 0
end

local function columnExists(tableName, columnName)
  if not MySQL then return false end

  local ok, cols = pcall(function()
    return MySQL.query.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
  end)

  return ok and cols and #cols > 0
end

local function addColumnIfNotExists(tableName, columnName, columnDef)
  if columnExists(tableName, columnName) then
    return true
  end

  local ok = pcall(function()
    MySQL.query.await(
      ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, columnDef)
    )
  end)

  if ok then
    U.dbg(('Coluna adicionada: %s.%s'):format(tableName, columnName))
  end

  return ok
end

--============================================================
-- Garantir Schema
--============================================================
local function ensureSchema()
  if ensured or not MySQL then return end
  ensured = true

  -- Tabela KV (key/value)
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy_state (
      `key` VARCHAR(64) PRIMARY KEY,
      `value` LONGTEXT,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Tabela principal (global row)
  MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS space_economy (
      id INT PRIMARY KEY,
      vaultBalance BIGINT NOT NULL DEFAULT 0,
      inflationRate DOUBLE NOT NULL DEFAULT 1.0,
      taxMultiplier DOUBLE NOT NULL DEFAULT 1.0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])

  -- Adicionar colunas se não existirem
  addColumnIfNotExists('space_economy', 'vaultBalance', 'BIGINT NOT NULL DEFAULT 0')
  addColumnIfNotExists('space_economy', 'inflationRate', 'DOUBLE NOT NULL DEFAULT 1.0')
  addColumnIfNotExists('space_economy', 'taxMultiplier', 'DOUBLE NOT NULL DEFAULT 1.0')

  -- Garantir row id=1 existe
  local defaultVault = U.toInt((Config.Treasury and Config.Treasury.StartBalance) or 0, 0)
  local defaultInflation = U.toNumber((Config.Inflation and Config.Inflation.DefaultRate) or 1.0, 1.0)
  local defaultTaxMult = U.toNumber(Config.TaxMultiplierDefault or 1.0, 1.0)

  pcall(function()
    MySQL.update.await([[
      INSERT INTO space_economy (id, vaultBalance, inflationRate, taxMultiplier)
      VALUES (1, ?, ?, ?)
      ON DUPLICATE KEY UPDATE id = id
    ]], { defaultVault, defaultInflation, defaultTaxMult })
  end)

  U.dbg('Schema garantido (sem information_schema)')
end

--============================================================
-- Marcar Estado como Modificado
--============================================================
function SE.Server.MarkDirty()
  S.dirty = true
end

--============================================================
-- Taxa de Inflação
--============================================================
function SE.Server.SetInflationRate(rate)
  rate = U.toNumber(rate, S.inflationRate)

  local minR = (Config.Inflation and Config.Inflation.MinRate) or 0.70
  local maxR = (Config.Inflation and Config.Inflation.MaxRate) or 2.00

  rate = U.clamp(rate, minR, maxR)

  if rate ~= S.inflationRate then
    S.inflationRate = rate
    SE.Server.MarkDirty()
    U.dbg(('Taxa de inflação atualizada: %.2f'):format(rate))
  end

  return S.inflationRate
end

function SE.Server.GetInflationRate()
  return U.toNumber(S.inflationRate, 1.0)
end

--============================================================
-- Multiplicador de Impostos
--============================================================
function SE.Server.SetTaxMultiplier(mult)
  mult = U.toNumber(mult, S.taxMultiplier)
  mult = U.clamp(mult, 0.10, 5.00)

  if mult ~= S.taxMultiplier then
    S.taxMultiplier = mult
    SE.Server.MarkDirty()
    U.dbg(('Multiplicador de impostos atualizado: %.2f'):format(mult))
  end

  return S.taxMultiplier
end

function SE.Server.GetTaxMultiplier()
  return U.toNumber(S.taxMultiplier, 1.0)
end

--============================================================
-- Carregar Estado do Banco de Dados
--============================================================
function SE.Server.LoadState()
  if not MySQL then
    U.dbg('AVISO: MySQL não disponível, usando valores padrão')
    return
  end

  ensureSchema()

  -- Carregar dados principais
  local ok, row = pcall(function()
    return MySQL.single.await(
      'SELECT vaultBalance, inflationRate, taxMultiplier FROM space_economy WHERE id = 1 LIMIT 1'
    )
  end)

  if ok and row then
    S.vaultBalance = U.toInt(row.vaultBalance, S.vaultBalance)
    S.inflationRate = U.toNumber(row.inflationRate, S.inflationRate)
    S.taxMultiplier = U.toNumber(row.taxMultiplier, S.taxMultiplier)
  else
    U.dbg('AVISO: Falha ao carregar estado principal, usando valores padrão')
  end

  -- Carregar settings (JSON)
  local ok2, settingsRow = pcall(function()
    return MySQL.single.await(
      'SELECT `value` FROM space_economy_state WHERE `key` = "settings" LIMIT 1'
    )
  end)

  if ok2 and settingsRow and settingsRow.value then
    local decoded = U.safeJsonDecode(settingsRow.value)
    if decoded and type(decoded) == 'table' then
      S.settings = decoded
    end
  end

  S.dirty = false

  U.dbg(('Estado carregado: Cofre=$%d | Inflação=%.2f | Impostos=%.2f'):format(
    S.vaultBalance,
    S.inflationRate,
    S.taxMultiplier
  ))
end

--============================================================
-- Salvar Estado no Banco de Dados
--============================================================
function SE.Server.SaveState(force)
  if not MySQL then return end
  if saving then return end
  if not force and not S.dirty then return end

  saving = true
  S.dirty = false

  -- Sanitização
  S.vaultBalance = U.toInt(S.vaultBalance, 0)
  S.inflationRate = U.toNumber(S.inflationRate, 1.0)
  S.taxMultiplier = U.toNumber(S.taxMultiplier, 1.0)

  if type(S.settings) ~= 'table' then
    S.settings = {}
  end

  -- Salvar estado principal
  local ok = pcall(function()
    MySQL.update.await(
      'UPDATE space_economy SET vaultBalance = ?, inflationRate = ?, taxMultiplier = ? WHERE id = 1',
      { S.vaultBalance, S.inflationRate, S.taxMultiplier }
    )
  end)

  if not ok then
    U.dbg('ERRO: Falha ao salvar estado principal')
  end

  -- Salvar settings
  local ok2 = pcall(function()
    MySQL.update.await([[
      INSERT INTO space_economy_state (`key`, `value`)
      VALUES ("settings", ?)
      ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)
    ]], { U.safeJsonEncode(S.settings) })
  end)

  if not ok2 then
    U.dbg('ERRO: Falha ao salvar settings')
  end

  saving = false

  if ok and ok2 then
    U.dbg(('Estado salvo: Cofre=$%d | Inflação=%.2f | Impostos=%.2f'):format(
      S.vaultBalance,
      S.inflationRate,
      S.taxMultiplier
    ))
  end
end

--============================================================
-- Thread de Persistência Automática
--============================================================
CreateThread(function()
  -- Aguardar MySQL
  local waited = 0
  while not MySQL do
    Wait(200)
    waited = waited + 200
    if waited > 30000 then
      U.dbg('ERRO CRÍTICO: MySQL não disponível após 30 segundos')
      return
    end
  end

  -- Carregar estado
  SE.Server.LoadState()

  -- Intervalo de salvamento
  local interval = U.toInt(U.cfg('Persistence.IntervalMs', 60000), 60000)
  if interval < 15000 then interval = 15000 end
  if interval > 600000 then interval = 600000 end

  U.dbg(('Persistência automática: %ds'):format(math.floor(interval / 1000)))

  -- Loop de salvamento
  while true do
    Wait(interval)
    SE.Server.SaveState(false)
  end
end)

--============================================================
-- Salvar ao Desligar
--============================================================
AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end

  U.dbg('Salvando estado antes de desligar...')
  SE.Server.SaveState(true)
end)

--============================================================
-- Exports
--============================================================
exports('GetVaultBalance', function()
  return U.toInt(S.vaultBalance, 0)
end)

exports('GetInflationRate', function()
  return U.toNumber(S.inflationRate, 1.0)
end)

exports('GetTaxMultiplier', function()
  return U.toNumber(S.taxMultiplier, 1.0)
end)

exports('SetInflationRate', SE.Server.SetInflationRate)
exports('SetTaxMultiplier', SE.Server.SetTaxMultiplier)
