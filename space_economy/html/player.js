/**
 * Space Economy - Player Panel Controller
 * Handles all player-facing UI interactions
 */

(() => {
  'use strict';

  // ===== CONSTANTS =====
  const RESOURCE_NAME = (typeof GetParentResourceName === 'function' && GetParentResourceName()) || 'space_economy';
  const DEBUG = false;

  // ===== UTILITIES =====
  const log = (...args) => DEBUG && console.log('[Player Panel]', ...args);
  const error = (...args) => console.error('[Player Panel Error]', ...args);

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
    currentTab: 'financial',
    playerData: null,
    organizations: [],
    stocks: [],
    bankingProducts: [],
    shops: [],
  };

  // ===== UI FUNCTIONS =====
  function showNotification(message, type = 'info') {
    // Implement your notification system here
    console.log(`[${type.toUpperCase()}] ${message}`);
  }

  function openPlayerPanel() {
    const overlay = $('#player-overlay');
    if (overlay) {
      overlay.classList.add('active');
      refreshPlayerData();
    }
  }

  function closePlayerPanel() {
    const overlay = $('#player-overlay');
    if (overlay) {
      overlay.classList.remove('active');
    }
    postNUI('closePlayerPanel');

    // Notify parent window to hide the iframe
    if (window.parent !== window) {
      window.parent.postMessage({ action: 'closeFromIframe', panelType: 'player' }, '*');
    }
  }

  function switchTab(tabName) {
    // Update buttons
    $$('.tab-btn').forEach(btn => {
      if (btn.dataset.tab === tabName) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    // Update content
    $$('.tab-content').forEach(content => {
      if (content.dataset.tab === tabName) {
        content.classList.add('active');
      } else {
        content.classList.remove('active');
      }
    });

    State.currentTab = tabName;

    // Load tab-specific data
    loadTabData(tabName);
  }

  function loadTabData(tabName) {
    switch (tabName) {
      case 'financial':
        loadFinancialData();
        break;
      case 'business':
        loadOrganizations();
        break;
      case 'stock':
        loadStockMarket();
        break;
      case 'banking':
        loadBankingProducts();
        break;
      case 'shop':
        loadShops();
        break;
    }
  }

  // ===== FINANCIAL TAB =====
  async function loadFinancialData() {
    try {
      const data = await postNUI('getFinancialData');
      if (data && data.success) {
        updateFinancialUI(data.data);
      }
    } catch (err) {
      error('Failed to load financial data:', err);
    }
  }

  function updateFinancialUI(data) {
    if (!data) return;

    // Update stats
    if ($('#credit-score')) $('#credit-score').textContent = data.creditScore || 750;
    if ($('#total-debts')) $('#total-debts').textContent = formatMoney(data.totalDebts || 0);
    if ($('#debts-count')) $('#debts-count').textContent = `${data.debtsCount || 0} ativas`;
    if ($('#total-installments')) $('#total-installments').textContent = data.installmentsCount || 0;
    if ($('#next-installment')) $('#next-installment').textContent = data.nextInstallment || 'Próx: --';

    // Update debts table
    renderDebtsTable(data.debts || []);

    // Update installments table
    renderInstallmentsTable(data.installments || []);
  }

  function renderDebtsTable(debts) {
    const container = $('#debts-table');
    if (!container) return;

    if (!debts || debts.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhuma dívida encontrada</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Motivo</th>
          <th>Valor</th>
          <th>Vencimento</th>
          <th>Ações</th>
        </tr>
      </thead>
      <tbody>
        ${debts.map(debt => `
          <tr>
            <td>${debt.reason || 'Dívida'}</td>
            <td>${formatMoney(debt.amount)}</td>
            <td>${debt.dueDate || '--'}</td>
            <td>
              <button class="btn btn-sm btn-primary" onclick="payDebt(${debt.id})">Pagar</button>
            </td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  function renderInstallmentsTable(installments) {
    const container = $('#installments-table');
    if (!container) return;

    if (!installments || installments.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhum parcelamento ativo</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Descrição</th>
          <th>Parcela</th>
          <th>Valor</th>
          <th>Próximo Vencimento</th>
          <th>Ações</th>
        </tr>
      </thead>
      <tbody>
        ${installments.map(inst => `
          <tr>
            <td>${inst.description || 'Parcelamento'}</td>
            <td>${inst.currentInstallment}/${inst.totalInstallments}</td>
            <td>${formatMoney(inst.installmentAmount)}</td>
            <td>${inst.nextDue || '--'}</td>
            <td>
              <button class="btn btn-sm btn-primary" onclick="payInstallment(${inst.id})">Pagar Parcela</button>
            </td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  async function simulateLoan() {
    const amount = parseNumber($('#loan-amount')?.value);
    const installments = parseNumber($('#loan-installments')?.value);
    const purpose = $('#loan-purpose')?.value || '';

    if (!amount || amount <= 0) {
      showNotification('Digite um valor válido', 'error');
      return;
    }

    if (!installments || installments <= 0) {
      showNotification('Digite um número de parcelas válido', 'error');
      return;
    }

    try {
      const result = await postNUI('simulateLoan', { amount, installments, purpose });
      if (result && result.success) {
        displayLoanSimulation(result.data);
      } else {
        showNotification(result.message || 'Erro ao simular empréstimo', 'error');
      }
    } catch (err) {
      error('Failed to simulate loan:', err);
    }
  }

  function displayLoanSimulation(data) {
    const container = $('#loan-simulation-result');
    if (!container) return;

    container.innerHTML = `
      <h4>Simulação de Empréstimo</h4>
      <div class="stats-grid">
        <div class="stat-item">
          <span class="stat-label">Valor Solicitado</span>
          <span class="stat-value">${formatMoney(data.amount)}</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Taxa de Juros</span>
          <span class="stat-value">${data.interestRate}%</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Valor da Parcela</span>
          <span class="stat-value">${formatMoney(data.installmentAmount)}</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Total a Pagar</span>
          <span class="stat-value">${formatMoney(data.totalAmount)}</span>
        </div>
      </div>
      <p style="margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">
        ${data.message || ''}
      </p>
    `;

    container.classList.remove('hidden');
  }

  async function requestLoan() {
    const amount = parseNumber($('#loan-amount')?.value);
    const installments = parseNumber($('#loan-installments')?.value);
    const purpose = $('#loan-purpose')?.value || '';

    if (!amount || amount <= 0) {
      showNotification('Digite um valor válido', 'error');
      return;
    }

    try {
      const result = await postNUI('requestLoan', { amount, installments, purpose });
      if (result && result.success) {
        showNotification('Empréstimo aprovado!', 'success');
        $('#loan-amount').value = '';
        $('#loan-purpose').value = '';
        $('#loan-simulation-result').classList.add('hidden');
        loadFinancialData();
      } else {
        showNotification(result.message || 'Empréstimo negado', 'error');
      }
    } catch (err) {
      error('Failed to request loan:', err);
    }
  }

  // ===== BUSINESS TAB =====
  async function loadOrganizations() {
    try {
      const result = await postNUI('getMyOrganizations');
      if (result && result.success) {
        State.organizations = result.data || [];
        renderOrganizations();
      }
    } catch (err) {
      error('Failed to load organizations:', err);
    }
  }

  function renderOrganizations() {
    const container = $('#organizations-list');
    if (!container) return;

    if (!State.organizations || State.organizations.length === 0) {
      container.innerHTML = '<p class="empty-state">Você não possui organizações. Crie uma para começar!</p>';
      return;
    }

    container.innerHTML = State.organizations.map(org => `
      <div class="org-card" onclick="showOrganizationDetail(${org.id})">
        <h3>${org.name} [${org.tag}]</h3>
        <div class="stat-item mt-3">
          <span class="stat-label">Saldo</span>
          <span class="stat-value">${formatMoney(org.balance)}</span>
        </div>
        <div class="stat-item mt-3">
          <span class="stat-label">Membros</span>
          <span class="stat-value">${org.members || 0}</span>
        </div>
      </div>
    `).join('');
  }

  async function createOrganization() {
    // Show modal to create organization
    const name = prompt('Nome da organização:');
    const tag = prompt('Tag da organização (2-6 caracteres):');

    if (!name || !tag) {
      showNotification('Preencha todos os campos', 'error');
      return;
    }

    try {
      const result = await postNUI('createOrganization', { name, tag });
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

  // ===== STOCK MARKET TAB =====
  async function loadStockMarket() {
    try {
      const [quotesResult, portfolioResult] = await Promise.all([
        postNUI('getStockQuotes'),
        postNUI('getMyPortfolio')
      ]);

      if (quotesResult && quotesResult.success) {
        State.stocks = quotesResult.data || [];
        renderStocks();
      }

      if (portfolioResult && portfolioResult.success) {
        updatePortfolio(portfolioResult.data);
      }
    } catch (err) {
      error('Failed to load stock market:', err);
    }
  }

  function updatePortfolio(data) {
    if ($('#portfolio-invested')) $('#portfolio-invested').textContent = formatMoney(data.invested || 0);
    if ($('#portfolio-current')) $('#portfolio-current').textContent = formatMoney(data.current || 0);
    if ($('#portfolio-profit')) {
      const profit = (data.current || 0) - (data.invested || 0);
      const element = $('#portfolio-profit');
      element.textContent = formatMoney(profit);
      element.style.color = profit >= 0 ? 'var(--success)' : 'var(--danger)';
    }

    renderMyStocks(data.stocks || []);
  }

  function renderStocks() {
    const container = $('#stocks-list');
    if (!container) return;

    if (!State.stocks || State.stocks.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhuma ação disponível</p>';
      return;
    }

    container.innerHTML = State.stocks.map(stock => `
      <div class="stock-card">
        <h4>${stock.symbol} - ${stock.name}</h4>
        <div class="stat-value mt-2">${formatMoney(stock.price)}</div>
        <div class="stat-change ${stock.change >= 0 ? 'positive' : 'negative'} mt-1">
          ${stock.change >= 0 ? '+' : ''}${stock.change}%
        </div>
        <div class="form-actions mt-3">
          <button class="btn btn-sm btn-success" onclick="buyStock('${stock.symbol}')">Comprar</button>
          <button class="btn btn-sm btn-danger" onclick="sellStock('${stock.symbol}')">Vender</button>
        </div>
      </div>
    `).join('');
  }

  function renderMyStocks(stocks) {
    const container = $('#my-stocks-table');
    if (!container) return;

    if (!stocks || stocks.length === 0) {
      container.innerHTML = '<p class="empty-state">Você não possui ações</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Ação</th>
          <th>Quantidade</th>
          <th>Preço Médio</th>
          <th>Valor Atual</th>
          <th>Lucro/Prejuízo</th>
        </tr>
      </thead>
      <tbody>
        ${stocks.map(stock => {
          const profit = (stock.currentPrice - stock.avgPrice) * stock.quantity;
          return `
            <tr>
              <td>${stock.symbol}</td>
              <td>${stock.quantity}</td>
              <td>${formatMoney(stock.avgPrice)}</td>
              <td>${formatMoney(stock.currentPrice)}</td>
              <td style="color: ${profit >= 0 ? 'var(--success)' : 'var(--danger)'}">${formatMoney(profit)}</td>
            </tr>
          `;
        }).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  async function buyStock(symbol) {
    const quantity = prompt(`Quantas ações de ${symbol} deseja comprar?`);
    if (!quantity || quantity <= 0) return;

    try {
      const result = await postNUI('buyStock', { symbol, quantity: parseNumber(quantity) });
      if (result && result.success) {
        showNotification('Ações compradas com sucesso!', 'success');
        loadStockMarket();
      } else {
        showNotification(result.message || 'Erro ao comprar ações', 'error');
      }
    } catch (err) {
      error('Failed to buy stock:', err);
    }
  }

  async function sellStock(symbol) {
    const quantity = prompt(`Quantas ações de ${symbol} deseja vender?`);
    if (!quantity || quantity <= 0) return;

    try {
      const result = await postNUI('sellStock', { symbol, quantity: parseNumber(quantity) });
      if (result && result.success) {
        showNotification('Ações vendidas com sucesso!', 'success');
        loadStockMarket();
      } else {
        showNotification(result.message || 'Erro ao vender ações', 'error');
      }
    } catch (err) {
      error('Failed to sell stock:', err);
    }
  }

  // ===== BANKING TAB =====
  async function loadBankingProducts() {
    try {
      const [productsResult, investmentsResult] = await Promise.all([
        postNUI('getBankingProducts'),
        postNUI('getMyInvestments')
      ]);

      if (productsResult && productsResult.success) {
        State.bankingProducts = productsResult.data || [];
        renderBankingProducts();
      }

      if (investmentsResult && investmentsResult.success) {
        renderInvestments(investmentsResult.data || []);
      }
    } catch (err) {
      error('Failed to load banking products:', err);
    }
  }

  function renderBankingProducts() {
    const container = $('#banking-products');
    if (!container) return;

    if (!State.bankingProducts || State.bankingProducts.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhum produto disponível</p>';
      return;
    }

    container.innerHTML = State.bankingProducts.map(product => `
      <div class="product-card">
        <h4>${product.name}</h4>
        <p>${product.description}</p>
        <div class="stat-item mt-3">
          <span class="stat-label">Rendimento</span>
          <span class="stat-value">${product.rate}% a.a.</span>
        </div>
        <div class="stat-item mt-2">
          <span class="stat-label">Mínimo</span>
          <span class="stat-value">${formatMoney(product.minAmount)}</span>
        </div>
        <button class="btn btn-primary mt-3" onclick="investInProduct('${product.id}')">Investir</button>
      </div>
    `).join('');
  }

  function renderInvestments(investments) {
    const container = $('#investments-table');
    if (!container) return;

    if (!investments || investments.length === 0) {
      container.innerHTML = '<p class="empty-state">Nenhum investimento ativo</p>';
      return;
    }

    const table = document.createElement('table');
    table.innerHTML = `
      <thead>
        <tr>
          <th>Produto</th>
          <th>Valor Investido</th>
          <th>Valor Atual</th>
          <th>Rendimento</th>
          <th>Ações</th>
        </tr>
      </thead>
      <tbody>
        ${investments.map(inv => `
          <tr>
            <td>${inv.productName}</td>
            <td>${formatMoney(inv.amount)}</td>
            <td>${formatMoney(inv.currentValue)}</td>
            <td style="color: var(--success)">${formatMoney(inv.profit)}</td>
            <td>
              <button class="btn btn-sm btn-secondary" onclick="redeemInvestment(${inv.id})">Resgatar</button>
            </td>
          </tr>
        `).join('')}
      </tbody>
    `;

    container.innerHTML = '';
    container.appendChild(table);
  }

  async function investInProduct(productId) {
    const amount = prompt('Quanto deseja investir?');
    if (!amount || amount <= 0) return;

    try {
      const result = await postNUI('invest', { productId, amount: parseNumber(amount) });
      if (result && result.success) {
        showNotification('Investimento realizado com sucesso!', 'success');
        loadBankingProducts();
      } else {
        showNotification(result.message || 'Erro ao investir', 'error');
      }
    } catch (err) {
      error('Failed to invest:', err);
    }
  }

  async function redeemInvestment(investmentId) {
    if (!confirm('Deseja realmente resgatar este investimento?')) return;

    try {
      const result = await postNUI('redeemInvestment', { investmentId });
      if (result && result.success) {
        showNotification('Investimento resgatado com sucesso!', 'success');
        loadBankingProducts();
      } else {
        showNotification(result.message || 'Erro ao resgatar', 'error');
      }
    } catch (err) {
      error('Failed to redeem investment:', err);
    }
  }

  // ===== SHOPS TAB =====
  async function loadShops() {
    try {
      const result = await postNUI('getMyShops');
      if (result && result.success) {
        State.shops = result.data || [];
        renderShops();
      }
    } catch (err) {
      error('Failed to load shops:', err);
    }
  }

  function renderShops() {
    const container = $('#shops-list');
    if (!container) return;

    if (!State.shops || State.shops.length === 0) {
      container.innerHTML = '<p class="empty-state">Você não possui lojas. Crie uma para vender seus produtos!</p>';
      return;
    }

    container.innerHTML = State.shops.map(shop => `
      <div class="shop-card" onclick="manageShop(${shop.id})">
        <h3>${shop.name}</h3>
        <div class="stat-item mt-3">
          <span class="stat-label">Produtos</span>
          <span class="stat-value">${shop.productsCount || 0}</span>
        </div>
        <div class="stat-item mt-2">
          <span class="stat-label">Vendas Hoje</span>
          <span class="stat-value">${formatMoney(shop.salesToday || 0)}</span>
        </div>
      </div>
    `).join('');
  }

  async function createShop() {
    const name = prompt('Nome da loja:');
    if (!name) return;

    try {
      const result = await postNUI('createShop', { name });
      if (result && result.success) {
        showNotification('Loja criada com sucesso!', 'success');
        loadShops();
      } else {
        showNotification(result.message || 'Erro ao criar loja', 'error');
      }
    } catch (err) {
      error('Failed to create shop:', err);
    }
  }

  // ===== ACCORDION TOGGLE =====
  function toggleAccordion(button) {
    const item = button.closest('.accordion-item');
    const content = item.querySelector('.accordion-content');

    button.classList.toggle('active');

    if (content.classList.contains('expanded')) {
      content.classList.remove('expanded');
      content.style.maxHeight = '0px';
    } else {
      // Close other accordions
      $$('.accordion-content.expanded').forEach(other => {
        other.classList.remove('expanded');
        other.style.maxHeight = '0px';
        other.previousElementSibling.classList.remove('active');
      });

      content.classList.add('expanded');
      content.style.maxHeight = content.scrollHeight + 'px';
    }
  }

  // ===== MODAL FUNCTIONS =====
  function closeModal(event) {
    if (event.target.classList.contains('modal-overlay')) {
      event.target.classList.remove('active');
    }
  }

  // ===== REFRESH =====
  async function refreshPlayerData() {
    loadTabData(State.currentTab);
  }

  // ===== MESSAGE HANDLER =====
  window.addEventListener('message', (event) => {
    const data = event.data;

    switch (data.action) {
      case 'open':
        openPlayerPanel();
        break;
      case 'close':
        closePlayerPanel();
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
      case 'financial':
        updateFinancialUI(data);
        break;
      case 'organizations':
        State.organizations = data;
        renderOrganizations();
        break;
      case 'stocks':
        State.stocks = data;
        renderStocks();
        break;
    }
  }

  // ===== KEYBOARD HANDLER =====
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      closePlayerPanel();
    }
  });

  // ===== EXPOSE GLOBAL FUNCTIONS =====
  window.closePlayerPanel = closePlayerPanel;
  window.switchTab = switchTab;
  window.toggleAccordion = toggleAccordion;
  window.simulateLoan = simulateLoan;
  window.requestLoan = requestLoan;
  window.createOrganization = createOrganization;
  window.refreshPlayerData = refreshPlayerData;
  window.buyStock = buyStock;
  window.sellStock = sellStock;
  window.refreshStockQuotes = loadStockMarket;
  window.investInProduct = investInProduct;
  window.redeemInvestment = redeemInvestment;
  window.createShop = createShop;
  window.closeModal = closeModal;

  log('Player Panel initialized');
})();
