<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { Crown, Clock, CircleCheck, CircleX, CirclePlus, Settings2, Search, Wallet, Users, Hourglass, Lock, Save, Banknote } from '@lucide/vue'
import { useBillingStore, subscriptionStatus, paidWith } from '@/stores/billing'
import CashSubscriptionModal from '@/components/super/CashSubscriptionModal.vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, timeAgo } from '@/utils/format'
import { NETWORKS, prettyPhone } from '@/lib/networks'
import BaseModal from '@/components/BaseModal.vue'

// Main admin: landlord subscriptions. Confirm payments, see who is paid up, add free days, set prices + numbers.
const billing = useBillingStore()
const rental = useRentalStore()

const landlordOf = (id) => rental.landlords.find((l) => l.id === id)
const nameOf = (id) => landlordOf(id)?.name || landlordOf(id)?.email || 'Landlord'

// ── Figures ──
const rows = computed(() =>
  rental.landlords.map((l) => ({
    ...l,
    sub: subscriptionStatus(l.subscriptionUntil, l.subscriptionPlan, { tier: l.subscriptionTier, exempt: l.subscriptionExempt }),
    units: rental.properties.filter((p) => p.landlordId === l.id).length,
  })),
)
const tierName = (t) => (t === 'big' ? 'Big scale' : 'Small scale')
const month = new Date().toISOString().slice(0, 7)
const kpis = computed(() => [
  { label: 'Paying', value: rows.value.filter((r) => r.sub.active && !r.sub.exempt).length, icon: Crown, tone: 'teal' },
  { label: 'Not paid yet', value: rows.value.filter((r) => r.sub.state === 'none').length, icon: Hourglass, tone: 'sky' },
  { label: 'Ended', value: rows.value.filter((r) => r.sub.state === 'expired').length, icon: Lock, tone: 'red' },
  { label: 'Waiting', value: billing.pending.length, icon: Clock, tone: 'amber' },
  {
    label: 'Received this month',
    value: formatUGX(billing.payments.filter((p) => p.status === 'confirmed' && (p.reviewedAt ?? '').startsWith(month)).reduce((a, p) => a + p.amount, 0)),
    icon: Wallet,
    tone: 'emerald',
  },
])

// ── Confirm / reject ──
const busyId = ref('')
const msg = ref('')
const err = ref('')
async function confirmPay(p) {
  if (!confirm(`Confirm ${formatUGX(p.amount)} from ${nameOf(p.landlordId)}?\n\nOnly confirm once you have seen the money from a line registered to ${p.senderName}.`)) return
  busyId.value = p.id
  err.value = ''
  try {
    const res = await billing.confirmPayment(p.id)
    await rental.loadLandlords()
    msg.value = `Confirmed. ${nameOf(p.landlordId)} is now subscribed until ${formatDate(res?.until)}.`
  } catch (e) {
    err.value = e.message
  } finally {
    busyId.value = ''
  }
}
const rejecting = ref(null)
const rejectReason = ref('')
async function rejectPay() {
  busyId.value = rejecting.value.id
  err.value = ''
  try {
    await billing.rejectPayment(rejecting.value.id, rejectReason.value)
    msg.value = 'Payment marked as not confirmed. The landlord has been told.'
    rejecting.value = null
    rejectReason.value = ''
  } catch (e) {
    err.value = e.message
  } finally {
    busyId.value = ''
  }
}

// ── Landlords ──
const q = ref('')
const filter = ref('all') // all | paying | unpaid | ended
const shown = computed(() => {
  const term = q.value.trim().toLowerCase()
  return rows.value
    .filter((r) => (filter.value === 'paying' ? r.sub.active && !r.sub.exempt : filter.value === 'unpaid' ? r.sub.state === 'none' : filter.value === 'ended' ? r.sub.state === 'expired' : true))
    .filter((r) => !term || [r.name, r.email, r.phone].some((v) => String(v ?? '').toLowerCase().includes(term)))
    .sort((a, b) => String(a.subscriptionUntil ?? '').localeCompare(String(b.subscriptionUntil ?? '')))
})
const stateLabel = (sub) =>
  sub.exempt ? ['Free for life', 'pill-gold'] : sub.state === 'none' ? ['Not paid yet', 'pill-sky'] : !sub.active ? ['Ended', 'pill-bad'] : sub.state === 'ending' ? ['Ending soon', 'pill-wait'] : ['Active', 'pill-ok']

// Paid in cash → record the package, the subscription is updated at once
const cashFor = ref(null)
const onCash = (r) => (msg.value = `Cash payment recorded. ${cashFor.value?.name || 'The landlord'} now runs until ${formatDate(r.until)}.`)

const granting = ref(null)
const grant = reactive({ days: 30, note: '' })
async function doGrant() {
  err.value = ''
  busyId.value = granting.value.id
  try {
    const until = await billing.grantDays(granting.value.id, grant.days, grant.note)
    await rental.loadLandlords()
    msg.value = `${granting.value.name} now runs until ${formatDate(until)}.`
    granting.value = null
    Object.assign(grant, { days: 30, note: '' })
  } catch (e) {
    err.value = e.message
  } finally {
    busyId.value = ''
  }
}

// ── Settings ──
const form = reactive({ smallMonthly: '', smallYearly: '', bigMonthly: '', bigYearly: '', smallMaxUnits: '', mtnPhone: '', mtnName: '', airtelPhone: '', airtelName: '' })
watch(
  () => billing.settings,
  (s) =>
    Object.assign(form, {
      smallMonthly: s.prices.small.monthly, smallYearly: s.prices.small.yearly,
      bigMonthly: s.prices.big.monthly, bigYearly: s.prices.big.yearly,
      smallMaxUnits: s.smallMaxUnits,
      mtnPhone: s.raw.mtn_phone ?? '', mtnName: s.raw.mtn_name ?? '', airtelPhone: s.raw.airtel_phone ?? '', airtelName: s.raw.airtel_name ?? '',
    }),
  { immediate: true },
)
const saving = ref(false)
async function saveSettings() {
  saving.value = true
  err.value = ''
  try {
    await billing.saveSettings(form)
    msg.value = 'Prices and payment numbers saved. Landlords see them straight away.'
  } catch (e) {
    err.value = e.message
  } finally {
    saving.value = false
  }
}
const recent = computed(() => billing.payments.filter((p) => p.status !== 'pending').slice(0, 30))
</script>

<template>
  <div>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="text-xs font-semibold tracking-[0.16em] text-brand-700 uppercase">Money</p>
        <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900">Subscriptions</h1>
        <p class="mt-1 text-sm text-slate-500">Landlords pay Renta UG monthly or yearly. Confirm payments once the money arrives.</p>
      </div>
    </header>

    <p v-if="billing.unavailable" class="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
      Run <code>database/update_existing.sql</code> in Supabase to switch on subscriptions.
    </p>

    <template v-else>
      <p v-if="msg" class="mb-4 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{{ msg }}</p>
      <p v-if="err" class="mb-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ err }}</p>

      <!-- Figures -->
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <div v-for="k in kpis" :key="k.label" class="sheet p-4" :class="`kpi-${k.tone}`">
          <span class="kpi-ico"><component :is="k.icon" class="size-4" /></span>
          <p class="mt-3 text-xl font-bold tracking-tight text-slate-900 tabular-nums">{{ k.value }}</p>
          <p class="text-xs text-slate-500">{{ k.label }}</p>
        </div>
      </div>

      <!-- Waiting payments -->
      <section class="mt-8">
        <h2 class="flex items-center gap-2 text-lg font-semibold text-slate-900"><Clock class="size-5 text-amber-600" /> Payments to confirm</h2>
        <div v-if="!billing.pending.length" class="sheet mt-3 p-6 text-center text-sm text-slate-500">Nothing waiting. New payments appear here straight away.</div>
        <div v-else class="mt-3 grid gap-3">
          <article v-for="p in billing.pending" :key="p.id" class="sheet flex flex-wrap items-center gap-4 p-4 sm:p-5">
            <span class="flex size-11 shrink-0 items-center justify-center rounded-xl text-xs font-extrabold" :style="{ background: NETWORKS[p.network].gradient, color: NETWORKS[p.network].ink }">{{ NETWORKS[p.network].short.toUpperCase() }}</span>
            <div class="min-w-0 flex-1">
              <p class="font-semibold text-slate-900">{{ nameOf(p.landlordId) }} · {{ tierName(p.tier) }}, <span class="capitalize">{{ p.plan }}</span></p>
              <p class="mt-0.5 text-sm text-slate-600">
                {{ formatUGX(p.amount) }} sent to your {{ NETWORKS[p.network].short }} line from a line registered to <strong>{{ p.senderName }}</strong>
                <template v-if="p.senderPhone"> ({{ prettyPhone(p.senderPhone) }})</template> on {{ formatDate(p.paidOn) }}
              </p>
              <p class="text-xs text-slate-400">Submitted {{ timeAgo(p.createdAt) }}</p>
            </div>
            <div class="flex gap-2">
              <button type="button" class="btn-secondary h-10 rounded-xl px-3 text-sm" :disabled="busyId === p.id" @click="rejecting = p">
                <CircleX class="size-4" /> Reject
              </button>
              <button type="button" class="btn-primary h-10 rounded-xl px-4 text-sm" :data-busy="busyId === p.id" :disabled="busyId === p.id" @click="confirmPay(p)">
                <CircleCheck class="size-4" /> Confirm
              </button>
            </div>
          </article>
        </div>
      </section>

      <!-- Landlords -->
      <section class="mt-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="flex items-center gap-2 text-lg font-semibold text-slate-900"><Users class="size-5 text-brand-600" /> Landlords</h2>
          <div class="flex flex-wrap items-center gap-2">
            <div class="relative">
              <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
              <input v-model="q" class="input h-10 w-56 pl-9 text-sm" placeholder="Name, email or phone" />
            </div>
            <div class="flex rounded-xl bg-slate-100 p-1 text-xs font-semibold">
              <button v-for="f in [['all', 'All'], ['paying', 'Paying'], ['unpaid', 'Not paid'], ['ended', 'Ended']]" :key="f[0]" type="button" class="rounded-lg px-3 py-1.5" :class="filter === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="filter = f[0]">{{ f[1] }}</button>
            </div>
          </div>
        </div>
        <div class="sheet mt-3 overflow-x-auto">
          <table class="w-full min-w-[40rem] text-sm">
            <thead class="bg-slate-50 text-left text-xs font-semibold tracking-wide text-slate-500 uppercase">
              <tr><th class="px-5 py-3">Landlord</th><th class="px-5 py-3">Phone</th><th class="px-5 py-3">Status</th><th class="px-5 py-3">Covered until</th><th class="px-5 py-3 text-right" /></tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="r in shown" :key="r.id">
                <td class="px-5 py-3"><RouterLink :to="`/admin2026/landlords/${r.id}`" class="font-medium text-slate-900 hover:text-brand-700">{{ r.name || r.email }}</RouterLink><p class="text-xs text-slate-500">{{ r.email }}</p></td>
                <td class="px-5 py-3 text-xs text-slate-600">{{ r.phone ? prettyPhone(r.phone) : '—' }}</td>
                <td class="px-5 py-3">
                  <span class="pill" :class="stateLabel(r.sub)[1]">{{ stateLabel(r.sub)[0] }}</span>
                  <span v-if="r.subscriptionPlan && !r.sub.exempt" class="ml-1.5 text-xs text-slate-500">{{ tierName(r.subscriptionTier) }} · <span class="capitalize">{{ r.subscriptionPlan }}</span></span>
                  <p class="mt-0.5 text-[11px] text-slate-400">{{ r.units }} house{{ r.units === 1 ? '' : 's' }}/rooms<template v-if="r.plannedUnits"> · plans {{ r.plannedUnits }}</template><template v-if="!r.sub.exempt && Math.max(r.units, r.plannedUnits ?? 0) > billing.settings.smallMaxUnits"> · needs Big scale</template></p>
                </td>
                <td class="px-5 py-3 text-slate-700">
                  <template v-if="r.sub.exempt">Never ends</template>
                  <template v-else>{{ formatDate(r.subscriptionUntil) }}<span v-if="r.sub.active" class="ml-1 text-xs text-slate-400">({{ r.sub.daysLeft }}d left)</span></template>
                </td>
                <td class="px-5 py-3 text-right">
                  <span v-if="!r.sub.exempt" class="inline-flex items-center gap-3">
                    <button type="button" class="inline-flex items-center gap-1 text-xs font-semibold text-amber-700" @click="cashFor = r"><Banknote class="size-4" /> Paid cash</button>
                    <button type="button" class="inline-flex items-center gap-1 text-xs font-semibold text-brand-700" @click="granting = r"><CirclePlus class="size-4" /> Add days</button>
                  </span>
                </td>
              </tr>
              <tr v-if="!shown.length"><td colspan="5" class="px-5 py-8 text-center text-slate-500">No landlords here.</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <div class="mt-8 grid gap-6 lg:grid-cols-2">
        <!-- Settings -->
        <section class="sheet p-5 sm:p-6">
          <h2 class="flex items-center gap-2 text-lg font-semibold text-slate-900"><Settings2 class="size-5 text-brand-600" /> Prices and payment numbers</h2>
          <form class="mt-4 grid gap-4 sm:grid-cols-3" @submit.prevent="saveSettings">
            <div class="sm:col-span-3 grid gap-4 rounded-2xl bg-slate-50 p-4 sm:grid-cols-2">
              <p class="text-xs font-semibold tracking-wide text-slate-500 uppercase sm:col-span-2">Small scale</p>
              <div><label class="label" for="bs-sm">Monthly (UGX)</label><input id="bs-sm" v-model="form.smallMonthly" class="input tabular-nums" inputmode="numeric" /></div>
              <div><label class="label" for="bs-sy">Yearly (UGX)</label><input id="bs-sy" v-model="form.smallYearly" class="input tabular-nums" inputmode="numeric" /></div>
              <p class="text-xs font-semibold tracking-wide text-slate-500 uppercase sm:col-span-2">Big scale</p>
              <div><label class="label" for="bs-bm">Monthly (UGX)</label><input id="bs-bm" v-model="form.bigMonthly" class="input tabular-nums" inputmode="numeric" /></div>
              <div><label class="label" for="bs-by">Yearly (UGX)</label><input id="bs-by" v-model="form.bigYearly" class="input tabular-nums" inputmode="numeric" /></div>
            </div>
            <div class="sm:col-span-3"><label class="label" for="bs-u">Small scale covers up to (houses + rooms)</label><input id="bs-u" v-model="form.smallMaxUnits" class="input tabular-nums" inputmode="numeric" /></div>
            <div class="sm:col-span-3 grid gap-4 rounded-2xl bg-slate-50 p-4 sm:grid-cols-2">
              <div><label class="label" for="bs-mp">MTN number</label><input id="bs-mp" v-model="form.mtnPhone" class="input" type="tel" placeholder="0772 123 456" /></div>
              <div><label class="label" for="bs-mn">Name MTN shows</label><input id="bs-mn" v-model="form.mtnName" class="input uppercase" placeholder="RENTA UG" /></div>
              <div><label class="label" for="bs-ap">Airtel number</label><input id="bs-ap" v-model="form.airtelPhone" class="input" type="tel" placeholder="0752 123 456" /></div>
              <div><label class="label" for="bs-an">Name Airtel shows</label><input id="bs-an" v-model="form.airtelName" class="input uppercase" placeholder="RENTA UG" /></div>
            </div>
            <p class="text-xs text-slate-500 sm:col-span-2">There is no free trial: a new landlord's account opens once you confirm their first payment. Leave a number empty to hide that network.</p>
            <button type="submit" class="btn-primary h-11 rounded-xl" :data-busy="saving" :disabled="saving"><Save class="size-4" /> {{ saving ? 'Saving…' : 'Save' }}</button>
          </form>
        </section>

        <!-- Recent -->
        <section class="sheet p-5 sm:p-6">
          <h2 class="text-lg font-semibold text-slate-900">Recent decisions</h2>
          <ul v-if="recent.length" class="mt-3 divide-y divide-slate-100 text-sm">
            <li v-for="p in recent" :key="p.id" class="flex items-center justify-between gap-3 py-2.5">
              <span class="min-w-0">
                <span class="block truncate font-medium text-slate-900">{{ nameOf(p.landlordId) }} · <span class="capitalize">{{ p.plan }}</span></span>
                <span class="block text-xs text-slate-500">{{ paidWith(p.network) }} · {{ formatDate(p.paidOn) }}<template v-if="p.periodEnd"> · to {{ formatDate(p.periodEnd) }}</template></span>
              </span>
              <span class="text-right">
                <span class="block font-semibold text-slate-900 tabular-nums">{{ formatUGX(p.amount) }}</span>
                <span class="text-xs capitalize" :class="p.status === 'confirmed' ? 'text-emerald-700' : 'text-slate-400'">{{ p.status }}</span>
              </span>
            </li>
          </ul>
          <p v-else class="mt-3 text-sm text-slate-500">No confirmed or rejected payments yet.</p>
        </section>
      </div>
    </template>

    <!-- Reject -->
    <BaseModal :model-value="Boolean(rejecting)" center width="max-w-md" title="Reject payment" @update:model-value="!$event && (rejecting = null)">
      <form v-if="rejecting" class="space-y-4" @submit.prevent="rejectPay">
        <p class="text-sm text-slate-600">{{ formatUGX(rejecting.amount) }} from {{ nameOf(rejecting.landlordId) }}. They are told it wasn't confirmed.</p>
        <div><label class="label" for="rj">Reason (shown to the landlord)</label><input id="rj" v-model="rejectReason" class="input" placeholder="e.g. No payment found from these names" maxlength="200" /></div>
        <div class="grid grid-cols-2 gap-2"><button type="button" class="btn-secondary h-11" @click="rejecting = null">Cancel</button><button type="submit" class="btn-primary h-11" :disabled="busyId === rejecting.id">Reject</button></div>
      </form>
    </BaseModal>

    <CashSubscriptionModal :landlord="cashFor" @close="cashFor = null" @done="onCash" />

    <!-- Add days -->
    <BaseModal :model-value="Boolean(granting)" center width="max-w-md" title="Add free days" @update:model-value="!$event && (granting = null)">
      <form v-if="granting" class="space-y-4" @submit.prevent="doGrant">
        <p class="text-sm text-slate-600">{{ granting.name || granting.email }} · covered until {{ formatDate(granting.subscriptionUntil) }}.</p>
        <div class="flex flex-wrap gap-2">
          <button v-for="d in [7, 30, 90, 365]" :key="d" type="button" class="rounded-full px-3 py-1.5 text-xs font-semibold" :class="Number(grant.days) === d ? 'bg-brand-600 text-white' : 'bg-slate-100 text-slate-600'" @click="grant.days = d">{{ d }} days</button>
        </div>
        <div><label class="label" for="gd">Days</label><input id="gd" v-model="grant.days" class="input" inputmode="numeric" /></div>
        <div><label class="label" for="gn">Note (shown to the landlord)</label><input id="gn" v-model="grant.note" class="input" placeholder="e.g. Paid in cash at the office" maxlength="200" /></div>
        <div class="grid grid-cols-2 gap-2"><button type="button" class="btn-secondary h-11" @click="granting = null">Cancel</button><button type="submit" class="btn-primary h-11" :disabled="busyId === granting.id">Add days</button></div>
      </form>
    </BaseModal>
  </div>
</template>

<style scoped>
.kpi-ico { display: flex; width: 2rem; height: 2rem; align-items: center; justify-content: center; border-radius: 0.7rem; }
.kpi-teal .kpi-ico { color: var(--color-brand-700); background: var(--color-brand-50); }
.kpi-sky .kpi-ico { color: var(--color-sky-700); background: var(--color-sky-50); }
.kpi-red .kpi-ico { color: var(--color-red-700); background: var(--color-red-50); }
.kpi-amber .kpi-ico { color: var(--color-amber-700); background: var(--color-amber-50); }
.kpi-emerald .kpi-ico { color: var(--color-emerald-700); background: var(--color-emerald-50); }
.pill { display: inline-flex; align-items: center; border-radius: 9999px; padding: 0.15rem 0.55rem; font-size: 0.72rem; font-weight: 600; }
.pill-ok { color: var(--color-emerald-700); background: var(--color-emerald-50); }
.pill-wait { color: var(--color-amber-700); background: var(--color-amber-50); }
.pill-bad { color: var(--color-red-700); background: var(--color-red-50); }
.pill-sky { color: var(--color-sky-700); background: var(--color-sky-50); }
.pill-gold { color: #713f12; background: #fef3c7; }
</style>
