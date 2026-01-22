/**
 * ==========================================================
 * Space Economy v5.0 - Modern UI Controller
 * Author: Space Economy Team
 * Description: Complete client-side controller with modern architecture
 * ==========================================================
 */

(() => {
  'use strict';

  // ===========================
  // CONFIGURATION & CONSTANTS
  // ===========================
  const RESOURCE_NAME = (typeof GetParentResourceName === 'function' && GetParentResourceName()) || 'space_economy';
  const DEBUG = false;

  const log = (...args) => DEBUG && console.log('[SpaceEco]', ...args);
  const error = (...args) => console.error('[SpaceEco Error]', ...args);

  // ===========================
  // UTILITY FUNCTIONS
  // ===========================
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  const formatMoney = (value) => {
    const num = Number(value);
    return Number.isFinite(num) ? `$${Math.floor(num).toLocaleString('pt-BR')}` : '$0';
  };

  const formatDecimal = (value, decimals = 2) => {
    const num = Number(value);
    return Number.isFinite(num) ? num.toFixed(decimals) : (0).toFixed(decimals);
  };

  const parsePositiveInt = (value) => {
    const str = String(value ?? '').replace(/[^\d]/g, '');
    const num = Number(str);
    return Number.isFinite(num) && Math.floor(num) > 0 ? Math.floor(num) : null;
  };

  const parseNumber = (value) => {
    const num = Number(String(value ?? '').replace(',', '.'));
    return Number.isFinite(num) ? num : null;
  };

  const setElementText = (element, text) => {
    if (element) element.textContent = String(text ?? '');
  };

  const deepClone = (obj) => {
    try {
      return JSON.parse(JSON.stringify(obj));
    } catch {
      return obj;
    }
  };

  const setByPath = (obj, path, value) => {
    if (!obj || !path) return;
    const parts = String(path).split('.').filter(Boolean);
    let current = obj;
    for (let i = 0; i < parts.length; i++) {
      const key = parts[i];
      if (i === parts.length - 1) {
        current[key] = value;
        return;
      }
      if (!current[key] || typeof current[key] !== 'object') {
        current[key] = {};
      }
      current = current[key];
    }
  };

  const getByPath = (obj, path) => {
    if (!obj || !path) return undefined;
    const parts = String(path).split('.').filter(Boolean);
    let current = obj;
    for (const key of parts) {
      if (!current || typeof current !== 'object') return undefined;
      current = current[key];
    }
    return current;
  };

  // ===========================
  // NUI COMMUNICATION
  // ===========================
  const postNUI = (event, data = {}, retries = 2) => {
    log('POST:', event, data);
    return fetch(`https://${RESOURCE_NAME}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    })
    .then(resp => resp.json())
    .catch((err) => {
      error('POST failed:', event, err);
      if (retries > 0) {
        log(`Retrying ${event}... (${retries} attempts left)`);
        return new Promise(resolve =>
          setTimeout(() => resolve(postNUI(event, data, retries - 1)), 500)
        );
      }
      // Notificar erro ao usuário
      Notification.show('Erro de comunicação com o servidor. Tente novamente.', 'error');
      UI.setBusy(false);
      LoadingIndicator.hide();
      throw err;
    });
  };

  // ===========================
  // STATE MANAGEMENT
  // ===========================
  const State = {
    uiOpen: false,
    currentView: 'overview',
    adminDraft: null,
    taxCatalog: [],
    isDirty: false,
    busy: false,
    payment: { amount: 0, reason: '' },
    inputModal: { callback: null, type: 'text' },
    pendingRequests: 0,
    players: [],
    dashboard: {
      charts: {},
    },
  };

  // ===========================
  // LOADING INDICATOR
  // ===========================
  const LoadingIndicator = {
    timeoutId: null,

    show(message = 'Processando...') {
      State.pendingRequests++;
      const indicator = $('#loading-overlay') || this.create();
      const msgEl = indicator.querySelector('.loading-message');
      if (msgEl) msgEl.textContent = message;
      indicator.style.display = 'flex';

      // Safety timeout: auto-hide after 30 seconds
      if (this.timeoutId) clearTimeout(this.timeoutId);
      this.timeoutId = setTimeout(() => {
        console.warn('[LoadingIndicator] Timeout reached - forcing hide');
        this.forceHide();
      }, 30000);
    },

    hide() {
      State.pendingRequests = Math.max(0, State.pendingRequests - 1);
      if (State.pendingRequests === 0) {
        if (this.timeoutId) {
          clearTimeout(this.timeoutId);
          this.timeoutId = null;
        }
        const indicator = $('#loading-overlay');
        if (indicator) indicator.style.display = 'none';
      }
    },

    forceHide() {
      if (this.timeoutId) {
        clearTimeout(this.timeoutId);
        this.timeoutId = null;
      }
      State.pendingRequests = 0;
      UI.setBusy(false);
      const indicator = $('#loading-overlay');
      if (indicator) indicator.style.display = 'none';
      Notification.show('Operação expirou. Tente novamente.', 'error');
    },

    create() {
      const overlay = document.createElement('div');
      overlay.id = 'loading-overlay';
      overlay.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0, 0, 0, 0.7);
        display: none;
        align-items: center;
        justify-content: center;
        z-index: 10000;
      `;

      overlay.innerHTML = `
        <div style="background: #1e1e2e; padding: 2rem; border-radius: 12px; text-align: center; min-width: 300px;">
          <div style="width: 48px; height: 48px; border: 4px solid #3b82f6; border-top-color: transparent; border-radius: 50%; margin: 0 auto 1rem; animation: spin 1s linear infinite;"></div>
          <div class="loading-message" style="color: #fff; font-size: 1rem;">Processando...</div>
        </div>
      `;

      document.body.appendChild(overlay);

      // Add animation
      if (!$('#loading-animation-style')) {
        const style = document.createElement('style');
        style.id = 'loading-animation-style';
        style.textContent = '@keyframes spin { to { transform: rotate(360deg); } }';
        document.head.appendChild(style);
      }

      return overlay;
    },
  };

  // ===========================
  // NOTIFICATION SYSTEM
  // ===========================
  const Notification = {
    show(message, type = 'info', duration = 4000) {
      const notification = this.create(message, type);
      document.body.appendChild(notification);

      requestAnimationFrame(() => {
        notification.style.transform = 'translateX(0)';
        notification.style.opacity = '1';
      });

      setTimeout(() => {
        notification.style.transform = 'translateX(400px)';
        notification.style.opacity = '0';
        setTimeout(() => notification.remove(), 300);
      }, duration);
    },

    create(message, type) {
      const colors = {
        success: { bg: '#10b981', icon: '✓' },
        error: { bg: '#ef4444', icon: '✕' },
        warning: { bg: '#f59e0b', icon: '⚠' },
        info: { bg: '#3b82f6', icon: 'ℹ' },
      };

      const config = colors[type] || colors.info;

      const notification = document.createElement('div');
      notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: ${config.bg};
        color: white;
        padding: 1rem 1.5rem;
        border-radius: 8px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        display: flex;
        align-items: center;
        gap: 0.75rem;
        max-width: 400px;
        z-index: 10001;
        transform: translateX(400px);
        opacity: 0;
        transition: all 0.3s ease;
        font-size: 0.95rem;
      `;

      notification.innerHTML = `
        <span style="font-size: 1.25rem; font-weight: bold;">${config.icon}</span>
        <span>${message}</span>
      `;

      return notification;
    },
  };

  // ===========================
  // PLAYER DIRECTORY SELECTOR
  // ===========================
  const PlayerDirectory = {
    selects: [],
    players: [],

    init() {
      this.selects = [];
      $$('.player-select').forEach((wrapper) => {
        const searchInput = wrapper.querySelector('.player-select-search');
        const listEl = wrapper.querySelector('.player-select-list');
        const hiddenInput = wrapper.querySelector('input[type="hidden"]');

        if (!searchInput || !listEl || !hiddenInput) return;

        const select = {
          wrapper,
          searchInput,
          listEl,
          hiddenInput,
          selected: null,
        };

        searchInput.addEventListener('input', () => {
          this.syncSelection(select);
          this.renderList(select);
        });
        searchInput.addEventListener('focus', () => this.renderList(select));

        listEl.addEventListener('click', (event) => {
          const button = event.target.closest('button[data-citizenid]');
          if (!button) return;
          const citizenid = button.dataset.citizenid;
          const label = button.dataset.label || citizenid;
          select.selected = citizenid;
          hiddenInput.value = citizenid;
          searchInput.value = label;
          this.renderList(select);
        });

        this.selects.push(select);
      });

      this.renderAll();
    },

    setPlayers(players = []) {
      const cleaned = Array.isArray(players) ? players : [];
      this.players = cleaned
        .map((p) => ({
          citizenid: String(p.citizenid || '').trim(),
          name: String(p.name || 'Desconhecido').trim(),
        }))
        .filter((p) => p.citizenid)
        .sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'));

      this.renderAll();
    },

    syncSelection(select) {
      const query = String(select.searchInput.value || '').trim();
      if (!query) {
        select.selected = null;
        select.hiddenInput.value = '';
        return;
      }

      const exact = this.players.find((p) => p.citizenid.toLowerCase() === query.toLowerCase());
      if (exact) {
        select.selected = exact.citizenid;
        select.hiddenInput.value = exact.citizenid;
      } else if (select.selected && select.searchInput.value !== this.getLabel(select.selected)) {
        select.selected = null;
        select.hiddenInput.value = '';
      }
    },

    getLabel(citizenid) {
      const entry = this.players.find((p) => p.citizenid === citizenid);
      if (!entry) return citizenid;
      return `${entry.name} • ${entry.citizenid}`;
    },

    renderList(select) {
      const query = String(select.searchInput.value || '').trim().toLowerCase();
      const list = select.listEl;
      const items = query
        ? this.players.filter((p) => {
          const label = `${p.name} ${p.citizenid}`.toLowerCase();
          return label.includes(query);
        })
        : this.players;

      if (!items.length) {
        list.innerHTML = '<div class="player-select-empty">Nenhum jogador encontrado</div>';
        return;
      }

      list.innerHTML = items.map((p) => {
        const label = `${p.name} • ${p.citizenid}`;
        const selected = select.selected === p.citizenid ? 'is-selected' : '';
        return `
          <button type="button" class="player-select-item ${selected}" data-citizenid="${p.citizenid}" data-label="${label}">
            <span class="player-select-name">${p.name}</span>
            <span class="player-select-id">${p.citizenid}</span>
          </button>
        `;
      }).join('');
    },

    renderAll() {
      this.selects.forEach((select) => this.renderList(select));
    },
  };

  // ===========================
  // UI CONTROLLER
  // ===========================
  const UI = {
    show(visible) {
      const body = document.body;
      const overlay = $('.overlay');

      if (visible) {
        body.style.display = 'block';
        requestAnimationFrame(() => {
          if (overlay) overlay.classList.add('is-active');
        });
      } else {
        if (overlay) overlay.classList.remove('is-active');
        setTimeout(() => {
          body.style.display = 'none';
        }, 300);
      }

      State.uiOpen = visible;
    },

    hideAllCards() {
      $$('.card').forEach((card) => (card.style.display = 'none'));
    },

    showCard(cardId, displayType = 'flex') {
      this.hideAllCards();
      const card = $(`#${cardId}`);
      if (!card) return error('Card not found:', cardId);

      card.style.display = displayType;
      this.show(true);

      // Auto-focus first input
      setTimeout(() => {
        const input = card.querySelector('.form-input, .form-select');
        if (input && !input.disabled) input.focus();
      }, 100);
    },

    close() {
      this.show(false);
      this.hideAllCards();
      postNUI('forceClose');
    },

    setBusy(busy) {
      State.busy = !!busy;

      $$('[data-action], .btn').forEach((btn) => {
        btn.disabled = State.busy;
        btn.style.opacity = State.busy ? '0.6' : '1';
        btn.style.pointerEvents = State.busy ? 'none' : 'auto';
      });
    },

    setDirty(dirty) {
      State.isDirty = !!dirty;
      const badge = $('#unsaved-badge');
      const saveBtn = $('#save-settings-btn');

      if (badge) badge.classList.toggle('hidden', !State.isDirty);
      if (saveBtn) {
        saveBtn.disabled = !State.isDirty;
        saveBtn.style.opacity = State.isDirty ? '1' : '0.5';
      }
    },

    switchView(viewName) {
      State.currentView = viewName;

      $$('.view').forEach((v) => v.classList.remove('is-active'));
      const view = $(`.view[data-view="${viewName}"]`);
      if (view) view.classList.add('is-active');

      $$('.nav-item').forEach((n) => n.classList.remove('is-active'));
      const navItem = $(`.nav-item[data-view="${viewName}"]`);
      if (navItem) navItem.classList.add('is-active');

      if (viewName === 'admin-dashboard') {
        Dashboard.request();
      }
    },
  };

  // ===========================
  // ADMIN MODULE
  // ===========================
  const Admin = {
    DEFAULT_TAX_CATALOG: [
      { key: 'IPTU', label: 'IPTU', mode: 'base_percent', percent: 0.3 },
      { key: 'IPVA', label: 'IPVA', mode: 'base_percent', percent: 1.5 },
      { key: 'IRPF', label: 'Imposto de Renda', mode: 'base_percent', percent: 2.0 },
      { key: 'ICMS', label: 'ICMS', mode: 'base_percent', percent: 12.0 },
      { key: 'ISS', label: 'ISS', mode: 'base_percent', percent: 2.0 },
      { key: 'ADMIN_FINE', label: 'Multa Administrativa', mode: 'fixed', fixed: 1000 },
      { key: 'GOV_FEE', label: 'Taxa Governamental', mode: 'fixed', fixed: 500 },
      { key: 'OUTRO', label: 'Outro', mode: 'fixed', fixed: 0 },
    ],

    open(payload = {}) {
      UI.showCard('admin-container', 'grid');
      UI.switchView('overview');

      this.applyState(payload);
      this.requestData('admin_state');
    },

    applyState(data = {}) {
      const metrics = data.metrics || {};
      const settings = data.settings || {};

      State.taxCatalog = data.taxCatalog || settings.taxCatalog || this.DEFAULT_TAX_CATALOG;
      State.players = Array.isArray(data.players) ? data.players : [];
      PlayerDirectory.setPlayers(State.players);

      // Update metrics
      setElementText($('#metric-vault'), formatMoney(metrics.vault || 0));
      setElementText($('#metric-inflation'), formatDecimal(metrics.inflation || 1, 2));
      setElementText($('#metric-taxrate'), `${formatDecimal(metrics.taxrate || 0, 1)}%`);
      setElementText($('#metric-today'), formatMoney(metrics.today || 0));

      // Apply settings
      if (!State.isDirty) {
        State.adminDraft = deepClone(settings);
        this.applySettings(settings);
      }

      this.populateTaxSelect();
    },

    applySettings(settings = {}) {
      // Inflation mode
      const inflationMode = String(getByPath(settings, 'mode.inflation') || 'auto').toLowerCase();
      $$('.segmented-btn[data-setting="mode.inflation"]').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.value === inflationMode);
      });

      const inflationInput = $('#manual-inflation');
      if (inflationInput) {
        inflationInput.disabled = inflationMode !== 'manual';
        inflationInput.value = String(getByPath(settings, 'manual.inflation') ?? '');
      }

      // Tax rate mode
      const taxrateMode = String(getByPath(settings, 'mode.taxrate') || 'auto').toLowerCase();
      $$('.segmented-btn[data-setting="mode.taxrate"]').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.value === taxrateMode);
      });

      const taxrateInput = $('#manual-taxrate');
      if (taxrateInput) {
        taxrateInput.disabled = taxrateMode !== 'manual';
        taxrateInput.value = String(getByPath(settings, 'manual.taxrate') ?? '');
      }
    },

    populateTaxSelect() {
      const select = $('#tax-type');
      if (!select) return;

      const catalog = State.taxCatalog;
      const currentValue = select.value;

      select.innerHTML = '';
      catalog.forEach((item) => {
        const option = document.createElement('option');
        option.value = item.key;
        option.textContent = item.label;
        select.appendChild(option);
      });

      if (currentValue && catalog.some((x) => x.key === currentValue)) {
        select.value = currentValue;
      } else {
        select.value = catalog[0]?.key || 'OUTRO';
      }
    },

    calculateTaxPreview() {
      const taxKey = $('#tax-type')?.value;
      const baseValue = parsePositiveInt($('#tax-base')?.value);

      const taxType = State.taxCatalog.find((x) => x.key === taxKey);
      const preview = $('#tax-preview');
      const previewText = $('#tax-preview-text');

      if (!taxType || !baseValue) {
        if (preview) preview.classList.add('hidden');
        return;
      }

      let amount = 0;
      let text = '';

      if (taxType.mode === 'base_percent') {
        const percent = Number(taxType.percent || 0);
        amount = Math.floor(baseValue * (percent / 100));
        text = `Base ${formatMoney(baseValue)} × ${formatDecimal(percent, 2)}% = ${formatMoney(amount)}`;
      } else {
        amount = Math.floor(Number(taxType.fixed || 0));
        text = `Valor fixo = ${formatMoney(amount)}`;
      }

      const amountInput = $('#tax-amount');
      if (amountInput) amountInput.value = String(amount);

      const reasonInput = $('#tax-reason');
      if (reasonInput && !reasonInput.value) reasonInput.value = taxType.label;

      if (preview && previewText) {
        previewText.textContent = text;
        preview.classList.remove('hidden');
      }
    },

    submitTax() {
      if (State.busy) return;

      const targetMode = $('#tax-target-mode')?.value || 'citizenid';
      const citizenid = String($('#tax-citizenid')?.value || '').trim();
      const type = $('#tax-type')?.value || 'OUTRO';
      const base = parsePositiveInt($('#tax-base')?.value);
      const amount = parsePositiveInt($('#tax-amount')?.value);
      const reason = String($('#tax-reason')?.value || '').trim();

      // Validations
      if (!amount || amount <= 0) {
        Notification.show('Valor inválido', 'error');
        return;
      }
      if (targetMode === 'citizenid' && !citizenid) {
        Notification.show('Informe o CitizenID', 'error');
        return;
      }
      if (!reason || reason.length < 3) {
        Notification.show('Informe um motivo válido (mín. 3 caracteres)', 'error');
        return;
      }

      UI.setBusy(true);
      LoadingIndicator.show('Lançando tributo...');

      postNUI('admin_requestData', {
        dataType: 'admin_issueTaxDebt',
        payload: { targetMode, citizenid, type, base, amount, reason },
      })
      .then(() => {
        // Clear form after successful submission
        ['#tax-base', '#tax-amount', '#tax-reason'].forEach((selector) => {
          const input = $(selector);
          if (input) input.value = '';
        });
        const preview = $('#tax-preview');
        if (preview) preview.classList.add('hidden');

        UI.setBusy(false);
        LoadingIndicator.hide();
        Notification.show('Tributo lançado com sucesso!', 'success');
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    saveSettings() {
      if (!State.adminDraft || State.busy) return;

      UI.setBusy(true);
      LoadingIndicator.show('Salvando configurações...');

      postNUI('admin_requestData', {
        dataType: 'admin_saveSettings',
        payload: State.adminDraft,
      })
      .then(() => {
        UI.setDirty(false);
        UI.setBusy(false);
        LoadingIndicator.hide();
        Notification.show('Configurações salvas com sucesso!', 'success');
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    requestData(dataType, payload = null) {
      if (State.busy) return;
      UI.setBusy(true);
      LoadingIndicator.show('Carregando dados...');
      postNUI('admin_requestData', { dataType, payload })
      .then(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },
  };

  // ===========================
  // DASHBOARD MODULE
  // ===========================
  const Dashboard = {
    ensureCharts() {
      if (typeof Chart === 'undefined') {
        Notification.show('Chart.js não carregado.', 'error');
        return;
      }

      const lineCanvas = $('#chart-pib-inflation');
      if (lineCanvas && !State.dashboard.charts.timeline) {
        State.dashboard.charts.timeline = new Chart(lineCanvas, {
          type: 'line',
          data: {
            labels: [],
            datasets: [
              {
                label: 'PIB',
                data: [],
                borderColor: '#3b82f6',
                backgroundColor: 'rgba(59, 130, 246, 0.15)',
                tension: 0.35,
                fill: true,
                yAxisID: 'y',
              },
              {
                label: 'Inflação (%)',
                data: [],
                borderColor: '#f59e0b',
                backgroundColor: 'rgba(245, 158, 11, 0.15)',
                tension: 0.35,
                fill: true,
                yAxisID: 'y1',
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
              y: {
                beginAtZero: true,
                ticks: { color: '#9ca3af' },
                grid: { color: 'rgba(255,255,255,0.05)' },
              },
              y1: {
                beginAtZero: true,
                position: 'right',
                ticks: { color: '#9ca3af' },
                grid: { display: false },
              },
              x: {
                ticks: { color: '#9ca3af' },
                grid: { color: 'rgba(255,255,255,0.05)' },
              },
            },
            plugins: {
              legend: { labels: { color: '#e5e7eb' } },
            },
          },
        });
      }

      const revenueCanvas = $('#chart-revenue');
      if (revenueCanvas && !State.dashboard.charts.revenue) {
        State.dashboard.charts.revenue = new Chart(revenueCanvas, {
          type: 'doughnut',
          data: {
            labels: [],
            datasets: [
              {
                data: [],
                backgroundColor: ['#3b82f6', '#10b981', '#ef4444', '#f59e0b', '#6b7280'],
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { position: 'bottom', labels: { color: '#e5e7eb' } },
            },
          },
        });
      }

      const sectorsCanvas = $('#chart-sectors');
      if (sectorsCanvas && !State.dashboard.charts.sectors) {
        State.dashboard.charts.sectors = new Chart(sectorsCanvas, {
          type: 'bar',
          data: {
            labels: [],
            datasets: [
              {
                label: 'Volume',
                data: [],
                backgroundColor: 'rgba(16, 185, 129, 0.7)',
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
              y: {
                beginAtZero: true,
                ticks: { color: '#9ca3af' },
                grid: { color: 'rgba(255,255,255,0.05)' },
              },
              x: {
                ticks: { color: '#9ca3af' },
                grid: { color: 'rgba(255,255,255,0.05)' },
              },
            },
            plugins: {
              legend: { labels: { color: '#e5e7eb' } },
            },
          },
        });
      }
    },

    update(payload = {}) {
      this.ensureCharts();

      const timeline = payload.timeline || {};
      const revenue = payload.revenue || {};
      const sectors = payload.sectors || {};

      const timelineChart = State.dashboard.charts.timeline;
      if (timelineChart) {
        timelineChart.data.labels = timeline.labels || [];
        timelineChart.data.datasets[0].data = timeline.pib || [];
        timelineChart.data.datasets[1].data = timeline.inflation || [];
        timelineChart.update();
      }

      const revenueChart = State.dashboard.charts.revenue;
      if (revenueChart) {
        revenueChart.data.labels = revenue.labels || [];
        revenueChart.data.datasets[0].data = revenue.values || [];
        revenueChart.update();
      }

      const sectorsChart = State.dashboard.charts.sectors;
      if (sectorsChart) {
        sectorsChart.data.labels = sectors.labels || [];
        sectorsChart.data.datasets[0].data = sectors.values || [];
        sectorsChart.update();
      }
    },

    request() {
      Admin.requestData('admin_dashboard');
    },
  };

  // ===========================
  // LOANS MODULE
  // ===========================
  const Loans = {
    simulateLoan() {
      const citizenid = String($('#loan-citizenid')?.value || '').trim();
      const amount = parsePositiveInt($('#loan-amount')?.value);
      const installments = parsePositiveInt($('#loan-installments')?.value);

      const resultContainer = $('#loan-simulation-result');
      const detailsContainer = $('#loan-sim-details');

      if (!citizenid || !amount || !installments) {
        if (resultContainer) resultContainer.classList.add('hidden');
        return alert('Preencha todos os campos');
      }

      UI.setBusy(true);
      LoadingIndicator.show('Simulando empréstimo...');
      postNUI('admin_requestData', {
        dataType: 'loan_simulation_admin',
        payload: {
          citizenid,
          amount,
          installments
        }
      })
      .then(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    renderSimulation(simulation = null) {
      const resultContainer = $('#loan-simulation-result');
      const detailsContainer = $('#loan-sim-details');

      if (!resultContainer || !detailsContainer || !simulation) {
        if (resultContainer) resultContainer.classList.add('hidden');
        return;
      }

      const termMonths = Number(simulation.termMonths || 0);
      const approvalLabel = simulation.approved ? '✅ Pré-aprovado' : '⚠️ Avaliação pendente';

      detailsContainer.innerHTML = `
        <div class="info-item">
          <span class="info-label">Valor Solicitado</span>
          <span class="money">${formatMoney(simulation.amount || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Taxa de Juros (${formatDecimal(simulation.interestRatePercent || 0, 1)}% a.m.)</span>
          <span class="money">${formatMoney(simulation.totalInterest || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Tarifa de abertura</span>
          <span class="money">${formatMoney(simulation.originationFee || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Valor liberado</span>
          <span class="money">${formatMoney(simulation.disbursedAmount || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Total a Pagar</span>
          <span class="money">${formatMoney(simulation.totalPayment || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Parcela Mensal</span>
          <span class="info-value">${formatMoney(simulation.monthlyPayment || 0)} × ${termMonths} meses</span>
        </div>
        <div class="info-item">
          <span class="info-label">Score Patrimonial</span>
          <span class="info-value">${simulation.assetScore || 0} (${formatMoney(simulation.assetValue || 0)})</span>
        </div>
        <div class="info-item">
          <span class="info-label">Score Final</span>
          <span class="info-value">${simulation.effectiveScore || 0} (${simulation.effectiveRating || '—'})</span>
        </div>
        <div class="info-item">
          <span class="info-label">Status</span>
          <span class="info-value">${approvalLabel}</span>
        </div>
      `;

      resultContainer.classList.remove('hidden');
    },
  };

  // ===========================
  // DEBT MODULE
  // ===========================
  const Debts = {
    showList(debts = []) {
      const tbody = $('#debt-list-tbody');
      if (!tbody) return;

      if (!Array.isArray(debts) || debts.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">Nenhuma dívida encontrada</td></tr>';
      } else {
        tbody.innerHTML = debts.map((d) => `
          <tr>
            <td>${String(d.playerName || 'Desconhecido')}</td>
            <td>${String(d.citizenid || '-')}</td>
            <td>${formatMoney(d.amount || 0)}</td>
            <td>${String(d.reason || '-')}</td>
          </tr>
        `).join('');
      }

      UI.showCard('debt-list-modal');
    },

    showDetail(debt = {}) {
      setElementText($('#debt-detail-name'), debt.playerName || 'Desconhecido');
      setElementText($('#debt-detail-citizenid'), debt.citizenid || '-');
      setElementText($('#debt-detail-amount'), formatMoney(debt.amount || 0));
      setElementText($('#debt-detail-reason'), debt.reason || '-');

      UI.showCard('debt-detail-modal');
    },
  };

  // ===========================
  // INPUT MODAL HELPER
  // ===========================
  const InputModal = {
    show(title, label, placeholder, callback, inputType = 'text') {
      setElementText($('#input-modal-title'), title);
      setElementText($('#input-modal-label'), label);

      const input = $('#input-modal-field');
      if (input) {
        input.type = inputType;
        input.placeholder = placeholder;
        input.value = '';
      }

      State.inputModal.callback = callback;
      State.inputModal.type = inputType;

      UI.showCard('input-modal');
    },

    confirm() {
      const input = $('#input-modal-field');
      const value = input?.value?.trim() || '';

      if (!value) {
        Notification.show('Preencha o campo', 'error');
        return;
      }

      if (State.inputModal.callback) {
        State.inputModal.callback(value);
      }

      // Não fecha UI aqui - deixa a callback decidir quando fechar
      // ou o loading indicator cuidar disso
    },
  };

  // ===========================
  // LOGS MODULE
  // ===========================
  const Logs = {
    render(logs = []) {
      const tbody = $('#logs-table tbody');
      if (!tbody) return;

      if (!Array.isArray(logs) || logs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" class="text-center text-muted">Nenhum log disponível</td></tr>';
      } else {
        tbody.innerHTML = logs.map((l) => `
          <tr>
            <td>${String(l.timestamp || '-')}</td>
            <td>${String(l.category || '-')}</td>
            <td>${String(l.message || '-')}</td>
          </tr>
        `).join('');
      }
    },
  };

  // ===========================
  // PLAYER TAXES MODULE
  // ===========================
  const PlayerTaxes = {
    currentTaxes: [],

    open(payload = {}) {
      UI.showCard('tax-panel');
      this.requestTaxes();
    },

    requestTaxes() {
      if (State.busy) return;
      UI.setBusy(true);
      LoadingIndicator.show('Carregando impostos...');

      postNUI('admin_requestData', {
        dataType: 'player_taxes',
        payload: {}
      })
      .then(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    render(taxes = []) {
      this.currentTaxes = Array.isArray(taxes) ? taxes : [];
      const tbody = $('#player-tax-tbody');
      const payAllBtn = $('#pay-all-taxes-btn');

      if (!tbody) return;

      // Calculate total
      const totalAmount = this.currentTaxes.reduce((sum, tax) => sum + (Number(tax.amount) || 0), 0);
      const count = this.currentTaxes.length;

      // Update metrics
      setElementText($('#player-tax-total'), formatMoney(totalAmount));
      setElementText($('#player-tax-count'), count);

      // Update pay all button
      if (payAllBtn) {
        payAllBtn.disabled = count === 0 || totalAmount <= 0;
        payAllBtn.textContent = `Pagar Todas (${formatMoney(totalAmount)})`;
      }

      // Render table
      if (count === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">✅ Nenhum imposto pendente</td></tr>';
      } else {
        tbody.innerHTML = this.currentTaxes.map((tax, index) => {
          const dueDate = tax.due_date ? new Date(tax.due_date).toLocaleDateString('pt-BR') : 'Sem vencimento';
          const type = String(tax.type || tax.tax_type || 'Imposto');
          const reason = String(tax.reason || tax.description || '-');
          const amount = Number(tax.amount) || 0;

          return `
            <tr>
              <td><strong>${type}</strong></td>
              <td>${reason}</td>
              <td class="money">${formatMoney(amount)}</td>
              <td>${dueDate}</td>
              <td>
                <button class="btn btn-success btn-sm" data-action="pay-single-tax" data-tax-id="${tax.id || index}" data-tax-amount="${amount}" data-tax-reason="${reason}">
                  Pagar
                </button>
              </td>
            </tr>
          `;
        }).join('');
      }
    },

    renderHistory(history = []) {
      const container = $('#player-tax-history');
      const tbody = $('#player-tax-history-tbody');

      if (!container || !tbody) return;

      container.classList.remove('hidden');

      if (!Array.isArray(history) || history.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">Sem histórico de pagamentos</td></tr>';
      } else {
        tbody.innerHTML = history.map((item) => {
          const date = item.timestamp ? new Date(item.timestamp).toLocaleDateString('pt-BR') : '-';
          const type = String(item.type || item.tax_type || 'Imposto');
          const amount = formatMoney(item.amount || 0);
          const status = item.status === 'paid' ? '✅ Pago' : item.status === 'pending' ? '⏳ Pendente' : '❌ Cancelado';

          return `
            <tr>
              <td>${date}</td>
              <td>${type}</td>
              <td class="money">${amount}</td>
              <td>${status}</td>
            </tr>
          `;
        }).join('');
      }
    },

    paySingleTax(taxId, amount, reason) {
      if (State.busy) return;

      let tax = this.currentTaxes.find(t => String(t.id || t.debt_id) === String(taxId));
      if (!tax && taxId !== undefined) {
        // Try by index if ID not found
        const index = Number(taxId);
        if (index >= 0 && index < this.currentTaxes.length) {
          tax = this.currentTaxes[index];
        }
      }

      const finalAmount = tax ? Number(tax.amount) : Number(amount);
      const finalReason = tax ? String(tax.reason || tax.description || reason) : String(reason);
      const finalId = tax ? (tax.id || tax.debt_id) : taxId;

      if (!finalAmount || finalAmount <= 0) {
        Notification.show('Valor inválido', 'error');
        return;
      }

      UI.setBusy(true);
      LoadingIndicator.show('Processando pagamento...');

      postNUI('admin_requestData', {
        dataType: 'player_payTax',
        payload: {
          tax_id: finalId,
          amount: finalAmount,
          reason: finalReason
        }
      })
      .then(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },

    payAllTaxes() {
      if (State.busy || this.currentTaxes.length === 0) return;

      const totalAmount = this.currentTaxes.reduce((sum, tax) => sum + (Number(tax.amount) || 0), 0);

      if (totalAmount <= 0) {
        Notification.show('Nenhum imposto para pagar', 'info');
        return;
      }

      if (!confirm(`Deseja pagar todos os impostos no valor de ${formatMoney(totalAmount)}?`)) {
        return;
      }

      UI.setBusy(true);
      LoadingIndicator.show('Processando pagamento de todos os impostos...');

      postNUI('admin_requestData', {
        dataType: 'player_payAllTaxes',
        payload: {
          taxes: this.currentTaxes.map(t => ({
            id: t.id || t.debt_id,
            amount: Number(t.amount) || 0,
            reason: t.reason || t.description || 'Imposto'
          }))
        }
      })
      .then(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },
  };

  // ===========================
  // PLAYER LOANS MODULE
  // ===========================
  const PlayerLoans = {
    lastSimulation: null,
    simulationTimeout: null,

    simulate() {
      const amount = parsePositiveInt($('#player-loan-amount')?.value);
      const installments = parsePositiveInt($('#player-loan-installments')?.value);
      const purpose = String($('#player-loan-purpose')?.value || '').trim();

      if (!amount || !installments) {
        Notification.show('Informe o valor e as parcelas', 'error');
        return;
      }

      LoadingIndicator.show('Simulando empréstimo...');
      postNUI('simulateLoan', {
        amount,
        installments,
        purpose,
      })
      .catch(() => {
        LoadingIndicator.hide();
      });

      if (this.simulationTimeout) clearTimeout(this.simulationTimeout);
      this.simulationTimeout = setTimeout(() => {
        LoadingIndicator.hide();
      }, 5000);
    },

    request() {
      const amount = parsePositiveInt($('#player-loan-amount')?.value);
      const installments = parsePositiveInt($('#player-loan-installments')?.value);
      const purpose = String($('#player-loan-purpose')?.value || '').trim();

      if (!amount || !installments) {
        Notification.show('Informe o valor e as parcelas', 'error');
        return;
      }

      LoadingIndicator.show('Enviando solicitação...');
      postNUI('requestLoan', {
        amount,
        installments,
        purpose,
      })
      .then(() => {
        setTimeout(() => {
          LoadingIndicator.hide();
        }, 1200);
      })
      .catch(() => {
        LoadingIndicator.hide();
      });
    },

    renderSimulation(simulation = null) {
      const resultContainer = $('#player-loan-simulation-result');
      const detailsContainer = $('#player-loan-sim-details');

      if (!resultContainer || !detailsContainer || !simulation) {
        if (resultContainer) resultContainer.classList.add('hidden');
        LoadingIndicator.hide();
        return;
      }

      this.lastSimulation = simulation;
      if (this.simulationTimeout) clearTimeout(this.simulationTimeout);

      const termMonths = Number(simulation.termMonths || 0);
      const approvalLabel = simulation.approved ? '✅ Pré-aprovado' : '⚠️ Avaliação pendente';

      detailsContainer.innerHTML = `
        <div class="info-item">
          <span class="info-label">Valor Solicitado</span>
          <span class="money">${formatMoney(simulation.amount || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Taxa de Juros (${formatDecimal(simulation.interestRatePercent || 0, 1)}% a.m.)</span>
          <span class="money">${formatMoney(simulation.totalInterest || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Tarifa de abertura</span>
          <span class="money">${formatMoney(simulation.originationFee || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Valor liberado</span>
          <span class="money">${formatMoney(simulation.disbursedAmount || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Total a pagar</span>
          <span class="money">${formatMoney(simulation.totalPayment || 0)}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Parcela mensal</span>
          <span class="info-value">${formatMoney(simulation.monthlyPayment || 0)} × ${termMonths} meses</span>
        </div>
        <div class="info-item">
          <span class="info-label">Score de crédito</span>
          <span class="info-value">${simulation.creditScore || 0} (${simulation.rating || '—'})</span>
        </div>
        <div class="info-item">
          <span class="info-label">Score Patrimonial</span>
          <span class="info-value">${simulation.assetScore || 0} (${formatMoney(simulation.assetValue || 0)})</span>
        </div>
        <div class="info-item">
          <span class="info-label">Score Final</span>
          <span class="info-value">${simulation.effectiveScore || 0} (${simulation.effectiveRating || '—'})</span>
        </div>
        <div class="info-item">
          <span class="info-label">Status</span>
          <span class="info-value">${approvalLabel}</span>
        </div>
      `;

      resultContainer.classList.remove('hidden');
      LoadingIndicator.hide();
    },

    handleApproval(loanId, simulation) {
      LoadingIndicator.hide();
      if (loanId) {
        Notification.show(`Empréstimo aprovado (#${loanId})`, 'success');
      }
      if (simulation) {
        this.renderSimulation(simulation);
      }
    },
  };

  // ===========================
  // ACTION ROUTER
  // ===========================
  const Actions = {
    // Admin actions
    'refresh-admin'() { Admin.requestData('admin_state'); },
    'refresh-dashboard'() { Dashboard.request(); },
    'reset-settings'() {
      if (confirm('Restaurar configurações padrão?')) {
        UI.setDirty(true);
        State.adminDraft = {};
        Admin.applySettings({});
      }
    },

    // Tax actions
    'calc-tax'() { Admin.calculateTaxPreview(); },
    'submit-tax'() { Admin.submitTax(); },

    // Treasury quick actions
    'quick-vault'() { Admin.requestData('viewVault'); },
    'quick-deposit'() {
      InputModal.show('Depositar no Tesouro', 'Valor', 'Digite o valor', (value) => {
        const amount = parsePositiveInt(value);
        if (amount) {
          LoadingIndicator.show('Processando depósito...');
          Admin.requestData('addVault', { amount, debitPlayer: false });
        } else {
          Notification.show('Valor inválido', 'error');
        }
      }, 'number');
    },
    'quick-withdraw'() {
      InputModal.show('Sacar do Tesouro', 'Valor', 'Digite o valor', (value) => {
        const amount = parsePositiveInt(value);
        if (amount) {
          LoadingIndicator.show('Processando saque...');
          Admin.requestData('withdrawVault', { amount });
        } else {
          Notification.show('Valor inválido', 'error');
        }
      }, 'number');
    },
    'quick-debts'() { Admin.requestData('debts_active'); },

    // Debt actions
    'refresh-debts'() { Admin.requestData('debts_stats'); },
    'list-all-debts'() { Admin.requestData('debts_active'); },
    'search-debt'() {
      const citizenid = String($('#debt-search-citizenid')?.value || '').trim();
      if (!citizenid) return alert('Informe o CitizenID');
      Admin.requestData('specific_debt', citizenid);
    },

    // Loan actions
    'refresh-loans'() { Admin.requestData('loans_stats'); },
    'list-all-loans'() { Admin.requestData('loans_list'); },
    'simulate-loan'() { Loans.simulateLoan(); },

    // Installment actions
    'refresh-installments'() { Admin.requestData('installments_stats'); },
    'list-all-installments'() { Admin.requestData('installments_list'); },
    'search-installment'() {
      const citizenid = String($('#installment-search-citizenid')?.value || '').trim();
      if (!citizenid) return alert('Informe o CitizenID');
      Admin.requestData('search_installment', { citizenid });
    },

    // Treasury actions
    'treasury-deposit'() { this['quick-deposit'](); },
    'treasury-withdraw'() { this['quick-withdraw'](); },

    // Logs
    'refresh-logs'() { Admin.requestData('admin_logs', { limit: 100 }); },

    // COPOM quick actions
    'copom-raise'() { Admin.requestData('admin_copom_action', { action: 'raise' }); },
    'copom-hold'() { Admin.requestData('admin_copom_action', { action: 'hold' }); },
    'copom-lower'() { Admin.requestData('admin_copom_action', { action: 'lower' }); },

    // Player Taxes actions
    'refresh-player-taxes'() { PlayerTaxes.requestTaxes(); },
    'load-player-tax-history'() {
      Admin.requestData('player_tax_history', {});
    },
    'pay-all-taxes'() { PlayerTaxes.payAllTaxes(); },
    'player-simulate-loan'() { PlayerLoans.simulate(); },
    'player-request-loan'() { PlayerLoans.request(); },

    // Payment modal
    'confirm-payment'() {
      if (State.busy) return;
      UI.setBusy(true);
      LoadingIndicator.show('Processando pagamento...');
      postNUI('payTax', { tax: State.payment.amount, reason: State.payment.reason })
      .then(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
        Notification.show('Pagamento realizado com sucesso!', 'success');
        UI.close();
      })
      .catch(() => {
        UI.setBusy(false);
        LoadingIndicator.hide();
      });
    },
    'refuse-payment'() {
      postNUI('refuseTax', { tax: State.payment.amount, reason: State.payment.reason });
      Notification.show('Pagamento recusado', 'info');
      UI.close();
    },
  };

  // ===========================
  // EVENT LISTENERS
  // ===========================
  function initEventListeners() {
    // Global close buttons
    $$('[data-close]').forEach((btn) => {
      btn.addEventListener('click', () => UI.close());
    });

    // Navigation
    $$('.nav-item[data-view]').forEach((btn) => {
      btn.addEventListener('click', () => UI.switchView(btn.dataset.view));
    });

    // Action buttons
    document.addEventListener('click', (e) => {
      const actionBtn = e.target.closest('[data-action]');
      if (actionBtn) {
        const action = actionBtn.dataset.action;

        // Handle pay-single-tax specially (needs parameters)
        if (action === 'pay-single-tax') {
          const taxId = actionBtn.dataset.taxId;
          const amount = actionBtn.dataset.taxAmount;
          const reason = actionBtn.dataset.taxReason;
          PlayerTaxes.paySingleTax(taxId, amount, reason);
          return;
        }

        if (Actions[action]) {
          log('Action:', action);
          Actions[action]();
        } else {
          error('Unknown action:', action);
        }
      }

      // Dashboard cards
      const dashCard = e.target.closest('.dashboard-card[data-action]');
      if (dashCard) {
        const action = dashCard.dataset.action;
        if (Actions[action]) Actions[action]();
      }

      // Tax chips
      const chip = e.target.closest('.chip[data-tax]');
      if (chip) {
        $$('.chip').forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
        const select = $('#tax-type');
        if (select) select.value = chip.dataset.tax;
        Admin.calculateTaxPreview();
      }

      // Segmented control
      const segBtn = e.target.closest('.segmented-btn[data-setting]');
      if (segBtn && State.adminDraft) {
        const setting = segBtn.dataset.setting;
        const value = segBtn.dataset.value;

        setByPath(State.adminDraft, setting, value);
        Admin.applySettings(State.adminDraft);
        UI.setDirty(true);
      }
    });

    // Form inputs for settings
    ['#manual-inflation', '#manual-taxrate'].forEach((selector) => {
      const input = $(selector);
      if (input) {
        input.addEventListener('input', (e) => {
          const path = selector.includes('inflation') ? 'manual.inflation' : 'manual.taxrate';
          const value = parseNumber(e.target.value);
          if (State.adminDraft) {
            setByPath(State.adminDraft, path, value);
            UI.setDirty(true);
          }
        });
      }
    });

    // Tax target mode change
    const taxTargetMode = $('#tax-target-mode');
    if (taxTargetMode) {
      taxTargetMode.addEventListener('change', (e) => {
        const group = $('#tax-citizenid-group');
        if (group) {
          group.style.display = e.target.value === 'citizenid' ? 'block' : 'none';
        }
      });
    }

    // Save settings button
    const saveBtn = $('#save-settings-btn');
    if (saveBtn) {
      saveBtn.addEventListener('click', () => Admin.saveSettings());
    }

    // Input modal confirm
    const inputConfirm = $('#input-modal-confirm');
    if (inputConfirm) {
      inputConfirm.addEventListener('click', () => InputModal.confirm());
    }

    // Pay all taxes button
    const payAllBtn = $('#pay-all-taxes-btn');
    if (payAllBtn) {
      payAllBtn.addEventListener('click', () => PlayerTaxes.payAllTaxes());
    }

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && State.uiOpen) {
        UI.close();
      }

      if (e.key === 'Enter' && State.uiOpen) {
        const activeElement = document.activeElement;
        if (activeElement && activeElement.tagName === 'TEXTAREA') return;

        // Find visible card with primary button
        const visibleCard = $$('.card').find((c) => {
          const style = window.getComputedStyle(c);
          return style.display !== 'none';
        });

        if (visibleCard) {
          const primaryBtn = visibleCard.querySelector('.btn-primary:not([disabled])');
          if (primaryBtn) primaryBtn.click();
        }
      }
    });
  }

  // ===========================
  // NUI MESSAGE HANDLER
  // ===========================
  window.addEventListener('message', (event) => {
    const data = event.data || {};
    const action = data.action;

    if (!action) return;
    log('NUI Message:', action, data);

    switch (action) {
      case 'close':
        UI.close();
        break;

      case 'open': {
        postNUI('ready', { ok: true });

        const mode = String(data.mode || '');
        const payload = data.payload || {};

        if (mode === 'admin') {
          Admin.open(payload);
        } else if (mode === 'tax') {
          // Open player tax panel
          PlayerTaxes.open(payload);
        } else if (mode === 'payment') {
          State.payment.amount = Number(payload.tax || 0);
          State.payment.reason = String(payload.reason || '—');
          setElementText($('#payment-amount'), formatMoney(State.payment.amount));
          setElementText($('#payment-reason'), State.payment.reason);
          UI.showCard('payment-modal');
        }
        break;
      }

      case 'adminData': {
        const key = data.key;
        const d = data.data;

        // Tratamento de erro do servidor
        if (key === 'error') {
          const errorMsg = (d && d.message) || 'Erro desconhecido';
          Notification.show(errorMsg, 'error');
          UI.setBusy(false);
          LoadingIndicator.hide();
          break;
        }

        if (key === 'admin_state') {
          Admin.applyState(d || {});
        } else if (key === 'admin_dashboard') {
          Dashboard.update((d && d.dashboard) || {});
        } else if (key === 'admin_logs') {
          Logs.render((d && d.logs) || []);
        } else if (key === 'debts_active') {
          Debts.showList(d || []);
        } else if (key === 'specific_debt' || key === 'debt_specific') {
          Debts.showDetail(d || {});
        } else if (key === 'admin_copom_action') {
          const result = d && d.result;
          if (result) {
            Notification.show(`COPOM: ${result.decision} para ${formatDecimal((result.selic || 0) * 100, 2)}%`, 'success');
          }
        } else if (key === 'loans_stats') {
          const stats = d || {};
          setElementText($('#loans-total'), formatMoney(stats.totalActive || 0));
          setElementText($('#loans-avg-rate'), `${formatDecimal(stats.avgRate || 0, 1)}%`);
          setElementText($('#loans-count'), stats.count || 0);
        } else if (key === 'loan_simulation_admin') {
          Loans.renderSimulation((d && d.simulation) || d);
        } else if (key === 'installments_stats') {
          const stats = d || {};
          setElementText($('#installments-total'), formatMoney(stats.totalActive || 0));
          setElementText($('#installments-count'), stats.count || 0);
        } else if (key === 'debts_stats') {
          const stats = d || {};
          setElementText($('#debts-total'), formatMoney(stats.totalActive || 0));
          setElementText($('#debts-count'), stats.count || 0);
        } else if (key === 'player_taxes') {
          PlayerTaxes.render((d && d.taxes) || d || []);
        } else if (key === 'player_tax_history') {
          PlayerTaxes.renderHistory((d && d.history) || d || []);
        } else if (key === 'player_payTax' || key === 'player_payAllTaxes') {
          // Payment successful - notifications already shown
          const message = (d && d.message) || 'Pagamento realizado com sucesso!';
          if (!d || d.success !== false) {
            Notification.show(message, 'success');
            PlayerTaxes.requestTaxes();
          }
        }

        UI.setBusy(false);
        LoadingIndicator.hide();
        break;
      }

      case 'loanSimulation': {
        PlayerLoans.renderSimulation(data.simulation || data.sim || data);
        break;
      }

      case 'loanApproved': {
        PlayerLoans.handleApproval(data.loanId, data.simulation || data.sim);
        break;
      }

      case 'openPlayerPanel': {
        log('Opening Player Panel (v5.0)...');
        // Hide old panels
        const overlay = $('.overlay');
        if (overlay) overlay.setAttribute('aria-hidden', 'true');

        // Show player panel iframe
        const playerFrame = $('#player-panel-frame');
        if (playerFrame) {
          playerFrame.style.display = 'block';
          // Send ready message to iframe
          postNUI('ready', { ok: true });
        }
        break;
      }

      case 'openStaffPanel': {
        log('Opening Staff Panel (v5.0)...');
        // Hide old panels
        const overlay = $('.overlay');
        if (overlay) overlay.setAttribute('aria-hidden', 'true');

        // Show staff panel iframe
        const staffFrame = $('#staff-panel-frame');
        if (staffFrame) {
          staffFrame.style.display = 'block';
          // Send ready message to iframe
          postNUI('ready', { ok: true });
        }
        break;
      }

      case 'closePlayerPanel': {
        log('Closing Player Panel...');
        const playerFrame = $('#player-panel-frame');
        if (playerFrame) playerFrame.style.display = 'none';
        break;
      }

      case 'closeStaffPanel': {
        log('Closing Staff Panel...');
        const staffFrame = $('#staff-panel-frame');
        if (staffFrame) staffFrame.style.display = 'none';
        break;
      }

      default:
        log('Unhandled action:', action);
    }
  });

  // ===========================
  // INITIALIZATION
  // ===========================
  function init() {
    log('Initializing Space Economy UI v5.0...');
    initEventListeners();
    PlayerDirectory.init();
    UI.show(false);
    log('UI Ready!');
  }

  // Start when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
