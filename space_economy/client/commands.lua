--============================================================
-- space_economy - client/commands.lua
-- Comandos + keymapping | Diagnóstico (test UI) | Server valida permissões
--============================================================

local function n(msg, typ)
  if lib and lib.notify then
    lib.notify({ title = 'Economia', description = msg, type = typ or 'inform' })
  else
    print(('[space_economy] %s'):format(msg))
  end
end

local function openTax()
  n('Solicitado: painel de impostos.', 'inform')
  TriggerServerEvent('space_economy:server_openTaxPanel')
end

local function openAdmin()
  n('Solicitado: painel administrativo (server vai validar permissão).', 'inform')
  TriggerServerEvent('space_economy:server_openAdminPanel')
end

-- TESTE: abre a NUI localmente (ignora permissão) pra diagnosticar se NUI está ok
local function testAdminUI()
  n('Teste: abrindo NUI ADMIN local (sem permissão).', 'inform')
  TriggerEvent('space_economy:client_open', 'admin', {})
end

local function getKeybind(keyName, fallback)
  if Config and Config.UI and Config.UI.Keybinds then
    return Config.UI.Keybinds[keyName] or fallback
  end
  return fallback
end

-- /taxas (DESATIVADO v5.0 - usar /player)
-- RegisterCommand('taxas', function()
--   openTax()
-- end, false)

-- /economia (DESATIVADO v5.0 - usar /admin)
-- RegisterCommand('economia', function()
--   openAdmin()
-- end, false)

RegisterCommand('taxas', function()
  n('Abrindo painel de impostos...', 'inform')
  if SE and SE.Client and SE.Client.OpenTaxPanel then
    SE.Client.OpenTaxPanel()
  else
    openTax()
  end
end, false)

RegisterCommand('eco_open_adminpanel', function()
  n('Solicitando painel administrativo...', 'inform')
  if SE and SE.Client and SE.Client.OpenAdminPanel then
    SE.Client.OpenAdminPanel()
  else
    TriggerServerEvent('space_economy:server_openStaffPanel')
  end
end, false)

RegisterCommand('eco_testui', function()
  if SE and SE.Client and SE.Client.OpenUITest then
    SE.Client.OpenUITest()
  else
    testAdminUI()
  end
end, false)

RegisterKeyMapping('taxas', 'Economia: abrir painel de impostos', 'keyboard', 'F7')
RegisterKeyMapping('eco_open_adminpanel', 'Economia: abrir painel administrativo', 'keyboard', 'F12')
RegisterKeyMapping('eco_testui', 'Economia: TESTE abrir NUI admin local', 'keyboard', '5')

CreateThread(function()
  Wait(1000)
  -- sugestões (se chat resource existir)
  pcall(function()
    -- TriggerEvent('chat:addSuggestion', '/taxas', 'Abrir painel de impostos/pagamentos') -- DESATIVADO v5.0
    -- TriggerEvent('chat:addSuggestion', '/economia', 'Abrir painel administrativo (requer permissão)') -- DESATIVADO v5.0
    TriggerEvent('chat:addSuggestion', '/taxas', 'Abrir painel de impostos')
    TriggerEvent('chat:addSuggestion', '/eco_open_adminpanel', 'Abrir painel administrativo (requer permissão)')
    TriggerEvent('chat:addSuggestion', '/eco_testui', 'TESTE: abrir painel admin local (diagnóstico NUI)')
  end)
end)
