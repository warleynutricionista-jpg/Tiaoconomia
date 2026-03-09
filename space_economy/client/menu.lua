--============================================================
-- space_economy - client/menu.lua
-- Menus de Intervenção Econômica + Painéis Admin/Player
--============================================================

local function notify(msg, typ)
  if lib and lib.notify then
    lib.notify({ title = 'Economia', description = msg, type = typ or 'inform' })
  else
    print(('[space_economy] %s'):format(msg))
  end
end

local function ensureLib()
  if not lib or not lib.registerContext then
    notify('ox_lib não disponível para menu.', 'error')
    return false
  end
  return true
end

local function runCommand(command, args)
  if args and #args > 0 then
    local parts = {}
    for _, arg in ipairs(args) do
      if arg ~= nil and tostring(arg) ~= '' then
        table.insert(parts, tostring(arg))
      end
    end
    if #parts > 0 then
      ExecuteCommand(('%s %s'):format(command, table.concat(parts, ' ')))
      return
    end
  end
  ExecuteCommand(command)
end

local function promptAndRun(title, command, fields, transform)
  if not ensureLib() then return end
  local input = lib.inputDialog(title, fields)
  if not input then return end
  local args = transform and transform(input) or input
  runCommand(command, args)
end

-- ============================================================
-- MENUS ADMIN
-- ============================================================

local function openEconomicEventsMenu()
  if not ensureLib() then return end

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

local function openAdminMonitorMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_monitor_menu',
    title = 'Admin: Economy Monitor',
    options = {
      {
        title = 'Relatório econômico completo',
        description = '/eco_relatorio',
        icon = 'chart-line',
        onSelect = function()
          runCommand('eco_relatorio')
        end,
      },
      {
        title = 'Relatório de política monetária',
        description = '/eco_politica',
        icon = 'scale-balanced',
        onSelect = function()
          runCommand('eco_politica')
        end,
      },
    },
  })

  lib.showContext('space_economy_admin_monitor_menu')
end

local function openAdminPolicyMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_policy_menu',
    title = 'Admin: Política Monetária',
    options = {
      {
        title = 'Relatório de política monetária',
        description = '/eco_politica',
        icon = 'scale-balanced',
        onSelect = function()
          runCommand('eco_politica')
        end,
      },
      {
        title = 'Forçar reunião do COPOM',
        description = '/eco_copom',
        icon = 'gavel',
        onSelect = function()
          runCommand('eco_copom')
        end,
      },
      {
        title = 'Ajustar IPC de categoria',
        description = '/eco_ipc <categoria> <±%>',
        icon = 'sliders',
        onSelect = function()
          promptAndRun('Ajustar IPC', 'eco_ipc', {
            {
              type = 'select',
              label = 'Categoria',
              options = {
                { label = 'Alimentação', value = 'alimentacao' },
                { label = 'Transporte', value = 'transporte' },
                { label = 'Habitação', value = 'habitacao' },
                { label = 'Saúde', value = 'saude' },
                { label = 'Lazer', value = 'lazer' },
              }
            },
            { type = 'input', label = 'Variação (%) ex: 2 ou -1.5' },
          }, function(input)
            return { input[1], input[2] }
          end)
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_policy_menu')
end

local function openAdminEventsMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_events_menu',
    title = 'Admin: Eventos Econômicos',
    options = {
      {
        title = 'Ver evento econômico ativo',
        description = '/eco_evento',
        icon = 'circle-info',
        onSelect = function()
          runCommand('eco_evento')
        end,
      },
      {
        title = 'Disparar evento manualmente',
        description = '/eco_trigger <evento_id>',
        icon = 'bolt',
        onSelect = function()
          promptAndRun('Disparar Evento', 'eco_trigger', {
            {
              type = 'select',
              label = 'Evento',
              options = {
                { label = 'Crise Financeira', value = 'crise_financeira' },
                { label = 'Recessão', value = 'recessao' },
                { label = 'Boom Econômico', value = 'boom_economico' },
                { label = 'Crescimento Acelerado', value = 'crescimento_acelerado' },
                { label = 'Crise de Combustível', value = 'crise_combustivel' },
                { label = 'Safra Recorde', value = 'safra_recorde' },
                { label = 'Bolha Imobiliária', value = 'bolha_imobiliaria' },
                { label = 'Greve na Saúde', value = 'greve_saude' },
                { label = 'Inovação Tecnológica', value = 'inovacao_tecnologica' },
                { label = 'Investimento Estrangeiro', value = 'investimento_estrangeiro' },
                { label = 'Desastre Natural', value = 'desastre_natural' },
                { label = 'Acordo Comercial', value = 'acordo_comercial' },
              }
            }
          })
        end,
      },
      {
        title = 'Definir desfecho do evento ativo',
        description = '/eco_desfecho <id|auto>',
        icon = 'flag-checkered',
        onSelect = function()
          promptAndRun('Desfecho do Evento', 'eco_desfecho', {
            { type = 'input', label = 'ID do evento ou "auto"' },
          })
        end,
      },
      {
        title = 'Histórico dos últimos 10 eventos',
        description = '/eco_historico',
        icon = 'clock-rotate-left',
        onSelect = function()
          runCommand('eco_historico')
        end,
      },
      {
        title = 'Menu de intervenção econômica',
        description = '/eco_eventos',
        icon = 'hand-holding-dollar',
        onSelect = function()
          openEconomicEventsMenu()
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_events_menu')
end

local function openAdminStockMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_stock_menu',
    title = 'Admin: Bolsa de Valores',
    options = {
      {
        title = 'Ver cotações da bolsa',
        description = '/bolsa',
        icon = 'chart-line',
        onSelect = function()
          runCommand('bolsa')
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_stock_menu')
end

local function openAdminLaborMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_labor_menu',
    title = 'Admin: Mercado de Trabalho',
    options = {
      {
        title = 'Relatório do mercado de trabalho',
        description = '/eco_trabalho',
        icon = 'briefcase',
        onSelect = function()
          runCommand('eco_trabalho')
        end,
      },
      {
        title = 'Forçar ajuste de salário mínimo',
        description = '/eco_ajustar_salario',
        icon = 'money-bill-wave',
        onSelect = function()
          runCommand('eco_ajustar_salario')
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_labor_menu')
end

local function openAdminOrganizationsMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_org_menu',
    title = 'Admin: Organizações',
    options = {
      {
        title = 'Criar organização (Admin)',
        description = '/org_admin_create <citizenid> <nome> <tag>',
        icon = 'building',
        onSelect = function()
          promptAndRun('Criar Organização (Admin)', 'org_admin_create', {
            { type = 'input', label = 'Citizen ID' },
            { type = 'input', label = 'Nome' },
            { type = 'input', label = 'Tag' },
          })
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_org_menu')
end

local function openAdminSystemsMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_systems_menu',
    title = 'Admin: Sistemas Base (v3.1)',
    options = {
      {
        title = 'Painel administrativo completo (NUI)',
        description = '/economia',
        icon = 'tablet-screen-button',
        onSelect = function()
          runCommand('economia')
        end,
      },
      {
        title = 'Estatísticas do cache LRU',
        description = '/cache_stats',
        icon = 'chart-simple',
        onSelect = function()
          runCommand('cache_stats')
        end,
      },
      {
        title = 'Limpar cache',
        description = '/cache_clear [categoria]',
        icon = 'broom',
        onSelect = function()
          promptAndRun('Limpar Cache', 'cache_clear', {
            { type = 'input', label = 'Categoria (opcional)' },
          }, function(input)
            local category = input[1]
            if category == nil or category == '' then
              return {}
            end
            return { category }
          end)
        end,
      },
      {
        title = 'Forçar pré-aquecimento do cache',
        description = '/cache_warmup',
        icon = 'fire',
        onSelect = function()
          runCommand('cache_warmup')
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_systems_menu')
end

local function openAdminMainMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_admin_main_menu',
    title = 'Menu Administrativo: Economia',
    options = {
      {
        title = 'Economy Monitor',
        description = 'PIB, circulação, relatórios',
        icon = 'chart-line',
        onSelect = function()
          openAdminMonitorMenu()
        end,
      },
      {
        title = 'Política Monetária',
        description = 'SELIC, inflação, IPC, COPOM',
        icon = 'scale-balanced',
        onSelect = function()
          openAdminPolicyMenu()
        end,
      },
      {
        title = 'Eventos Econômicos',
        description = 'Eventos, gatilhos e histórico',
        icon = 'bolt',
        onSelect = function()
          openAdminEventsMenu()
        end,
      },
      {
        title = 'Bolsa de Valores',
        description = 'Cotações e painel de ações',
        icon = 'chart-simple',
        onSelect = function()
          openAdminStockMenu()
        end,
      },
      {
        title = 'Mercado de Trabalho',
        description = 'Relatórios e ajustes',
        icon = 'briefcase',
        onSelect = function()
          openAdminLaborMenu()
        end,
      },
      {
        title = 'Organizações (Admin)',
        description = 'Criar organização via admin',
        icon = 'building',
        onSelect = function()
          openAdminOrganizationsMenu()
        end,
      },
      {
        title = 'Sistemas Base (v3.1)',
        description = 'Painel admin e cache',
        icon = 'gears',
        onSelect = function()
          openAdminSystemsMenu()
        end,
      },
    }
  })

  lib.showContext('space_economy_admin_main_menu')
end

-- ============================================================
-- MENUS PLAYER
-- ============================================================

local function openPlayerBankingMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_player_banking_menu',
    title = 'Player: Banking',
    options = {
      {
        title = 'Investir em produto bancário',
        description = '/banco_investir <produto> <valor>',
        icon = 'piggy-bank',
        onSelect = function()
          promptAndRun('Investir', 'banco_investir', {
            { type = 'input', label = 'Produto (poupanca, cdb_30, cdb_60, cdb_90, cdb_180, lci, tesouro)' },
            { type = 'input', label = 'Valor' },
          })
        end,
      },
      {
        title = 'Resgatar investimento',
        description = '/banco_resgatar <id>',
        icon = 'hand-holding-dollar',
        onSelect = function()
          promptAndRun('Resgatar Investimento', 'banco_resgatar', {
            { type = 'input', label = 'ID do investimento' },
          })
        end,
      },
      {
        title = 'Extrato de investimentos',
        description = '/banco_extrato',
        icon = 'receipt',
        onSelect = function()
          runCommand('banco_extrato')
        end,
      },
    }
  })

  lib.showContext('space_economy_player_banking_menu')
end

local function openPlayerStockMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_player_stock_menu',
    title = 'Player: Bolsa de Valores',
    options = {
      {
        title = 'Ver cotações',
        description = '/bolsa',
        icon = 'chart-line',
        onSelect = function()
          runCommand('bolsa')
        end,
      },
    }
  })

  lib.showContext('space_economy_player_stock_menu')
end

local function openPlayerOrgMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_player_org_menu',
    title = 'Player: Organizações',
    options = {
      {
        title = 'Criar organização',
        description = '/org_create <nome> <tag>',
        icon = 'building',
        onSelect = function()
          promptAndRun('Criar Organização', 'org_create', {
            { type = 'input', label = 'Nome' },
            { type = 'input', label = 'Tag' },
          })
        end,
      },
      {
        title = 'Adicionar membro',
        description = '/org_addmember <org_id> <citizenid> [role]',
        icon = 'user-plus',
        onSelect = function()
          promptAndRun('Adicionar Membro', 'org_addmember', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Citizen ID' },
            { type = 'input', label = 'Role (opcional)' },
          }, function(input)
            local args = { input[1], input[2] }
            if input[3] and input[3] ~= '' then
              table.insert(args, input[3])
            end
            return args
          end)
        end,
      },
      {
        title = 'Remover membro',
        description = '/org_removemember <org_id> <citizenid>',
        icon = 'user-minus',
        onSelect = function()
          promptAndRun('Remover Membro', 'org_removemember', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Citizen ID' },
          })
        end,
      },
      {
        title = 'Ajustar logística',
        description = '/org_setlogistica <org_id> <entrega%> <armazenagem%> <taxa%>',
        icon = 'truck',
        onSelect = function()
          promptAndRun('Ajustar Logística', 'org_setlogistica', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Entrega (%)' },
            { type = 'input', label = 'Armazenagem (%)' },
            { type = 'input', label = 'Taxa (%)' },
          })
        end,
      },
      {
        title = 'Adicionar produto',
        description = '/org_addproduct <org_id> <item> <quantidade> <preco> [label]',
        icon = 'box-open',
        onSelect = function()
          promptAndRun('Adicionar Produto', 'org_addproduct', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Item' },
            { type = 'input', label = 'Quantidade' },
            { type = 'input', label = 'Preço' },
            { type = 'input', label = 'Label (opcional)' },
          }, function(input)
            local args = { input[1], input[2], input[3], input[4] }
            if input[5] and input[5] ~= '' then
              table.insert(args, input[5])
            end
            return args
          end)
        end,
      },
      {
        title = 'Repor estoque',
        description = '/org_restock <org_id> <item> <quantidade>',
        icon = 'warehouse',
        onSelect = function()
          promptAndRun('Repor Estoque', 'org_restock', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Item' },
            { type = 'input', label = 'Quantidade' },
          })
        end,
      },
      {
        title = 'Definir preço',
        description = '/org_setprice <org_id> <item> <preco>',
        icon = 'tags',
        onSelect = function()
          promptAndRun('Definir Preço', 'org_setprice', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Item' },
            { type = 'input', label = 'Preço' },
          })
        end,
      },
      {
        title = 'Comprar',
        description = '/org_buy <org_id> <item> [quantidade]',
        icon = 'cart-shopping',
        onSelect = function()
          promptAndRun('Comprar', 'org_buy', {
            { type = 'input', label = 'ID da organização' },
            { type = 'input', label = 'Item' },
            { type = 'input', label = 'Quantidade (opcional)' },
          }, function(input)
            local args = { input[1], input[2] }
            if input[3] and input[3] ~= '' then
              table.insert(args, input[3])
            end
            return args
          end)
        end,
      },
      {
        title = 'Informações da organização',
        description = '/org_info <org_id>',
        icon = 'circle-info',
        onSelect = function()
          promptAndRun('Info Organização', 'org_info', {
            { type = 'input', label = 'ID da organização' },
          })
        end,
      },
    }
  })

  lib.showContext('space_economy_player_org_menu')
end

local function openPlayerDebtsMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_player_debts_menu',
    title = 'Player: Dívidas',
    options = {
      {
        title = 'Ver suas dívidas',
        description = '/dividas',
        icon = 'file-invoice-dollar',
        onSelect = function()
          runCommand('dividas')
        end,
      },
      {
        title = 'Ver parcelamentos ativos',
        description = '/parcelas',
        icon = 'calendar',
        onSelect = function()
          runCommand('parcelas')
        end,
      },
      {
        title = 'Ver score de crédito',
        description = '/credito',
        icon = 'star',
        onSelect = function()
          runCommand('credito')
        end,
      },
      {
        title = 'Solicitar empréstimo',
        description = '/emprestimo <valor>',
        icon = 'handshake',
        onSelect = function()
          promptAndRun('Solicitar Empréstimo', 'emprestimo', {
            { type = 'input', label = 'Valor' },
          })
        end,
      },
    }
  })

  lib.showContext('space_economy_player_debts_menu')
end

local function openPlayerMainMenu()
  if not ensureLib() then return end

  lib.registerContext({
    id = 'space_economy_player_main_menu',
    title = 'Painel do Player: Economia',
    options = {
      {
        title = 'Banking',
        description = 'Investimentos e extratos',
        icon = 'piggy-bank',
        onSelect = function()
          openPlayerBankingMenu()
        end,
      },
      {
        title = 'Bolsa de Valores',
        description = 'Cotações e mercado',
        icon = 'chart-line',
        onSelect = function()
          openPlayerStockMenu()
        end,
      },
      {
        title = 'Organizações',
        description = 'Empresas e logística',
        icon = 'building',
        onSelect = function()
          openPlayerOrgMenu()
        end,
      },
      {
        title = 'Dívidas e Crédito',
        description = 'Parcelas, score e empréstimos',
        icon = 'file-invoice-dollar',
        onSelect = function()
          openPlayerDebtsMenu()
        end,
      },
    }
  })

  lib.showContext('space_economy_player_main_menu')
end

-- ============================================================
-- COMANDOS + SUGESTÕES
-- ============================================================

RegisterCommand('eco_eventos', function()
  openEconomicEventsMenu()
end, false)

RegisterCommand('eco_menu_admin', function()
  openAdminMainMenu()
end, false)

RegisterCommand('eco_menu_monitor', function()
  openAdminMonitorMenu()
end, false)

RegisterCommand('eco_menu_politica', function()
  openAdminPolicyMenu()
end, false)

RegisterCommand('eco_menu_eventos', function()
  openAdminEventsMenu()
end, false)

RegisterCommand('eco_menu_bolsa', function()
  openAdminStockMenu()
end, false)

RegisterCommand('eco_menu_trabalho', function()
  openAdminLaborMenu()
end, false)

RegisterCommand('eco_menu_org_admin', function()
  openAdminOrganizationsMenu()
end, false)

RegisterCommand('eco_menu_sistemas', function()
  openAdminSystemsMenu()
end, false)

RegisterCommand('eco_menu_player', function()
  openPlayerMainMenu()
end, false)

RegisterCommand('eco_menu_banco', function()
  openPlayerBankingMenu()
end, false)

RegisterCommand('eco_menu_bolsa_player', function()
  openPlayerStockMenu()
end, false)

RegisterCommand('eco_menu_org', function()
  openPlayerOrgMenu()
end, false)

RegisterCommand('eco_menu_dividas', function()
  openPlayerDebtsMenu()
end, false)


CreateThread(function()
  Wait(1000)
  pcall(function()
    TriggerEvent('chat:addSuggestion', '/eco_eventos', 'Abrir menu de intervenção econômica (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_admin', 'Abrir menu administrativo (categorias)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_monitor', 'Abrir menu de monitor econômico (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_politica', 'Abrir menu de política monetária (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_eventos', 'Abrir menu de eventos econômicos (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_bolsa', 'Abrir menu de bolsa (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_trabalho', 'Abrir menu de mercado de trabalho (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_org_admin', 'Abrir menu de organizações (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_sistemas', 'Abrir menu de sistemas base (admin)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_player', 'Abrir painel do player (economia)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_banco', 'Abrir menu de banking (player)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_bolsa_player', 'Abrir menu de bolsa (player)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_org', 'Abrir menu de organizações (player)')
    TriggerEvent('chat:addSuggestion', '/eco_menu_dividas', 'Abrir menu de dívidas (player)')
  end)
end)
