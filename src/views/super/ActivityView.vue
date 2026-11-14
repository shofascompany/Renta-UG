<script setup>
import { computed, ref } from 'vue'
import {
  Search, ShieldCheck, Building2, Users, Megaphone, Briefcase, ArrowDownLeft, Banknote, DoorOpen, UserPlus, Activity,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'

// Main admin: one timeline of what happened on the platform — your own changes (activity log),
// money received, cash reviews, requests to leave and new tenants.
const rental = useRentalStore()
const show = ref('all') // all | admin | money | people
const query = ref('')

const when = (iso) =>
  new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true })
const tenantName = (id) => rental.tenantById(id)?.name ?? 'A tenant'
const landlordName = (id) => rental.landlords.find((l) => l.id === id)?.name ?? 'a landlord'

const ICON = { property: Building2, tenant: Users, broadcast: Megaphone, landlord: Briefcase, account: Users }
const events = computed(() => {
  const out = []
  for (const a of rental.audit) {
    out.push({ id: `a${a.id}`, kind: 'admin', at: a.createdAt, icon: ICON[a.targetType] ?? ShieldCheck, tone: 'disc-brand', title: a.summary, sub: 'You (main admin)' })
  }
  for (const r of rental.payment_receipts) {
    const cash = /cash/i.test(r.method ?? '')
    out.push({
      id: `r${r.id}`, kind: 'money', at: r.receivedAt, icon: cash ? Banknote : ArrowDownLeft, tone: cash ? 'disc-amber' : 'disc-emerald',
      title: `${tenantName(r.tenantId)} paid ${formatUGX(r.amount)}`, sub: `${cash ? 'Cash' : r.method} · ${landlordName(r.landlordId)}`, to: `/admin2026/tenants/${r.tenantId}`,
    })
  }
  for (const c of rental.cash_payments) {
    if (c.status === 'pending') continue
    out.push({
      id: `c${c.id}`, kind: 'money', at: c.reviewedAt ?? c.createdAt, icon: Banknote, tone: c.status === 'confirmed' ? 'disc-emerald' : 'disc-red',
      title: `Cash ${c.status === 'confirmed' ? 'confirmed' : 'not confirmed'}: ${formatUGX(c.confirmedAmount ?? c.amount)} from ${tenantName(c.tenantId)}`,
      sub: `Reviewed by ${c.reviewedRole === 'superadmin' ? 'you' : 'the landlord'}`, to: '/admin2026/cash',
    })
  }
  for (const m of rental.move_out_requests) {
    out.push({
      id: `m${m.id}`, kind: 'people', at: m.decidedAt ?? m.createdAt, icon: DoorOpen, tone: m.status === 'pending' ? 'disc-amber' : 'disc-sky',
      title: `${tenantName(m.tenantId)} ${m.status === 'pending' ? 'asked to leave' : `— request to leave ${m.status}`}`, sub: m.reason, to: '/admin2026/move-outs',
    })
  }
  for (const t of rental.tenants) {
    out.push({
      id: `t${t.id}`, kind: 'people', at: t.createdAt, icon: UserPlus, tone: 'disc-sky',
      title: `${landlordName(t.landlordId)} registered ${t.name}`, sub: rental.placeName(t.propertyId ?? t.lastPropertyId), to: `/admin2026/tenants/${t.id}`,
    })
  }
  const q = query.value.trim().toLowerCase()
  return out
    .filter((e) => e.at && (show.value === 'all' || e.kind === show.value))
    .filter((e) => !q || `${e.title} ${e.sub ?? ''}`.toLowerCase().includes(q))
    .sort((a, b) => String(b.at).localeCompare(String(a.at)))
})
const shown = ref(50)

// Group by day
const groups = computed(() => {
  const map = new Map()
  for (const e of events.value.slice(0, shown.value)) {
    const day = new Date(e.at).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })
    if (!map.has(day)) map.set(day, [])
    map.get(day).push(e)
  }
  return [...map.entries()]
})
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <SuperHero eyebrow="History" title="Activity" subtitle="Everything that happened, newest first. Your own changes are logged automatically." tone="amber" />

    <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
      <div class="relative flex-1">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search activity" />
      </div>
      <div class="grid grid-cols-4 rounded-2xl bg-slate-100 p-1 text-sm sm:w-96">
        <button v-for="f in [['all', 'All'], ['admin', 'Mine'], ['money', 'Money'], ['people', 'People']]" :key="f[0]" type="button" class="h-9 rounded-xl font-medium transition" :class="show === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="show = f[0]">{{ f[1] }}</button>
      </div>
    </div>

    <div v-if="groups.length" class="space-y-6">
      <section v-for="[day, items] in groups" :key="day">
        <h2 class="section-title">{{ day }}</h2>
        <ol class="sheet timeline divide-y divide-slate-100">
          <li v-for="e in items" :key="e.id">
            <component :is="e.to ? 'RouterLink' : 'div'" :to="e.to" class="flex items-start gap-3.5 px-4 py-3.5 transition-colors sm:px-5" :class="e.to && 'hover:bg-slate-50'">
              <span class="icon-disc" :class="e.tone"><component :is="e.icon" class="size-5" /></span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-slate-900">{{ e.title }}</p>
                <p v-if="e.sub" class="mt-0.5 truncate text-xs text-slate-500">{{ e.sub }}</p>
              </div>
              <span class="shrink-0 text-[11px] text-slate-400">{{ when(e.at).split(', ').at(-1) }}</span>
            </component>
          </li>
        </ol>
      </section>
      <button v-if="events.length > shown" type="button" class="btn-secondary w-full" @click="shown += 50">Show older</button>
    </div>
    <div v-else class="sheet flex flex-col items-center px-6 py-14 text-center">
      <span class="icon-tile tile-amber size-12"><Activity class="size-6" /></span>
      <p class="mt-3 font-semibold text-slate-900">Nothing yet</p>
    </div>
  </div>
</template>
