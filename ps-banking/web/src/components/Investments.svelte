<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import Chart from "chart.js/auto";
  import { fetchNui } from "../utils/fetchNui";
  import { Notify, Locales, Currency } from "../store/data";

  let marketData = {
    companies: [],
    ibovespa: 0,
    ibovespaChange: 0,
    isOpen: false,
    circuitBreaker: false,
  };

  let portfolioData = {
    stocks: [],
    totalInvested: 0,
    totalCurrent: 0,
    totalGain: 0,
    totalGainPercent: 0,
  };

  let investments = [];
  let products = [];
  let indicators = {
    selic: 0,
    inflation: 0,
    pib: 0,
    circulation: 0,
    velocity: 0,
  };

  let integrationAvailable = true;
  let loading = true;

  let investmentAmounts: Record<string, number> = {};
  let selectedTicker = "";
  let tradeQuantity = 1;

  let ibovespaChart: Chart | null = null;
  let portfolioChart: Chart | null = null;
  let ibovespaCanvas: HTMLCanvasElement;
  let portfolioCanvas: HTMLCanvasElement;

  let marketHistory: Array<{ time: string; value: number }> = [];
  let refreshTimer: ReturnType<typeof setInterval>;

  const maxHistoryPoints = 20;

  const formatMoney = (value: number) =>
    new Intl.NumberFormat($Currency.lang, {
      style: "currency",
      currency: $Currency.currency,
      maximumFractionDigits: 0,
    }).format(value || 0);

  const formatPercent = (value: number) =>
    `${(value * 100).toFixed(2)}%`;

  const formatPercentShort = (value: number) =>
    `${(value * 100).toFixed(2)}%`;

  function ensureMarketChart() {
    if (ibovespaCanvas && !ibovespaChart) {
      ibovespaChart = new Chart(ibovespaCanvas, {
        type: "line",
        data: {
          labels: marketHistory.map((point) => point.time),
          datasets: [
            {
              label: "Ibovespa",
              data: marketHistory.map((point) => point.value),
              borderColor: "#60a5fa",
              backgroundColor: "rgba(96, 165, 250, 0.2)",
              tension: 0.3,
              fill: true,
            },
          ],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            y: {
              beginAtZero: false,
              ticks: {
                color: "rgba(255,255,255,0.7)",
              },
              grid: {
                color: "rgba(255,255,255,0.1)",
              },
            },
            x: {
              ticks: {
                color: "rgba(255,255,255,0.7)",
              },
              grid: {
                display: false,
              },
            },
          },
          plugins: {
            legend: {
              labels: {
                color: "rgba(255,255,255,0.8)",
              },
            },
          },
        },
      });
    }
  }

  function ensurePortfolioChart() {
    if (portfolioCanvas && !portfolioChart) {
      portfolioChart = new Chart(portfolioCanvas, {
        type: "bar",
        data: {
          labels: ["Investido", "Atual"],
          datasets: [
            {
              label: "Carteira",
              data: [portfolioData.totalInvested, portfolioData.totalCurrent],
              backgroundColor: ["rgba(16,185,129,0.6)", "rgba(59,130,246,0.6)"],
              borderColor: ["#10b981", "#3b82f6"],
              borderWidth: 1,
              borderRadius: 8,
            },
          ],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            y: {
              beginAtZero: true,
              ticks: {
                color: "rgba(255,255,255,0.7)",
              },
              grid: {
                color: "rgba(255,255,255,0.1)",
              },
            },
            x: {
              ticks: {
                color: "rgba(255,255,255,0.7)",
              },
              grid: {
                display: false,
              },
            },
          },
          plugins: {
            legend: {
              labels: {
                color: "rgba(255,255,255,0.8)",
              },
            },
          },
        },
      });
    }
  }

  function updateMarketHistory(value: number) {
    if (!value) return;
    const time = new Date().toLocaleTimeString("pt-BR", {
      hour: "2-digit",
      minute: "2-digit",
    });
    marketHistory = [...marketHistory, { time, value }].slice(-maxHistoryPoints);
    ensureMarketChart();
    if (ibovespaChart) {
      ibovespaChart.data.labels = marketHistory.map((point) => point.time);
      ibovespaChart.data.datasets[0].data = marketHistory.map(
        (point) => point.value
      );
      ibovespaChart.update();
    }
  }

  function updatePortfolioChart() {
    ensurePortfolioChart();
    if (portfolioChart) {
      portfolioChart.data.datasets[0].data = [
        portfolioData.totalInvested,
        portfolioData.totalCurrent,
      ];
      portfolioChart.update();
    }
  }

  async function fetchIndicators() {
    const response = await fetchNui("ps-banking:client:getEconomyIndicators", {});
    if (response?.available === false) {
      integrationAvailable = false;
      return;
    }
    indicators = response?.indicators || indicators;
  }

  async function fetchProducts() {
    const response = await fetchNui("ps-banking:client:getInvestmentProducts", {});
    if (response?.available === false) {
      integrationAvailable = false;
      return;
    }
    products = response?.products || [];
  }

  async function fetchInvestments() {
    const response = await fetchNui("ps-banking:client:getInvestments", {});
    if (response?.available === false) {
      integrationAvailable = false;
      return;
    }
    investments = response?.investments || [];
  }

  async function fetchMarket() {
    const response = await fetchNui("ps-banking:client:getStockQuotes", {});
    if (response?.available === false) {
      integrationAvailable = false;
      return;
    }
    marketData = response?.quotes || marketData;
    if (!selectedTicker && marketData.companies?.length) {
      selectedTicker = marketData.companies[0].ticker;
    }
    updateMarketHistory(marketData.ibovespa);
  }

  async function fetchPortfolio() {
    const response = await fetchNui("ps-banking:client:getStockPortfolio", {});
    if (response?.available === false) {
      integrationAvailable = false;
      return;
    }
    portfolioData = response?.portfolio || portfolioData;
    updatePortfolioChart();
  }

  async function refreshAll() {
    loading = true;
    await Promise.all([
      fetchIndicators(),
      fetchProducts(),
      fetchInvestments(),
      fetchMarket(),
      fetchPortfolio(),
    ]);
    loading = false;
  }

  async function invest(productId: string) {
    const amount = Number(investmentAmounts[productId] || 0);
    if (amount <= 0) {
      Notify(
        $Locales.amount_required || "Informe um valor para investir.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
      return;
    }
    const response = await fetchNui("ps-banking:client:invest", {
      productId,
      amount,
    });
    if (response?.success) {
      Notify(
        response.message || $Locales.investment_success || "Investimento aplicado.",
        $Locales.payment_completed || "Sucesso",
        "chart-line"
      );
      investmentAmounts = { ...investmentAmounts, [productId]: 0 };
      await fetchInvestments();
    } else {
      Notify(
        response?.message || $Locales.investment_failed || "Não foi possível investir.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
    }
  }

  async function redeem(investmentId: number) {
    const response = await fetchNui("ps-banking:client:redeemInvestment", {
      investmentId,
    });
    if (response?.success) {
      Notify(
        response.message || $Locales.redemption_success || "Resgate realizado.",
        $Locales.payment_completed || "Sucesso",
        "money-bill-trend-up"
      );
      await fetchInvestments();
    } else {
      Notify(
        response?.message || $Locales.redemption_failed || "Não foi possível resgatar.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
    }
  }

  async function buyStock() {
    if (!selectedTicker || tradeQuantity <= 0) {
      Notify(
        $Locales.invalid_data || "Preencha o ticker e a quantidade.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
      return;
    }
    const response = await fetchNui("ps-banking:client:buyStock", {
      ticker: selectedTicker,
      quantity: tradeQuantity,
    });
    if (response?.success) {
      Notify(
        response.message || $Locales.stock_buy_success || "Compra realizada.",
        $Locales.payment_completed || "Sucesso",
        "chart-line"
      );
      await fetchPortfolio();
    } else {
      Notify(
        response?.message || $Locales.stock_buy_failed || "Não foi possível comprar.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
    }
  }

  async function sellStock() {
    if (!selectedTicker || tradeQuantity <= 0) {
      Notify(
        $Locales.invalid_data || "Preencha o ticker e a quantidade.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
      return;
    }
    const response = await fetchNui("ps-banking:client:sellStock", {
      ticker: selectedTicker,
      quantity: tradeQuantity,
    });
    if (response?.success) {
      Notify(
        response.message || $Locales.stock_sell_success || "Venda realizada.",
        $Locales.payment_completed || "Sucesso",
        "chart-line-down"
      );
      await fetchPortfolio();
    } else {
      Notify(
        response?.message || $Locales.stock_sell_failed || "Não foi possível vender.",
        $Locales.error || "Erro",
        "circle-exclamation"
      );
    }
  }

  onMount(async () => {
    await refreshAll();
    refreshTimer = setInterval(async () => {
      await fetchMarket();
      await fetchPortfolio();
    }, 10000);
  });

  onDestroy(() => {
    if (refreshTimer) clearInterval(refreshTimer);
    ibovespaChart?.destroy();
    portfolioChart?.destroy();
  });
</script>

<div class="h-full flex flex-col p-8 overflow-y-auto">
  <div class="flex items-center justify-between mb-8">
    <div>
      <h1 class="text-3xl font-bold text-white mb-2">
        {$Locales.investments || "Investimentos & Bolsa"}
      </h1>
      <p class="text-white/60">
        {$Locales.investments_description ||
          "Acompanhe indicadores econômicos, aplicações e carteira de ações."}
      </p>
    </div>
    <div class="flex items-center space-x-4">
      <div class="modern-card px-4 py-2">
        <div class="flex items-center space-x-2">
          <i class="fas fa-chart-line text-green-400"></i>
          <span class="text-sm text-white/80">
            {$Locales.market_overview || "Painel Econômico"}
          </span>
        </div>
      </div>
    </div>
  </div>

  {#if !integrationAvailable}
    <div class="modern-card p-6 mb-6">
      <div class="flex items-center space-x-4">
        <div class="w-12 h-12 bg-red-500/20 rounded-xl flex items-center justify-center">
          <i class="fas fa-triangle-exclamation text-red-400 text-lg"></i>
        </div>
        <div>
          <h3 class="text-lg font-semibold text-white">
            {$Locales.integration_unavailable || "Integração indisponível"}
          </h3>
          <p class="text-white/60 text-sm">
            {$Locales.integration_unavailable_desc ||
              "O sistema econômico não está ativo no momento."}
          </p>
        </div>
      </div>
    </div>
  {/if}

  <div class="grid grid-cols-1 lg:grid-cols-5 gap-4 mb-8">
    <div class="modern-card p-4">
      <p class="text-white/60 text-xs">{$Locales.selic || "SELIC"}</p>
      <p class="text-xl font-bold text-white">
        {formatPercentShort(indicators.selic || 0)}
      </p>
    </div>
    <div class="modern-card p-4">
      <p class="text-white/60 text-xs">{$Locales.inflation || "Inflação"}</p>
      <p class="text-xl font-bold text-white">
        {formatPercentShort(indicators.inflation || 0)}
      </p>
    </div>
    <div class="modern-card p-4">
      <p class="text-white/60 text-xs">{$Locales.pib || "PIB"}</p>
      <p class="text-xl font-bold text-white">{formatMoney(indicators.pib || 0)}</p>
    </div>
    <div class="modern-card p-4">
      <p class="text-white/60 text-xs">{$Locales.circulation || "Circulação"}</p>
      <p class="text-xl font-bold text-white">
        {formatMoney(indicators.circulation || 0)}
      </p>
    </div>
    <div class="modern-card p-4">
      <p class="text-white/60 text-xs">{$Locales.velocity || "Velocidade"}</p>
      <p class="text-xl font-bold text-white">
        {(indicators.velocity || 0).toFixed(2)}
      </p>
    </div>
  </div>

  <div class="grid grid-cols-1 xl:grid-cols-2 gap-6 mb-8">
    <div class="modern-card p-6">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h3 class="text-lg font-semibold text-white">Ibovespa</h3>
          <p class="text-white/60 text-sm">
            {marketData.isOpen ? $Locales.market_open || "Mercado aberto" : $Locales.market_closed || "Mercado fechado"}
          </p>
        </div>
        <div class={`text-right ${marketData.ibovespaChange >= 0 ? "text-green-400" : "text-red-400"}`}>
          <p class="text-2xl font-bold">{marketData.ibovespa.toFixed(2)}</p>
          <p class="text-sm">{formatPercent(marketData.ibovespaChange)}</p>
        </div>
      </div>
      {#if marketData.circuitBreaker}
        <div class="mb-4 px-3 py-2 bg-red-500/20 border border-red-500/30 rounded-lg text-sm text-red-300">
          {$Locales.circuit_breaker || "Circuit Breaker ativo"}
        </div>
      {/if}
      <div class="h-52">
        <canvas bind:this={ibovespaCanvas}></canvas>
      </div>
    </div>

    <div class="modern-card p-6">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h3 class="text-lg font-semibold text-white">{$Locales.portfolio || "Carteira"}</h3>
          <p class="text-white/60 text-sm">
            {$Locales.portfolio_summary || "Resumo dos ativos em bolsa"}
          </p>
        </div>
        <div class={`text-right ${portfolioData.totalGain >= 0 ? "text-green-400" : "text-red-400"}`}>
          <p class="text-2xl font-bold">{formatMoney(portfolioData.totalCurrent || 0)}</p>
          <p class="text-sm">
            {formatMoney(portfolioData.totalGain || 0)} ({formatPercentShort(portfolioData.totalGainPercent || 0)})
          </p>
        </div>
      </div>
      <div class="h-52">
        <canvas bind:this={portfolioCanvas}></canvas>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-1 xl:grid-cols-3 gap-6 mb-8">
    <div class="modern-card p-6 xl:col-span-2">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-white">{$Locales.stock_quotes || "Cotações"}</h3>
        <span class="text-xs text-white/50">{marketData.companies?.length || 0} {$Locales.assets || "ativos"}</span>
      </div>
      <div class="space-y-3 max-h-72 overflow-y-auto pr-2">
        {#if marketData.companies?.length}
          {#each marketData.companies as company}
            <div class="flex items-center justify-between bg-gradient-to-r from-white/10 to-white/5 hover:from-white/15 hover:to-white/10 rounded-xl px-4 py-3 border border-white/10 transition-all duration-200 hover:border-white/20">
              <div>
                <p class="text-white font-bold text-sm">{company.ticker} - {company.name}</p>
                <p class="text-xs text-white/70">{company.sector}</p>
              </div>
              <div class="text-right">
                <p class="text-white font-bold">{formatMoney(company.price)}</p>
                <p class={`text-sm font-semibold ${company.dayChange >= 0 ? "text-green-400" : "text-red-400"}`}>
                  {company.dayChange >= 0 ? "↑" : "↓"} {formatPercent(company.dayChange)}
                </p>
              </div>
            </div>
          {/each}
        {:else}
          <div class="text-white/60 text-sm">
            {$Locales.no_quotes || "Nenhuma cotação disponível."}
          </div>
        {/if}
      </div>
    </div>

    <div class="modern-card p-6 bg-gradient-to-br from-indigo-500/10 to-purple-500/10 border-2 border-indigo-500/30">
      <h3 class="text-lg font-semibold text-white mb-4 flex items-center gap-2">
        <i class="fas fa-chart-line text-indigo-400"></i>
        {$Locales.trade || "Negociação"}
      </h3>
      <div class="space-y-4">
        <div>
          <label for="trade-ticker" class="text-sm font-medium text-white/90 mb-2 block">{$Locales.ticker || "Ticker"}</label>
          <select
            id="trade-ticker"
            class="w-full bg-black/40 text-white rounded-lg px-4 py-3 border-2 border-white/20 focus:outline-none focus:border-indigo-400 transition-colors appearance-none cursor-pointer hover:bg-black/50"
            style="background-image: url('data:image/svg+xml;charset=UTF-8,%3csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 24 24%27 fill=%27none%27 stroke=%27white%27 stroke-width=%272%27 stroke-linecap=%27round%27 stroke-linejoin=%27round%27%3e%3cpolyline points=%276 9 12 15 18 9%27%3e%3c/polyline%3e%3c/svg%3e'); background-repeat: no-repeat; background-position: right 0.75rem center; background-size: 1.5rem; padding-right: 2.5rem;"
            bind:value={selectedTicker}
          >
            {#each marketData.companies as company}
              <option value={company.ticker} class="bg-gray-900 text-white py-2">{company.ticker} - {company.name}</option>
            {/each}
          </select>
        </div>
        <div>
          <label for="trade-quantity" class="text-sm font-medium text-white/90 mb-2 block">{$Locales.quantity || "Quantidade"}</label>
          <input
            id="trade-quantity"
            type="number"
            min="1"
            class="w-full bg-black/40 text-white rounded-lg px-4 py-3 border-2 border-white/20 focus:outline-none focus:border-indigo-400 transition-colors hover:bg-black/50"
            placeholder="Ex: 10"
            bind:value={tradeQuantity}
          />
        </div>
        <div class="flex items-center gap-3 pt-2">
          <button class="flex-1 bg-green-500/20 hover:bg-green-500/30 border-2 border-green-500/50 text-white font-semibold rounded-lg px-4 py-3 transition-all duration-200 hover:scale-105 hover:shadow-lg hover:shadow-green-500/20 flex items-center justify-center gap-2" on:click={buyStock}>
            <i class="fas fa-arrow-trend-up"></i>
            <span>{$Locales.buy || "Comprar"}</span>
          </button>
          <button class="flex-1 bg-red-500/20 hover:bg-red-500/30 border-2 border-red-500/50 text-white font-semibold rounded-lg px-4 py-3 transition-all duration-200 hover:scale-105 hover:shadow-lg hover:shadow-red-500/20 flex items-center justify-center gap-2" on:click={sellStock}>
            <i class="fas fa-arrow-trend-down"></i>
            <span>{$Locales.sell || "Vender"}</span>
          </button>
        </div>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-1 xl:grid-cols-2 gap-6 mb-8">
    <div class="modern-card p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-white">{$Locales.portfolio_positions || "Posições"}</h3>
        <span class="text-xs text-white/50">{portfolioData.stocks?.length || 0} {$Locales.assets || "ativos"}</span>
      </div>
      <div class="space-y-3 max-h-72 overflow-y-auto pr-2">
        {#if portfolioData.stocks?.length}
          {#each portfolioData.stocks as stock}
            <div class="flex items-center justify-between bg-gradient-to-r from-white/10 to-white/5 hover:from-white/15 hover:to-white/10 rounded-xl px-4 py-3 border border-white/10 transition-all duration-200 hover:border-white/20">
              <div>
                <p class="text-white font-bold text-sm">{stock.ticker} - {stock.name}</p>
                <p class="text-xs text-white/70">
                  {stock.quantity} {$Locales.shares || "ações"} • {$Locales.avg_price || "Preço médio"} {formatMoney(stock.purchasePrice)}
                </p>
              </div>
              <div class={`text-right ${stock.gain >= 0 ? "text-green-400" : "text-red-400"}`}>
                <p class="font-bold">{formatMoney(stock.current)}</p>
                <p class="text-sm font-semibold">
                  {stock.gain >= 0 ? "↑" : "↓"} {formatMoney(stock.gain)} ({formatPercentShort(stock.gainPercent || 0)})
                </p>
              </div>
            </div>
          {/each}
        {:else}
          <div class="text-white/60 text-sm">
            {$Locales.no_portfolio || "Nenhuma posição em aberto."}
          </div>
        {/if}
      </div>
    </div>

    <div class="modern-card p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-white">{$Locales.investment_products || "Produtos Bancários"}</h3>
        <span class="text-xs text-white/50">{products.length} {$Locales.options || "opções"}</span>
      </div>
      <div class="space-y-4 max-h-72 overflow-y-auto pr-2">
        {#if products.length}
          {#each products as product}
            <div class="bg-gradient-to-r from-white/10 to-white/5 border border-white/10 rounded-xl p-4 hover:from-white/15 hover:to-white/10 transition-all duration-200">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <p class="text-white font-bold">{product.name}</p>
                  <p class="text-xs text-white/70">{product.description}</p>
                </div>
                <span class="text-xs text-white/80 bg-white/10 px-2 py-1 rounded-lg">
                  {$Locales.min || "Mín."}: {formatMoney(product.minInvestment)}
                </span>
              </div>
              <div class="flex items-center gap-3">
                <input
                  type="number"
                  min={product.minInvestment}
                  class="flex-1 bg-black/40 text-white rounded-lg px-3 py-2 border-2 border-white/20 focus:outline-none focus:border-green-400 transition-colors"
                  placeholder={$Locales.amount || "Valor"}
                  bind:value={investmentAmounts[product.id]}
                />
                <button class="bg-green-500/20 hover:bg-green-500/30 border-2 border-green-500/50 text-white font-semibold rounded-lg px-4 py-2 transition-all duration-200 hover:scale-105 flex items-center gap-2" on:click={() => invest(product.id)}>
                  <i class="fas fa-coins"></i>
                  <span>{$Locales.invest || "Investir"}</span>
                </button>
              </div>
              <div class="text-xs text-white/70 mt-2 flex items-center gap-2">
                <i class="fas fa-clock text-blue-400"></i>
                <span>{$Locales.liquidity || "Liquidez"}: {product.liquidity}</span>
              </div>
            </div>
          {/each}
        {:else}
          <div class="text-white/60 text-sm">
            {$Locales.no_products || "Nenhum produto disponível no momento."}
          </div>
        {/if}
      </div>
    </div>
  </div>

  <div class="modern-card p-6">
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-lg font-semibold text-white">{$Locales.my_investments || "Meus investimentos"}</h3>
      <span class="text-xs text-white/50">{investments.length} {$Locales.records || "registros"}</span>
    </div>
    <div class="space-y-3">
      {#if investments.length}
        {#each investments as investment}
          <div class="flex flex-col md:flex-row md:items-center md:justify-between bg-white/5 rounded-xl px-4 py-3">
            <div>
              <p class="text-white font-semibold">{investment.productName}</p>
              <p class="text-xs text-white/50">
                {$Locales.invested || "Aplicado"} {formatMoney(investment.amount)} • {$Locales.yield || "Rendimento"} {formatMoney(investment.yield || 0)}
              </p>
              <p class="text-xs text-white/50">
                {$Locales.maturity || "Vencimento"}: {investment.maturityDate || $Locales.not_applicable || "—"}
              </p>
            </div>
            <div class="mt-3 md:mt-0 flex items-center gap-3">
              {#if investment.canRedeem}
                <button class="action-button" on:click={() => redeem(investment.id)}>
                  <i class="fas fa-hand-holding-dollar"></i>
                  <span>{$Locales.redeem || "Resgatar"}</span>
                </button>
              {:else}
                <span class="text-xs text-white/50">{$Locales.redeemed || "Resgatado"}</span>
              {/if}
            </div>
          </div>
        {/each}
      {:else if loading}
        <div class="text-white/60 text-sm">{$Locales.loading || "Carregando..."}</div>
      {:else}
        <div class="text-white/60 text-sm">{$Locales.no_investments || "Nenhum investimento encontrado."}</div>
      {/if}
    </div>
  </div>
</div>
