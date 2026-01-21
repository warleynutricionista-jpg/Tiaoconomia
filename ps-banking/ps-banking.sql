-- =====================================================
-- PS-Banking Database Schema
-- Enhanced version with indexes, constraints, and logs
-- =====================================================

-- Transactions table with improved structure
CREATE TABLE IF NOT EXISTS `ps_banking_transactions` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(50) NOT NULL,
    `description` VARCHAR(255) NOT NULL,
    `type` VARCHAR(50) NOT NULL,
    `amount` DECIMAL(20, 2) NOT NULL,
    `date` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `isIncome` BOOLEAN NOT NULL,
    `account_id` INT NULL,
    `metadata` JSON NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_date` (`date`),
    INDEX `idx_type` (`type`),
    INDEX `idx_identifier_date` (`identifier`, `date`)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Bills table with improved structure
CREATE TABLE IF NOT EXISTS `ps_banking_bills` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(50) NOT NULL,
    `identifier2` VARCHAR(50) NULL,
    `description` VARCHAR(255) NOT NULL,
    `type` VARCHAR(50) NOT NULL,
    `amount` DECIMAL(20, 2) NOT NULL CHECK (`amount` > 0),
    `date` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `due_date` DATETIME NULL,
    `isPaid` BOOLEAN NOT NULL DEFAULT 0,
    `paid_date` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_identifier2` (`identifier2`),
    INDEX `idx_isPaid` (`isPaid`),
    INDEX `idx_due_date` (`due_date`),
    INDEX `idx_identifier_paid` (`identifier`, `isPaid`)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Accounts table with improved structure
CREATE TABLE IF NOT EXISTS `ps_banking_accounts` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `balance` BIGINT NOT NULL DEFAULT 0 CHECK (`balance` >= 0),
    `holder` VARCHAR(255) NOT NULL,
    `cardNumber` VARCHAR(255) NOT NULL,
    `users` JSON NOT NULL,
    `owner` JSON NOT NULL,
    `status` ENUM('active', 'frozen', 'closed') NOT NULL DEFAULT 'active',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_holder` (`holder`),
    UNIQUE KEY `unique_cardNumber` (`cardNumber`),
    INDEX `idx_status` (`status`),
    INDEX `idx_holder` (`holder`)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Investments table for tracking player investments
CREATE TABLE IF NOT EXISTS `ps_banking_investments` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(50) NOT NULL,
    `product_id` VARCHAR(50) NOT NULL,
    `amount` DECIMAL(20, 2) NOT NULL CHECK (`amount` > 0),
    `invested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `redeemable_at` DATETIME NOT NULL,
    `redeemed_at` DATETIME NULL,
    `status` ENUM('active', 'redeemed', 'cancelled') NOT NULL DEFAULT 'active',
    `return_amount` DECIMAL(20, 2) NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_status` (`status`),
    INDEX `idx_redeemable_at` (`redeemable_at`)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit log table for tracking all banking operations
CREATE TABLE IF NOT EXISTS `ps_banking_audit_log` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `action` VARCHAR(100) NOT NULL,
    `identifier` VARCHAR(50) NOT NULL,
    `target_identifier` VARCHAR(50) NULL,
    `account_id` INT NULL,
    `amount` DECIMAL(20, 2) NULL,
    `details` JSON NULL,
    `ip_address` VARCHAR(45) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_action` (`action`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_account_id` (`account_id`)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Transfer limits table for security
CREATE TABLE IF NOT EXISTS `ps_banking_transfer_limits` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(50) NOT NULL,
    `daily_transferred` DECIMAL(20, 2) NOT NULL DEFAULT 0,
    `last_reset` DATE NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_identifier` (`identifier`),
    INDEX `idx_last_reset` (`last_reset`)
) ENGINE = InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

  
    
/* Dummy data (Ignore)
INSERT INTO `ps_banking_bills` (`identifier`, `description`, `type`, `amount`, `date`, `isPaid`) VALUES
('char1:df6c12c50e2712c57b1386e7103d5a372fb960a0', 'Utility Bill', 'Expense', 150.00, '2024-07-20', 0);

INSERT INTO `ps_banking_transactions` (`identifier`, `description`, `type`, `amount`, `date`, `isIncome`) VALUES
('char1:df6c12c50e2712c57b1386e7103d5a372fb960a0', 'Opened a new account', 'From account', 1000.00, '2022-08-13', 0),
('char1:df6c12c50e2712c57b1386e7103d5a372fb960a0', 'Deposited 500 DKK to account', 'To account', 500.00, '2022-08-13', 1),
('char1:df6c12c50e2712c57b1386e7103d5a372fb960a0', 'Deposited 500 DKK to account', 'To account', 500.00, '2022-08-13', 1),
('char1:df6c12c50e2712c57b1386e7103d5a372fb960a0', 'Withdrew 500 DKK from ATM', 'From account', -500.00, '2022-08-13', 0),
('char1:df6c12c50e2712c57b1386e7103d5a372fb960a0', 'Deposited 500 DKK to account', 'To account', 500.00, '2022-08-13', 1),
('char2:ab12c34d5e67f89g01234h56789i012j34kl567m8', 'Opened a new account', 'From account', 2000.00, '2022-08-14', 0),
('char2:ab12c34d5e67f89g01234h56789i012j34kl567m8', 'Deposited 1000 DKK to account', 'To account', 1000.00, '2022-08-14', 1),
('char2:ab12c34d5e67f89g01234h56789i012j34kl567m8', 'Withdrew 300 DKK from ATM', 'From account', -300.00, '2022-08-14', 0),
('char2:ab12c34d5e67f89g01234h56789i012j34kl567m8', 'Deposited 400 DKK to account', 'To account', 400.00, '2022-08-14', 1),
('char2:ab12c34d5e67f89g01234h56789i012j34kl567m8', 'Withdrew 200 DKK from ATM', 'From account', -200.00, '2022-08-14', 0);

 */
