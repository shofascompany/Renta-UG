<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { Inbox, Wallet, Banknote, ShieldCheck, UserPlus, Megaphone, ChevronRight } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { timeAgo } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'

// Inbox for landlords and the main admin: payments received, cash to confirm, tenants connecting,
// sign-in alerts. A clean list (no cards), grouped by day. Tap → marked read (and opens its page).
const rental = useRentalStore()
const auth = useAuthStore()
const router = useRouter()

const items = computed(() => [...rental.staff_notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt)))
const unread = computed(() => items.value.filter((n) => !n.read).length)

const kinds = {
  payment: { icon: Wallet, cls: 'disc-emerald' },
  cash: { icon: Banknote, cls: 'disc-amber' },
  security: { icon: ShieldCheck, cls: 'disc-slate' },
  tenant: { icon: UserPlus, cls: 'disc-brand' },
}
const kind = (n) => kinds[n.type] ?? { icon: Megaphone, cls: 'disc-sky' }
const sender = (n) => (n.title ?? '').replace(/^[\p{Extended_Pictographic}️\s]+/u, '') || 'Renta UG'
const shortTime = (iso) => {
  const d = new Date(iso)
  return new Date().toDateString() === d.toDateString()
    ? d.toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', hour12: true })
    : timeAgo(iso)
}

const groups = computed(() => {
  const startOf = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const today = startOf(new Date())
  const label = (iso) => {
    const d = new Date(iso)
    const days = Math.round((today - startOf(d)) / 86400000)
    if (days <= 0) return 'Today'
    if (days === 1) return 'Yesterday'
    if (days < 7) return 'This week'
    return d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
  }
  const out = []
  for (const n of items.value) {
    const l = label(n.createdAt)
    if (out.at(-1)?.label !== l) out.push({ label: l, items: [] })
    out.at(-1).items.push(n)
  }
  return out
})

function open(n) {
  if (!n.read) rental.markStaffRead(n.id).catch(() => {})
  if (n.url && n.url !== router.currentRoute.value.path) router.push(n.url)
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <AdminHeader
      eyebrow="Messages"
      title="Inbox"
      :subtitle="unread ? `${unread} new` : auth.isSuperadmin ? 'Payments and alerts across all landlords' : 'Payments, cash to confirm, tenant connections and security alerts'"
    />

    <div v-if="items.length" class="-mt-3 rounded-2xl border border-slate-200 bg-white px-4 pb-2 sm:px-5">
      <section v-for="g in groups" :key="g.label">
        <h2 class="sticky top-16 z-10 -mx-4 bg-white/95 px-4 pt-5 pb-2 text-[11px] font-bold tracking-[0.14em] text-slate-400 uppercase backdrop-blur sm:mx-0 sm:px-0">
          {{ g.label }}
        </h2>
        <ul class="-mx-4 divide-y divide-slate-100 sm:mx-0">
          <li v-for="n in g.items" :key="n.id">
            <button
              type="button"
              class="flex w-full items-start gap-3.5 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:rounded-2xl sm:px-3"
              :class="!n.read && 'unread'"
              @click="open(n)"
            >
              <span class="icon-disc rounded-full" :class="kind(n).cls"><component :is="kind(n).icon" class="size-[1.15rem]" /></span>
              <span class="min-w-0 flex-1">
                <span class="flex items-baseline justify-between gap-3">
                  <span class="truncate text-[15px]" :class="n.read ? 'font-medium text-slate-700' : 'font-semibold text-slate-900'">{{ sender(n) }}</span>
                  <span class="shrink-0 text-xs" :class="n.read ? 'text-slate-400' : 'font-semibold text-brand-700'">{{ shortTime(n.createdAt) }}</span>
                </span>
                <span class="mt-0.5 flex items-start gap-3">
                  <span class="line-clamp-3 flex-1 text-sm leading-relaxed" :class="n.read ? 'text-slate-500' : 'text-slate-700'">{{ n.body }}</span>
                  <span v-if="!n.read" class="mt-1.5 size-2 shrink-0 rounded-full bg-brand-600" aria-label="Unread" />
                  <ChevronRight v-else-if="n.url" class="mt-0.5 size-4 shrink-0 text-slate-300" />
                </span>
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <div v-else class="flex flex-col items-center px-6 py-20 text-center">
      <span class="icon-disc disc-slate size-14 rounded-full"><Inbox class="size-6" /></span>
      <p class="mt-4 font-semibold text-slate-900">No messages yet</p>
      <p class="mt-1 max-w-xs text-sm text-slate-500">Payments received, cash to confirm, tenant connections and security alerts appear here.</p>
    </div>
  </div>
</template>

<style scoped>
.unread {
  background: linear-gradient(90deg, var(--color-brand-50) 0%, transparent 85%);
}
</style>
