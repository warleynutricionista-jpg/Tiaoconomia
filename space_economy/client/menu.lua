--============================================================
-- space_economy - client/menu.lua
-- Menu de Intervenção Econômica (Game Master)
--============================================================

local function notify(msg, typ)
  if lib and lib.notify then
    lib.notify({ title = 'Economia', description = msg, type = typ or 'inform' })
  else
    print(('[space_economy] %s'):format(msg))
  end
end

local function openEconomicMenu()
  if not lib or not lib.registerContext then
    notify('ox_lib não disponível para menu.', 'error')
    return
  end

  lib.registerContext({
    id = 'space_economy_event_menu',
    title = 'Intervenção Econômica',
    options = {
      {
        title = 'Boom da Mineração',
        description = 'Reduz impostos sobre minérios por 2h.',
        icon = 'gem',
        onSelect = function()
          TriggerServerEvent('space_economy:server_triggerEconomicEvent', 'mining_boom')
        end,
      },
      {
        title = 'Crise do Petróleo',
        description = 'Aumenta impostos sobre combustível.',
        icon = 'oil-can',
        onSelect = function()
          TriggerServerEvent('space_economy:server_triggerEconomicEvent', 'oil_crisis')
        end,
      },
      {
        title = 'Estímulo Governamental',
        description = 'Distribui UBI extra para todos online.',
        icon = 'hand-holding-dollar',
        onSelect = function()
          TriggerServerEvent('space_economy:server_triggerEconomicEvent', 'gov_stimulus')
        end,
      },
      {
        title = 'Auditoria Fiscal',
        description = 'Verifica top 10 ricos e aplica multa.',
        icon = 'file-invoice-dollar',
        onSelect = function()
          TriggerServerEvent('space_economy:server_triggerEconomicEvent', 'tax_audit')
        end,
      },
    }
  })

  lib.showContext('space_economy_event_menu')
end

RegisterCommand('eco_eventos', function()
  openEconomicMenu()
end, false)

RegisterKeyMapping('eco_eventos', 'Economia: menu de intervenção econômica', 'keyboard', 'F10')

CreateThread(function()
  Wait(1000)
  pcall(function()
    TriggerEvent('chat:addSuggestion', '/eco_eventos', 'Abrir menu de intervenção econômica (admin)')
  end)
end)
