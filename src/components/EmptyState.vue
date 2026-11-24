<script setup>
import { computed } from 'vue'
import { Archive, BadgeCheck, Building2, CalendarClock, FileQuestion, Inbox, Megaphone, MessageCircle, SearchX, ShieldCheck, Users, Wallet } from '@lucide/vue'

// Shown where a list has nothing in it (or a page can't find what it was asked for).
//   kind     picks the icon; tone its colour     compact  smaller, for cards inside a page
//   to / action  an optional button               default slot: anything else under the text
const props = defineProps({
  title: { type: String, required: true },
  text: String,
  icon: [Object, Function],
  kind: { type: String, default: 'inbox' },
  compact: Boolean,
  to: [String, Object],
  action: String,
})
const KINDS = {
  inbox: [Inbox, 'slate'],
  money: [Wallet, 'brand'],
  people: [Users, 'brand'],
  places: [Building2, 'sky'],
  time: [CalendarClock, 'amber'],
  search: [SearchX, 'slate'],
  missing: [FileQuestion, 'amber'],
  archive: [Archive, 'sky'],
  messages: [MessageCircle, 'brand'],
  announce: [Megaphone, 'brand'],
  activity: [ShieldCheck, 'brand'],
  done: [BadgeCheck, 'emerald'],
}
const look = computed(() => KINDS[props.kind] ?? KINDS.inbox)
</script>

<template>
  <div class="flex flex-col items-center justify-center px-6 text-center" :class="compact ? 'py-8' : 'py-14'">
    <span class="es-halo" :class="[`es-${look[1]}`, compact && 'es-sm']"><component :is="icon ?? look[0]" :class="compact ? 'size-5' : 'size-6'" stroke-width="1.75" /></span>
    <p class="mt-4 font-semibold text-slate-900" :class="compact ? 'text-sm' : 'text-base'">{{ title }}</p>
    <p v-if="text" class="mt-1 max-w-xs text-sm leading-relaxed text-slate-500">{{ text }}</p>
    <RouterLink v-if="to && action" :to="to" class="btn-secondary mt-5 h-11 rounded-2xl px-5">{{ action }}</RouterLink>
    <slot />
  </div>
</template>

<style scoped>
/* A soft disc inside two fading rings */
.es-halo {
  --c: var(--color-slate-500);
  --b: var(--color-slate-100);
  display: flex;
  width: 3.5rem;
  height: 3.5rem;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  color: var(--c);
  background: var(--b);
  box-shadow: 0 0 0 0.45rem color-mix(in srgb, var(--b) 55%, transparent), 0 0 0 0.9rem color-mix(in srgb, var(--b) 25%, transparent);
  margin-block: 0.6rem 0.4rem;
}
.es-sm { width: 2.75rem; height: 2.75rem; box-shadow: 0 0 0 0.35rem color-mix(in srgb, var(--b) 55%, transparent), 0 0 0 0.7rem color-mix(in srgb, var(--b) 25%, transparent); }
.es-brand { --c: var(--color-brand-700); --b: var(--color-brand-50); }
.es-sky { --c: var(--color-sky-700); --b: var(--color-sky-50); }
.es-amber { --c: var(--color-amber-700); --b: var(--color-amber-50); }
.es-emerald { --c: var(--color-emerald-700); --b: var(--color-emerald-50); }
</style>
