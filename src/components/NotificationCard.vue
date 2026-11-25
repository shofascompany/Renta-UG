<script setup>
import { computed, ref } from 'vue'
import { CalendarClock, Check, ChevronRight, Copy, Tag, Trash2, UserRound, Users, X } from '@lucide/vue'
import { copyText } from '@/lib/clipboard'
import BaseModal from './BaseModal.vue'

// The details of one notification, in a card: what it is, who it is from, when, the whole message, who got it.
//   item    { title, body, createdAt, recipients?: [{ name, read }] }, or null = closed
//   look    { label, icon, tone }      tone: emerald | amber | red | sky | brand | slate
const props = defineProps({
  item: { type: Object, default: null },
  look: { type: Object, default: () => ({}) },
  from: { type: String, default: '' },
  openLabel: { type: String, default: '' }, // text of the "go there" button (none = no button)
  canDelete: Boolean,
})
const emit = defineEmits(['close', 'open', 'delete'])

const open = computed({ get: () => Boolean(props.item), set: (v) => !v && emit('close') })
const date = computed(() =>
  props.item ? new Date(props.item.createdAt).toLocaleString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true }) : '',
)
const copied = ref(false)
async function copy() {
  if (!(await copyText(`${props.from || 'Renta UG'}\n\n${props.item.body}\n\n${date.value}`))) return
  copied.value = true
  setTimeout(() => (copied.value = false), 2000)
}
</script>

<template>
  <BaseModal v-model="open" center bare width="max-w-md" :title="look.label || 'Notification'">
    <div v-if="item" class="nc -m-5" :class="`nc-${look.tone ?? 'brand'}`">
      <header class="nc-head relative px-6 pt-6 pb-7">
        <button type="button" class="absolute top-4 right-4 flex size-9 items-center justify-center rounded-full bg-white/20 transition hover:bg-white/30" aria-label="Close" @click="open = false"><X class="size-4.5" /></button>
        <span class="flex size-12 items-center justify-center rounded-2xl bg-white/20 ring-1 ring-white/30"><component :is="look.icon" class="size-6" /></span>
        <p class="mt-4 text-xs font-semibold tracking-[0.14em] uppercase opacity-85">{{ look.label }}</p>
        <h2 class="mt-0.5 pr-10 text-xl leading-snug font-bold">{{ from || 'Renta UG' }}</h2>
      </header>

      <div class="px-6 pt-5 pb-6">
        <p class="rounded-2xl bg-slate-50 p-4 text-[15px] leading-relaxed break-words whitespace-pre-line text-slate-800 select-text">{{ item.body }}</p>

        <dl class="mt-4 divide-y divide-slate-100 text-sm">
          <div class="flex items-start gap-3 py-3"><Tag class="mt-0.5 size-4 shrink-0 text-slate-400" /><dt class="text-slate-500">Type</dt><dd class="flex-1 text-right font-medium text-slate-900">{{ look.label }}</dd></div>
          <div v-if="from" class="flex items-start gap-3 py-3"><UserRound class="mt-0.5 size-4 shrink-0 text-slate-400" /><dt class="text-slate-500">Title</dt><dd class="flex-1 text-right font-medium text-slate-900">{{ from }}</dd></div>
          <div class="flex items-start gap-3 py-3"><CalendarClock class="mt-0.5 size-4 shrink-0 text-slate-400" /><dt class="text-slate-500">{{ item.recipients ? 'Sent' : 'Received' }}</dt><dd class="flex-1 text-right font-medium text-slate-900">{{ date }}</dd></div>
          <div v-if="item.recipients" class="py-3">
            <p class="flex items-center gap-3 text-slate-500"><Users class="size-4 text-slate-400" /> Sent to <span class="flex-1 text-right font-medium text-slate-900">read by {{ item.recipients.filter((r) => r.read).length }} of {{ item.recipients.length }}</span></p>
            <ul class="mt-2 max-h-40 space-y-1.5 overflow-y-auto pl-7">
              <li v-for="(r, i) in item.recipients" :key="i" class="flex items-center justify-between gap-3"><span class="truncate text-slate-900">{{ r.name }}</span><span class="shrink-0 text-xs font-medium" :class="r.read ? 'text-emerald-700' : 'text-slate-400'">{{ r.read ? 'Read' : 'Not read yet' }}</span></li>
            </ul>
          </div>
        </dl>

        <button v-if="openLabel" type="button" class="btn-primary mt-3 h-12 w-full" @click="emit('open')">{{ openLabel }} <ChevronRight class="size-4" /></button>
        <div class="mt-2.5 grid gap-2.5" :class="canDelete && 'grid-cols-2'">
          <button type="button" class="btn-secondary h-11" @click="copy"><Check v-if="copied" class="size-4 text-emerald-600" /><Copy v-else class="size-4" /> {{ copied ? 'Copied' : 'Copy' }}</button>
          <button v-if="canDelete" type="button" class="btn-secondary h-11 border-red-200 text-red-600! hover:bg-red-50" @click="emit('delete')"><Trash2 class="size-4" /> Delete</button>
        </div>
      </div>
    </div>
  </BaseModal>
</template>

<style scoped>
.nc { --a: #14918a; --b: #0a3b38; }
.nc-emerald { --a: #10b981; --b: #065f46; }
.nc-amber { --a: #f59e0b; --b: #92400e; }
.nc-red { --a: #ef4444; --b: #7f1d1d; }
.nc-sky { --a: #0ea5e9; --b: #0c4a6e; }
.nc-slate { --a: #64748b; --b: #1e293b; }
/* Fixed colours, the same in light and dark mode */
.nc-head { --color-white: #fff; color: #fff; background: linear-gradient(135deg, var(--a), var(--b)); }
</style>
