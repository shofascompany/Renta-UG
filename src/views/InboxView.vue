<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Inbox, Wallet, Banknote, Bug, Crown, DoorOpen, ShieldCheck, UserPlus, Megaphone, ChevronRight, Eye, Trash2 } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { timeAgo } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import EmptyState from '@/components/EmptyState.vue'
import NotificationCard from '@/components/NotificationCard.vue'
import PressMenu from '@/components/PressMenu.vue'
import { usePressMenu } from '@/composables/usePressMenu'
import { askConfirm } from '@/composables/useConfirm'

// Inbox for landlords and the main admin: payments received, cash to confirm, tenants connecting,
// sign-in alerts, grouped by day. Tap → its details card (and marked read).
const rental = useRentalStore()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const items = computed(() => [...rental.staff_notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt)))
const unread = computed(() => items.value.filter((n) => !n.read).length)

// go = the text of the button that opens the page it is about
const kinds = {
  payment: { label: 'Payment', icon: Wallet, cls: 'disc-emerald', tone: 'emerald', go: 'See the payment' },
  cash: { label: 'Payment to confirm', icon: Banknote, cls: 'disc-amber', tone: 'amber', go: 'Check the payment' },
  security: { label: 'Security', icon: ShieldCheck, cls: 'disc-slate', tone: 'slate', go: 'Open' },
  tenant: { label: 'Tenant', icon: UserPlus, cls: 'disc-brand', tone: 'brand', go: 'See the tenant' },
  move_out: { label: 'Request to leave', icon: DoorOpen, cls: 'disc-amber', tone: 'amber', go: 'See the request' },
  subscription: { label: 'Subscription', icon: Crown, cls: 'disc-amber', tone: 'amber', go: 'Open subscription' },
  error: { label: 'App error', icon: Bug, cls: 'disc-red', tone: 'red', go: 'Open' },
}
const kind = (n) => kinds[n?.type] ?? { label: 'Message', icon: Megaphone, cls: 'disc-sky', tone: 'sky', go: 'Open' }
const sender = (n) => (n?.title ?? '').replace(/^[\p{Extended_Pictographic}️\s]+/u, '') || 'Renta UG'
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

// Its page, unless that is this inbox
const goesTo = (n) => (n?.url && n.url.split('?')[0] !== route.path ? n.url : '')
function go(n) {
  const to = goesTo(n)
  if (to) router.push(to)
}

// Right click, or press and hold → View / Delete
const menu = usePressMenu()
const viewing = ref(null)
function view(n) {
  viewing.value = n
  if (!n.read) rental.markStaffRead(n.id).catch(() => {})
}
function closeCard() {
  viewing.value = null
  if (route.query.open) router.replace({ query: {} })
}
// Opened from the pop-up at the top of the screen (?open=<id>)
watch(
  () => [route.query.open, items.value.length],
  ([id]) => {
    const n = id && items.value.find((x) => x.id === id)
    if (n && viewing.value?.id !== n.id) view(n)
  },
  { immediate: true },
)
async function remove(n) {
  const yes = await askConfirm({
    title: 'Delete this notification?',
    text: 'It is removed from your inbox for good. Payments and tenants are not affected.',
    note: n.body.length > 140 ? `${n.body.slice(0, 140)}…` : n.body,
    confirm: 'Delete', working: 'Deleting…', icon: Trash2,
    action: () => rental.deleteStaff(n.id),
  })
  if (yes && viewing.value?.id === n.id) closeCard()
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
              v-bind="menu.row(n)"
              @click="menu.consumed() || view(n)"
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
                  <ChevronRight v-else class="mt-0.5 size-4 shrink-0 text-slate-300" />
                </span>
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <p v-if="items.length" class="mt-4 text-center text-xs text-slate-400">Press and hold a message (or right-click it) for options</p>

    <PressMenu :menu="menu" label="Notification options">
      <template #default="{ item, close }">
        <button type="button" class="menu-item" role="menuitem" @click="close(); view(item)"><Eye class="size-4 text-slate-500" /> View</button>
        <button type="button" class="menu-item text-red-600!" role="menuitem" @click="close(); remove(item)"><Trash2 class="size-4" /> Delete</button>
      </template>
    </PressMenu>

    <NotificationCard
      :item="viewing"
      :look="kind(viewing)"
      :from="sender(viewing)"
      :open-label="goesTo(viewing) ? kind(viewing).go : ''"
      can-delete
      @close="closeCard"
      @open="go(viewing)"
      @delete="remove(viewing)"
    />

    <div v-if="!items.length" class="sheet"><EmptyState :icon="Inbox" title="No messages yet" text="Payments received, cash to confirm, tenant connections and security alerts appear here." /></div>
  </div>
</template>
