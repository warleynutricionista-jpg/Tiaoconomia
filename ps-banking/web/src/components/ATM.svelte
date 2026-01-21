<script lang="ts">
  import { writable } from "svelte/store";
  import { onMount } from "svelte";
  import { fetchNui } from "../utils/fetchNui";
  import { fade } from "svelte/transition";
  import { quintOut } from "svelte/easing";
  import {
    showATM,
    currentCash,
    bankBalance,
    Notify,
    type Notification,
    Locales,
    Currency,
  } from "../store/data";

  let withdrawAmounts = writable([]);
  let depositAmounts = writable([]);
  let gridColsPreset = writable(3);
  let customWithdraw = writable(0);
  let customDeposit = writable(0);
  let transferAmount = writable(0);
  let transferTarget = writable("");
  let transferMethod = writable("id");
  let phoneTransferEnabled = false;
  let recentTransactions = writable([]);

  // Initialize custom amounts but don't auto-update them
  $: if ($customDeposit === 0) customDeposit.set($currentCash);
  // Remove auto-update for customWithdraw to prevent showing wrong balance after withdrawal

  async function getAmountPresets() {
    try {
      const response = await fetchNui("ps-banking:client:getAmountPresets", {});
      const amounts = JSON.parse(response);
      withdrawAmounts.set(amounts.withdrawAmounts);
      depositAmounts.set(amounts.depositAmounts);
      gridColsPreset.set(amounts.grid);
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

  async function heav(amount: number) {
    try {
      if (amount <= 0 || amount > $bankBalance) return;
      
      const response = await fetchNui("ps-banking:client:ATMwithdraw", {
        amount: amount,
      });
      
      if (response) {
        // Only update balances if transaction was successful
        // Update balances from server to ensure accuracy
        await updateBalances();
        
        // Reset custom amount
        customWithdraw.set(0);
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function deposit(amount: number) {
    try {
      if (amount <= 0 || amount > $currentCash) return;
      
      const response = await fetchNui("ps-banking:client:ATMdeposit", {
        amount: amount,
      });
      
      if (response) {
        // Only update balances if transaction was successful
        // Update balances from server to ensure accuracy
        await updateBalances();
        
        // Reset custom amount
        customDeposit.set(0);
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function getRecentTransactions() {
    try {
      const response = await fetchNui("ps-banking:client:getHistory", {});
      if (Array.isArray(response)) {
        recentTransactions.set(response.slice(0, 5));
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function sendTransfer() {
    if (!$transferTarget || $transferAmount <= 0) return;
    try {
      const response = await fetchNui("ps-banking:client:transferMoney", {
        id: $transferTarget,
        amount: $transferAmount,
        method: $transferMethod,
      });

      if (response?.success) {
        Notify(response.message, $Locales.payment_completed, "user");
        transferAmount.set(0);
        transferTarget.set("");
        await updateBalances();
        await getRecentTransactions();
      } else {
        Notify(response?.message || $Locales.error, $Locales.error, "user");
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function getLocales() {
    try {
      const response = await fetchNui("ps-banking:client:getLocales", {});
      Locales.set(response);
    } catch (error) {
      console.error(error);
    }
  }

  function closeATM() {
    showATM.set(false);
    fetchNui("ps-banking:client:hideUI");
  }

  // Handle escape key
  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      closeATM();
    }
  }

  onMount(() => {
    getAmountPresets();
    getLocales();
    updateBalances();
    getRecentTransactions();
    fetchNui("ps-banking:client:phoneOption", {}).then((enabled) => {
      phoneTransferEnabled = enabled;
      if (!enabled) {
        transferMethod.set("id");
      }
    });
    window.addEventListener('keydown', handleKeydown);
    return () => {
      window.removeEventListener('keydown', handleKeydown);
    };
  });
</script>

<svelte:window on:keydown={handleKeydown}/>

{#if $showATM}
  <div class="fixed inset-0 z-50">
    <div class="absolute w-screen h-screen flex items-center justify-center">
      <div
        class="w-[760px] modern-card overflow-hidden"
        in:fade={{ duration: 200 }}
        out:fade={{ duration: 150 }}
      >
        <!-- Header -->
        <div class="p-4 border-b border-white/10 flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div class="w-10 h-10 bg-indigo-500 rounded-xl flex items-center justify-center">
              <i class="fas fa-credit-card text-white text-lg"></i>
            </div>
            <div>
              <h1 class="text-lg font-semibold text-white">{$Locales.atm}</h1>
              <p class="text-sm text-white/50">{$Locales.quick_management}</p>
            </div>
          </div>
          <button
            class="w-8 h-8 flex items-center justify-center rounded-lg bg-white/5 hover:bg-white/10 transition-colors text-white/50 hover:text-white/80"
            on:click={closeATM}
          >
            <i class="fas fa-times text-lg"></i>
          </button>
        </div>

        <div class="p-5 space-y-6">
          <!-- Balance Cards -->
          <div class="grid grid-cols-3 gap-4">
            <div class="bg-black/20 border border-white/10 rounded-lg p-4">
              <div class="flex items-center space-x-2 mb-1">
                <i class="fas fa-wallet text-green-400 text-lg"></i>
                <span class="text-white/80">{$Locales.cash}</span>
              </div>
              <p class="text-xl font-bold text-white">
                R$ {$currentCash.toLocaleString()}
              </p>
            </div>

            <div class="bg-black/20 border border-white/10 rounded-lg p-4">
              <div class="flex items-center space-x-2 mb-1">
                <i class="fas fa-university text-blue-400 text-lg"></i>
                <span class="text-white/80">{$Locales.bank_balance}</span>
              </div>
              <p class="text-xl font-bold text-white">
                R$ {$bankBalance.toLocaleString()}
              </p>
            </div>

            <div class="bg-black/20 border border-white/10 rounded-lg p-4">
              <div class="flex items-center space-x-2 mb-1">
                <i class="fas fa-signal text-indigo-400 text-lg"></i>
                <span class="text-white/80">{$Locales.transfer}</span>
              </div>
              <p class="text-sm text-white/60">
                {$Locales.atm_transfer_tip || "Envie transferências rápidas."}
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div class="space-y-4">
              <!-- Quick Actions -->
              <div class="bg-black/20 border border-white/10 rounded-lg p-4">
                <div class="flex items-center justify-between mb-3">
                  <div class="flex items-center space-x-2">
                    <i class="fas fa-arrow-down text-red-400"></i>
                    <span class="text-white/80">{$Locales.withdraw}</span>
                  </div>
                  <span class="text-xs text-white/50">{$Locales.quick_amounts || "Valores rápidos"}</span>
                </div>
                <div class="grid grid-cols-3 gap-2">
                  {#each $withdrawAmounts as amount}
                    <button
                      class="bg-black/30 border border-white/10 hover:bg-white/5 transition-colors rounded-lg p-2 text-center group relative overflow-hidden"
                      on:click={() => heav(amount)}
                    >
                      <div class="absolute inset-0 bg-red-500/10 opacity-0 group-hover:opacity-100 transition-opacity"></div>
                      <span class="text-white/80 text-sm">R$ {amount.toLocaleString()}</span>
                    </button>
                  {/each}
                </div>
                <div class="flex space-x-2 mt-3">
                  <input
                    id="atm-withdraw"
                    type="number"
                    bind:value={$customWithdraw}
                    class="w-full bg-black/30 text-white px-3 py-2 rounded-lg border border-white/10 focus:outline-none focus:border-white/20 focus:ring-1 focus:ring-red-500/20"
                    placeholder={$Locales.enter_amount}
                    min="0"
                    max={$bankBalance}
                  />
                  <button
                    class="px-4 py-2 bg-red-500/20 hover:bg-red-500/30 transition-colors rounded-lg text-white min-w-[110px]"
                    on:click={() => heav($customWithdraw)}
                    disabled={$customWithdraw <= 0 || $customWithdraw > $bankBalance}
                  >
                    {$Locales.submit}
                  </button>
                </div>
              </div>

              <div class="bg-black/20 border border-white/10 rounded-lg p-4">
                <div class="flex items-center justify-between mb-3">
                  <div class="flex items-center space-x-2">
                    <i class="fas fa-arrow-up text-green-400"></i>
                    <span class="text-white/80">{$Locales.deposit_money}</span>
                  </div>
                  <span class="text-xs text-white/50">{$Locales.quick_amounts || "Valores rápidos"}</span>
                </div>
                <div class="grid grid-cols-3 gap-2">
                  {#each $depositAmounts as amount}
                    <button
                      class="bg-black/30 border border-white/10 hover:bg-white/5 transition-colors rounded-lg p-2 text-center group relative overflow-hidden"
                      on:click={() => deposit(amount)}
                    >
                      <div class="absolute inset-0 bg-green-500/10 opacity-0 group-hover:opacity-100 transition-opacity"></div>
                      <span class="text-white/80 text-sm">R$ {amount.toLocaleString()}</span>
                    </button>
                  {/each}
                </div>
                <div class="flex space-x-2 mt-3">
                  <input
                    id="atm-deposit"
                    type="number"
                    bind:value={$customDeposit}
                    class="w-full bg-black/30 text-white px-3 py-2 rounded-lg border border-white/10 focus:outline-none focus:border-white/20 focus:ring-1 focus:ring-green-500/20"
                    placeholder={$Locales.enter_amount}
                    min="0"
                    max={$currentCash}
                  />
                  <button
                    class="px-4 py-2 bg-green-500/20 hover:bg-green-500/30 transition-colors rounded-lg text-white min-w-[110px]"
                    on:click={() => deposit($customDeposit)}
                    disabled={$customDeposit <= 0 || $customDeposit > $currentCash}
                  >
                    {$Locales.submit}
                  </button>
                </div>
              </div>
            </div>

            <div class="space-y-4">
              <div class="bg-black/20 border border-white/10 rounded-lg p-4">
                <div class="flex items-center space-x-2 mb-3">
                  <i class="fas fa-paper-plane text-indigo-400"></i>
                  <span class="text-white/80">{$Locales.transfer}</span>
                </div>
                <div class="space-y-3">
                  <div class="flex items-center gap-2">
                    <label class="text-xs text-white/50" for="atm-transfer-target">
                      {$Locales.transfer_target || "Destino"}
                    </label>
                    {#if phoneTransferEnabled}
                      <select
                        class="ml-auto bg-black/30 text-white text-xs px-2 py-1 rounded-lg border border-white/10"
                        bind:value={$transferMethod}
                      >
                        <option value="id">ID</option>
                        <option value="phone">Telefone</option>
                      </select>
                    {/if}
                  </div>
                  <input
                    id="atm-transfer-target"
                    type="text"
                    class="w-full bg-black/30 text-white px-3 py-2 rounded-lg border border-white/10 focus:outline-none focus:border-white/20"
                    placeholder={$Locales.enter_recipient || "Digite o ID ou telefone"}
                    bind:value={$transferTarget}
                  />
                  <input
                    id="atm-transfer-amount"
                    type="number"
                    min="1"
                    class="w-full bg-black/30 text-white px-3 py-2 rounded-lg border border-white/10 focus:outline-none focus:border-white/20"
                    placeholder={$Locales.transfer_amount || "Valor da transferência"}
                    bind:value={$transferAmount}
                  />
                  <button
                    class="w-full px-4 py-2 bg-indigo-500/20 hover:bg-indigo-500/30 transition-colors rounded-lg text-white"
                    on:click={sendTransfer}
                    disabled={!$transferTarget || $transferAmount <= 0}
                  >
                    {$Locales.send_transfer || "Enviar transferência"}
                  </button>
                </div>
              </div>

              <div class="bg-black/20 border border-white/10 rounded-lg p-4">
                <div class="flex items-center justify-between mb-3">
                  <div class="flex items-center space-x-2">
                    <i class="fas fa-clock-rotate-left text-yellow-400"></i>
                    <span class="text-white/80">{$Locales.recent_transactions || "Últimas movimentações"}</span>
                  </div>
                  <button
                    class="text-xs text-white/50 hover:text-white"
                    on:click={getRecentTransactions}
                  >
                    {$Locales.refresh || "Atualizar"}
                  </button>
                </div>
                <div class="space-y-2 max-h-44 overflow-y-auto pr-1">
                  {#if $recentTransactions.length}
                    {#each $recentTransactions as transaction}
                      <div class="flex items-center justify-between bg-black/30 rounded-lg px-3 py-2 text-xs">
                        <div>
                          <p class="text-white/80">{transaction.description}</p>
                          <p class="text-white/40">{transaction.date}</p>
                        </div>
                        <span class={transaction.isIncome ? "text-green-400" : "text-red-400"}>
                          {transaction.isIncome ? "+" : "-"}R$ {transaction.amount.toLocaleString()}
                        </span>
                      </div>
                    {/each}
                  {:else}
                    <p class="text-xs text-white/50">{$Locales.no_recent_transactions || "Nenhuma transação recente."}</p>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
{/if}
