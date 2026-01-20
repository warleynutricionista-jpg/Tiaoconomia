--============================================================
-- space_economy - server/bills_export.lua
-- Export padrão para bancos consumirem dívidas
--============================================================
SE = SE or {}

local function SafeStr(v) v = tostring(v or ''):gsub('%s+', ''); return v end
local function SafeNum(v) v = tonumber(v); return v or 0 end

exports('GetActiveDebtsByCitizen', function(citizenid, limit)
    citizenid = SafeStr(citizenid)
    limit = math.min(math.max(SafeNum(limit), 50), 200)
    if citizenid == '' then return {} end

    -- preferir API do módulo
    if SE.Debts and SE.Debts.GetActiveByCitizen then
        local ok, rows = pcall(SE.Debts.GetActiveByCitizen, citizenid, limit)
        if ok and type(rows) == 'table' then return rows end
    end

    -- fallback direto SQL
    if MySQL and MySQL.query and MySQL.query.await then
        return MySQL.query.await([[
            SELECT id, citizenid, amount, reason, status, due_date, created_at, metadata
              FROM space_economy_debts
             WHERE citizenid = ?
               AND status = 'active'
             ORDER BY due_date ASC, id DESC
             LIMIT ?
        ]], { citizenid, limit }) or {}
    end

    return {}
end)
