<script setup>
import { computed } from 'vue'

const props = defineProps({ status: String })

const styles = {
  paid: 'bg-emerald-50 text-emerald-700 ring-emerald-600/15',
  occupied: 'bg-emerald-50 text-emerald-700 ring-emerald-600/15',
  active: 'bg-emerald-50 text-emerald-700 ring-emerald-600/15',
  suspended: 'bg-red-50 text-red-700 ring-red-600/15',
  former: 'bg-slate-50 text-slate-600 ring-slate-500/15',
  ended: 'bg-slate-50 text-slate-600 ring-slate-500/15',
  resolved: 'bg-slate-50 text-slate-600 ring-slate-500/15',
  pending: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  medium: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  open: 'bg-sky-50 text-sky-700 ring-sky-600/15',
  low: 'bg-sky-50 text-sky-700 ring-sky-600/15',
  vacant: 'bg-slate-50 text-slate-600 ring-slate-500/15',
  overdue: 'bg-red-50 text-red-700 ring-red-600/15',
  high: 'bg-red-50 text-red-700 ring-red-600/15',
}

const cls = computed(() => styles[props.status] ?? styles.vacant)
</script>

<template>
  <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize ring-1 ring-inset" :class="cls">
    {{ status }}
  </span>
</template>
