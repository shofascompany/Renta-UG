<script setup>
import { ChevronRight } from '@lucide/vue'

// One tappable row: icon · title + subtitle · value on the right · chevron.
// Pass `to` for a link, or listen to @click for a button. Roomy on phones, tighter on computers.
defineProps({
  to: { type: [String, Object], default: null },
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  value: { type: String, default: '' },
  valueSub: { type: String, default: '' },
  valueClass: { type: String, default: 'text-slate-900' },
  chevron: { type: Boolean, default: true },
})
defineEmits(['click'])
</script>

<template>
  <li>
    <component
      :is="to ? 'RouterLink' : 'button'"
      :to="to || undefined"
      :type="to ? undefined : 'button'"
      class="group flex w-full items-center gap-3.5 px-4 py-4 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:px-5 lg:py-3.5"
      @click="$emit('click', $event)"
    >
      <slot name="icon" />
      <div class="min-w-0 flex-1">
        <p class="truncate font-medium text-slate-900"><slot name="title">{{ title }}</slot></p>
        <p v-if="subtitle || $slots.subtitle" class="mt-0.5 truncate text-xs text-slate-500"><slot name="subtitle">{{ subtitle }}</slot></p>
        <slot name="below" />
      </div>
      <div v-if="value || $slots.value" class="shrink-0 text-right">
        <slot name="value">
          <p class="text-sm font-semibold tabular-nums" :class="valueClass">{{ value }}</p>
          <p v-if="valueSub" class="mt-0.5 text-[11px] text-slate-500">{{ valueSub }}</p>
        </slot>
      </div>
      <ChevronRight v-if="chevron" class="size-4 shrink-0 text-slate-300 transition group-hover:translate-x-0.5 group-hover:text-slate-500" />
    </component>
  </li>
</template>
