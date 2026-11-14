<script setup>
import { computed, reactive, ref } from 'vue'
import { Send, CheckCircle2, BellOff, Megaphone, Wallet, CalendarClock, Wrench, Eye } from '@lucide/vue'
import { useRentalStore, landlordSenderLine } from '@/stores/rental'
import { timeAgo } from '@/utils/format'
import NotificationItem from '@/components/NotificationItem.vue'
import AdminHeader from '@/components/admin/AdminHeader.vue'

// Landlord: write a notice to tenants. Every notification is titled "Renta UG" and shows
// who it's from; it also appears on tenants' phones.
const rental = useRentalStore()
const form = reactive({ to: 'all', body: '' })
const busy = ref(false)
const error = ref('')
const flash = ref('')
const filter = ref('all')

const activeTenants = computed(() => rental.currentTenants)
const preview = computed(() => ({ title: landlordSenderLine(), body: form.body.trim() }))

const templates = [
  'Reminder: rent for this month is due on the 5th. You can pay with MTN MoMo or Airtel Money in the app.',
  'Please note that the water supply will be interrupted on Saturday from 8:00 AM to 2:00 PM for tank cleaning.',
  'The compound will be cleaned this weekend. Please keep the parking area clear.',
]

async function send() {
  busy.value = true
  error.value = ''
  try {
    await rental.sendNotification({ tenantIds: form.to === 'all' ? 'all' : [form.to], body: form.body.trim() })
    form.body = ''
    flash.value = 'Sent. Tenants with phone notifications on get it straight away.'
    setTimeout(() => (flash.value = ''), 5000)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

const kinds = {
  general: { label: 'Notice', icon: Megaphone, cls: 'disc-brand' },
  maintenance: { label: 'Maintenance', icon: Wrench, cls: 'disc-amber' },
  payment: { label: 'Payment', icon: Wallet, cls: 'disc-emerald' },
  reminder: { label: 'Automatic reminder', icon: CalendarClock, cls: 'disc-sky' },
}
// Personal/automatic notices (sign-in alerts, daily rent status, welcome, overdue reminders) aren't listed here
const SHOWN = new Set(Object.keys(kinds))

// Group identical messages sent to several tenants at once
const sent = computed(() => {
  const groups = new Map()
  for (const n of [...rental.notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt))) {
    if (!SHOWN.has(n.type)) continue
    if (filter.value !== 'all' && n.type !== filter.value) continue
    const key = `${n.title}|${n.body}|${n.createdAt.slice(0, 16)}`
    if (!groups.has(key)) groups.set(key, { ...n, recipients: [] })
    groups.get(key).recipients.push({ name: rental.tenantById(n.tenantId)?.name ?? 'Former tenant', read: n.read })
  }
  return [...groups.values()].slice(0, 50)
})
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <AdminHeader eyebrow="Communication" title="Notices" subtitle="Send messages to your tenants. They arrive in the app and on their phones." />

    <div class="grid gap-6 lg:grid-cols-5">
      <!-- Compose -->
      <section class="rise lg:col-span-2" style="--d: 60ms">
        <h2 class="section-title">New notice</h2>
        <form class="sheet space-y-4 p-5" @submit.prevent="send">
          <div>
            <label class="label" for="nto">To</label>
            <select id="nto" v-model="form.to" class="input h-11 rounded-xl">
              <option value="all">All current tenants ({{ activeTenants.length }})</option>
              <option v-for="t in activeTenants" :key="t.id" :value="t.id">{{ t.name }}</option>
            </select>
          </div>
          <div>
            <label class="label" for="nbody">Message</label>
            <textarea id="nbody" v-model="form.body" rows="5" class="input rounded-xl" maxlength="500" placeholder="Write your message…" required />
            <div class="mt-1 flex items-center justify-between gap-2">
              <div class="flex gap-1.5 overflow-x-auto">
                <button
                  v-for="(t, i) in templates"
                  :key="i"
                  type="button"
                  class="shrink-0 rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-medium text-slate-600 hover:bg-slate-200"
                  @click="form.body = t"
                >{{ ['Rent due', 'Water', 'Cleaning'][i] }}</button>
              </div>
              <p class="shrink-0 text-xs text-slate-400">{{ form.body.length }}/500</p>
            </div>
          </div>

          <!-- Exactly what the tenant will see -->
          <div v-if="form.body.trim()" class="overflow-hidden rounded-xl border border-slate-200">
            <p class="flex items-center gap-1.5 border-b border-slate-200 bg-slate-50 px-4 py-2 text-[11px] font-semibold tracking-wider text-slate-500 uppercase"><Eye class="size-3.5" /> Preview</p>
            <NotificationItem :notification="preview" preview />
          </div>

          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <p v-if="flash" class="flex items-start gap-2 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800"><CheckCircle2 class="mt-0.5 size-4 shrink-0" /> {{ flash }}</p>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary h-11 w-full" :disabled="busy || !activeTenants.length || !form.body.trim()">
            <Send class="size-4" /> {{ busy ? 'Sending…' : 'Send notice' }}
          </button>
          <p v-if="!activeTenants.length" class="text-xs text-slate-500">Add a tenant first to send notices.</p>
        </form>
      </section>

      <!-- Sent -->
      <section class="rise lg:col-span-3" style="--d: 120ms">
        <h2 class="section-title">Sent</h2>
        <div class="-mx-4 mb-3 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0">
          <button
            v-for="f in [['all', 'All'], ['general', 'Notices'], ['maintenance', 'Maintenance'], ['payment', 'Payments'], ['reminder', 'Reminders']]"
            :key="f[0]"
            class="h-9 shrink-0 rounded-full px-4 text-sm font-medium transition"
            :class="filter === f[0] ? 'bg-slate-900 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'"
            @click="filter = f[0]"
          >{{ f[1] }}</button>
        </div>
        <div class="sheet">
          <ul v-if="sent.length" class="divide-y divide-slate-100">
            <li v-for="n in sent" :key="n.id" class="flex gap-3.5 px-4 py-4 sm:px-5">
              <span class="icon-disc rounded-full" :class="kinds[n.type].cls"><component :is="kinds[n.type].icon" class="size-[1.15rem]" /></span>
              <div class="min-w-0 flex-1">
                <div class="flex items-baseline justify-between gap-3">
                  <p class="truncate text-sm font-semibold text-slate-900">{{ kinds[n.type].label }}</p>
                  <span class="shrink-0 text-xs text-slate-400">{{ timeAgo(n.createdAt) }}</span>
                </div>
                <p class="mt-0.5 line-clamp-3 text-sm leading-relaxed text-slate-600">{{ n.body }}</p>
                <p class="mt-1.5 flex flex-wrap gap-x-3 text-xs text-slate-500">
                  <span>To {{ n.recipients.length > 3 ? `${n.recipients.length} tenants` : n.recipients.map((r) => r.name).join(', ') }}</span>
                  <span class="font-medium" :class="n.recipients.every((r) => r.read) ? 'text-emerald-700' : ''">
                    Read by {{ n.recipients.filter((r) => r.read).length }}/{{ n.recipients.length }}
                  </span>
                </p>
              </div>
            </li>
          </ul>
          <div v-else class="flex flex-col items-center px-6 py-14 text-center">
            <span class="icon-disc disc-slate size-12 rounded-full"><BellOff class="size-6" /></span>
            <p class="mt-3 font-semibold text-slate-900">Nothing sent yet</p>
            <p class="mt-1 max-w-xs text-sm text-slate-500">Notices you send, automatic reminders and payment confirmations appear here.</p>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
