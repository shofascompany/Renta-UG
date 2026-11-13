<script setup>
import { computed } from 'vue'
import { timeAgo } from '@/utils/format'
import LogoMark from './LogoMark.vue'

// One notification: always titled "Renta UG", then who it's from (the stored title), then the message.
// Used for tenant notifications, the landlord/admin inbox and the landlord's preview.
const props = defineProps({
  notification: Object, // { title, body, read, createdAt }
  compact: Boolean,
  preview: Boolean, // landlord's "how it will look" preview: no time ago / unread state
})
defineEmits(['read'])

// Older notifications started with an emoji; keep the sender line clean
const sender = computed(() => (props.notification.title ?? '').replace(/^[\p{Extended_Pictographic}️\s]+/u, ''))
const unread = computed(() => !props.preview && !props.notification.read)
</script>

<template>
  <div
    class="flex gap-3.5 px-5 py-4 transition-colors"
    :class="unread ? 'cursor-pointer bg-brand-50/40 hover:bg-brand-50/70' : ''"
    @click="unread && $emit('read', notification.id)"
  >
    <LogoMark class="size-10 shrink-0 rounded-[10px] shadow-sm" />
    <div class="min-w-0 flex-1">
      <div class="flex items-baseline justify-between gap-3">
        <p class="text-sm font-semibold text-slate-900">Renta UG</p>
        <span class="flex shrink-0 items-center gap-2 text-xs text-slate-400">
          {{ preview ? 'now' : timeAgo(notification.createdAt) }}
          <span v-if="unread" class="size-2 rounded-full bg-brand-600" aria-label="Unread" />
        </span>
      </div>
      <p v-if="sender" class="mt-0.5 text-[13px] font-medium text-brand-700">{{ sender }}</p>
      <p class="mt-1.5 text-sm leading-relaxed whitespace-pre-line text-slate-600" :class="compact && 'line-clamp-2'">
        {{ notification.body }}
      </p>
    </div>
  </div>
</template>
