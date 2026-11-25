<script setup>
import { computed, ref } from 'vue'
import { RefreshCw, TriangleAlert } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'

// Main admin: where the numbers on this page come from, and how fresh they are. Never a saved copy: if the
// database could not be read, it says so and shows when it last was.
const rental = useRentalStore()
const busy = ref(false)
async function refresh() {
  busy.value = true
  await rental.refresh()
  busy.value = false
}
const time = computed(() => (rental.updatedAt ? new Date(rental.updatedAt).toLocaleTimeString('en-GB') : ''))
const state = computed(() =>
  rental.refreshError ? { cls: 'off', text: `Not updated since ${time.value}. ${rental.refreshError}` }
  : rental.live ? { cls: 'on', text: `Live from the database · ${time.value}` }
  : { cls: 'wait', text: `From the database · ${time.value}` },
)
</script>

<template>
  <div class="mb-4">
    <div class="flex items-center gap-2.5 rounded-2xl border border-slate-200 bg-white py-1.5 pr-1.5 pl-4 text-xs text-slate-600" role="status">
      <span class="dot" :class="state.cls" />
      <span class="min-w-0 flex-1 tabular-nums">{{ state.text }}</span>
      <button type="button" class="flex h-9 shrink-0 items-center gap-1.5 rounded-xl px-3 font-semibold text-brand-700 hover:bg-slate-50" :disabled="busy" @click="refresh"><RefreshCw class="size-3.5" :class="busy && 'animate-spin'" /> Refresh</button>
    </div>
    <p v-if="rental.unavailable.length" class="mt-2 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
      <TriangleAlert class="mt-0.5 size-4 shrink-0" />
      <span>Some figures are not complete: {{ rental.unavailable.join(', ') }} could not be read. Run <strong>database/update_existing.sql</strong> in Supabase → SQL Editor if it was never run, then refresh.</span>
    </p>
  </div>
</template>

<style scoped>
.dot { width: 0.55rem; height: 0.55rem; flex-shrink: 0; border-radius: 9999px; }
.on { background: #22c55e; box-shadow: 0 0 0 4px rgb(34 197 94 / 0.18); }
.wait { background: #0ea5e9; }
.off { background: #f59e0b; }
</style>
