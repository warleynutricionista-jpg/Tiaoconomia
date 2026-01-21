-- ============================================================
-- Script de Diagnóstico e Correção de Tabelas
-- Corrige problemas de charset, collation e estrutura
-- ============================================================

-- ============================================================
-- 1. Verificar e corrigir charset/collation nas tabelas principais
-- ============================================================

-- Garantir que a tabela space_economy existe com configuração correta
ALTER TABLE `space_economy`
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Garantir que a tabela space_economy_state existe
ALTER TABLE `space_economy_state`
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Corrigir tabela de investimentos (Banking System)
ALTER TABLE `space_economy_investments`
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Corrigir tabela de dívidas
ALTER TABLE `space_economy_debts`
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Corrigir tabela de logs
ALTER TABLE `space_economy_logs`
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ============================================================
-- 2. Garantir que tabelas essenciais existem
-- ============================================================

-- Tabela de estado global (necessária para cofre público)
CREATE TABLE IF NOT EXISTS `space_economy` (
  `id` INT PRIMARY KEY,
  `vaultBalance` BIGINT NOT NULL DEFAULT 0,
  `inflationRate` DOUBLE NOT NULL DEFAULT 1.0,
  `taxMultiplier` DOUBLE NOT NULL DEFAULT 1.0,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Inserir registro inicial se não existir
INSERT IGNORE INTO `space_economy` (`id`, `vaultBalance`, `inflationRate`, `taxMultiplier`)
VALUES (1, 0, 1.0, 1.0);

-- Tabela de estado key-value
CREATE TABLE IF NOT EXISTS `space_economy_state` (
  `key` VARCHAR(64) PRIMARY KEY,
  `value` LONGTEXT,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de investimentos (Banking System)
CREATE TABLE IF NOT EXISTS `space_economy_investments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL,
  `product_id` VARCHAR(32) NOT NULL,
  `amount` BIGINT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `maturity_date` DATE NULL,
  `redeemed_at` TIMESTAMP NULL,
  `yield` BIGINT DEFAULT 0,
  `tax` BIGINT DEFAULT 0,
  INDEX `idx_citizenid` (`citizenid`),
  INDEX `idx_product` (`product_id`),
  INDEX `idx_redeemed` (`redeemed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de dívidas
CREATE TABLE IF NOT EXISTS `space_economy_debts` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `amount` BIGINT NOT NULL DEFAULT 0,
  `original_amount` BIGINT NOT NULL DEFAULT 0,
  `reason` VARCHAR(200) NOT NULL DEFAULT 'Imposto',
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `interest_rate` DECIMAL(10,4) NOT NULL DEFAULT 0.01,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `due_at` TIMESTAMP NULL,
  `grace_until` TIMESTAMP NULL,
  `paid_at` TIMESTAMP NULL,
  `last_interest_at` TIMESTAMP NULL,
  `meta` LONGTEXT NULL,
  INDEX `idx_citizen_status` (`citizenid`, `status`),
  INDEX `idx_status_due` (`status`, `due_at`),
  INDEX `idx_grace` (`grace_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 3. Verificar e adicionar colunas faltantes
-- ============================================================

-- Garantir que player_vehicles tem a coluna last_ipva_at
SET @dbname = DATABASE();
SET @tablename = 'player_vehicles';
SET @columnname = 'last_ipva_at';

-- Verifica se a tabela existe antes de tentar adicionar coluna
SET @table_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
                      WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename);

-- Se a tabela existir, adiciona a coluna se ela não existir
SET @preparedStatement = (SELECT IF(
  @table_exists > 0 AND (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname
   AND TABLE_NAME = @tablename
   AND COLUMN_NAME = @columnname) = 0,
  CONCAT('ALTER TABLE `', @tablename, '` ADD COLUMN `', @columnname, '` TIMESTAMP NULL'),
  'SELECT "Column already exists or table does not exist" as message'
));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- Garantir que player_houses tem a coluna last_iptu_at
SET @tablename = 'player_houses';
SET @columnname = 'last_iptu_at';

SET @table_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
                      WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename);

SET @preparedStatement = (SELECT IF(
  @table_exists > 0 AND (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = @dbname
   AND TABLE_NAME = @tablename
   AND COLUMN_NAME = @columnname) = 0,
  CONCAT('ALTER TABLE `', @tablename, '` ADD COLUMN `', @columnname, '` TIMESTAMP NULL'),
  'SELECT "Column already exists or table does not exist" as message'
));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- ============================================================
-- 4. Corrigir problemas de collation em JOINs (dealership_vehicles)
-- ============================================================

-- Se a tabela dealership_vehicles existir, corrigir charset/collation
SET @table_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
                      WHERE TABLE_SCHEMA = DATABASE()
                      AND TABLE_NAME = 'dealership_vehicles');

SET @preparedStatement = (SELECT IF(
  @table_exists > 0,
  'ALTER TABLE `dealership_vehicles` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT "Table dealership_vehicles does not exist" as message'
));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- Corrigir coluna model especificamente se a tabela existir
SET @preparedStatement = (SELECT IF(
  @table_exists > 0 AND (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
   AND TABLE_NAME = 'dealership_vehicles'
   AND COLUMN_NAME = 'model') > 0,
  'ALTER TABLE `dealership_vehicles` MODIFY COLUMN `model` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT "Column model does not exist in dealership_vehicles" as message'
));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- ============================================================
-- 5. Verificar integridade dos dados
-- ============================================================

-- Limpar registros órfãos de investimentos (sem citizenid válido)
DELETE FROM `space_economy_investments`
WHERE `citizenid` = '' OR `citizenid` IS NULL;

-- Limpar registros órfãos de dívidas
DELETE FROM `space_economy_debts`
WHERE `citizenid` = '' OR `citizenid` IS NULL;

-- ============================================================
-- 6. Otimizar tabelas
-- ============================================================

OPTIMIZE TABLE `space_economy`;
OPTIMIZE TABLE `space_economy_state`;
OPTIMIZE TABLE `space_economy_investments`;
OPTIMIZE TABLE `space_economy_debts`;
OPTIMIZE TABLE `space_economy_logs`;

-- ============================================================
-- 7. Relatório de Status
-- ============================================================

SELECT 'Correção de tabelas concluída!' as status;

SELECT
  'space_economy' as tabela,
  COUNT(*) as registros,
  TABLE_COLLATION as collation
FROM `space_economy`, INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'space_economy'
GROUP BY TABLE_COLLATION;

SELECT
  'space_economy_investments' as tabela,
  COUNT(*) as registros_ativos,
  SUM(amount) as total_investido
FROM `space_economy_investments`
WHERE `redeemed_at` IS NULL;

SELECT
  'space_economy_debts' as tabela,
  COUNT(*) as dividas_ativas,
  SUM(amount) as total_devido
FROM `space_economy_debts`
WHERE `status` = 'active';

-- Verificar saldo do cofre público
SELECT
  'Cofre Público' as item,
  vaultBalance as saldo
FROM `space_economy`
WHERE id = 1;
