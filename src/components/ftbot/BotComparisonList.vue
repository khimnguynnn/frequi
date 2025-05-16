<script setup lang="ts">
import { useBotStore } from '@/stores/ftbotwrapper';
import type { ProfitInterface, ComparisonTableItems } from '@/types';
import { onMounted, watch, ref } from 'vue';
  
const botStore = useBotStore();
const loadedBots = ref<Set<string>>(new Set());

const allToggled = computed<boolean>({
  get: () => Object.values(botStore.botStores).every((i) => i.isSelected),
  set: (val) => {
    for (const botId in botStore.botStores) {
      botStore.botStores[botId].isSelected = val;
    }
  },
});

// Watch for changes in bot selection and load data only when selected
watch(
  () => Object.values(botStore.botStores).map(bot => bot.isSelected),
  async () => {
    // Only load data for selected bots
    for (const botId in botStore.botStores) {
      const bot = botStore.botStores[botId];
      if (bot.isSelected) {
        await bot.refreshSlow(true);
        // Mark this bot as having loaded data
        loadedBots.value.add(botId);
      }
    }
  },
  { deep: true }
);

onMounted(() => {
  Object.values(botStore.botStores).forEach((bot) => {
    bot.isSelected = false;
  });
});
  
const tableItems = computed<ComparisonTableItems[]>(() => {
  const val: ComparisonTableItems[] = [];
  const summary: ComparisonTableItems = {
    botId: undefined,
    botName: 'Summary',
    profitClosed: 0,
    profitClosedRatio: undefined,
    profitOpen: 0,
    profitOpenRatio: undefined,
    stakeCurrency: 'USDT',
    wins: 0,
    losses: 0,
  };

  // Add all bots to the table regardless of selection status
  Object.keys(botStore.botStores).forEach((k) => {
    const botItem: ComparisonTableItems = {
      botId: k,
      botName: botStore.availableBots[k].botName || botStore.availableBots[k].botId,
      trades: '-',
      profitClosed: 0,
      profitClosedRatio: 0,
      stakeCurrency: '',
      profitOpenRatio: 0,
      profitOpen: 0,
      wins: 0,
      losses: 0,
      isDryRun: botStore.allBotState[k]?.dry_run,
      isOnline: botStore.botStores[k]?.isBotOnline,
    };
    
    // Check if this bot has been loaded before
    if (loadedBots.value.has(k)) {
      const v = botStore.allProfit[k];
      if (v) {
        const allStakes = botStore.allOpenTrades[k].reduce((a, b) => a + b.stake_amount, 0);
        const profitOpenRatio = allStakes ? 
          botStore.allOpenTrades[k].reduce(
            (a, b) => a + (b.total_profit_ratio ?? b.profit_ratio) * b.stake_amount,
            0,
          ) / allStakes : 0;
        const profitOpen = botStore.allOpenTrades[k].reduce(
          (a, b) => a + (b.total_profit_abs ?? b.profit_abs ?? 0),
          0,
        );

        botItem.trades = `${botStore.allOpenTradeCount[k]} / ${
          botStore.allBotState[k]?.max_open_trades || 'N/A'
        }`;
        botItem.profitClosed = v.profit_closed_coin;
        botItem.profitClosedRatio = v.profit_closed_ratio || 0;
        botItem.stakeCurrency = botStore.allBotState[k]?.stake_currency || '';
        botItem.profitOpenRatio = profitOpenRatio;
        botItem.profitOpen = profitOpen;
        botItem.wins = v.winning_trades;
        botItem.losses = v.losing_trades;
        botItem.balance = botStore.allBalance[k]?.total_bot ?? botStore.allBalance[k]?.total;
        botItem.stakeCurrencyDecimals = botStore.allBotState[k]?.stake_currency_decimals || 3;

        // Only add to summary if currently selected
        if (v.profit_closed_coin !== undefined && botStore.botStores[k].isSelected) {
          summary.profitClosed += v.profit_closed_coin;
          summary.profitOpen += profitOpen;
          summary.wins += v.winning_trades;
          summary.losses += v.losing_trades;
          summary.stakeCurrency = botStore.allBotState[k]?.stake_currency || summary.stakeCurrency;
        }
      }
    }
    
    val.push(botItem);
  });
  
  val.push(summary);
  return val;
});

// Create a separate computed property to ensure summary is reactive to selection changes
const selectedBots = computed(() => 
  Object.keys(botStore.botStores).filter(botId => botStore.botStores[botId].isSelected)
);
</script>

<template>
  <DataTable size="small" :value="tableItems">
    <Column field="botName" header="Bot">
      <template #body="{ data, field }">
        <div class="flex flex-row justify-between items-center">
          <div>
            <BaseCheckbox
              v-if="data.botId && botStore.botCount > 1"
              v-model="
                botStore.botStores[(data as unknown as ComparisonTableItems).botId ?? ''].isSelected
              "
              title="Show this bot in Dashboard"
              >{{ data[field] }}</BaseCheckbox
            >
            <BaseCheckbox
              v-if="!data.botId && botStore.botCount > 1"
              v-model="allToggled"
              title="Toggle all bots"
              class="font-bold"
              >{{ data[field] }}</BaseCheckbox
            >
            <span v-if="botStore.botCount <= 1">{{ data[field] }}</span>
          </div>
          <Badge
            v-if="data.isOnline && data.isDryRun"
            class="items-center bg-green-800 text-slate-200"
            severity="success"
            >Dry</Badge
          >
          <Badge v-if="data.isOnline && !data.isDryRun" class="items-center" severity="warning"
            >Live</Badge
          >
          <Badge v-if="data.isOnline === false" class="items-center" severity="secondary"
            >Offline</Badge
          >
        </div>
      </template>
    </Column>
    <Column field="trades" header="Trades"> </Column>
    <Column header="Open Profit">
      <template #body="{ data }">
        <ProfitPill
          v-if="data.profitOpen && data.botId != 'Summary' && loadedBots.has(data.botId)"
          :profit-ratio="(data as unknown as ComparisonTableItems).profitOpenRatio"
          :profit-abs="(data as unknown as ComparisonTableItems).profitOpen"
          :profit-desc="`Total Profit (Open and realized) ${formatPercent(
            (data as ComparisonTableItems).profitOpenRatio ?? 0.0,
          )}`"
          :stake-currency="(data as unknown as ComparisonTableItems).stakeCurrency"
        />
        <ProfitPill
          v-if="data.botId === undefined && selectedBots.length > 0"
          :profit-ratio="undefined"
          :profit-abs="(data as unknown as ComparisonTableItems).profitOpen"
          :stake-currency="(data as unknown as ComparisonTableItems).stakeCurrency"
        />
      </template>
    </Column>
    <Column header="Closed Profit">
      <template #body="{ data }">
        <ProfitPill
          v-if="data.profitClosed && data.botId != 'Summary' && loadedBots.has(data.botId)"
          :profit-ratio="(data as ComparisonTableItems).profitClosedRatio"
          :profit-abs="(data as ComparisonTableItems).profitClosed"
          :stake-currency="(data as unknown as ComparisonTableItems).stakeCurrency"
        />
        <ProfitPill
          v-if="data.botId === undefined && selectedBots.length > 0"
          :profit-ratio="undefined"
          :profit-abs="(data as unknown as ComparisonTableItems).profitClosed"
          :stake-currency="(data as unknown as ComparisonTableItems).stakeCurrency"
        />
      </template>
    </Column>
    <Column field="balance" header="Balance">
      <template #body="{ data }">
        <div v-if="data.balance && loadedBots.has(data.botId)">
          <span :title="(data as ComparisonTableItems).stakeCurrency"
            >{{
              formatPrice(
                (data as ComparisonTableItems).balance ?? 0,
                (data as ComparisonTableItems).stakeCurrencyDecimals,
              )
            }}
          </span>
          <span class="text-sm">{{
            ` ${data.stakeCurrency}${data.isDryRun ? ' (dry)' : ''}`
          }}</span>
        </div>
      </template>
    </Column>
    <Column field="winVsLoss" header="W/L">
      <template #body="{ data }">
        <div v-if="data.losses !== undefined && (data.botId === undefined || loadedBots.has(data.botId))">
          <span class="text-profit">{{ data.wins }}</span> /
          <span class="text-loss">{{ data.losses }}</span>
        </div>
      </template>
    </Column>
  </DataTable>
</template>
