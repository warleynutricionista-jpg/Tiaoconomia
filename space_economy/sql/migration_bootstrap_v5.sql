-- Space Economy bootstrap migration (MariaDB/oxmysql-safe)

CREATE TABLE IF NOT EXISTS `space_economy_intercepted_transactions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `timestamp` INT NOT NULL,
  `source` INT DEFAULT NULL,
  `resource` VARCHAR(100) DEFAULT 'unknown',
  `event_name` VARCHAR(120) DEFAULT 'unknown',
  `amount` DECIMAL(20,2) NOT NULL DEFAULT 0,
  `transaction_type` VARCHAR(50) DEFAULT 'unknown',
  `account` VARCHAR(40) DEFAULT 'unknown',
  `reason` VARCHAR(255) DEFAULT '',
  `metadata` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_ts` (`timestamp`),
  INDEX `idx_resource` (`resource`),
  INDEX `idx_type` (`transaction_type`),
  INDEX `idx_account` (`account`),
  INDEX `idx_source` (`source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_sql_monitor` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `timestamp` INT NOT NULL,
  `resource` VARCHAR(100) DEFAULT 'unknown',
  `query_text` LONGTEXT,
  `params` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_ts` (`timestamp`),
  INDEX `idx_resource` (`resource`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_organizations` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL,
  `tag` VARCHAR(8) NOT NULL,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `balance` BIGINT NOT NULL DEFAULT 0,
  `settings` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_org_name` (`name`),
  UNIQUE KEY `uk_org_tag` (`tag`),
  INDEX `idx_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `space_economy_org_members` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `org_id` INT NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `role` VARCHAR(32) NOT NULL DEFAULT 'staff',
  `permissions` LONGTEXT,
  `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_member` (`org_id`, `citizenid`),
  INDEX `idx_org_id` (`org_id`),
  INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
