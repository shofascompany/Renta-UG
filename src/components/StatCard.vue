<script setup>
defineProps({
  label: String,
  value: [String, Number],
  hint: String,
  icon: [Object, Function],
  tone: { type: String, default: 'default' }, // default | warn | danger
})
</script>

<template>
  <div class="card p-5">
    <div class="flex items-center justify-between">
      <p class="text-sm text-slate-500">{{ label }}</p>
      <component :is="icon" v-if="icon" class="size-4 text-slate-400" />
    </div>
    <p
      class="mt-2 text-2xl font-semibold tracking-tight"
      :class="{ 'text-slate-900': tone === 'default', 'text-amber-600': tone === 'warn', 'text-red-600': tone === 'danger' }"
    >
      {{ value }}
    </p>
    <p v-if="hint" class="mt-1 text-xs text-slate-500">{{ hint }}</p>
  </div>
</template>
