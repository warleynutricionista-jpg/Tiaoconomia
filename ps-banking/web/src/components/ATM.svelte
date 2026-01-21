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
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
    <!-- ATM Machine Frame -->
    <div
      class="relative w-[550px] bg-gradient-to-b from-gray-800 via-gray-900 to-black rounded-3xl shadow-2xl border-8 border-gray-700"
      in:fade={{ duration: 200 }}
      out:fade={{ duration: 150 }}
      style="box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5), inset 0 2px 4px rgba(255, 255, 255, 0.1);"
    >
      <!-- ATM Header with Bank Branding -->
      <div class="bg-gradient-to-r from-blue-600 via-blue-500 to-cyan-500 rounded-t-2xl p-4 flex items-center justify-between border-b-4 border-blue-700">
        <div class="flex items-center space-x-3">
          <div class="w-12 h-12 bg-white rounded-xl flex items-center justify-center shadow-lg">
            <i class="fas fa-university text-blue-600 text-xl"></i>
          </div>
          <div>
            <h1 class="text-xl font-bold text-white tracking-wide">CAIXA ELETRÔNICO</h1>
            <p class="text-xs text-blue-100">Banco Painel Financeiro</p>
          </div>
        </div>
        <button
          class="w-10 h-10 flex items-center justify-center rounded-lg bg-white/20 hover:bg-white/30 transition-all hover:rotate-90 duration-300 text-white shadow-lg"
          on:click={closeATM}
        >
          <i class="fas fa-times text-xl"></i>
        </button>
      </div>

      <!-- LCD Screen -->
      <div class="bg-gradient-to-b from-gray-900 to-black p-6">
        <div class="bg-gradient-to-b from-green-950/40 to-black border-4 border-gray-700 rounded-xl p-5 shadow-inner" style="box-shadow: inset 0 4px 8px rgba(0,0,0,0.5);">
          <!-- Screen Content -->
          <div class="space-y-4 max-h-[500px] overflow-y-auto pr-2 scrollbar-thin scrollbar-thumb-green-500/50 scrollbar-track-gray-800">

            <!-- Balance Display -->
            <div class="bg-gradient-to-r from-green-900/40 to-blue-900/40 border-2 border-green-500/30 rounded-lg p-4 shadow-lg">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <div class="flex items-center space-x-2 mb-2">
                    <i class="fas fa-wallet text-green-400 text-xl"></i>
                    <span class="text-green-300 font-semibold text-sm">{$Locales.cash}</span>
                  </div>
                  <p class="text-2xl font-bold text-green-400 font-mono">
                    R$ {$currentCash.toLocaleString()}
                  </p>
                </div>
                <div>
                  <div class="flex items-center space-x-2 mb-2">
                    <i class="fas fa-building-columns text-cyan-400 text-xl"></i>
                    <span class="text-cyan-300 font-semibold text-sm">{$Locales.bank_balance}</span>
                  </div>
                  <p class="text-2xl font-bold text-cyan-400 font-mono">
                    R$ {$bankBalance.toLocaleString()}
                  </p>
                </div>
              </div>
            </div>

            <!-- Main Menu Options -->
            <div class="grid grid-cols-2 gap-3">
              <!-- Withdraw Section -->
              <div class="bg-gradient-to-br from-red-900/30 to-red-950/30 border-2 border-red-500/40 rounded-lg p-4 shadow-lg">
                <div class="flex items-center space-x-2 mb-3">
                  <i class="fas fa-hand-holding-dollar text-red-400 text-lg"></i>
                  <span class="text-red-300 font-bold text-sm">{$Locales.withdraw}</span>
                </div>
                <div class="space-y-2">
                  {#each $withdrawAmounts as amount}
                    <button
                      class="w-full bg-black/50 border-2 border-red-500/50 hover:bg-red-500/30 hover:border-red-400 transition-all rounded-lg py-2 text-center group shadow-md hover:shadow-red-500/20 hover:scale-105 duration-200"
                      on:click={() => heav(amount)}
                    >
                      <span class="text-red-300 font-bold font-mono">R$ {amount.toLocaleString()}</span>
                    </button>
                  {/each}
                  <div class="flex gap-2 mt-3">
                    <input
                      id="atm-withdraw"
                      type="number"
                      bind:value={$customWithdraw}
                      class="flex-1 bg-black/70 text-green-300 px-3 py-2 rounded-lg border-2 border-red-500/50 focus:outline-none focus:border-red-400 font-mono placeholder-gray-500"
                      placeholder="Outro valor"
                      min="0"
                      max={$bankBalance}
                    />
                    <button
                      class="px-3 py-2 bg-red-500/30 hover:bg-red-500/50 border-2 border-red-400 transition-all rounded-lg text-red-300 font-bold hover:scale-105 duration-200"
                      on:click={() => heav($customWithdraw)}
                      disabled={$customWithdraw <= 0 || $customWithdraw > $bankBalance}
                    >
                      <i class="fas fa-check"></i>
                    </button>
                  </div>
                </div>
              </div>

              <!-- Deposit Section -->
              <div class="bg-gradient-to-br from-green-900/30 to-green-950/30 border-2 border-green-500/40 rounded-lg p-4 shadow-lg">
                <div class="flex items-center space-x-2 mb-3">
                  <i class="fas fa-money-bill-transfer text-green-400 text-lg"></i>
                  <span class="text-green-300 font-bold text-sm">{$Locales.deposit_money}</span>
                </div>
                <div class="space-y-2">
                  {#each $depositAmounts as amount}
                    <button
                      class="w-full bg-black/50 border-2 border-green-500/50 hover:bg-green-500/30 hover:border-green-400 transition-all rounded-lg py-2 text-center group shadow-md hover:shadow-green-500/20 hover:scale-105 duration-200"
                      on:click={() => deposit(amount)}
                    >
                      <span class="text-green-300 font-bold font-mono">R$ {amount.toLocaleString()}</span>
                    </button>
                  {/each}
                  <div class="flex gap-2 mt-3">
                    <input
                      id="atm-deposit"
                      type="number"
                      bind:value={$customDeposit}
                      class="flex-1 bg-black/70 text-green-300 px-3 py-2 rounded-lg border-2 border-green-500/50 focus:outline-none focus:border-green-400 font-mono placeholder-gray-500"
                      placeholder="Outro valor"
                      min="0"
                      max={$currentCash}
                    />
                    <button
                      class="px-3 py-2 bg-green-500/30 hover:bg-green-500/50 border-2 border-green-400 transition-all rounded-lg text-green-300 font-bold hover:scale-105 duration-200"
                      on:click={() => deposit($customDeposit)}
                      disabled={$customDeposit <= 0 || $customDeposit > $currentCash}
                    >
                      <i class="fas fa-check"></i>
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Transfer Section -->
            <div class="bg-gradient-to-br from-blue-900/30 to-purple-900/30 border-2 border-blue-500/40 rounded-lg p-4 shadow-lg">
              <div class="flex items-center space-x-2 mb-3">
                <i class="fas fa-paper-plane text-blue-400 text-lg"></i>
                <span class="text-blue-300 font-bold">{$Locales.transfer}</span>
              </div>
              <div class="space-y-3">
                <div class="flex items-center gap-2">
                  <label class="text-xs text-blue-200 font-semibold" for="atm-transfer-target">
                    {$Locales.transfer_target || "Destino"}
                  </label>
                  {#if phoneTransferEnabled}
                    <select
                      class="ml-auto bg-black/70 text-blue-300 text-xs px-3 py-1 rounded-lg border-2 border-blue-500/50 focus:outline-none focus:border-blue-400"
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
                  class="w-full bg-black/70 text-green-300 px-3 py-2 rounded-lg border-2 border-blue-500/50 focus:outline-none focus:border-blue-400 font-mono placeholder-gray-500"
                  placeholder={$Locales.enter_recipient || "Digite o ID ou telefone"}
                  bind:value={$transferTarget}
                />
                <input
                  id="atm-transfer-amount"
                  type="number"
                  min="1"
                  class="w-full bg-black/70 text-green-300 px-3 py-2 rounded-lg border-2 border-blue-500/50 focus:outline-none focus:border-blue-400 font-mono placeholder-gray-500"
                  placeholder={$Locales.transfer_amount || "Valor da transferência"}
                  bind:value={$transferAmount}
                />
                <button
                  class="w-full px-4 py-3 bg-blue-500/30 hover:bg-blue-500/50 border-2 border-blue-400 transition-all rounded-lg text-blue-300 font-bold hover:scale-105 duration-200 shadow-md hover:shadow-blue-500/20"
                  on:click={sendTransfer}
                  disabled={!$transferTarget || $transferAmount <= 0}
                >
                  <i class="fas fa-paper-plane mr-2"></i>
                  {$Locales.send_transfer || "Enviar transferência"}
                </button>
              </div>
            </div>

            <!-- Recent Transactions -->
            <div class="bg-gradient-to-br from-yellow-900/30 to-orange-900/30 border-2 border-yellow-500/40 rounded-lg p-4 shadow-lg">
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center space-x-2">
                  <i class="fas fa-receipt text-yellow-400 text-lg"></i>
                  <span class="text-yellow-300 font-bold">{$Locales.recent_transactions || "Últimas movimentações"}</span>
                </div>
                <button
                  class="text-xs text-yellow-300 hover:text-yellow-200 bg-black/40 px-2 py-1 rounded border border-yellow-500/50 hover:border-yellow-400 transition-all"
                  on:click={getRecentTransactions}
                >
                  <i class="fas fa-rotate-right mr-1"></i>
                  {$Locales.refresh || "Atualizar"}
                </button>
              </div>
              <div class="space-y-2 max-h-32 overflow-y-auto pr-1">
                {#if $recentTransactions.length}
                  {#each $recentTransactions as transaction}
                    <div class="flex items-center justify-between bg-black/50 border border-yellow-500/30 rounded-lg px-3 py-2">
                      <div>
                        <p class="text-yellow-200 text-xs font-semibold">{transaction.description}</p>
                        <p class="text-yellow-400/60 text-xs">{transaction.date}</p>
                      </div>
                      <span class={`font-bold font-mono text-sm ${transaction.isIncome ? "text-green-400" : "text-red-400"}`}>
                        {transaction.isIncome ? "+" : "-"}R$ {transaction.amount.toLocaleString()}
                      </span>
                    </div>
                  {/each}
                {:else}
                  <p class="text-xs text-yellow-400/60 text-center py-2">{$Locales.no_recent_transactions || "Nenhuma transação recente."}</p>
                {/if}
              </div>
            </div>

          </div>
        </div>
      </div>

      <!-- ATM Footer with Instructions -->
      <div class="bg-gradient-to-r from-gray-800 via-gray-700 to-gray-800 rounded-b-2xl p-3 border-t-4 border-gray-600">
        <div class="flex items-center justify-center space-x-6 text-xs text-gray-300">
          <div class="flex items-center space-x-2">
            <div class="w-6 h-6 bg-green-500 rounded-full animate-pulse"></div>
            <span>ONLINE</span>
          </div>
          <div class="flex items-center space-x-2">
            <i class="fas fa-shield-halved text-blue-400"></i>
            <span>CONEXÃO SEGURA</span>
          </div>
          <div class="flex items-center space-x-2">
            <i class="fas fa-keyboard text-yellow-400"></i>
            <span>Pressione ESC para sair</span>
          </div>
        </div>
      </div>

      <!-- Decorative Card Slot -->
      <div class="absolute -right-4 top-32 w-16 h-3 bg-gray-800 border-2 border-gray-600 rounded-r-lg shadow-inner"></div>

      <!-- Decorative Cash Dispenser -->
      <div class="absolute -bottom-2 left-1/2 transform -translate-x-1/2 w-48 h-4 bg-gradient-to-b from-gray-700 to-gray-900 border-2 border-gray-600 rounded-b-xl shadow-lg"></div>
    </div>
  </div>
{/if}
