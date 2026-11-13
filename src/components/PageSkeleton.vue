<script setup>
// Placeholder layout shown while a page's data loads: header, stat cards, a list and a side card.
defineProps({ stats: { type: Number, default: 4 }, rows: { type: Number, default: 5 } })
</script>

<template>
  <div aria-busy="true" aria-label="Loading">
    <div class="mb-8 flex items-end justify-between gap-4">
      <div class="space-y-2">
        <div class="skeleton h-7 w-56" />
        <div class="skeleton h-4 w-72 max-w-full" />
      </div>
      <div class="skeleton hidden h-9 w-32 sm:block" />
    </div>

    <div v-if="stats" class="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
      <div v-for="i in stats" :key="i" class="card space-y-3 p-5">
        <div class="skeleton h-3.5 w-24" />
        <div class="skeleton h-7 w-32" />
        <div class="skeleton h-3 w-20" />
      </div>
    </div>

    <div class="grid gap-6 lg:grid-cols-3">
      <div class="card lg:col-span-2">
        <div class="border-b border-slate-100 px-5 py-4"><div class="skeleton h-4 w-40" /></div>
        <div class="divide-y divide-slate-100">
          <div v-for="i in rows" :key="i" class="flex items-center gap-4 px-5 py-4">
            <div class="skeleton size-9 shrink-0 rounded-full" />
            <div class="flex-1 space-y-2">
              <div class="skeleton h-3.5 w-2/5" />
              <div class="skeleton h-3 w-3/5" />
            </div>
            <div class="skeleton h-5 w-16 rounded-full" />
          </div>
        </div>
      </div>
      <div class="card space-y-3 p-5">
        <div class="skeleton h-4 w-28" />
        <div class="skeleton h-5 w-44" />
        <div class="skeleton h-3.5 w-36" />
        <div class="space-y-2 border-t border-slate-100 pt-4">
          <div v-for="i in 3" :key="i" class="flex justify-between">
            <div class="skeleton h-3.5 w-20" />
            <div class="skeleton h-3.5 w-24" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
