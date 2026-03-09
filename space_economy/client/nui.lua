--============================================================
-- space_economy - client/nui.lua
-- Ponte Client <-> NUI (fetch callbacks do HTML)
-- Protocolo ÚNICO: SendNUIMessage({ action="open", mode, payload })
--============================================================

SE = SE or {}
SE.Client = SE.Client or {}

local uiOpen = false
local uiAck = false
local currentPanel = nil

SE.Client.EconomyUIOpen = false

-- usado quando abrimos modo "payment" (opcional)
local lastPayment = { tax = 0, reason = 'Imposto' }

local function setFocus(state)
  SetNuiFocus(state, state)
  SetNuiFocusKeepInput(false)
end

local function openUI(mode, payload)
  uiOpen = true
  uiAck = false

  payload = payload or {}

  -- guarda pagamento (se vier)
  if mode == 'payment' then
    lastPayment.tax = tonumber(payload.tax or 0) or 0
    lastPayment.reason = tostring(payload.reason or 'Imposto')
  end

  setFocus(true)

  -- Protocolo único (compat com html/script.js novo)
  SendNUIMessage({
    action = 'open',
    mode = tostring(mode or ''),
    payload = payload
  })

  -- watchdog com retry: aguarda resposta da NUI antes de fechar
  CreateThread(function()
    Wait(5000) -- aumentado de 2500 para 5000ms

    if uiOpen and not uiAck then
      -- Retry uma vez antes de desistir
      SendNUIMessage({
        action = 'open',
        mode = tostring(mode or ''),
        payload = payload
      })

      Wait(3000) -- aguarda mais 3 segundos

      if uiOpen and not uiAck then
        -- Ainda sem resposta, fecha UI
        uiOpen = false
        setFocus(false)
        SendNUIMessage({ action = 'close' })

        if lib and lib.notify then
          lib.notify({
            title = 'Economia',
            description = 'Erro ao abrir interface. Tente novamente.',
            type = 'error'
          })
        end
      end
    end
  end)
end

local function applyClosedState()
  uiOpen = false
  currentPanel = nil
  uiAck = false
  SE.Client.EconomyUIOpen = false
  setFocus(false)
end

local function closeUI(notifyNui)
  applyClosedState()
  if notifyNui ~= false then
    SendNUIMessage({ action = 'close' })
  end
end

function SE.Client.OpenTaxPanel()
  if uiOpen then return end
  currentPanel = 'tax'
  SE.Client.EconomyUIOpen = true
  openUI('tax', {})
end

function SE.Client.OpenAdminPanel()
  if uiOpen then return end
  currentPanel = 'staff'
  SE.Client.EconomyUIOpen = true
  TriggerServerEvent('space_economy:server_openStaffPanel')
end

function SE.Client.OpenUITest()
  if uiOpen then return end
  currentPanel = 'test'
  SE.Client.EconomyUIOpen = true
  TriggerEvent('space_economy:client_open', 'admin', {})
end

function SE.Client.CloseEconomyUI()
  closeUI(true)
end

--============================================================
-- Eventos vindos do server
--============================================================
RegisterNetEvent('space_economy:client_open', function(mode, payload)
  openUI(mode, payload or {})
end)

RegisterNetEvent('space_economy:client_notify', function(msg, typ)
  if lib and lib.notify then
    lib.notify({
      title = 'Economia',
      description = msg or '...',
      type = typ or 'inform'
    })
  else
    -- fallback simples
    print(('[space_economy] %s'):format(msg or '...'))
  end
end)

-- server -> NUI (roteador único)
RegisterNetEvent('space_economy:client_adminData', function(key, data)
  SendNUIMessage({
    action = 'adminData',
    key = key,
    data = data
  })
end)

--============================================================
-- NUI callbacks (fetch -> client)
--============================================================

-- handshake / ACK (script.js chama post("ready"))
RegisterNUICallback('ready', function(_, cb)
  uiAck = true
  cb({ ok = true })
end)

-- compat extra (se você usar ACK por token em algum momento)
RegisterNUICallback('nui_ack', function(_, cb)
  uiAck = true
  cb({ ok = true })
end)

-- fechar forçado (script.js chama post("forceClose"))
RegisterNUICallback('forceClose', function(_, cb)
  closeUI()
  cb({ ok = true })
end)

-- fechar normal
RegisterNUICallback('close', function(_, cb)
  closeUI()
  cb({ ok = true })
end)

-- admin router (script.js chama post("admin_requestData"))
RegisterNUICallback('admin_requestData', function(data, cb)
  local dataType = data and data.dataType
  local payload = data and data.payload
  TriggerServerEvent('space_economy:server_requestAdminData', dataType, payload)
  cb({ ok = true })
end)

-- pagamento UI (script.js chama post("payTax"))
RegisterNUICallback('payTax', function(data, cb)
  local tax = tonumber((data and data.tax) or lastPayment.tax or 0) or 0
  local reason = tostring((data and data.reason) or lastPayment.reason or 'Imposto')
  TriggerServerEvent('space_economy:server_payTax', tax, reason)
  cb({ ok = true })
end)

RegisterNUICallback('refuseTax', function(data, cb)
  TriggerServerEvent('space_economy:server_refuseTax', data and data.tax, data and data.reason)
  cb({ ok = true })
end)

-- calculadora (script.js chama post("calculateTax"))
RegisterNUICallback('calculateTax', function(data, cb)
  TriggerServerEvent('space_economy:server_calculateTax', data and data.amount)
  cb({ ok = true })
end)

-- lavagem (script.js chama post("washMoney"))
RegisterNUICallback('washMoney', function(data, cb)
  TriggerServerEvent('space_economy:server_washMoney',
    data and data.businessId,
    data and data.amount,
    data and (data.fee_percent or data.feePercent)
  )
  cb({ ok = true })
end)

-- empréstimos (player)
RegisterNUICallback('simulateLoan', function(data, cb)
  TriggerServerEvent('space_economy:server_simulateLoan',
    data and data.amount,
    data and data.installments,
    data and data.purpose
  )
  cb({ ok = true })
end)

RegisterNUICallback('requestLoan', function(data, cb)
  TriggerServerEvent('space_economy:server_requestLoan',
    data and data.amount,
    data and data.installments,
    data and data.purpose
  )
  cb({ ok = true })
end)

RegisterNetEvent('space_economy:client_loanSimulation', function(simulation)
  SendNUIMessage({
    action = 'loanSimulation',
    simulation = simulation
  })
end)

RegisterNetEvent('space_economy:client_loanApproved', function(loanId, simulation)
  SendNUIMessage({
    action = 'loanApproved',
    loanId = loanId,
    simulation = simulation
  })
end)

--============================================================
-- NEW PLAYER PANEL
--============================================================
RegisterNetEvent('space_economy:client_open_player', function()
  if uiOpen then return end
  uiOpen = true
  currentPanel = 'player'
  SE.Client.EconomyUIOpen = true
  setFocus(true)
  SendNUIMessage({ action = 'openPlayerPanel' })
end)

RegisterNUICallback('closePlayerPanel', function(_, cb)
  closeUI(false)
  cb({ ok = true })
end)

-- Player panel data requests
RegisterNUICallback('getFinancialData', function(_, cb)
  TriggerServerCallback('space_economy:getFinancialData', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getMyOrganizations', function(_, cb)
  TriggerServerCallback('space_economy:getMyOrganizations', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getStockQuotes', function(_, cb)
  TriggerServerCallback('space_economy:getStockQuotes', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getMyPortfolio', function(_, cb)
  TriggerServerCallback('space_economy:getMyPortfolio', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getBankingProducts', function(_, cb)
  TriggerServerCallback('space_economy:getBankingProducts', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getMyInvestments', function(_, cb)
  TriggerServerCallback('space_economy:getMyInvestments', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getMyShops', function(_, cb)
  TriggerServerCallback('space_economy:getMyShops', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('createOrganization', function(data, cb)
  TriggerServerEvent('space_economy:server_createOrg', data.name, data.tag)
  cb({ success = true })
end)

RegisterNUICallback('buyStock', function(data, cb)
  TriggerServerEvent('space_economy:server_buyStock', data.symbol, data.quantity)
  cb({ success = true })
end)

RegisterNUICallback('sellStock', function(data, cb)
  TriggerServerEvent('space_economy:server_sellStock', data.symbol, data.quantity)
  cb({ success = true })
end)

RegisterNUICallback('invest', function(data, cb)
  TriggerServerEvent('space_economy:server_invest', data.productId, data.amount)
  cb({ success = true })
end)

RegisterNUICallback('redeemInvestment', function(data, cb)
  TriggerServerEvent('space_economy:server_redeemInvestment', data.investmentId)
  cb({ success = true })
end)

RegisterNUICallback('createShop', function(data, cb)
  TriggerServerEvent('space_economy:server_createShop', data.name)
  cb({ success = true })
end)

--============================================================
-- NEW STAFF PANEL
--============================================================
RegisterNetEvent('space_economy:client_open_staff', function()
  if uiOpen then return end
  uiOpen = true
  currentPanel = 'staff'
  SE.Client.EconomyUIOpen = true
  setFocus(true)
  SendNUIMessage({ action = 'openStaffPanel' })
end)

RegisterNUICallback('closeStaffPanel', function(_, cb)
  closeUI(false)
  cb({ ok = true })
end)

-- Staff panel data requests
RegisterNUICallback('getEconomyOverview', function(_, cb)
  TriggerServerCallback('space_economy:getEconomyOverview', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getEconomyData', function(_, cb)
  TriggerServerCallback('space_economy:getEconomyData', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getAllOrganizations', function(_, cb)
  TriggerServerCallback('space_economy:getAllOrganizations', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getStockMarketAdmin', function(_, cb)
  TriggerServerCallback('space_economy:getStockMarketAdmin', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getActiveEvent', function(_, cb)
  TriggerServerCallback('space_economy:getActiveEvent', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getEventHistory', function(_, cb)
  TriggerServerCallback('space_economy:getEventHistory', function(data)
    cb({ success = true, data = data })
  end)
end)

RegisterNUICallback('getCacheStats', function(_, cb)
  TriggerServerCallback('space_economy:getCacheStats', function(data)
    cb({ success = true, data = data })
  end)
end)


AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  closeUI(true)
end)

-- Helper function for callbacks (if not already present)
function TriggerServerCallback(name, cb, ...)
  lib.callback(name, false, cb, ...)
end
