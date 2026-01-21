-- ============================================================
-- space_economy - Índices de performance e limpeza
-- ============================================================

-- Veículos (player_vehicles)
CREATE INDEX idx_player_vehicles_citizenid ON player_vehicles (citizenid);
CREATE INDEX idx_player_vehicles_plate ON player_vehicles (plate);
CREATE INDEX idx_player_vehicles_depotprice ON player_vehicles (depotprice);

-- Propriedades (ps-housing)
CREATE INDEX idx_properties_owner ON properties (owner_citizenid);
CREATE INDEX idx_properties_price ON properties (price);

-- Empresas / organizações
CREATE INDEX idx_management_funds_job ON management_funds (job_name);
CREATE INDEX idx_ps_banking_holder ON ps_banking_accounts (holder);

-- Limpeza de tabelas antigas (remover apenas se estiver vazia)
-- SELECT COUNT(*) FROM tiao_properties;
DROP TABLE IF EXISTS tiao_properties;
