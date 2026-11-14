<script setup>
// Console panel: white card with a title row (title, description, optional action) and a body.
defineProps({ title: String, subtitle: String, flush: Boolean }) // flush = body without padding (tables, lists)
</script>

<template>
  <section class="overflow-hidden rounded-2xl border border-slate-200 bg-white">
    <div v-if="title || $slots.action" class="flex items-start justify-between gap-3 border-b border-slate-100 px-5 py-4">
      <div class="min-w-0">
        <h2 class="text-[15px] font-semibold text-slate-900">{{ title }}</h2>
        <p v-if="subtitle" class="mt-0.5 text-xs text-slate-500">{{ subtitle }}</p>
      </div>
      <div v-if="$slots.action" class="shrink-0"><slot name="action" /></div>
    </div>
    <div :class="!flush && 'p-5'"><slot /></div>
  </section>
</template>
