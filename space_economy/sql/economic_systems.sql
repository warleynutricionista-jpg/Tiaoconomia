-- ============================================================
-- Tião Economia - Economic Systems Tables
-- Tabelas para sistemas econômicos avançados (v4.0)
-- ============================================================

-- Tabela de Transações para Economy Monitor
CREATE TABLE IF NOT EXISTS `space_economy_transactions` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `category` VARCHAR(64) NOT NULL,
  `amount` BIGINT NOT NULL,
  `metadata` TEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_category` (`category`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabela de Rastreamento do Dinheiro (Alta Granularidade)
CREATE TABLE IF NOT EXISTS `space_economy_money_trail` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `amount` BIGINT NOT NULL,
  `account` VARCHAR(16) NOT NULL,
  `flow_type` VARCHAR(16) NOT NULL,
  `reason` VARCHAR(128) NULL,
  `from_type` VARCHAR(32) NULL,
  `from_id` VARCHAR(64) NULL,
  `to_type` VARCHAR(32) NULL,
  `to_id` VARCHAR(64) NULL,
  `metadata` LONGTEXT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_timestamp` (`timestamp`),
  INDEX `idx_from` (`from_type`, `from_id`),
  INDEX `idx_to` (`to_type`, `to_id`),
  INDEX `idx_amount` (`amount`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabela de Histórico da SELIC (Monetary Policy)
CREATE TABLE IF NOT EXISTS `space_economy_selic_history` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `selic` DOUBLE NOT NULL,
  `decision` VARCHAR(16),
  `inflation` DOUBLE,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabela de Ações (Stock Market)
CREATE TABLE IF NOT EXISTS `space_economy_stocks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL,
  `ticker` VARCHAR(8) NOT NULL,
  `quantity` INT NOT NULL DEFAULT 0,
  `purchase_price` DOUBLE NOT NULL,
  `purchased_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_holding` (`citizenid`, `ticker`),
  INDEX `idx_citizenid` (`citizenid`),
  INDEX `idx_ticker` (`ticker`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabela de Investimentos (Banking System)
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabela de Histórico de Salário Mínimo (Labor Market)
CREATE TABLE IF NOT EXISTS `space_economy_wage_history` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `old_wage` INT NOT NULL,
  `new_wage` INT NOT NULL,
  `adjustment` DOUBLE NOT NULL,
  `inflation` DOUBLE,
  `pib_growth` DOUBLE,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- Organizações/Empresas de Players
-- ============================================================
CREATE TABLE IF NOT EXISTS `space_economy_organizations` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(64) NOT NULL UNIQUE,
  `tag` VARCHAR(8) NOT NULL UNIQUE,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `balance` BIGINT NOT NULL DEFAULT 0,
  `settings` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `space_economy_org_members` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `org_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `role` VARCHAR(32) NOT NULL DEFAULT 'staff',
  `permissions` JSON NULL,
  `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_member` (`org_id`, `citizenid`),
  INDEX `idx_org_id` (`org_id`),
  INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `space_economy_org_products` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `org_id` INT NOT NULL,
  `item` VARCHAR(64) NOT NULL,
  `label` VARCHAR(64) NULL,
  `base_cost` BIGINT NOT NULL DEFAULT 0,
  `price` BIGINT NOT NULL DEFAULT 0,
  `stock` INT NOT NULL DEFAULT 0,
  `metadata` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_product` (`org_id`, `item`),
  INDEX `idx_org_id` (`org_id`),
  INDEX `idx_item` (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `space_economy_org_transactions` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `org_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `item` VARCHAR(64) NOT NULL,
  `quantity` INT NOT NULL,
  `unit_price` BIGINT NOT NULL,
  `logistics_fee` BIGINT NOT NULL DEFAULT 0,
  `tax_amount` BIGINT NOT NULL DEFAULT 0,
  `total` BIGINT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_org_id` (`org_id`),
  INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- Views para Relatórios
-- ============================================================

-- View: Resumo de Transações por Categoria
CREATE OR REPLACE VIEW `vw_economy_transactions_summary` AS
SELECT
  `category`,
  COUNT(*) as `count`,
  SUM(`amount`) as `total_volume`,
  AVG(`amount`) as `avg_amount`,
  MIN(`amount`) as `min_amount`,
  MAX(`amount`) as `max_amount`,
  DATE(`created_at`) as `date`
FROM `space_economy_transactions`
WHERE `created_at` >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY `category`, DATE(`created_at`)
ORDER BY `date` DESC, `total_volume` DESC;

-- View: Portfólio Consolidado de Ações
CREATE OR REPLACE VIEW `vw_stock_portfolio_summary` AS
SELECT
  `citizenid`,
  COUNT(DISTINCT `ticker`) as `unique_stocks`,
  SUM(`quantity`) as `total_shares`,
  SUM(`quantity` * `purchase_price`) as `total_invested`
FROM `space_economy_stocks`
WHERE `quantity` > 0
GROUP BY `citizenid`;

-- View: Investimentos Ativos
CREATE OR REPLACE VIEW `vw_active_investments` AS
SELECT
  `citizenid`,
  `product_id`,
  COUNT(*) as `count`,
  SUM(`amount`) as `total_invested`,
  MIN(`created_at`) as `oldest_investment`,
  MAX(`maturity_date`) as `latest_maturity`
FROM `space_economy_investments`
WHERE `redeemed_at` IS NULL
GROUP BY `citizenid`, `product_id`;

-- View: Desempenho da SELIC
CREATE OR REPLACE VIEW `vw_selic_performance` AS
SELECT
  `selic`,
  `decision`,
  `inflation`,
  `created_at`,
  LAG(`selic`) OVER (ORDER BY `created_at`) as `previous_selic`,
  (`selic` - LAG(`selic`) OVER (ORDER BY `created_at`)) as `change`
FROM `space_economy_selic_history`
ORDER BY `created_at` DESC
LIMIT 50;

-- ============================================================
-- Stored Procedures
-- ============================================================

-- Procedure: Limpar transações antigas (>30 dias)
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS `sp_cleanup_old_transactions`()
BEGIN
  DELETE FROM `space_economy_transactions`
  WHERE `created_at` < DATE_SUB(NOW(), INTERVAL 30 DAY);

  SELECT ROW_COUNT() as `deleted_rows`;
END$$
DELIMITER ;

-- Procedure: Calcular métricas diárias
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS `sp_calculate_daily_metrics`()
BEGIN
  -- Total de transações hoje
  SELECT
    COUNT(*) as `total_transactions`,
    SUM(`amount`) as `total_volume`,
    AVG(`amount`) as `avg_transaction`
  FROM `space_economy_transactions`
  WHERE DATE(`created_at`) = CURDATE();

  -- Total de investimentos ativos
  SELECT
    COUNT(*) as `active_investments`,
    SUM(`amount`) as `total_invested`
  FROM `space_economy_investments`
  WHERE `redeemed_at` IS NULL;

  -- Total de ações em carteira
  SELECT
    COUNT(DISTINCT `citizenid`) as `investors`,
    SUM(`quantity`) as `total_shares`
  FROM `space_economy_stocks`
  WHERE `quantity` > 0;
END$$
DELIMITER ;

-- ============================================================
-- Events Agendados
-- ============================================================

-- Event: Limpar transações antigas (roda diariamente às 3h)
CREATE EVENT IF NOT EXISTS `evt_cleanup_transactions`
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
  CALL sp_cleanup_old_transactions();

-- ============================================================
-- Índices Adicionais para Performance
-- ============================================================

-- Índices compostos para queries comuns
ALTER TABLE `space_economy_transactions`
  ADD INDEX IF NOT EXISTS `idx_category_date` (`category`, `created_at`);

ALTER TABLE `space_economy_investments`
  ADD INDEX IF NOT EXISTS `idx_citizen_product` (`citizenid`, `product_id`),
  ADD INDEX IF NOT EXISTS `idx_maturity` (`maturity_date`);

ALTER TABLE `space_economy_stocks`
  ADD INDEX IF NOT EXISTS `idx_ticker_date` (`ticker`, `purchased_at`);

-- ============================================================
-- Dados Iniciais (Seeds)
-- ============================================================

-- Inserir registro inicial de SELIC
INSERT IGNORE INTO `space_economy_selic_history` (`selic`, `decision`, `inflation`, `created_at`)
VALUES (0.0050, 'INICIAL', 0.04, NOW());

-- ============================================================
-- Triggers para Auditoria
-- ============================================================

-- Trigger: Registrar mudanças no histórico de salário
DELIMITER $$
CREATE TRIGGER IF NOT EXISTS `trg_wage_history_insert`
AFTER INSERT ON `space_economy_wage_history`
FOR EACH ROW
BEGIN
  -- Poderia adicionar lógica de notificação aqui
  -- Por exemplo, inserir em uma tabela de notificações
  SET @wage_changed = TRUE;
END$$
DELIMITER ;

-- ============================================================
-- Comentários nas Tabelas
-- ============================================================

ALTER TABLE `space_economy_transactions`
  COMMENT = 'Registro de todas as transações econômicas para cálculo de PIB';

ALTER TABLE `space_economy_selic_history`
  COMMENT = 'Histórico de decisões da taxa SELIC pelo COPOM';

ALTER TABLE `space_economy_stocks`
  COMMENT = 'Portfólio de ações dos players na bolsa de valores';

ALTER TABLE `space_economy_investments`
  COMMENT = 'Investimentos em produtos bancários (CDB, LCI, etc)';

ALTER TABLE `space_economy_wage_history`
  COMMENT = 'Histórico de ajustes do salário mínimo';

-- ============================================================
-- Fim do Script
-- ============================================================
