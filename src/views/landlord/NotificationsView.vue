<script setup>
import { computed, reactive, ref } from 'vue'
import { Send, CheckCircle2, BellOff } from '@lucide/vue'
import { useRentalStore, landlordSenderLine } from '@/stores/rental'
import PageHeader from '@/components/PageHeader.vue'
import EmptyState from '@/components/EmptyState.vue'
import NotificationItem from '@/components/NotificationItem.vue'

// Landlord: write a message to tenants. Every notification is titled "Renta UG" and shows
// who it's from; it also appears on tenants' phones.
const rental = useRentalStore()
const form = reactive({ to: 'all', body: '' })
const busy = ref(false)
const error = ref('')
const flash = ref('')
const filter = ref('all')

const activeTenants = computed(() => rental.currentTenants)
const preview = computed(() => ({ title: landlordSenderLine(), body: form.body.trim() }))

async function send() {
  busy.value = true
  error.value = ''
  try {
    await rental.sendNotification({ tenantIds: form.to === 'all' ? 'all' : [form.to], body: form.body.trim() })
    form.body = ''
    flash.value = 'Your notification has been sent. Tenants with notifications enabled will receive it immediately.'
    setTimeout(() => (flash.value = ''), 5000)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

const labels = { general: 'Message', maintenance: 'Maintenance', payment: 'Payment', reminder: 'Automatic reminder' }
// Personal/automatic notices to tenants (sign-in alerts, daily rent status, welcome, overdue reminders) aren't listed here
const SHOWN = new Set(Object.keys(labels))

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
  <PageHeader title="Notifications" subtitle="Send notices to your tenants. They are delivered in the app and to their phones." />

  <div class="grid gap-6 lg:grid-cols-5">
    <section class="card h-fit p-5 lg:col-span-2">
      <h2 class="mb-4 text-sm font-semibold text-slate-900">New notification</h2>
      <form class="space-y-4" @submit.prevent="send">
        <div>
          <label class="label" for="nto">Recipients</label>
          <select id="nto" v-model="form.to" class="input">
            <option value="all">All current tenants</option>
            <option v-for="t in activeTenants" :key="t.id" :value="t.id">{{ t.name }}</option>
          </select>
        </div>
        <div>
          <label class="label" for="nbody">Message</label>
          <textarea
            id="nbody"
            v-model="form.body"
            rows="5"
            class="input"
            maxlength="500"
            placeholder="e.g. Please note that the water supply will be interrupted on Saturday from 8:00 AM to 2:00 PM for tank cleaning."
            required
          />
          <p class="mt-1 text-right text-xs text-slate-500">{{ form.body.length }}/500</p>
        </div>

        <!-- Exactly what the tenant will see -->
        <div v-if="form.body.trim()" class="overflow-hidden rounded-xl border border-slate-200">
          <p class="border-b border-slate-200 bg-slate-50 px-4 py-2 text-xs font-medium tracking-wide text-slate-500 uppercase">Preview</p>
          <NotificationItem :notification="preview" preview />
        </div>

        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <p v-if="flash" class="flex items-start gap-2 text-sm text-emerald-700"><CheckCircle2 class="mt-0.5 size-4 shrink-0" /> {{ flash }}</p>
        <button type="submit" class="btn-primary w-full" :disabled="busy || !activeTenants.length || !form.body.trim()">
          <Send class="size-4" /> {{ busy ? 'Sending…' : 'Send notification' }}
        </button>
        <p v-if="!activeTenants.length" class="text-xs text-slate-500">Add a tenant first to send notifications.</p>
      </form>
    </section>

    <section class="card overflow-hidden lg:col-span-3">
      <div class="flex items-center justify-between gap-3 border-b border-slate-100 px-5 py-3">
        <h2 class="text-sm font-semibold text-slate-900">Sent</h2>
        <select v-model="filter" class="input w-auto py-1.5">
          <option value="all">All types</option>
          <option value="general">Messages</option>
          <option value="maintenance">Maintenance</option>
          <option value="payment">Payment</option>
          <option value="reminder">Automatic reminders</option>
        </select>
      </div>
      <ul v-if="sent.length" class="divide-y divide-slate-100">
        <li v-for="n in sent" :key="n.id">
          <NotificationItem :notification="{ ...n, read: true }" />
          <p class="-mt-2 pr-5 pb-4 pl-[4.625rem] text-xs text-slate-500">
            {{ labels[n.type] ?? n.type }} · Sent to
            {{ n.recipients.length > 3 ? `${n.recipients.length} tenants` : n.recipients.map((r) => r.name).join(', ') }}
            · Read by {{ n.recipients.filter((r) => r.read).length }} of {{ n.recipients.length }}
          </p>
        </li>
      </ul>
      <EmptyState v-else :icon="BellOff" title="No notifications sent yet" text="Notices you send, automatic reminders and payment confirmations will appear here." />
    </section>
  </div>
</template>
