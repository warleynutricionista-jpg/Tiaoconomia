<script lang="ts">
  import { onMount } from "svelte";
  import { useNuiEvent } from "../utils/useNuiEvent";
  import { fetchNui } from "../utils/fetchNui";
  import { visibility } from "../store/stores";
  import OverviewPage from "./Overview.svelte";
  import BillsPage from "./Bills.svelte";
  import HistoryPage from "./History.svelte";
  import HeavPage from "./Heav.svelte";
  import IndseatPage from "./Indseat.svelte";
  import StatsPage from "./Stats.svelte";
  import AccountsPage from "./Accounts.svelte";
  import InvestmentsPage from "./Investments.svelte";
  import { slide, fade, scale } from "svelte/transition";
  import { quintOut, cubicOut } from "svelte/easing";
  import {
    showOverview,
    showBills,
    showHistory,
    showHeav,
    showIndseat,
    showStats,
    showAccounts,
    showInvestments,
    Locales,
    bankBalance,
    currentCash,
    activeView
  } from "../store/data";

  let currentActiveView;
  activeView.subscribe(value => {
    currentActiveView = value;
  });

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

  onMount(async () => {
    updateBalances();
    try {
      const response = await fetchNui("ps-banking:client:getLocales", {});
      Locales.set(response);
    } catch (error) {
      console.error(error);
    }
  });

  const navigationItems = [
    { key: 'overview', icon: 'house', label: 'overview' },
    { key: 'bills', icon: 'file-invoice', label: 'bills' },
    { key: 'history', icon: 'clock-rotate-left', label: 'history' },
    { key: 'investments', icon: 'chart-line', label: 'investments' },
    { key: 'withdraw', icon: 'arrow-down', label: 'withdraw' },
    { key: 'deposit', icon: 'arrow-up', label: 'deposit' },
    { key: 'accounts', icon: 'piggy-bank', label: 'accounts' }
  ];

  function setActiveView(view) {
    // Reset all views first
    showOverview.set(false);
    showBills.set(false);
    showHistory.set(false);
    showHeav.set(false);
    showIndseat.set(false);
    showStats.set(false);
    showAccounts.set(false);
    showInvestments.set(false);

    // Then set the active view
    activeView.set(view);

    // Finally, set the corresponding view to true
    switch (view) {
      case 'overview':
        showOverview.set(true);
        break;
      case 'bills':
        showBills.set(true);
        break;
      case 'history':
        showHistory.set(true);
        break;
      case 'investments':
        showInvestments.set(true);
        break;
      case 'withdraw':
        showHeav.set(true);
        break;
      case 'deposit':
        showIndseat.set(true);
        break;
      case 'accounts':
        showAccounts.set(true);
        break;
    }
  }

</script>

<div class="fixed inset-0 flex items-center justify-center p-4 z-10 bg-dots">
  <div
    class="w-full max-w-7xl h-full max-h-[900px] elevated-card overflow-hidden shadow-deep"
    in:scale={{ duration: 600, easing: cubicOut }}
    out:fade={{ duration: 400 }}
  >
    <div class="flex h-full">
      <!-- Modern Sidebar -->
      <div class="w-80 flex flex-col bg-gradient-to-b from-black/30 to-black/20 border-r border-white/10 backdrop-blur-sm">
        <!-- Header -->
        <div class="p-6 border-b border-white/10 bg-gradient-to-br from-white/5 to-transparent">
          <div class="flex items-center space-x-4 animate-fade-in-up">
            <div class="relative">
              <div class="w-14 h-14 bg-gradient-to-br from-emerald-500 via-green-500 to-emerald-600 rounded-2xl flex items-center justify-center shadow-neon-green animate-gentle-bounce">
                <i class="fas fa-piggy-bank text-white text-2xl"></i>
              </div>
              <div class="absolute -top-1 -right-1 w-4 h-4 bg-green-400 rounded-full border-2 border-black/50 animate-pulse"></div>
            </div>
            <div>
              <h1 class="text-2xl font-bold text-white gradient-text-green">Banco</h1>
              <p class="text-sm text-white/70 font-medium">Painel Financeiro Premium</p>
            </div>
          </div>
        </div>

        <!-- Balance Card -->
        <div class="p-6">
          <div class="premium-card p-6 animate-scale-in">
            <div class="relative z-10">
              <div class="flex items-center justify-between mb-4">
                <div class="flex items-center space-x-3">
                  <div class="w-12 h-12 bg-gradient-to-br from-green-500/30 to-emerald-600/20 rounded-xl flex items-center justify-center border border-green-400/30 animate-glow-pulse">
                    <i class="fas fa-wallet text-green-400 text-xl animate-pulse-soft"></i>
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-white/70 font-medium mb-1">Saldo Total</p>
                    <p class="text-2xl font-bold gradient-text-green truncate" title="{$bankBalance.toLocaleString('pt-BR', {
                      style: 'currency',
                      currency: 'BRL',
                      minimumFractionDigits: 0,
                    })}">
                      {#if $bankBalance >= 1000000}
                        R$ {($bankBalance / 1000000).toFixed(1)}M
                      {:else if $bankBalance >= 1000}
                        R$ {($bankBalance / 1000).toFixed(1)}K
                      {:else}
                        R$ {$bankBalance.toLocaleString()}
                      {/if}
                    </p>
                  </div>
                </div>
              </div>
              <div class="flex items-center justify-between p-3 bg-white/5 rounded-xl border border-white/10">
                <div class="flex items-center space-x-2">
                  <i class="fas fa-money-bill-wave text-yellow-400 text-sm"></i>
                  <span class="text-xs text-white/60 font-medium">Dinheiro</span>
                </div>
                <span class="text-sm font-bold text-yellow-400">
                  {#if $currentCash >= 1000000}
                    R$ {($currentCash / 1000000).toFixed(1)}M
                  {:else if $currentCash >= 1000}
                    R$ {($currentCash / 1000).toFixed(1)}K
                  {:else}
                    R$ {$currentCash.toLocaleString()}
                  {/if}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Navigation -->
        <div class="flex-1 px-4 pb-4 overflow-y-auto">
          <div class="space-y-2">
            {#each navigationItems as item, index}
              <button
                class="nav-item w-full p-4 flex items-center space-x-4 text-left {$activeView === item.key ? 'active' : ''}"
                on:click={() => setActiveView(item.key)}
                style="animation-delay: {(index + 1) * 0.05}s"
              >
                <div class="icon-container {$activeView === item.key ? 'bg-gradient-to-br from-green-500/25 to-emerald-600/20 border border-green-400/30' : 'bg-white/5'} transition-smooth">
                  <i class="fas fa-{item.icon} {$activeView === item.key ? 'text-green-400' : 'text-white/70'} text-lg transition-smooth"></i>
                </div>
                <div class="flex-1">
                  <p class="font-semibold capitalize {$activeView === item.key ? 'text-white' : 'text-white/80'} transition-smooth">{$Locales[item.label] || item.label}</p>
                </div>
                {#if $activeView === item.key}
                  <div class="flex items-center space-x-1">
                    <div class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
                    <i class="fas fa-chevron-right text-green-400 text-xs"></i>
                  </div>
                {/if}
              </button>
            {/each}
          </div>
        </div>

        <!-- Close Button -->
        <div class="p-4 border-t border-white/10 bg-gradient-to-t from-black/20 to-transparent">
          <button
            class="w-full p-4 rounded-xl bg-gradient-to-r from-red-500/15 to-red-600/10 border-2 border-red-500/30 hover:bg-red-500/25 hover:border-red-500/50 transition-smooth flex items-center justify-center space-x-3 group shadow-medium hover:shadow-deep"
            on:click={() => {
              fetchNui("ps-banking:client:hideUI");
              visibility.set(false);
            }}
          >
            <div class="w-10 h-10 bg-red-500/20 rounded-lg flex items-center justify-center group-hover:bg-red-500/30 transition-smooth">
              <i class="fas fa-times text-red-400 text-lg group-hover:rotate-90 transition-smooth"></i>
            </div>
            <span class="text-red-400 font-bold text-lg group-hover:text-red-300 transition-smooth">{$Locales.close || 'Fechar'}</span>
          </button>
        </div>
      </div>

      <!-- Main Content Area -->
      <div class="flex-1 flex flex-col bg-gradient-to-br from-black/10 to-transparent bg-grid">
        <div class="flex-1 overflow-hidden relative">
          <!-- Decorative gradient overlay -->
          <div class="absolute inset-0 bg-gradient-to-br from-green-500/5 via-transparent to-emerald-500/5 pointer-events-none"></div>

          <div class="relative z-10 h-full">
            {#if $showOverview}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <OverviewPage />
              </div>
            {:else if $showBills}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <BillsPage />
              </div>
            {:else if $showHistory}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <HistoryPage />
              </div>
            {:else if $showHeav}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <HeavPage />
              </div>
            {:else if $showIndseat}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <IndseatPage />
              </div>
            {:else if $showStats}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <StatsPage />
              </div>
            {:else if $showAccounts}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <AccountsPage />
              </div>
            {:else if $showInvestments}
              <div in:fade={{ duration: 200 }} out:fade={{ duration: 100 }} class="h-full">
                <InvestmentsPage />
              </div>
            {/if}
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
