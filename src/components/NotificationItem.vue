<script setup>
import { computed } from 'vue'
import { Bell, CreditCard, Wrench, Megaphone, Hourglass } from '@lucide/vue'
import { timeAgo } from '@/utils/format'

const props = defineProps({ notification: Object, compact: Boolean })
defineEmits(['read'])

const icons = { payment: CreditCard, maintenance: Wrench, general: Megaphone, reminder: Hourglass }
const icon = computed(() => icons[props.notification.type] ?? Bell)
</script>

<template>
  <div
    class="flex gap-3 px-5 py-4 transition-colors"
    :class="notification.read ? '' : 'cursor-pointer bg-brand-50/40 hover:bg-brand-50/70'"
    @click="!notification.read && $emit('read', notification.id)"
  >
    <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-slate-50">
      <component :is="icon" class="size-4 text-slate-500" />
    </div>
    <div class="min-w-0 flex-1">
      <div class="flex items-start justify-between gap-3">
        <p class="text-sm font-medium text-slate-900">{{ notification.title }}</p>
        <span class="shrink-0 text-xs text-slate-400">{{ timeAgo(notification.createdAt) }}</span>
      </div>
      <p class="mt-0.5 text-sm text-slate-600" :class="compact && 'line-clamp-1'">{{ notification.body }}</p>
    </div>
    <span v-if="!notification.read" class="mt-1.5 size-2 shrink-0 rounded-full bg-brand-600" aria-label="Unread" />
  </div>
</template>
