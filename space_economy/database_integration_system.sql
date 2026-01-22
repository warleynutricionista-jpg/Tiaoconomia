-- =====================================================
-- SISTEMA DE INTEGRAÇÃO ECONÔMICA CENTRALIZADA
-- Tabelas necessárias para o novo sistema de controle total
-- =====================================================

-- =====================================================
-- TABELA: SERVIÇOS REGISTRADOS
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_services` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `service_name` VARCHAR(100) NOT NULL UNIQUE,
  `service_type` VARCHAR(50) NOT NULL,
  `description` TEXT,
  `resource` VARCHAR(100) NOT NULL,
  `status` VARCHAR(50) NOT NULL DEFAULT 'pending',

  -- Configurações de integração (JSON)
  `integration_config` TEXT,

  -- Configurações de preços (JSON)
  `pricing_config` TEXT,

  -- Estatísticas (JSON)
  `stats` TEXT,

  -- Callbacks disponíveis (JSON)
  `callbacks` TEXT,

  -- Metadados adicionais (JSON)
  `metadata` TEXT,

  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  INDEX `idx_service_name` (`service_name`),
  INDEX `idx_service_type` (`service_type`),
  INDEX `idx_status` (`status`),
  INDEX `idx_resource` (`resource`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: SERVIÇOS NÃO REGISTRADOS DETECTADOS
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_unregistered_services` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `resource_name` VARCHAR(100) NOT NULL UNIQUE,
  `first_detected` INT NOT NULL,
  `last_seen` INT NOT NULL,
  `transaction_count` INT DEFAULT 0,
  `total_volume` DECIMAL(20, 2) DEFAULT 0,
  `suggested_type` VARCHAR(50),

  -- Amostras de transações detectadas (JSON)
  `sample_data` LONGTEXT,

  -- Status (pending, reviewed, integrated, ignored)
  `status` VARCHAR(50) DEFAULT 'pending',

  -- Notas do administrador
  `admin_notes` TEXT,

  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  INDEX `idx_resource_name` (`resource_name`),
  INDEX `idx_status` (`status`),
  INDEX `idx_last_seen` (`last_seen`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: PREÇOS DINÂMICOS
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_prices` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `item_id` VARCHAR(200) NOT NULL UNIQUE,
  `base_price` DECIMAL(20, 2) NOT NULL,
  `current_price` DECIMAL(20, 2) NOT NULL,
  `category` VARCHAR(50) DEFAULT 'GENERAL',
  `multiplier` DECIMAL(10, 4) DEFAULT 1.0000,
  `last_update` INT NOT NULL,

  -- Histórico de variação de preços (JSON)
  `price_history` LONGTEXT,

  -- Metadados do item (JSON)
  `metadata` TEXT,

  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  INDEX `idx_item_id` (`item_id`),
  INDEX `idx_category` (`category`),
  INDEX `idx_last_update` (`last_update`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: HISTÓRICO DE PREÇOS
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_price_history` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `item_id` VARCHAR(200) NOT NULL,
  `price` DECIMAL(20, 2) NOT NULL,
  `multiplier` DECIMAL(10, 4) NOT NULL,
  `global_multiplier` DECIMAL(10, 4) NOT NULL,
  `category_multiplier` DECIMAL(10, 4) NOT NULL,

  -- Fatores econômicos no momento (JSON)
  `economic_factors` TEXT,

  `timestamp` INT NOT NULL,

  PRIMARY KEY (`id`),
  INDEX `idx_item_id` (`item_id`),
  INDEX `idx_timestamp` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: TRANSAÇÕES INTERCEPTADAS
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_intercepted_transactions` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `timestamp` INT NOT NULL,
  `source` INT,
  `resource` VARCHAR(100) NOT NULL,
  `event_name` VARCHAR(200) NOT NULL,
  `amount` DECIMAL(20, 2),
  `transaction_type` VARCHAR(50),
  `account` VARCHAR(50),
  `reason` TEXT,

  -- Metadados completos da transação (JSON)
  `metadata` TEXT,

  -- Se foi bloqueada ou permitida
  `was_blocked` BOOLEAN DEFAULT FALSE,

  -- Se impostos foram aplicados
  `taxes_applied` DECIMAL(20, 2) DEFAULT 0,

  PRIMARY KEY (`id`),
  INDEX `idx_timestamp` (`timestamp`),
  INDEX `idx_resource` (`resource`),
  INDEX `idx_source` (`source`),
  INDEX `idx_transaction_type` (`transaction_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: MONITOR DE SQL DIRETO
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_sql_monitor` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `timestamp` INT NOT NULL,
  `resource` VARCHAR(100) NOT NULL,
  `query_text` TEXT NOT NULL,
  `params` TEXT,

  -- Análise da query (JSON)
  `query_analysis` TEXT,

  -- Status (reviewed, flagged, safe, dangerous)
  `status` VARCHAR(50) DEFAULT 'pending',

  PRIMARY KEY (`id`),
  INDEX `idx_timestamp` (`timestamp`),
  INDEX `idx_resource` (`resource`),
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: RELATÓRIOS DE INTEGRAÇÃO
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_integration_reports` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `report_date` DATE NOT NULL,

  -- Estatísticas gerais
  `total_registered_services` INT DEFAULT 0,
  `total_unregistered_services` INT DEFAULT 0,
  `total_transactions` INT DEFAULT 0,
  `total_volume` DECIMAL(20, 2) DEFAULT 0,
  `blocked_transactions` INT DEFAULT 0,
  `blocked_volume` DECIMAL(20, 2) DEFAULT 0,

  -- Estatísticas por tipo (JSON)
  `by_service_type` TEXT,

  -- Estatísticas por recurso (JSON)
  `by_resource` TEXT,

  -- Top serviços não integrados (JSON)
  `top_unregistered` TEXT,

  -- Alertas e problemas (JSON)
  `alerts` TEXT,

  -- Dados completos do relatório (JSON)
  `full_report` LONGTEXT,

  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  UNIQUE INDEX `idx_report_date` (`report_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- TABELA: CONFIGURAÇÕES DE BALANCEAMENTO
-- =====================================================
CREATE TABLE IF NOT EXISTS `space_economy_balance_config` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `config_key` VARCHAR(100) NOT NULL UNIQUE,
  `config_value` TEXT NOT NULL,
  `config_type` VARCHAR(50) DEFAULT 'json',
  `description` TEXT,

  -- Quem modificou por último
  `modified_by` VARCHAR(50),
  `modified_at` INT,

  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  INDEX `idx_config_key` (`config_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================
-- INSERIR CONFIGURAÇÕES PADRÃO
-- =====================================================
INSERT IGNORE INTO `space_economy_balance_config` (`config_key`, `config_value`, `config_type`, `description`) VALUES
('global_price_multiplier', '1.0', 'number', 'Multiplicador global manual de preços'),
('auto_balance_enabled', 'true', 'boolean', 'Habilita balanceamento automático de preços'),
('enforce_integration', 'false', 'boolean', 'Força integração bloqueando serviços não registrados'),
('auto_apply_taxes', 'true', 'boolean', 'Aplica impostos automaticamente em transações interceptadas'),
('alert_threshold', '10000', 'number', 'Valor mínimo para alertar admins sobre transações'),
('price_update_interval', '300000', 'number', 'Intervalo de atualização de preços em ms (5 minutos padrão)');

-- =====================================================
-- VIEWS PARA CONSULTAS RÁPIDAS
-- =====================================================

-- View: Serviços não integrados com mais atividade
CREATE OR REPLACE VIEW `v_top_unregistered_services` AS
SELECT
    resource_name,
    suggested_type,
    transaction_count,
    total_volume,
    DATEDIFF(NOW(), FROM_UNIXTIME(last_seen)) as days_since_last,
    status
FROM space_economy_unregistered_services
WHERE status = 'pending'
ORDER BY total_volume DESC, transaction_count DESC
LIMIT 50;

-- View: Estatísticas de serviços registrados
CREATE OR REPLACE VIEW `v_registered_services_stats` AS
SELECT
    service_type,
    COUNT(*) as total_services,
    SUM(JSON_EXTRACT(stats, '$.total_transactions')) as total_transactions,
    SUM(JSON_EXTRACT(stats, '$.total_volume')) as total_volume
FROM space_economy_services
GROUP BY service_type;

-- View: Atividade de transações por hora
CREATE OR REPLACE VIEW `v_transaction_activity_hourly` AS
SELECT
    DATE_FORMAT(FROM_UNIXTIME(timestamp), '%Y-%m-%d %H:00') as hour,
    COUNT(*) as transaction_count,
    SUM(ABS(amount)) as total_volume,
    AVG(ABS(amount)) as avg_amount,
    COUNT(DISTINCT resource) as unique_resources
FROM space_economy_intercepted_transactions
WHERE timestamp > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 24 HOUR))
GROUP BY hour
ORDER BY hour DESC;

-- View: Resumo diário de economia
CREATE OR REPLACE VIEW `v_daily_economy_summary` AS
SELECT
    DATE(FROM_UNIXTIME(timestamp)) as date,
    COUNT(*) as total_transactions,
    SUM(CASE WHEN transaction_type = 'add' THEN amount ELSE 0 END) as total_added,
    SUM(CASE WHEN transaction_type = 'remove' THEN amount ELSE 0 END) as total_removed,
    SUM(taxes_applied) as total_taxes,
    COUNT(CASE WHEN was_blocked = 1 THEN 1 END) as blocked_count
FROM space_economy_intercepted_transactions
GROUP BY date
ORDER BY date DESC
LIMIT 30;

-- =====================================================
-- TRIGGERS PARA AUDITORIA
-- =====================================================

-- Trigger: Atualiza timestamp de serviço quando stats mudam
DELIMITER //
CREATE TRIGGER IF NOT EXISTS `trg_service_stats_update`
BEFORE UPDATE ON `space_economy_services`
FOR EACH ROW
BEGIN
    IF NEW.stats != OLD.stats THEN
        SET NEW.updated_at = CURRENT_TIMESTAMP;
    END IF;
END//
DELIMITER ;

-- Trigger: Registra mudanças de configuração
DELIMITER //
CREATE TRIGGER IF NOT EXISTS `trg_balance_config_audit`
AFTER UPDATE ON `space_economy_balance_config`
FOR EACH ROW
BEGIN
    INSERT INTO space_economy_audit_log (
        timestamp,
        action_type,
        target_type,
        target_id,
        details
    ) VALUES (
        UNIX_TIMESTAMP(),
        'config_change',
        'balance_config',
        NEW.id,
        JSON_OBJECT(
            'config_key', NEW.config_key,
            'old_value', OLD.config_value,
            'new_value', NEW.config_value,
            'modified_by', NEW.modified_by
        )
    );
END//
DELIMITER ;

-- =====================================================
-- STORED PROCEDURES ÚTEIS
-- =====================================================

-- Procedure: Gera relatório de integração
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS `sp_generate_integration_report`(IN report_date DATE)
BEGIN
    DECLARE total_reg INT DEFAULT 0;
    DECLARE total_unreg INT DEFAULT 0;
    DECLARE total_tx INT DEFAULT 0;
    DECLARE total_vol DECIMAL(20,2) DEFAULT 0;
    DECLARE blocked_tx INT DEFAULT 0;
    DECLARE blocked_vol DECIMAL(20,2) DEFAULT 0;

    -- Conta serviços registrados
    SELECT COUNT(*) INTO total_reg FROM space_economy_services;

    -- Conta serviços não registrados
    SELECT COUNT(*) INTO total_unreg FROM space_economy_unregistered_services WHERE status = 'pending';

    -- Conta transações do dia
    SELECT
        COUNT(*),
        SUM(ABS(amount)),
        SUM(CASE WHEN was_blocked = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN was_blocked = 1 THEN ABS(amount) ELSE 0 END)
    INTO total_tx, total_vol, blocked_tx, blocked_vol
    FROM space_economy_intercepted_transactions
    WHERE DATE(FROM_UNIXTIME(timestamp)) = report_date;

    -- Insere ou atualiza relatório
    INSERT INTO space_economy_integration_reports (
        report_date,
        total_registered_services,
        total_unregistered_services,
        total_transactions,
        total_volume,
        blocked_transactions,
        blocked_volume
    ) VALUES (
        report_date,
        total_reg,
        total_unreg,
        total_tx,
        total_vol,
        blocked_tx,
        blocked_vol
    ) ON DUPLICATE KEY UPDATE
        total_registered_services = total_reg,
        total_unregistered_services = total_unreg,
        total_transactions = total_tx,
        total_volume = total_vol,
        blocked_transactions = blocked_tx,
        blocked_volume = blocked_vol;

    SELECT 'Relatório gerado com sucesso' as message;
END//
DELIMITER ;

-- Procedure: Limpa dados antigos (manutenção)
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS `sp_cleanup_old_data`(IN days_to_keep INT)
BEGIN
    DECLARE cutoff_timestamp INT;
    SET cutoff_timestamp = UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL days_to_keep DAY));

    -- Limpa transações interceptadas antigas
    DELETE FROM space_economy_intercepted_transactions WHERE timestamp < cutoff_timestamp;

    -- Limpa histórico de preços antigo
    DELETE FROM space_economy_price_history WHERE timestamp < cutoff_timestamp;

    -- Limpa monitor SQL antigo
    DELETE FROM space_economy_sql_monitor WHERE timestamp < cutoff_timestamp;

    SELECT
        CONCAT('Limpeza concluída. Dados antes de ', FROM_UNIXTIME(cutoff_timestamp), ' removidos.') as message;
END//
DELIMITER ;

-- =====================================================
-- INDICES ADICIONAIS PARA PERFORMANCE
-- =====================================================

-- Índice composto para queries de relatório
ALTER TABLE `space_economy_intercepted_transactions`
ADD INDEX `idx_report_queries` (`timestamp`, `resource`, `transaction_type`);

-- Índice para buscas por volume
ALTER TABLE `space_economy_unregistered_services`
ADD INDEX `idx_volume_activity` (`total_volume`, `transaction_count`);

-- Índice para histórico de preços por item e data
ALTER TABLE `space_economy_price_history`
ADD INDEX `idx_item_timeline` (`item_id`, `timestamp`);

-- =====================================================
-- COMENTÁRIOS NAS TABELAS
-- =====================================================

ALTER TABLE `space_economy_services`
COMMENT = 'Registro central de todos os serviços que realizam transações financeiras';

ALTER TABLE `space_economy_unregistered_services`
COMMENT = 'Serviços detectados automaticamente que ainda não estão registrados no sistema';

ALTER TABLE `space_economy_prices`
COMMENT = 'Preços dinâmicos de todos os itens e serviços do servidor';

ALTER TABLE `space_economy_price_history`
COMMENT = 'Histórico de variações de preço ao longo do tempo';

ALTER TABLE `space_economy_intercepted_transactions`
COMMENT = 'Log de todas as transações interceptadas pelo sistema';

ALTER TABLE `space_economy_sql_monitor`
COMMENT = 'Monitoramento de queries SQL diretas que modificam dinheiro';

ALTER TABLE `space_economy_integration_reports`
COMMENT = 'Relatórios diários de integração e saúde do sistema econômico';

ALTER TABLE `space_economy_balance_config`
COMMENT = 'Configurações do sistema de balanceamento econômico';

-- =====================================================
-- FINALIZAÇÃO
-- =====================================================

-- Mensagem de sucesso
SELECT 'Sistema de Integração Econômica instalado com sucesso!' as status;
SELECT 'Tabelas criadas: 8' as tables_created;
SELECT 'Views criadas: 4' as views_created;
SELECT 'Procedures criadas: 2' as procedures_created;
SELECT 'Triggers criados: 2' as triggers_created;
