<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { Inbox, Wallet, Banknote, Bug, Crown, DoorOpen, ShieldCheck, UserPlus, Megaphone, ChevronRight } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { timeAgo } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import EmptyState from '@/components/EmptyState.vue'

// Inbox for landlords and the main admin: payments received, cash to confirm, tenants connecting,
// sign-in alerts, grouped by day. Tap → marked read (and opens its page).
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
  move_out: { icon: DoorOpen, cls: 'disc-amber' },
  subscription: { icon: Crown, cls: 'disc-amber' },
  error: { icon: Bug, cls: 'disc-red' },
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

    <div v-if="items.length">
      <section v-for="g in groups" :key="g.label">
        <h2 class="section-title mt-6">{{ g.label }}</h2>
        <ul class="sheet nt-list">
          <li v-for="n in g.items" :key="n.id">
            <button
              type="button"
              class="nt-row w-full text-left"
              :class="!n.read && 'nt-unread'"
              @click="open(n)"
            >
              <span class="icon-disc rounded-full" :class="kind(n).cls"><component :is="kind(n).icon" class="size-[1.15rem]" /></span>
              <span class="min-w-0 flex-1">
                <span class="flex items-baseline justify-between gap-3">
                  <span class="truncate text-[15px]" :class="n.read ? 'font-medium text-slate-700' : 'font-semibold text-slate-900'">{{ sender(n) }}</span>
                  <span class="nt-time shrink-0" :class="!n.read && 'nt-time-new'">{{ shortTime(n.createdAt) }}</span>
                </span>
                <span class="mt-0.5 flex items-start gap-3">
                  <span class="line-clamp-3 flex-1 text-sm leading-relaxed" :class="n.read ? 'text-slate-500' : 'text-slate-700'">{{ n.body }}</span>
                  <span v-if="!n.read" class="nt-dot mt-1.5" aria-label="Unread" />
                  <ChevronRight v-else-if="n.url" class="mt-0.5 size-4 shrink-0 text-slate-300" />
                </span>
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <div v-else class="sheet"><EmptyState :icon="Inbox" title="No messages yet" text="Payments received, cash to confirm, tenant connections and security alerts appear here." /></div>
  </div>
</template>
