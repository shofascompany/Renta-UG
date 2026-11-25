<script setup>
import BaseSelect from '@/components/BaseSelect.vue'
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Megaphone, Users, Briefcase, Globe, Send, CheckCircle2 } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import ListRow from '@/components/admin/ListRow.vue'
import EmptyState from '@/components/EmptyState.vue'

// Main admin: send an announcement from "Renta UG" to tenants, landlords or everyone —
// across the platform or for one landlord only. It also pops up on phones that allow notifications.
const rental = useRentalStore()
const route = useRoute()
const audience = ref('tenants')
const linked = () => (typeof route.query.landlord === 'string' ? route.query.landlord : '')
const landlordId = ref(linked())
watch(() => route.query.landlord, () => route.name === 'super-broadcast' && (landlordId.value = linked()))
const message = ref('')
const busy = ref(false)
const error = ref('')
const sent = ref(null)

const AUDIENCES = [
  { id: 'tenants', label: 'Tenants', hint: 'Who use the app', icon: Users, tile: 'tile-violet' },
  { id: 'landlords', label: 'Landlords', hint: 'Active ones', icon: Briefcase, tile: 'tile-teal' },
  { id: 'everyone', label: 'Everyone', hint: 'Tenants + landlords', icon: Globe, tile: 'tile-sky' },
]
const reach = computed(() => {
  const tenants = rental.tenants.filter((t) => t.propertyId && t.userId && (!landlordId.value || t.landlordId === landlordId.value)).length
  const landlords = rental.landlords.filter((l) => l.active && (!landlordId.value || l.id === landlordId.value)).length
  return { tenants: audience.value === 'landlords' ? 0 : tenants, landlords: audience.value === 'tenants' ? 0 : landlords }
})
const history = computed(() => rental.audit.filter((a) => a.action === 'broadcast'))

async function send() {
  busy.value = true
  error.value = ''
  try {
    const n = await rental.adminBroadcast({ audience: audience.value, landlordId: landlordId.value, message: message.value })
    sent.value = n
    message.value = ''
    setTimeout(() => (sent.value = null), 6000)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <SuperHero eyebrow="Communication" title="Announcements" subtitle="Send a message from Renta UG. It lands in their notifications and pops up on their phones." tone="violet" />

    <section class="sheet p-5 sm:p-6">
      <h2 class="section-title">1 · Who gets it?</h2>
      <div class="grid grid-cols-3 gap-2.5">
        <button
          v-for="a in AUDIENCES"
          :key="a.id"
          type="button"
          class="aud flex flex-col items-center gap-2 rounded-2xl border p-3.5 text-center transition"
          :class="audience === a.id ? 'aud-on border-transparent text-white' : 'border-slate-200 bg-white text-slate-800'"
          @click="audience = a.id"
        >
          <span class="icon-tile size-10 rounded-xl" :class="a.tile"><component :is="a.icon" class="size-5" /></span>
          <span class="text-sm font-semibold">{{ a.label }}</span>
          <span class="text-[11px]" :class="audience === a.id ? 'text-white/75' : 'text-slate-500'">{{ a.hint }}</span>
        </button>
      </div>
      <div class="mt-4">
        <label class="label" for="bc-landlord">Only for one landlord <span class="font-normal text-slate-400">(optional)</span></label>
        <BaseSelect id="bc-landlord" v-model="landlordId" :options="[{ value: '', label: 'All landlords on Renta UG' }, ...rental.landlords.map((l) => ({ value: l.id, label: (l.name || l.email) + (audience !== 'landlords' ? ' (and their tenants)' : '') }))]" />
      </div>

      <h2 class="section-title mt-6">2 · Message</h2>
      <textarea v-model="message" rows="5" maxlength="1000" class="input" placeholder="e.g. Renta UG will be under maintenance on Sunday from 10 PM to 11 PM." />
      <p class="mt-1 text-right text-xs text-slate-400">{{ message.length }}/1000</p>

      <p class="mt-2 rounded-xl bg-slate-50 p-3 text-sm text-slate-600">
        Reaches <strong class="text-slate-900">{{ reach.tenants }}</strong> tenant{{ reach.tenants === 1 ? '' : 's' }} and
        <strong class="text-slate-900">{{ reach.landlords }}</strong> landlord{{ reach.landlords === 1 ? '' : 's' }}.
      </p>
      <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>
      <p v-if="sent !== null" class="mt-3 flex items-center gap-2 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800"><CheckCircle2 class="size-4.5" /> Sent to {{ sent }} {{ sent === 1 ? 'person' : 'people' }}.</p>
      <button :data-busy="Boolean(busy)" class="btn-primary mt-4 h-12 w-full rounded-2xl" :disabled="busy || message.trim().length < 3 || !(reach.tenants + reach.landlords)" @click="send">
        <Send class="size-4" /> {{ busy ? 'Sending…' : 'Send announcement' }}
      </button>
    </section>

    <h2 class="section-title mt-6">Sent before</h2>
    <div class="sheet">
      <ul v-if="history.length" class="divide-y divide-slate-100">
        <ListRow v-for="h in history" :key="h.id" :title="h.summary.replace(/^Announcement to /, '')" :subtitle="formatDate(h.createdAt)" :chevron="false">
          <template #icon><span class="icon-disc disc-brand"><Megaphone class="size-5" /></span></template>
        </ListRow>
      </ul>
      <EmptyState v-else compact kind="announce" title="No announcements yet" text="Announcements you send appear here." />
    </div>
  </div>
</template>

<style scoped>
.aud:active { transform: scale(0.97); }
.aud-on {
  --color-white: #fff;
  background: linear-gradient(140deg, #6d28d9, #2e1065);
  box-shadow: 0 12px 26px -14px rgb(76 29 149 / 0.9);
}
</style>
