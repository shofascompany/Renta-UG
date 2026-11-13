<script setup>
import { computed, reactive, ref } from 'vue'
import { Send, CheckCircle2, BellOff } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { timeAgo } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import EmptyState from '@/components/EmptyState.vue'

// Landlord: send notifications (they also pop up on tenants' phones) and see everything sent,
// including the automatic end-of-stay reminders and payment receipts.
const rental = useRentalStore()
const form = reactive({ to: 'all', type: 'general', title: '', body: '' })
const busy = ref(false)
const error = ref('')
const flash = ref('')
const filter = ref('all')

const activeTenants = computed(() => rental.currentTenants)

async function send() {
  busy.value = true
  error.value = ''
  try {
    await rental.sendNotification({
      tenantIds: form.to === 'all' ? 'all' : [form.to],
      type: form.type,
      title: form.title.trim(),
      body: form.body.trim(),
    })
    Object.assign(form, { title: '', body: '' })
    flash.value = 'Sent. Tenants with phone notifications on will see it right away.'
    setTimeout(() => (flash.value = ''), 4000)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

const labels = { general: 'General', maintenance: 'Maintenance', payment: 'Payment', reminder: 'Automatic reminder' }

// Group identical messages sent to several tenants at once
const sent = computed(() => {
  const groups = new Map()
  for (const n of [...rental.notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt))) {
    if (filter.value !== 'all' && n.type !== filter.value) continue
    const key = `${n.title}|${n.body}|${n.createdAt.slice(0, 16)}`
    if (!groups.has(key)) groups.set(key, { ...n, recipients: [] })
    groups.get(key).recipients.push({ name: rental.tenantById(n.tenantId)?.name ?? 'Former tenant', read: n.read })
  }
  return [...groups.values()].slice(0, 50)
})
</script>

<template>
  <PageHeader title="Notifications" subtitle="Message your tenants. Notifications also appear on their phones." />

  <div class="grid gap-6 lg:grid-cols-5">
    <section class="card h-fit p-5 lg:col-span-2">
      <h2 class="mb-4 text-sm font-semibold text-slate-900">New notification</h2>
      <form class="space-y-4" @submit.prevent="send">
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label" for="nto">Send to</label>
            <select id="nto" v-model="form.to" class="input">
              <option value="all">All current tenants</option>
              <option v-for="t in activeTenants" :key="t.id" :value="t.id">{{ t.name }}</option>
            </select>
          </div>
          <div>
            <label class="label" for="ntype">Type</label>
            <select id="ntype" v-model="form.type" class="input">
              <option value="general">General</option>
              <option value="maintenance">Maintenance</option>
              <option value="payment">Payment</option>
            </select>
          </div>
        </div>
        <div>
          <label class="label" for="ntitle">Title</label>
          <input id="ntitle" v-model="form.title" class="input" maxlength="80" placeholder="e.g. Water maintenance on Saturday" required />
        </div>
        <div>
          <label class="label" for="nbody">Message</label>
          <textarea id="nbody" v-model="form.body" rows="4" class="input" maxlength="500" required />
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <p v-if="flash" class="flex items-center gap-2 text-sm text-emerald-700"><CheckCircle2 class="size-4" /> {{ flash }}</p>
        <button type="submit" class="btn-primary w-full" :disabled="busy || !activeTenants.length">
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
          <option value="general">General</option>
          <option value="maintenance">Maintenance</option>
          <option value="payment">Payment</option>
          <option value="reminder">Automatic reminders</option>
        </select>
      </div>
      <ul v-if="sent.length" class="divide-y divide-slate-100">
        <li v-for="n in sent" :key="n.id" class="px-5 py-4">
          <div class="flex items-start justify-between gap-3">
            <p class="text-sm font-medium text-slate-900">{{ n.title }}</p>
            <span class="shrink-0 text-xs text-slate-400">{{ timeAgo(n.createdAt) }}</span>
          </div>
          <p class="mt-0.5 text-sm text-slate-600">{{ n.body }}</p>
          <p class="mt-2 text-xs text-slate-500">
            {{ labels[n.type] ?? n.type }} · to
            {{ n.recipients.length > 3 ? `${n.recipients.length} tenants` : n.recipients.map((r) => r.name).join(', ') }}
            · {{ n.recipients.filter((r) => r.read).length }}/{{ n.recipients.length }} read
          </p>
        </li>
      </ul>
      <EmptyState v-else :icon="BellOff" title="Nothing sent yet" text="Notifications you send, reminders and payment receipts show up here." />
    </section>
  </div>
</template>
