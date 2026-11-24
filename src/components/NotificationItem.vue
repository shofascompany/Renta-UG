<script setup>
import { computed } from 'vue'
import { timeAgo } from '@/utils/format'
import LogoMark from './LogoMark.vue'

// The landlord's preview of a notice: always titled "Renta UG", then who it's from (the stored title),
// then the message, exactly as the tenant will see it.
const props = defineProps({
  notification: Object, // { title, body, read, createdAt }
  compact: Boolean,
  preview: Boolean, // "how it will look": no time ago / unread state
})
defineEmits(['read'])

// Older notifications started with an emoji; keep the sender line clean
const sender = computed(() => (props.notification.title ?? '').replace(/^[\p{Extended_Pictographic}️\s]+/u, ''))
const unread = computed(() => !props.preview && !props.notification.read)
</script>

<template>
  <div class="nt-row" :class="unread && 'nt-unread cursor-pointer'" @click="unread && $emit('read', notification.id)">
    <LogoMark class="size-10 shrink-0 rounded-[0.85rem] shadow-sm" />
    <div class="min-w-0 flex-1">
      <div class="flex items-baseline justify-between gap-3">
        <p class="text-sm font-semibold text-slate-900">Renta UG</p>
        <span class="nt-time flex shrink-0 items-center gap-2">
          {{ preview ? 'now' : timeAgo(notification.createdAt) }}
          <span v-if="unread" class="nt-dot" aria-label="Unread" />
        </span>
      </div>
      <p v-if="sender" class="mt-0.5 text-[13px] font-semibold text-brand-700">{{ sender }}</p>
      <p class="mt-1 text-sm leading-relaxed whitespace-pre-line text-slate-600" :class="compact && 'line-clamp-2'">{{ notification.body }}</p>
    </div>
  </div>
</template>
