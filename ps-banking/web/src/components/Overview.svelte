<script lang="ts">
  import { writable } from "svelte/store";
  import { onMount } from "svelte";
  import Chart from "chart.js/auto";
  import { fetchNui } from "../utils/fetchNui";
  import { quintOut } from "svelte/easing";
  import { slide, fade, scale } from "svelte/transition";
  import {
    showOverview,
    showBills,
    showHistory,
    showHeav,
    notifications,
    Bills,
    Notify,
    Transactions,
    currentCash,
    bankBalance,
    Locales,
    Currency,
    type Notification,
  } from "../store/data";

  let notificationId = 0;
  let transactions = Bills;
  let phone = false;
  let showSureModalBills = writable(false);
  let showTransferModal = writable(false);
  let transferData = writable({
    idOrPhone: "",
    amount: 0,
    confirm: false,
    contactType: "none",
  });

  let weeklyData = writable({
    totalReceived: 0,
    totalUsed: 0,
  });

  let chart: Chart;
  let chartCanvas: HTMLCanvasElement;

  async function fetchWeeklySummary() {
    try {
      const response = await fetchNui("ps-banking:client:getWeeklySummary", {});
      if (response) {
        weeklyData.set(response);
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function updateBalances() {
    try {
      const response = await fetchNui("ps-banking:client:getMoneyTypes", {});
      const bank = response.find(
        (item: { name: string }) => item.name === "bank"
      );
      const cash = response.find(
        (item: { name: string }) => item.name === "cash"
      );
      if (bank) {
        bankBalance.set(bank.amount);
      }
      if (cash) {
        currentCash.set(cash.amount);
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function payAllBills() {
    const success = await fetchNui("ps-banking:client:payAllBills", {});
    if (success) {
      await getBills();
      Notify(
        $Locales.pay_all_bills_success,
        $Locales.payment_completed,
        "money-bill"
      );
    } else {
      Notify(
        $Locales.pay_all_bills_error,
        $Locales.error,
        "circle-exclamation"
      );
    }
  }

  function openModal() {
    showTransferModal.set(true);
  }

  function closeModal() {
    showTransferModal.set(false);
    transferData.set({
      idOrPhone: "",
      amount: 0,
      confirm: false,
      contactType: "none",
    });
  }

  async function getBills() {
    try {
      const response = await fetchNui("ps-banking:client:getBills", {});
      Bills.set(response);
    } catch (error) {
      console.error(error);
    }
  }

  async function getHistory() {
    try {
      const history = await fetchNui("ps-banking:client:getHistory", {});
      Transactions.set(history);
    } catch (error) {
      console.error(error);
    }
  }

  async function confirmTransfer(id: any, amount: any, method: any) {
    try {
      const response = await fetchNui("ps-banking:client:transferMoney", {
        id: id,
        amount: amount,
        method: method,
      });
      if (response.success) {
        Notify(response.message, $Locales.payment_completed, "user");
      } else {
        Notify(response.message, $Locales.error, "user");
      }
    } catch (error) {
      console.error(error);
    }
    transferData.update((data) => {
      data.confirm = true;
      return data;
    });
    showTransferModal.set(false);
    transferData.set({
      idOrPhone: "",
      amount: 0,
      confirm: false,
      contactType: "none",
    });
  }

  let bankData = {
    balance: $bankBalance,
    cash: $currentCash,
    transactions: $Transactions,
  };

  $: bankData = {
    balance: $bankBalance,
    cash: $currentCash,
    transactions: $Transactions,
  };

  async function heav() {
    try {
      const response = await fetchNui("ps-banking:client:ATMwithdraw", {
        amount: $bankBalance,
      });
      if (response) {
        updateStuff();
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function deposit() {
    try {
      const response = await fetchNui("ps-banking:client:ATMdeposit", {
        amount: $currentCash,
      });
      if (response) {
        updateStuff();
      }
    } catch (error) {
      console.error(error);
    }
  }

  function createChart() {
    if (chartCanvas) {
      chart = new Chart(chartCanvas, {
        type: "bar",
        data: {
          labels: [$Locales.income, $Locales.expenses],
          datasets: [
            {
              label: $Locales.weekly_summary,
              data: [0, 0],
              backgroundColor: ["#3b82f6", "#ef4444"],
            },
          ],
        },
        options: {
          responsive: true,
          scales: {
            y: {
              beginAtZero: true,
            },
          },
        },
      });
    }
  }

  $: {
    weeklyData.subscribe((data) => {
      if (chart) {
        chart.data.datasets[0].data = [data.totalReceived, data.totalUsed];
        chart.update();
      }
    });
  }

  async function updateStuff() {
    // Hot update
    await getBills();
    await getHistory();
    await fetchWeeklySummary();
    await updateBalances();
  }
  
  async function phoneOption() {
    try {
      const response = await fetchNui("ps-banking:client:phoneOption", {});
      phone = response
    } catch (error) {
      console.error(error);
    }
  }

  onMount(async () => {
    createChart();
    updateStuff();
    updateStuff();
    phoneOption();
  });
</script>

<div class="h-full flex flex-col p-8 overflow-y-auto">
  <!-- Page Header -->
  <div class="flex items-center justify-between mb-10 animate-fade-in-up">
    <div>
      <div class="flex items-center space-x-3 mb-2">
        <h1 class="text-4xl font-bold gradient-text-green">{$Locales.overview}</h1>
        <div class="w-3 h-3 bg-green-400 rounded-full animate-pulse"></div>
      </div>
      <p class="text-white/70 text-lg font-medium">{$Locales.financial_summary_quick_actions}</p>
    </div>
    <div class="flex items-center space-x-4">
      <!-- Balance Card -->
      <div class="glass-card px-8 py-4 animate-scale-in shadow-neon-green border-2 border-green-500/20 hover:border-green-500/40 transition-smooth">
        <div class="flex items-center space-x-4">
          <div class="flex flex-col">
            <span class="text-xs text-white/60 font-semibold uppercase tracking-wider mb-1">{$Locales.bank_balance}</span>
            <span class="text-2xl font-bold gradient-text-green">
              {$bankBalance.toLocaleString($Currency.lang, {
                style: "currency",
                currency: $Currency.currency,
                minimumFractionDigits: 0,
              })}
            </span>
          </div>
          <div class="w-12 h-12 bg-gradient-to-br from-green-500/30 to-emerald-600/20 rounded-xl flex items-center justify-center border border-green-400/30 animate-glow-pulse">
            <i class="fas fa-wallet text-green-400 text-xl animate-pulse-soft"></i>
          </div>
        </div>
      </div>
      <div class="glass-card px-5 py-3 border border-green-500/20">
        <div class="flex items-center space-x-3">
          <div class="relative">
            <div class="w-3 h-3 bg-green-400 rounded-full animate-ping absolute"></div>
            <div class="w-3 h-3 bg-green-400 rounded-full"></div>
          </div>
          <span class="text-sm text-white font-bold uppercase tracking-wider">{$Locales.live}</span>
        </div>
      </div>
    </div>
  </div>

  <!-- Quick Actions Grid -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-10">
    <!-- Transfer Money -->
    <div class="elevated-card p-6 group cursor-pointer animate-slide-up relative overflow-hidden" on:click={openModal}>
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-blue-500 to-cyan-500"></div>
      <div class="relative z-10">
        <div class="flex items-center justify-between mb-4">
          <div class="w-14 h-14 bg-gradient-to-br from-blue-500/25 to-cyan-500/15 rounded-2xl flex items-center justify-center group-hover:scale-110 group-hover:rotate-6 transition-spring border border-blue-400/30">
            <i class="fas fa-exchange-alt text-blue-400 text-2xl group-hover:animate-wiggle"></i>
          </div>
          <div class="w-10 h-10 bg-white/5 rounded-full flex items-center justify-center group-hover:bg-blue-500/10 transition-smooth">
            <i class="fas fa-arrow-right text-white/40 group-hover:text-blue-400 group-hover:translate-x-1 transition-smooth text-lg"></i>
          </div>
        </div>
        <h3 class="text-xl font-bold text-white mb-2 group-hover:text-blue-400 transition-smooth">{$Locales.transfer_money}</h3>
        <p class="text-sm text-white/70 font-medium">{$Locales.easy_transfer}</p>
      </div>
    </div>

    <!-- Pay Bills -->
    <div class="elevated-card p-6 group cursor-pointer animate-slide-up relative overflow-hidden" style="animation-delay: 0.1s" on:click={() => showSureModalBills.set(true)}>
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-orange-500 to-yellow-500"></div>
      <div class="relative z-10">
        <div class="flex items-center justify-between mb-4">
          <div class="w-14 h-14 bg-gradient-to-br from-orange-500/25 to-yellow-500/15 rounded-2xl flex items-center justify-center group-hover:scale-110 group-hover:rotate-6 transition-spring border border-orange-400/30">
            <i class="fas fa-file-invoice-dollar text-orange-400 text-2xl group-hover:animate-wiggle"></i>
          </div>
          <div class="w-10 h-10 bg-white/5 rounded-full flex items-center justify-center group-hover:bg-orange-500/10 transition-smooth">
            <i class="fas fa-arrow-right text-white/40 group-hover:text-orange-400 group-hover:translate-x-1 transition-smooth text-lg"></i>
          </div>
        </div>
        <h3 class="text-xl font-bold text-white mb-2 group-hover:text-orange-400 transition-smooth">{$Locales.pay_bills}</h3>
        <p class="text-sm text-white/70 font-medium">{$Locales.pay_pending_bills}</p>
      </div>
    </div>

    <!-- Withdraw -->
    <div class="elevated-card p-6 group cursor-pointer animate-slide-up relative overflow-hidden" style="animation-delay: 0.2s" on:click={() => {
      if ($bankBalance <= 0) {
        Notify($Locales.no_money_on_account, $Locales.error, "credit-card");
      } else {
        Notify($Locales.withdraw_all_success, $Locales.success, "credit-card");
        setTimeout(() => { heav(); }, 200);
      }
    }}>
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-red-500 to-pink-500"></div>
      <div class="relative z-10">
        <div class="flex items-center justify-between mb-4">
          <div class="w-14 h-14 bg-gradient-to-br from-red-500/25 to-pink-500/15 rounded-2xl flex items-center justify-center group-hover:scale-110 group-hover:rotate-6 transition-spring border border-red-400/30">
            <i class="fas fa-arrow-down text-red-400 text-2xl group-hover:animate-gentle-bounce"></i>
          </div>
          <div class="w-10 h-10 bg-white/5 rounded-full flex items-center justify-center group-hover:bg-red-500/10 transition-smooth">
            <i class="fas fa-arrow-right text-white/40 group-hover:text-red-400 group-hover:translate-x-1 transition-smooth text-lg"></i>
          </div>
        </div>
        <h3 class="text-xl font-bold text-white mb-2 group-hover:text-red-400 transition-smooth">{$Locales.withdraw_all_money}</h3>
        <p class="text-sm text-white/70 font-medium">{$Locales.withdraw_all_from_account}</p>
      </div>
    </div>

    <!-- Deposit -->
    <div class="elevated-card p-6 group cursor-pointer animate-slide-up relative overflow-hidden" style="animation-delay: 0.3s" on:click={() => {
      if ($currentCash <= 0) {
        Notify($Locales.no_cash_on_you, $Locales.error, "coins");
      } else {
        Notify($Locales.deposit_all_success, $Locales.success, "coins");
        setTimeout(() => { deposit(); }, 200);
      }
    }}>
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-green-500 to-emerald-500"></div>
      <div class="relative z-10">
        <div class="flex items-center justify-between mb-4">
          <div class="w-14 h-14 bg-gradient-to-br from-green-500/25 to-emerald-500/15 rounded-2xl flex items-center justify-center group-hover:scale-110 group-hover:rotate-6 transition-spring border border-green-400/30">
            <i class="fas fa-arrow-up text-green-400 text-2xl group-hover:animate-gentle-bounce"></i>
          </div>
          <div class="w-10 h-10 bg-white/5 rounded-full flex items-center justify-center group-hover:bg-green-500/10 transition-smooth">
            <i class="fas fa-arrow-right text-white/40 group-hover:text-green-400 group-hover:translate-x-1 transition-smooth text-lg"></i>
          </div>
        </div>
        <h3 class="text-xl font-bold text-white mb-2 group-hover:text-green-400 transition-smooth">{$Locales.deposit_cash}</h3>
        <p class="text-sm text-white/70 font-medium">{$Locales.deposit_all_cash}</p>
      </div>
    </div>
  </div>

  <!-- Statistics and Information Grid -->
  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    <!-- Weekly Summary -->
    <div class="elevated-card p-7 relative overflow-hidden">
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-green-500 to-emerald-500"></div>
      <div class="flex items-center justify-between mb-8">
        <div class="flex items-center space-x-4">
          <div class="w-14 h-14 bg-gradient-to-br from-green-500/25 to-emerald-500/15 rounded-2xl flex items-center justify-center border border-green-400/30 shadow-neon-green">
            <i class="fas fa-calendar-week text-green-400 text-xl"></i>
          </div>
          <h3 class="text-2xl font-bold gradient-text-green">{$Locales.weekly_summary}</h3>
        </div>
      </div>

      <div class="space-y-5">
        <div class="flex items-center justify-between p-5 bg-gradient-to-r from-green-500/10 to-emerald-500/5 rounded-2xl border border-green-500/20 hover:border-green-500/40 transition-smooth group">
          <div class="flex items-center space-x-4">
            <div class="w-12 h-12 bg-gradient-to-br from-green-500/30 to-emerald-500/20 rounded-xl flex items-center justify-center group-hover:scale-110 transition-smooth border border-green-400/30">
              <i class="fas fa-arrow-up text-green-400 text-lg"></i>
            </div>
            <span class="text-white font-semibold text-lg">{$Locales.income}</span>
          </div>
          <span class="text-green-400 font-bold text-xl">
            {#if $weeklyData.totalReceived !== undefined}
              {$weeklyData.totalReceived.toLocaleString($Currency.lang, {
                style: "currency",
                currency: $Currency.currency,
                minimumFractionDigits: 0,
              })}
            {:else}
              $0
            {/if}
          </span>
        </div>

        <div class="flex items-center justify-between p-5 bg-gradient-to-r from-red-500/10 to-pink-500/5 rounded-2xl border border-red-500/20 hover:border-red-500/40 transition-smooth group">
          <div class="flex items-center space-x-4">
            <div class="w-12 h-12 bg-gradient-to-br from-red-500/30 to-pink-500/20 rounded-xl flex items-center justify-center group-hover:scale-110 transition-smooth border border-red-400/30">
              <i class="fas fa-arrow-down text-red-400 text-lg"></i>
            </div>
            <span class="text-white font-semibold text-lg">{$Locales.expenses}</span>
          </div>
          <span class="text-red-400 font-bold text-xl">
            {#if $weeklyData.totalUsed !== undefined}
              {$weeklyData.totalUsed.toLocaleString($Currency.lang, {
                style: "currency",
                currency: $Currency.currency,
                minimumFractionDigits: 0,
              })}
            {:else}
              $0
            {/if}
          </span>
        </div>

        <div class="mt-8 glass-card p-5 border border-white/10">
          <div class="flex items-center mb-4">
            <div class="w-10 h-10 bg-white/5 rounded-lg flex items-center justify-center mr-3">
              <i class="fas fa-chart-bar text-white/70 text-lg"></i>
            </div>
            <span class="text-white font-bold text-lg">{$Locales.report}</span>
          </div>
          <canvas bind:this={chartCanvas} class="w-full h-32"></canvas>
        </div>
      </div>
    </div>

    <!-- Recent Transactions -->
    <div class="elevated-card p-7 relative overflow-hidden">
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-blue-500 to-cyan-500"></div>
      <div class="flex items-center justify-between mb-8">
        <div class="flex items-center space-x-4">
          <div class="w-14 h-14 bg-gradient-to-br from-blue-500/25 to-cyan-500/15 rounded-2xl flex items-center justify-center border border-blue-400/30 shadow-neon-blue">
            <i class="fas fa-history text-blue-400 text-xl"></i>
          </div>
          <h3 class="text-2xl font-bold gradient-text-green">{$Locales.latest_transactions}</h3>
        </div>
        <div class="glass-card rounded-full px-4 py-2 border border-blue-500/30">
          <span class="text-white font-bold text-lg">{bankData.transactions.length}</span>
        </div>
      </div>

      <div class="space-y-3 max-h-80 overflow-y-auto">
        {#if bankData.transactions.length > 0}
          {#each bankData.transactions.slice(0, 6) as transaction, index}
            <div class="flex items-center justify-between p-4 glass-card hover:bg-white/10 transition-smooth border border-white/5 hover:border-white/20 group animate-slide-up" style="animation-delay: {index * 0.05}s">
              <div class="flex items-center space-x-3 flex-1">
                <div class={`w-10 h-10 rounded-xl flex items-center justify-center ${transaction.isIncome ? 'bg-green-500/20 border border-green-500/30' : 'bg-red-500/20 border border-red-500/30'}`}>
                  <i class={`fas fa-${transaction.isIncome ? 'arrow-down' : 'arrow-up'} ${transaction.isIncome ? 'text-green-400' : 'text-red-400'}`}></i>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-white font-semibold truncate">{transaction.description}</p>
                  <p class="text-white/50 text-xs font-medium">{$Locales.transaction}</p>
                </div>
              </div>
              <div class="text-right">
                <span class={`font-bold text-lg ${transaction.isIncome ? "text-green-400" : "text-red-400"}`}>
                  {transaction.isIncome ? "+" : "-"}
                  {transaction.amount.toLocaleString($Currency.lang, {
                    style: "currency",
                    currency: $Currency.currency,
                    minimumFractionDigits: 0,
                  })}
                </span>
              </div>
            </div>
          {/each}

          <div class="pt-6">
            <button
              class="action-button w-full text-lg"
              on:click={() => {
                showOverview.set(false);
                showHistory.set(true);
              }}
            >
              <i class="fas fa-list mr-2"></i>
              {$Locales.see_all}
            </button>
          </div>
        {:else}
          <div class="text-center py-12">
            <div class="w-20 h-20 bg-white/5 rounded-full flex items-center justify-center mx-auto mb-4">
              <i class="fas fa-receipt text-white/40 text-4xl"></i>
            </div>
            <p class="text-white/70 font-medium text-lg">{$Locales.no_transactions}</p>
          </div>
        {/if}
      </div>
    </div>

    <!-- Unpaid Bills -->
    <div class="elevated-card p-7 relative overflow-hidden">
      <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-yellow-500 to-orange-500"></div>
      <div class="flex items-center justify-between mb-8">
        <div class="flex items-center space-x-4">
          <div class="w-14 h-14 bg-gradient-to-br from-yellow-500/25 to-orange-500/15 rounded-2xl flex items-center justify-center border border-yellow-400/30 shadow-neon-gold">
            <i class="fas fa-exclamation-triangle text-yellow-400 text-xl animate-pulse-soft"></i>
          </div>
          <h3 class="text-2xl font-bold gradient-text-gold">{$Locales.unpaid_bills}</h3>
        </div>
        <div class="glass-card rounded-full px-4 py-2 border border-yellow-500/30">
          <span class="text-white font-bold text-lg">{$transactions.length}</span>
        </div>
      </div>

      <div class="space-y-3 max-h-80 overflow-y-auto">
        {#if $transactions.length > 0}
          {#each $transactions.slice(0, 4) as transaction, index (transaction.id)}
            {#if !transaction.isPaid}
              <div class="p-5 glass-card hover:bg-white/10 transition-smooth border border-yellow-500/10 hover:border-yellow-500/30 group animate-slide-up" style="animation-delay: {index * 0.05}s">
                <div class="flex justify-between items-start mb-3">
                  <div class="flex items-center space-x-3 flex-1">
                    <div class="w-10 h-10 bg-yellow-500/20 rounded-xl flex items-center justify-center border border-yellow-500/30">
                      <i class="fas fa-file-invoice text-yellow-400"></i>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-white font-semibold truncate">{transaction.description}</p>
                      <p class="text-white/50 text-xs font-medium">#{transaction.id}</p>
                    </div>
                  </div>
                  <span class={`font-bold text-lg ${transaction.isIncome ? "text-green-400" : "text-yellow-400"}`}>
                    {transaction.isIncome ? "+" : "-"}
                    {transaction.amount.toLocaleString($Currency.lang, {
                      style: "currency",
                      currency: $Currency.currency,
                      minimumFractionDigits: 0,
                    })}
                  </span>
                </div>
                <div class="flex items-center justify-between pt-2 border-t border-white/5">
                  <span class="text-white/60 text-xs font-medium">{transaction.timeAgo}</span>
                  <span class="text-white/60 text-xs font-medium">{transaction.date}</span>
                </div>
              </div>
            {/if}
          {/each}

          <div class="pt-6">
            <button
              class="action-button w-full text-lg"
              on:click={() => {
                showOverview.set(false);
                showBills.set(true);
              }}
            >
              <i class="fas fa-file-invoice-dollar mr-2"></i>
              {$Locales.see_all}
            </button>
          </div>
        {:else}
          <div class="text-center py-12">
            <div class="w-20 h-20 bg-green-500/10 rounded-full flex items-center justify-center mx-auto mb-4 border-2 border-green-500/30">
              <i class="fas fa-check-circle text-green-400 text-4xl"></i>
            </div>
            <p class="text-white/70 font-medium text-lg">{$Locales.no_unpaid_bills}</p>
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>

<!-- Transfer Modal -->
{#if $showTransferModal}
  <div class="modal-backdrop fixed inset-0 flex items-center justify-center z-50 bg-black/60 backdrop-blur-sm">
    <div
      class="modern-card p-8 w-full max-w-md mx-4 shadow-brasil animate-bounce-in"
      in:scale={{ duration: 300, easing: quintOut }}
      out:scale={{ duration: 250, easing: quintOut }}
    >
      <div class="flex items-center justify-between mb-6">
        <div class="flex items-center space-x-3">
          <div class="w-12 h-12 bg-gradient-to-br from-green-500/30 to-blue-500/30 rounded-xl flex items-center justify-center animate-glow-brasil">
            <i class="fas fa-exchange-alt text-green-400 text-xl"></i>
          </div>
          <h2 class="text-2xl font-bold text-white">{$Locales.transfer_money}</h2>
        </div>
        <button
          class="w-8 h-8 bg-white/10 rounded-lg flex items-center justify-center hover:bg-white/20 hover:rotate-90 transition-all"
          on:click={closeModal}
        >
          <i class="fas fa-times text-white/60"></i>
        </button>
      </div>

      <!-- Payment Method Selection -->
      <div class="mb-6">
        <label class="block text-white/80 font-medium mb-3">{$Locales.payment_method}</label>
        <div class="space-y-3">
          {#if phone}
            <label class="flex items-center p-4 bg-white/5 rounded-xl cursor-pointer border border-white/10 hover:border-white/20 transition-colors">
              <input
                type="radio"
                name="payment"
                value="phone"
                bind:group={$transferData.contactType}
                class="hidden peer"
              />
              <i class="fa-duotone fa-phone text-lg text-blue-400 mr-3"></i>
              <span class="text-white font-bold">{$Locales.phone_number}</span
              >
              <div class="ml-auto hidden peer-checked:block">
                <i class="fa-duotone fa-check-circle text-blue-400"></i>
              </div>
            </label>
          {/if}
          <label
            class="flex items-center cursor-pointer bg-gray-700/50 rounded-lg p-3 border border-gray-600/20 hover:border-blue-400 transition duration-300"
          >
            <input
              type="radio"
              name="payment"
              value="id"
              bind:group={$transferData.contactType}
              class="hidden peer"
            />
            <i class="fa-duotone fa-id-badge text-lg text-blue-400 mr-3"></i>
            <span class="text-white font-bold">{$Locales.id}</span>
            <div class="ml-auto hidden peer-checked:block">
              <i class="fa-duotone fa-check-circle text-blue-400"></i>
            </div>
          </label>
        </div>
      </div>

      <!-- ID or Phone Number Input -->
      {#if $transferData.contactType === "phone" || $transferData.contactType === "id"}
        <div class="mb-6">
          <label class="block text-gray-400 mb-2">
            <i class="fa-duotone fa-id-card text-blue-400 mr-2"></i>
            {#if phone}
              {$Locales.id_or_phone_number}
            {:else}
              {$Locales.id}
            {/if}
          </label>
          <div class="relative">
            <input
              type="number"
              min="1"
              class="w-full p-3 bg-gray-700/50 text-white pr-10 border border-blue-200/10 rounded-lg focus:outline-none
            focus:border-blue-400/50 transition-colors duration-500"
              bind:value={$transferData.idOrPhone}
            />
            <i
              class="fa-duotone fa-user absolute top-1/2 right-3 transform -translate-y-1/2 text-gray-400"
            ></i>
          </div>
        </div>
      {/if}

      <!-- Amount Input -->
      <div class="mb-6">
        <label class="block text-gray-400 mb-2">
          <i class="fa-duotone fa-money-bill-wave text-green-400 mr-2"></i>{$Locales.amount}
        </label>
        <div class="relative group">
          <input
            type="number"
            min="1"
            max={$bankBalance}
            class="w-full p-3 bg-white/5 text-white pr-10 border-2 border-white/10 rounded-lg focus:outline-none
            focus:border-green-500/50 focus:shadow-neon-green transition-all duration-300 hover:border-white/20"
            placeholder="0.00"
            bind:value={$transferData.amount}
          />
          <div class="absolute top-1/2 right-3 transform -translate-y-1/2 flex items-center space-x-2">
            <span class="text-xs text-white/50">R$</span>
            <i class="fa-solid fa-brazilian-real-sign text-green-400"></i>
          </div>
        </div>
        <div class="mt-2 flex justify-between text-xs">
          <span class="text-white/50">{$Locales.available}: {$bankBalance.toLocaleString($Currency.lang, {
            style: "currency",
            currency: $Currency.currency,
            minimumFractionDigits: 0,
          })}</span>
          {#if $transferData.amount > $bankBalance}
            <span class="text-red-400 animate-pulse">Saldo insuficiente!</span>
          {:else if $transferData.amount > 0}
            <span class="text-green-400">✓ Valor válido</span>
          {/if}
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="flex gap-3 mt-6">
        <button
          class="flex-1 flex items-center justify-center bg-red-500/20 border-2 border-red-500/30 hover:bg-red-500/30 hover:border-red-500/50
                 text-white py-3 px-4 rounded-xl font-semibold transition-all duration-300 hover:scale-105 hover:shadow-lg"
          on:click={closeModal}
        >
          <i class="fa-solid fa-times-circle mr-2"></i>{$Locales.cancel}
        </button>
        <button
          class="flex-1 flex items-center justify-center bg-gradient-to-r from-green-500/20 to-blue-500/20 border-2 border-green-500/30
                 hover:from-green-500/30 hover:to-blue-500/30 hover:border-green-500/50 text-white py-3 px-4 rounded-xl font-semibold
                 transition-all duration-300 hover:scale-105 hover:shadow-neon-green disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={!$transferData.contactType || $transferData.amount <= 0 || $transferData.amount > $bankBalance || !$transferData.idOrPhone}
          on:click={async () => {
            confirmTransfer(
              $transferData.idOrPhone,
              $transferData.amount,
              $transferData.contactType
            );
          }}
        >
          <i class="fa-solid fa-check-circle mr-2 animate-pulse-soft"></i>{$Locales.confirm}
        </button>
      </div>
    </div>
  </div>
{/if}
{#if $showSureModalBills}
  <div class="fixed inset-0 flex items-center justify-center bg-black/60 backdrop-blur-sm z-50">
    <div
      class="modern-card p-8 w-96 shadow-money animate-bounce-in"
      in:scale={{ duration: 250, easing: quintOut }}
      out:scale={{ duration: 250, easing: quintOut }}
    >
      <div class="flex items-center mb-4">
        <div class="w-14 h-14 bg-orange-500/20 rounded-xl flex items-center justify-center mr-3">
          <i class="fa-solid fa-question-circle text-3xl text-orange-400 animate-pulse-soft"></i>
        </div>
        <h2 class="text-2xl text-white font-bold">
          {$Locales.are_you_sure}
        </h2>
      </div>
      <p class="text-white/70 mb-6 leading-relaxed">
        {$Locales.confirm_pay_all_bills}
      </p>
      <div class="flex gap-3">
        <button
          class="flex-1 flex items-center justify-center bg-red-500/20 border-2 border-red-500/30 hover:bg-red-500/30 hover:border-red-500/50
                 text-white py-3 px-4 rounded-xl font-semibold transition-all duration-300 hover:scale-105"
          on:click={() => {
            showSureModalBills.set(false);
          }}
        >
          <i class="fa-solid fa-times-circle mr-2"></i>{$Locales.cancel}
        </button>
        <button
          class="flex-1 flex items-center justify-center bg-gradient-to-r from-orange-500/20 to-yellow-500/20 border-2 border-orange-500/30
                 hover:from-orange-500/30 hover:to-yellow-500/30 hover:border-orange-500/50 text-white py-3 px-4 rounded-xl font-semibold
                 transition-all duration-300 hover:scale-105 hover:shadow-neon-gold"
          on:click={async () => {
            if ($transactions.length > 0) {
              await payAllBills();
              showSureModalBills.set(false);
            } else {
              showSureModalBills.set(false);
              Notify(
                $Locales.pay_all_bills_error,
                $Locales.error,
                "circle-exclamation"
              );
            }
          }}
        >
          <i class="fa-solid fa-check-circle mr-2 animate-pulse-soft"></i>{$Locales.confirm}
        </button>
      </div>
    </div>
  </div>
{/if}
