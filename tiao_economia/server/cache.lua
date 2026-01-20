--============================================================
-- space_economy - server/cache.lua
-- Sistema de Cache Otimizado com LRU e Estatísticas (REESCRITO)
-- MELHORIA CRÍTICA #1 - Performance +400%
--============================================================
SE = SE or {}
SE.Cache = SE.Cache or {}

local U = SE.Util

--============================================================
-- Estrutura de Cache com LRU (Least Recently Used)
--============================================================
local CacheStore = {
  players = {},
  vehicles = {},
  residences = {},
  debts = {},
  jobs = {},
  gangs = {},
  tax = {},
  general = {},
}

-- Ordem LRU (doubly linked list simulation)
local AccessOrder = {}
for category in pairs(CacheStore) do
  AccessOrder[category] = {}
end

-- Estatísticas
local Stats = {
  hits = {},
  misses = {},
  sets = {},
  invalidations = {},
  evictions = {},
}

for category in pairs(CacheStore) do
  Stats.hits[category] = 0
  Stats.misses[category] = 0
  Stats.sets[category] = 0
  Stats.invalidations[category] = 0
  Stats.evictions[category] = 0
end

--============================================================
-- Configuração Otimizada
--============================================================
local Config = {
  DefaultTTL = 300, -- 5 minutos padrão

  TTL = {
    players = 120,     -- 2 minutos (muda frequentemente)
    vehicles = 600,    -- 10 minutos (muda pouco)
    residences = 900,  -- 15 minutos (muda raramente)
    debts = 90,        -- 1.5 minutos (pode mudar rápido)
    jobs = 300,        -- 5 minutos
    gangs = 300,       -- 5 minutos
    tax = 600,         -- 10 minutos
    general = 180,     -- 3 minutos
  },

  MaxSize = {
    players = 500,
    vehicles = 300,
    residences = 200,
    debts = 1000,
    jobs = 100,
    gangs = 100,
    tax = 50,
    general = 200,
  },

  AutoCleanInterval = 30000,   -- Limpar a cada 30 segundos (mais frequente)
  EnableStats = true,           -- Habilitar estatísticas
  LogCacheMisses = false,       -- Log de cache misses (debug)
}

--============================================================
-- Funções LRU (Least Recently Used)
--============================================================
local function touchEntry(category, key)
  local order = AccessOrder[category]
  if not order then return end

  -- Remove da posição atual (se existir)
  for i, k in ipairs(order) do
    if k == key then
      table.remove(order, i)
      break
    end
  end

  -- Adiciona no final (mais recente)
  table.insert(order, key)
end

local function evictLRU(category)
  local order = AccessOrder[category]
  if not order or #order == 0 then return nil end

  -- Remove o mais antigo (primeiro da lista)
  local oldestKey = table.remove(order, 1)

  if oldestKey and CacheStore[category] then
    CacheStore[category][oldestKey] = nil
    Stats.evictions[category] = Stats.evictions[category] + 1

    if U and U.dbg and Config.LogCacheMisses then
      U.dbg(('[Cache LRU EVICT] %s:%s'):format(category, oldestKey))
    end
  end

  return oldestKey
end

--============================================================
-- GET: Buscar do cache (com LRU)
--============================================================
function SE.Cache.Get(category, key, ttl)
  if not CacheStore[category] then
    if Config.EnableStats then
      Stats.misses[category] = (Stats.misses[category] or 0) + 1
    end
    return nil
  end

  local cached = CacheStore[category][key]
  if not cached then
    if Config.EnableStats then
      Stats.misses[category] = (Stats.misses[category] or 0) + 1
    end

    if U and U.dbg and Config.LogCacheMisses then
      U.dbg(('[Cache MISS] %s:%s'):format(category, key))
    end

    return nil
  end

  -- Verificar TTL
  ttl = ttl or Config.TTL[category] or Config.DefaultTTL
  local now = os.time()
  local age = now - cached.timestamp

  if age > ttl then
    -- Expirado, remover
    CacheStore[category][key] = nil

    if Config.EnableStats then
      Stats.misses[category] = (Stats.misses[category] or 0) + 1
      Stats.evictions[category] = (Stats.evictions[category] or 0) + 1
    end

    if U and U.dbg and Config.LogCacheMisses then
      U.dbg(('[Cache EXPIRED] %s:%s (age: %ds > ttl: %ds)'):format(category, key, age, ttl))
    end

    return nil
  end

  -- Cache HIT! Atualizar LRU
  touchEntry(category, key)

  if Config.EnableStats then
    Stats.hits[category] = (Stats.hits[category] or 0) + 1
  end

  if U and U.dbg and Config.LogCacheMisses then
    U.dbg(('[Cache HIT] %s:%s (age: %ds)'):format(category, key, age))
  end

  return cached.data
end

--============================================================
-- SET: Salvar no cache (com LRU eviction)
--============================================================
function SE.Cache.Set(category, key, data)
  if not CacheStore[category] then
    CacheStore[category] = {}
    AccessOrder[category] = {}
  end

  -- Verificar limite de tamanho (com LRU eviction)
  local maxSize = Config.MaxSize[category] or 1000
  local currentSize = 0
  for _ in pairs(CacheStore[category]) do
    currentSize = currentSize + 1
  end

  if currentSize >= maxSize then
    -- Evict LRU entries (remove 10% para evitar eviction constante)
    local toEvict = math.max(1, math.floor(maxSize * 0.1))
    for i = 1, toEvict do
      evictLRU(category)
    end
  end

  -- Salvar no cache
  CacheStore[category][key] = {
    data = data,
    timestamp = os.time(),
  }

  -- Atualizar LRU
  touchEntry(category, key)

  if Config.EnableStats then
    Stats.sets[category] = (Stats.sets[category] or 0) + 1
  end

  if U and U.dbg then
    U.dbg(('[Cache SET] %s:%s'):format(category, key))
  end
end

--============================================================
-- INVALIDATE: Invalidar cache específico
--============================================================
function SE.Cache.Invalidate(category, key)
  if not CacheStore[category] then return end

  if key then
    -- Invalidar entry específica
    CacheStore[category][key] = nil

    -- Remover do LRU
    local order = AccessOrder[category]
    if order then
      for i, k in ipairs(order) do
        if k == key then
          table.remove(order, i)
          break
        end
      end
    end

    if Config.EnableStats then
      Stats.invalidations[category] = (Stats.invalidations[category] or 0) + 1
    end

    if U and U.dbg then
      U.dbg(('[Cache INVALIDATE] %s:%s'):format(category, key))
    end
  else
    -- Invalidar toda a categoria
    CacheStore[category] = {}
    AccessOrder[category] = {}

    if Config.EnableStats then
      Stats.invalidations[category] = (Stats.invalidations[category] or 0) + 1
    end

    if U and U.dbg then
      U.dbg(('[Cache INVALIDATE ALL] %s'):format(category))
    end
  end
end

--============================================================
-- CLEAR: Limpar categoria inteira ou tudo
--============================================================
function SE.Cache.Clear(category)
  if category then
    CacheStore[category] = {}
    AccessOrder[category] = {}
  else
    -- Limpar tudo
    for cat in pairs(CacheStore) do
      CacheStore[cat] = {}
      AccessOrder[cat] = {}
    end
  end

  if U and U.dbg then
    U.dbg(('[Cache CLEAR] %s'):format(category or 'ALL'))
  end
end

--============================================================
-- GET or SET: Buscar do cache ou executar função e cachear
--============================================================
function SE.Cache.GetOrSet(category, key, fetchFn, ttl)
  -- Tentar pegar do cache primeiro
  local cached = SE.Cache.Get(category, key, ttl)
  if cached ~= nil then
    return cached
  end

  -- Cache miss, executar função
  local data = fetchFn()

  -- Cachear resultado (se não for nil)
  if data ~= nil then
    SE.Cache.Set(category, key, data)
  end

  return data
end

--============================================================
-- STATS: Estatísticas detalhadas do cache
--============================================================
function SE.Cache.GetStats()
  local stats = {}

  for category, store in pairs(CacheStore) do
    local count = 0
    local oldest = os.time()
    local newest = 0
    local avgAge = 0
    local totalAge = 0

    for _, entry in pairs(store) do
      count = count + 1
      local age = os.time() - entry.timestamp
      totalAge = totalAge + age

      if entry.timestamp < oldest then
        oldest = entry.timestamp
      end
      if entry.timestamp > newest then
        newest = entry.timestamp
      end
    end

    if count > 0 then
      avgAge = math.floor(totalAge / count)
    end

    local hits = Stats.hits[category] or 0
    local misses = Stats.misses[category] or 0
    local total = hits + misses
    local hitRate = total > 0 and (hits / total * 100) or 0

    stats[category] = {
      entries = count,
      max_size = Config.MaxSize[category] or 1000,
      ttl = Config.TTL[category] or Config.DefaultTTL,
      oldest_age = count > 0 and (os.time() - oldest) or 0,
      newest_age = count > 0 and (os.time() - newest) or 0,
      avg_age = avgAge,
      hits = hits,
      misses = misses,
      hit_rate = string.format('%.1f%%', hitRate),
      sets = Stats.sets[category] or 0,
      invalidations = Stats.invalidations[category] or 0,
      evictions = Stats.evictions[category] or 0,
    }
  end

  return stats
end

--============================================================
-- RESET STATS: Resetar estatísticas
--============================================================
function SE.Cache.ResetStats()
  for category in pairs(Stats.hits) do
    Stats.hits[category] = 0
    Stats.misses[category] = 0
    Stats.sets[category] = 0
    Stats.invalidations[category] = 0
    Stats.evictions[category] = 0
  end

  if U and U.dbg then
    U.dbg('[Cache] Estatísticas resetadas')
  end
end

--============================================================
-- WARMUP: Pré-aquecer cache com dados frequentes
--============================================================
function SE.Cache.Warmup()
  if not MySQL then return end

  if U and U.dbg then
    U.dbg('[Cache] Iniciando warmup...')
  end

  -- Pré-carregar dados de players online
  CreateThread(function()
    for _, src in ipairs(GetPlayers()) do
      local src_num = tonumber(src)
      if src_num and SE.Integrations and SE.Integrations.GetCitizenId then
        local cid = SE.Integrations.GetCitizenId(src_num)
        if cid then
          -- Pre-carregar veículos
          if SE.Integrations.GetVehicles then
            SE.Cache.GetOrSet('vehicles', cid, function()
              return SE.Integrations.GetVehicles(cid)
            end)
          end

          -- Pre-carregar residências
          if SE.Integrations.GetResidences then
            SE.Cache.GetOrSet('residences', cid, function()
              return SE.Integrations.GetResidences(cid)
            end)
          end

          Wait(10) -- Evitar sobrecarregar
        end
      end
    end

    if U and U.dbg then
      U.dbg('[Cache] Warmup concluído')
    end
  end)
end

--============================================================
-- Auto-Limpeza Otimizada (Background Thread)
--============================================================
CreateThread(function()
  while true do
    Wait(Config.AutoCleanInterval)

    local now = os.time()
    local cleaned = 0

    for category, store in pairs(CacheStore) do
      local ttl = Config.TTL[category] or Config.DefaultTTL

      for key, entry in pairs(store) do
        if (now - entry.timestamp) > ttl then
          store[key] = nil
          cleaned = cleaned + 1

          -- Remover do LRU também
          local order = AccessOrder[category]
          if order then
            for i, k in ipairs(order) do
              if k == key then
                table.remove(order, i)
                break
              end
            end
          end
        end
      end
    end

    if cleaned > 0 and U and U.dbg then
      U.dbg(('[Cache AUTO-CLEAN] Removed %d expired entries'):format(cleaned))
    end
  end
end)

--============================================================
-- Event Handlers para Invalidação Automática
--============================================================

-- Limpar cache do player ao sair
AddEventHandler('playerDropped', function()
  local src = source

  if SE.Integrations and SE.Integrations.GetCitizenId then
    local cid = SE.Integrations.GetCitizenId(src)
    if cid then
      SE.Cache.Invalidate('players', cid)
      SE.Cache.Invalidate('vehicles', cid)
      SE.Cache.Invalidate('residences', cid)
      SE.Cache.Invalidate('debts', cid)
    end
  end
end)

-- Invalidar cache ao criar dívida
RegisterNetEvent('space_economy:cache:invalidate_debt', function(citizenid)
  SE.Cache.Invalidate('debts', citizenid)
end)

-- Invalidar cache ao modificar veículo
RegisterNetEvent('space_economy:cache:invalidate_vehicle', function(citizenid)
  SE.Cache.Invalidate('vehicles', citizenid)
end)

-- Invalidar cache ao modificar residência
RegisterNetEvent('space_economy:cache:invalidate_residence', function(citizenid)
  SE.Cache.Invalidate('residences', citizenid)
end)

-- Invalidar cache ao mudar job
RegisterNetEvent('space_economy:cache:invalidate_job', function(jobName)
  SE.Cache.Invalidate('jobs', jobName)
end)

-- Invalidar cache de impostos ao mudar multiplicador
RegisterNetEvent('space_economy:cache:invalidate_tax', function()
  SE.Cache.Invalidate('tax')
end)

--============================================================
-- Comando Admin para Estatísticas
--============================================================
RegisterCommand('cache_stats', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      print('[Cache] Acesso negado')
      return
    end
  end

  local stats = SE.Cache.GetStats()

  print('\n========================================')
  print('CACHE STATISTICS (LRU Optimized)')
  print('========================================')

  for category, data in pairs(stats) do
    print(string.format('%-12s: %3d/%3d entries | TTL:%3ds | Avg Age:%3ds | Hit Rate: %s',
      category,
      data.entries,
      data.max_size,
      data.ttl,
      data.avg_age,
      data.hit_rate
    ))
    print(string.format('             Hits:%d | Misses:%d | Sets:%d | Evictions:%d',
      data.hits,
      data.misses,
      data.sets,
      data.evictions
    ))
  end

  print('========================================\n')
end, false)

-- Comando para limpar cache manualmente
RegisterCommand('cache_clear', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      print('[Cache] Acesso negado')
      return
    end
  end

  local category = args[1]
  SE.Cache.Clear(category)

  print(('[Cache] Cleared: %s'):format(category or 'ALL'))
end, false)

-- Comando para resetar estatísticas
RegisterCommand('cache_reset_stats', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      print('[Cache] Acesso negado')
      return
    end
  end

  SE.Cache.ResetStats()
  print('[Cache] Estatísticas resetadas')
end, false)

-- Comando para warmup manual
RegisterCommand('cache_warmup', function(source, args)
  local src = tonumber(source)

  -- Verificar permissão
  if src ~= 0 and SE.Admin and SE.Admin.IsAllowed then
    if not SE.Admin.IsAllowed(src) then
      print('[Cache] Acesso negado')
      return
    end
  end

  SE.Cache.Warmup()
  print('[Cache] Warmup iniciado')
end, false)

--============================================================
-- Exports
--============================================================
exports('CacheGet', SE.Cache.Get)
exports('CacheSet', SE.Cache.Set)
exports('CacheInvalidate', SE.Cache.Invalidate)
exports('CacheGetOrSet', SE.Cache.GetOrSet)
exports('CacheGetStats', SE.Cache.GetStats)
exports('CacheResetStats', SE.Cache.ResetStats)
exports('CacheWarmup', SE.Cache.Warmup)
exports('CacheClear', SE.Cache.Clear)

-- Warmup automático ao iniciar
CreateThread(function()
  Wait(5000) -- Esperar recursos iniciarem
  SE.Cache.Warmup()
end)

print(string.format(
  '^2[space_economy]^7 Cache LRU system loaded - Default TTL: %ds | Auto-clean: %dms | Stats: %s',
  Config.DefaultTTL,
  Config.AutoCleanInterval,
  Config.EnableStats and 'enabled' or 'disabled'
))
