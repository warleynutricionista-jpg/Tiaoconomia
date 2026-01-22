/**
 * Space Economy - Staff Panel Controller
 * Administrative interface for managing the economy
 */

(() => {
  'use strict';

  // ===== CONSTANTS =====
  const RESOURCE_NAME = (typeof GetParentResourceName === 'function' && GetParentResourceName()) || 'space_economy';
  const DEBUG = false;

  // ===== UTILITIES =====
  const log = (...args) => DEBUG && console.log('[Staff Panel]', ...args);
  const error = (...args) => console.error('[Staff Panel Error]', ...args);

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  const formatMoney = (value) => {
    const num = Number(value);
    return Number.isFinite(num) ? `$${Math.floor(num).toLocaleString('pt-BR')}` : '$0';
  };

  const parseNumber = (value) => {
    const num = Number(String(value ?? '').replace(',', '.'));
    return Number.isFinite(num) ? num : 0;
  };

  // ===== NUI COMMUNICATION =====
  const postNUI = (event, data = {}) => {
    log('POST:', event, data);
    return fetch(`https://${RESOURCE_NAME}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    })
    .then(resp => resp.json())
    .catch((err) => {
      error('POST failed:', event, err);
      showNotification('Erro de comunicação. Tente novamente.', 'error');
      throw err;
    });
  };

  // ===== STATE =====
  const State = {
    currentTab: 'overview',
    economyData: null,
    organizations: [],
    listedCompanies: [],
    events: [],
  };

  // ===== UI FUNCTIONS =====
  function showNotification(message, type = 'info') {
    console.log(`[${type.toUpperCase()}] ${message}`);
  }

  function openStaffPanel() {
    const overlay = $('#staff-overlay');
    if (overlay) {
      overlay.classList.add('active');
      refreshAdminData();
    }
  }

  function closeStaffPanel() {
    const overlay = $('#staff-overlay');
    if (overlay) {
      overlay.classList.remove('active');
    }
    postNUI('closeStaffPanel');
  }

  function switchTab(tabName) {
    $$('.tab-btn').forEach(btn => {
      if (btn.dataset.tab === tabName) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    $$('.tab-content').forEach(content => {
      if (content.dataset.tab === tabName) {
        content.classList.add('active');
      } else {
        content.classList.remove('active');
      }
    });

    State.currentTab = tabName;
    loadTabData(tabName);
  }

  function loadTabData(tabName) {
    switch (tabName) {
      case 'overview':
        loadOverview();
        break;
      case 'economy':
        loadEconomyData();
        break;
      case 'organizations':
        loadOrganizations();
        break;
      case 'stock-market':
        loadStockMarketAdmin();
        break;
      case 'events':
        loadEvents();
        break;
      case 'policies':
        loadPolicies();
        break;
      case 'cache':
        loadCacheStats();
        break;
    }
  }

  // ===== OVERVIEW TAB =====
  async function loadOverview() {
    try {
      const result = await postNUI('getEconomyOverview');
      if (result && result.success) {
        updateOverviewUI(result.data);
      }
    } catch (err) {
      error('Failed to load overview:', err);
    }
  }

  function updateOverviewUI(data) {
    if (!data) return;

    if ($('#treasury-balance')) $('#treasury-balance').textContent = formatMoney(data.treasury || 0);
    if ($('#pib-value')) $('#pib-value').textContent = formatMoney(data.pib || 0);
    if ($('#pib-per-capita')) $('#pib-per-capita').textContent = `Per capita: ${formatMoney(data.pibPerCapita || 0)}`;
    if ($('#money-circulation')) $('#money-circulation').textContent = formatMoney(data.circulation || 0);
    if ($('#velocity')) $('#velocity').textContent = `Velocidade: ${data.velocity || 0}x`;
    if ($('#selic-rate')) $('#selic-rate').textContent = `${data.selic || 0}%`;
    if ($('#inflation')) $('#inflation').textContent = `Inflação: ${data.inflation || 0}%`;
    if ($('#unemployment-rate')) $('#unemployment-rate').textContent = `${data.unemployment || 0}%`;
    if ($('#min-wage')) $('#min-wage').textContent = `Salário mín: ${formatMoney(data.minWage || 0)}`;
    if ($('#total-orgs')) $('#total-orgs').textContent = data.totalOrgs || 0;
    if ($('#active-orgs')) $('#active-orgs').textContent = `Ativas: ${data.activeOrgs || 0}`;
  }

  async function depositTreasury() {
    const amount = prompt('Quanto deseja depositar no tesouro?');
    if (!amount || amount <= 0) return;

    try {
      const result = await postNUI('treasuryDeposit', { amount: parseNumber(amount) });
      if (result && result.success) {
        showNotification('Depósito realizado com sucesso!', 'success');
        loadOverview();
      } else {
        showNotification(result.message || 'Erro ao depositar', 'error');
      }
    } catch (err) {
      error('Failed to deposit:', err);
    }
  }

  async function withdrawTreasury() {
    const amount = prompt('Quanto deseja sacar do tesouro?');
    if (!amount || amount <= 0) return;

    try {
      const result = await postNUI('treasuryWithdraw', { amount: parseNumber(amount) });
      if (result && result.success) {
        showNotification('Saque realizado com sucesso!', 'success');
        loadOverview();
      } else {
        showNotification(result.message || 'Erro ao sacar', 'error');
      }
    } catch (err) {
      error('Failed to withdraw:', err);
    }
  }

  async function forceWageAdjustment() {
    if (!confirm('Forçar ajuste de salário mínimo?')) return;

    try {
      const result = await postNUI('forceWageAdjustment');
      if (result && result.success) {
        showNotification('Salário mínimo ajustado!', 'success');
        loadOverview();
      } else {
        showNotification(result.message || 'Erro ao ajustar', 'error');
      }
    } catch (err) {
      error('Failed to adjust wage:', err);
    }
  }

  async function triggerCOPOM() {
    if (!confirm('Forçar reunião do COPOM?')) return;

    try {
      const result = await postNUI('forceCOPOM');
      if (result && result.success) {
        showNotification('Reunião do COPOM realizada!', 'success');
        loadOverview();
      } else {
        showNotification(result.message || 'Erro ao executar COPOM', 'error');
      }
    } catch (err) {
      error('Failed to trigger COPOM:', err);
    }
  }

  async function generateReport() {
    try {
      const result = await postNUI('generateEconomyReport');
      if (result && result.success) {
        showReportModal(result.data);
      } else {
        showNotification(result.message || 'Erro ao gerar relatório', 'error');
      }
    } catch (err) {
      error('Failed to generate report:', err);
    }
  }

  function showReportModal(report) {
    const modalContent = $('#modal-content');
    if (!modalContent) return;

    modalContent.innerHTML = `
      <h2>Relatório Econômico</h2>
      <div class="stats-display">
        <pre>${JSON.stringify(report, null, 2)}</pre>
      </div>
      <button class="btn btn-primary mt-3" onclick="closeModal({target: document.querySelector('.modal-overlay')})">Fechar</button>
    `;

    $('#modal-container').classList.add('active');
  }

  function openEventManager() {
    switchTab('events');
  }

  // ===== ECONOMY TAB =====
  async function loadEconomyData() {
    try {
      const result = await postNUI('getEconomyData');
      if (result && result.success) {
        updateEconomyUI(result.data);
      }
    } catch (err) {
      error('Failed to load economy data:', err);
    }
  }

  function updateEconomyUI(data) {
    if (!data) return;

    if ($('#copom-selic')) $('#copom-selic').textContent = `${data.selic || 0}%`;
    if ($('#copom-target')) $('#copom-target').textContent = `${data.inflationTarget || 4.5}%`;
    if ($('#copom-inflation')) $('#copom-inflation').textContent = `${data.inflation || 0}%`;
  }

  async function showLaborMarketReport() {
    try {
      const result = await postNUI('getLaborMarketReport');
      if (result && result.success) {
        const container = $('#labor-market-data');
        if (container) {
          container.innerHTML = `<pre>${JSON.stringify(result.data, null, 2)}</pre>`;
        }
      }
    } catch (err) {
      error('Failed to load labor market report:', err);
    }
  }

  async function adjustSELIC(action) {
    try {
      const result = await postNUI('adjustSELIC', { action });
      if (result && result.success) {
        showNotification(`SELIC ${action === 'raise' ? 'aumentada' : action === 'lower' ? 'reduzida' : 'mantida'}!`, 'success');
        loadEconomyData();
      } else {
        showNotification(result.message || 'Erro ao ajustar SELIC', 'error');
      }
    } catch (err) {
      error('Failed to adjust SELIC:', err);
    }
  }

  async function forceCOPOM() {
    if (!confirm('Forçar reunião do COPOM?')) return;

    try {
      const result = await postNUI('forceCOPOM');
      if (result && result.success) {
        showNotification('Reunião do COPOM realizada!', 'success');
        loadEconomyData();
      } else {
        showNotification(result.message || 'Erro ao executar COPOM', 'error');
      }
    } catch (err) {
      error('Failed to force COPOM:', err);
    }
  }

  async function adjustIPC(category) {
    const inputId = `ipc-${category}`;
    const value = parseNumber($(`#${inputId}`)?.value);

    if (!value) {
      showNotification('Digite um valor válido', 'error');
      return;
    }

    try {
      const result = await postNUI('adjustIPC', { category, value });
      if (result && result.success) {
        showNotification(`IPC de ${category} ajustado!`, 'success');
        $(`#${inputId}`).value = '';
      } else {
        showNotification(result.message || 'Erro ao ajustar IPC', 'error');
      }
    } catch (err) {
      error('Failed to adjust IPC:', err);
    }
  }

  // ===== ORGANIZATIONS TAB =====
  async function loadOrganizations() {
    try {
      const result = await postNUI('getAllOrganizations');
      if (result && result.success) {
        State.organizations = result.data || [];
        renderOrganizationsTable();
      }
    } catch (err) {
      error('Failed to load organizations:', err);
    }
  }

  function renderOrganizationsTable() {
    const container = $('#organizations-table');
    if (!container) return;

    if (!State.organizations || State.organizations.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhuma organização encontrada</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>ID</th>
          <th>Nome</th>
          <th>Tag</th>
          <th>Dono</th>
          <th>Saldo</th>
          <th>Membros</th>
          <th>Ações</th>
        </tr>
      </thead>
      <tbody>
        ${State.organizations.map(org => `
          <tr>
            <td>${org.id}</td>
            <td>${org.name}</td>
            <td>${org.tag}</td>
            <td>${org.owner_citizenid}</td>
            <td>${formatMoney(org.balance)}</td>
            <td>${org.members || 0}</td>
            <td>
              <button class="btn btn-sm btn-secondary" onclick="manageOrganization(${org.id})">Gerenciar</button>
            </td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  async function createOrgAdmin() {
    const citizenid = prompt('CitizenID do dono:');
    const name = prompt('Nome da organização:');
    const tag = prompt('Tag da organização:');

    if (!citizenid || !name || !tag) {
      showNotification('Preencha todos os campos', 'error');
      return;
    }

    try {
      const result = await postNUI('createOrgAdmin', { citizenid, name, tag });
      if (result && result.success) {
        showNotification('Organização criada com sucesso!', 'success');
        loadOrganizations();
      } else {
        showNotification(result.message || 'Erro ao criar organização', 'error');
      }
    } catch (err) {
      error('Failed to create organization:', err);
    }
  }

  async function refreshOrganizations() {
    loadOrganizations();
  }

  // ===== STOCK MARKET TAB =====
  async function loadStockMarketAdmin() {
    try {
      const result = await postNUI('getStockMarketAdmin');
      if (result && result.success) {
        State.listedCompanies = result.data.companies || [];
        updateStockMarketUI(result.data);
      }
    } catch (err) {
      error('Failed to load stock market admin:', err);
    }
  }

  function updateStockMarketUI(data) {
    renderListedCompanies();

    if ($('#stock-index')) $('#stock-index').textContent = data.index || 1000;
    if ($('#stock-volume')) $('#stock-volume').textContent = formatMoney(data.volume || 0);
    if ($('#stock-companies')) $('#stock-companies').textContent = data.companiesCount || 0;
    if ($('#stock-transactions')) $('#stock-transactions').textContent = data.transactionsToday || 0;

    // Populate company select
    const select = $('#stock-company-select');
    if (select) {
      select.innerHTML = '<option value="">Selecione...</option>' +
        State.listedCompanies.map(c => `<option value="${c.id}">${c.name} [${c.symbol}]</option>`).join('');
    }
  }

  function renderListedCompanies() {
    const container = $('#listed-companies-table');
    if (!container) return;

    if (!State.listedCompanies || State.listedCompanies.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhuma empresa listada</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Símbolo</th>
          <th>Empresa</th>
          <th>Cotação</th>
          <th>Variação</th>
          <th>Valor de Mercado</th>
          <th>Ações</th>
        </tr>
      </thead>
      <tbody>
        ${State.listedCompanies.map(company => `
          <tr>
            <td>${company.symbol}</td>
            <td>${company.name}</td>
            <td>${formatMoney(company.price)}</td>
            <td style="color: ${company.change >= 0 ? 'var(--success)' : 'var(--danger)'}">
              ${company.change >= 0 ? '+' : ''}${company.change}%
            </td>
            <td>${formatMoney(company.marketCap || 0)}</td>
            <td>
              <button class="btn btn-sm btn-secondary" onclick="editCompany(${company.id})">Editar</button>
              <button class="btn btn-sm btn-danger" onclick="delistCompany(${company.id})">Remover</button>
            </td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  async function listCompanyOnStock() {
    const orgId = prompt('ID da organização:');
    const symbol = prompt('Símbolo da ação (3-5 letras):');
    const initialPrice = prompt('Preço inicial:');

    if (!orgId || !symbol || !initialPrice) {
      showNotification('Preencha todos os campos', 'error');
      return;
    }

    try {
      const result = await postNUI('listCompanyOnStock', {
        orgId: parseNumber(orgId),
        symbol,
        initialPrice: parseNumber(initialPrice)
      });

      if (result && result.success) {
        showNotification('Empresa listada com sucesso!', 'success');
        loadStockMarketAdmin();
      } else {
        showNotification(result.message || 'Erro ao listar empresa', 'error');
      }
    } catch (err) {
      error('Failed to list company:', err);
    }
  }

  async function adjustStockPrice() {
    const companyId = $('#stock-company-select')?.value;
    const adjustment = parseNumber($('#stock-adjustment')?.value);

    if (!companyId || !adjustment) {
      showNotification('Preencha todos os campos', 'error');
      return;
    }

    try {
      const result = await postNUI('adjustStockPrice', { companyId, adjustment });
      if (result && result.success) {
        showNotification('Cotação ajustada!', 'success');
        $('#stock-adjustment').value = '';
        loadStockMarketAdmin();
      } else {
        showNotification(result.message || 'Erro ao ajustar cotação', 'error');
      }
    } catch (err) {
      error('Failed to adjust stock price:', err);
    }
  }

  // ===== EVENTS TAB =====
  async function loadEvents() {
    try {
      const [activeResult, historyResult] = await Promise.all([
        postNUI('getActiveEvent'),
        postNUI('getEventHistory')
      ]);

      if (activeResult && activeResult.success) {
        displayActiveEvent(activeResult.data);
      }

      if (historyResult && historyResult.success) {
        renderEventHistory(historyResult.data || []);
      }

      // Load available events for trigger
      loadAvailableEvents();
    } catch (err) {
      error('Failed to load events:', err);
    }
  }

  function displayActiveEvent(event) {
    const container = $('#active-event-display');
    if (!container) return;

    if (!event) {
      container.innerHTML = '<p class="empty-state">Nenhum evento ativo no momento</p>';
      return;
    }

    container.innerHTML = `
      <h4>${event.name}</h4>
      <p>${event.description}</p>
      <div class="event-meta">
        <span>Iniciado: ${event.startedAt || 'Agora'}</span>
        <span>Duração: ${event.duration || '--'}</span>
      </div>
    `;
  }

  async function loadAvailableEvents() {
    try {
      const result = await postNUI('getAvailableEvents');
      if (result && result.success) {
        const select = $('#event-select');
        if (select) {
          select.innerHTML = '<option value="">Selecione um evento...</option>' +
            (result.data || []).map(e => `<option value="${e.id}">${e.name}</option>`).join('');
        }
      }
    } catch (err) {
      error('Failed to load available events:', err);
    }
  }

  async function triggerEvent() {
    const eventId = $('#event-select')?.value;
    if (!eventId) {
      showNotification('Selecione um evento', 'error');
      return;
    }

    try {
      const result = await postNUI('triggerEvent', { eventId });
      if (result && result.success) {
        showNotification('Evento disparado!', 'success');
        loadEvents();
      } else {
        showNotification(result.message || 'Erro ao disparar evento', 'error');
      }
    } catch (err) {
      error('Failed to trigger event:', err);
    }
  }

  async function setEventOutcome() {
    const outcome = $('#outcome-select')?.value;
    if (!outcome) {
      showNotification('Selecione um desfecho', 'error');
      return;
    }

    try {
      const result = await postNUI('setEventOutcome', { outcome });
      if (result && result.success) {
        showNotification('Desfecho definido!', 'success');
        loadEvents();
      } else {
        showNotification(result.message || 'Erro ao definir desfecho', 'error');
      }
    } catch (err) {
      error('Failed to set outcome:', err);
    }
  }

  function renderEventHistory(events) {
    const container = $('#events-history-table');
    if (!container) return;

    if (!events || events.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhum evento no histórico</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Evento</th>
          <th>Data</th>
          <th>Duração</th>
          <th>Desfecho</th>
        </tr>
      </thead>
      <tbody>
        ${events.map(event => `
          <tr>
            <td>${event.name}</td>
            <td>${event.date || '--'}</td>
            <td>${event.duration || '--'}</td>
            <td><span class="badge badge-${event.outcome === 'positive' ? 'success' : event.outcome === 'negative' ? 'danger' : 'info'}">${event.outcome || 'Auto'}</span></td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  async function loadEventHistory() {
    try {
      const result = await postNUI('getEventHistory');
      if (result && result.success) {
        renderEventHistory(result.data || []);
      }
    } catch (err) {
      error('Failed to load event history:', err);
    }
  }

  // ===== POLICIES TAB =====
  async function loadPolicies() {
    // Load policy data
  }

  async function getEconomyReport() {
    try {
      const result = await postNUI('getEconomyReport');
      if (result && result.success) {
        showReportModal(result.data);
      }
    } catch (err) {
      error('Failed to get economy report:', err);
    }
  }

  async function getPoliticalReport() {
    try {
      const result = await postNUI('getPoliticalReport');
      if (result && result.success) {
        showReportModal(result.data);
      }
    } catch (err) {
      error('Failed to get political report:', err);
    }
  }

  async function getLaborReport() {
    try {
      const result = await postNUI('getLaborMarketReport');
      if (result && result.success) {
        showReportModal(result.data);
      }
    } catch (err) {
      error('Failed to get labor report:', err);
    }
  }

  // ===== CACHE TAB =====
  async function loadCacheStats() {
    refreshCacheStats();
  }

  async function refreshCacheStats() {
    try {
      const result = await postNUI('getCacheStats');
      if (result && result.success) {
        const container = $('#cache-stats-display');
        if (container) {
          container.innerHTML = `<pre>${JSON.stringify(result.data, null, 2)}</pre>`;
        }
      }
    } catch (err) {
      error('Failed to load cache stats:', err);
    }
  }

  async function warmupCache() {
    try {
      const result = await postNUI('warmupCache');
      if (result && result.success) {
        showNotification('Cache pré-aquecido!', 'success');
        refreshCacheStats();
      }
    } catch (err) {
      error('Failed to warmup cache:', err);
    }
  }

  async function clearCache() {
    if (!confirm('Tem certeza que deseja limpar o cache?')) return;

    try {
      const result = await postNUI('clearCache');
      if (result && result.success) {
        showNotification('Cache limpo!', 'success');
        refreshCacheStats();
      }
    } catch (err) {
      error('Failed to clear cache:', err);
    }
  }

  async function refreshLogs() {
    try {
      const result = await postNUI('getSystemLogs');
      if (result && result.success) {
        renderSystemLogs(result.data || []);
      }
    } catch (err) {
      error('Failed to load logs:', err);
    }
  }

  function renderSystemLogs(logs) {
    const container = $('#system-logs-table');
    if (!container) return;

    if (!logs || logs.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhum log encontrado</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Data/Hora</th>
          <th>Categoria</th>
          <th>Mensagem</th>
        </tr>
      </thead>
      <tbody>
        ${logs.map(log => `
          <tr>
            <td>${log.timestamp || '--'}</td>
            <td><span class="badge badge-${log.level === 'error' ? 'danger' : log.level === 'warning' ? 'warning' : 'info'}">${log.category || 'System'}</span></td>
            <td>${log.message || ''}</td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  // ===== MODAL FUNCTIONS =====
  function closeModal(event) {
    if (event.target.classList.contains('modal-overlay')) {
      event.target.classList.remove('active');
    }
  }

  // ===== REFRESH =====
  async function refreshAdminData() {
    loadTabData(State.currentTab);
  }

  // ===== MESSAGE HANDLER =====
  window.addEventListener('message', (event) => {
    const data = event.data;

    switch (data.action) {
      case 'open':
        openStaffPanel();
        break;
      case 'close':
        closeStaffPanel();
        break;
      case 'updateData':
        if (data.dataType && data.data) {
          handleDataUpdate(data.dataType, data.data);
        }
        break;
    }
  });

  function handleDataUpdate(type, data) {
    switch (type) {
      case 'overview':
        updateOverviewUI(data);
        break;
      case 'economy':
        updateEconomyUI(data);
        break;
    }
  }

  // ===== KEYBOARD HANDLER =====
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      closeStaffPanel();
    }
  });

  // ===== EXPOSE GLOBAL FUNCTIONS =====
  window.closeStaffPanel = closeStaffPanel;
  window.switchTab = switchTab;
  window.refreshAdminData = refreshAdminData;
  window.depositTreasury = depositTreasury;
  window.withdrawTreasury = withdrawTreasury;
  window.forceWageAdjustment = forceWageAdjustment;
  window.triggerCOPOM = triggerCOPOM;
  window.generateReport = generateReport;
  window.openEventManager = openEventManager;
  window.showLaborMarketReport = showLaborMarketReport;
  window.adjustSELIC = adjustSELIC;
  window.forceCOPOM = forceCOPOM;
  window.adjustIPC = adjustIPC;
  window.createOrgAdmin = createOrgAdmin;
  window.refreshOrganizations = refreshOrganizations;
  window.listCompanyOnStock = listCompanyOnStock;
  window.adjustStockPrice = adjustStockPrice;
  window.triggerEvent = triggerEvent;
  window.setEventOutcome = setEventOutcome;
  window.loadEventHistory = loadEventHistory;
  window.getEconomyReport = getEconomyReport;
  window.getPoliticalReport = getPoliticalReport;
  window.getLaborReport = getLaborReport;
  window.refreshCacheStats = refreshCacheStats;
  window.warmupCache = warmupCache;
  window.clearCache = clearCache;
  window.refreshLogs = refreshLogs;
  window.closeModal = closeModal;

  log('Staff Panel initialized');
})();
