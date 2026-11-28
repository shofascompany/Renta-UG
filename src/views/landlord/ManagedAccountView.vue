<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeft, Phone, Banknote, Smartphone, DoorOpen, CalendarClock, Wallet, Trash2, LogOut, Pencil, MessageCircle, ImageDown,
  Loader2, Mail, User, Timer, CalendarX, CalendarCheck, Save, X, KeyRound,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useReceiptDownload } from '@/composables/useReceiptDownload'
import { rentalTime } from '@/lib/receiptImage'
import { isValidPhone, samePhone, toE164, prettyPhone } from '@/lib/phone'
import { timeLeft } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import { rentDaysLeft } from '@/lib/now'
import RecordPaymentModal from '@/components/RecordPaymentModal.vue'
import DeleteTenantModal from '@/components/DeleteTenantModal.vue'
import EndTenancyModal from '@/components/EndTenancyModal.vue'
import EditPaymentModal from '@/components/EditPaymentModal.vue'
import PhoneInput from '@/components/PhoneInput.vue'
import AppInvite from '@/components/AppInvite.vue'
import EmptyState from '@/components/EmptyState.vue'

// Full account page for a tenant without a smartphone: the landlord runs everything from here:
// their details (all editable), rental time, every payment (editable, with receipts to download or send on
// WhatsApp), and an invite link for when they get a smartphone.
const props = defineProps({ id: String })
const rental = useRentalStore()
const router = useRouter()
const { saving, saveRevenue, shareRevenue, canShare, windowsFor } = useReceiptDownload()

const showCash = ref(false)
const payAmount = ref(0)
function recordPay(amount = 0) {
  payAmount.value = amount
  showCash.value = true
}
const deleteOpen = ref(false)
const endOpen = ref(false) // End tenancy instead (history kept in Records)

const t = computed(() => rental.tenantById(props.id))
const house = computed(() => t.value && rental.propertyById(t.value.propertyId))
const dues = computed(() => (t.value ? rental.duesForTenant(t.value.id) : []))
const owed = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
const pay = computed(() => (t.value ? rental.payStateFor(t.value.id) : null)) // Paid / Part paid / Not paid
const pendingCash = computed(() => (t.value ? rental.cashForTenant(t.value.id).filter((c) => c.status === 'pending') : []))
const left = computed(() => rentDaysLeft(t.value))
const initials = (name) => (name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()
const canEditPayments = computed(() => t.value?.managedByLandlord === true)

// ── Payments and the rental time each one bought ──
const receipts = computed(() =>
  t.value ? rental.payment_receipts.filter((r) => r.tenantId === t.value.id).sort((a, b) => String(b.receivedAt).localeCompare(String(a.receivedAt))) : [],
)
const windows = computed(() => (t.value ? windowsFor(t.value.id) : new Map()))
const when = (d) => (d ? new Date(d).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—')

// Last paid: when it was paid, how long it gives, when the rent ends
const last = computed(() => {
  const r = receipts.value[0]
  if (!r) return null
  const w = windows.value.get(r.id)
  return { paidAt: r.receivedAt, days: w?.days ?? 0, ends: w?.to ?? t.value?.leaseEnd ?? null }
})

// Recent months: the same three facts for each rent month
const history = computed(() =>
  (t.value ? rental.paymentsForTenant(t.value.id).slice(0, 4) : []).map((p) => {
    const rs = receipts.value.filter((r) => r.paymentId === p.id)
    const ws = rs.map((r) => windows.value.get(r.id)).filter(Boolean)
    return {
      p,
      paidAt: rs[0]?.receivedAt ?? null, // receipts are newest first
      days: ws.reduce((s, w) => s + w.days, 0),
      ends: ws.map((w) => w.to).sort().at(-1) ?? null,
    }
  }),
)

const showAll = ref(false)
const shownReceipts = computed(() => (showAll.value ? receipts.value : receipts.value.slice(0, 5)))
const forReceipt = (r) => {
  const p = rental.payments.find((x) => x.id === r.paymentId)
  return { id: r.id, paymentId: r.paymentId, tenantId: r.tenantId, propertyId: p?.propertyId, period: p?.period, amount: r.amount, method: r.method, reference: r.reference, note: r.note, at: r.receivedAt }
}

// ── Edit a payment ──
const editing = ref(null)
const editOpen = computed({ get: () => Boolean(editing.value), set: (v) => !v && (editing.value = null) })

// ── Edit their details ──
const editDetails = ref(false)
const form = reactive({ name: '', email: '', phone: '' })
const detailError = ref('')
const detailSaving = ref(false)
function startEdit() {
  Object.assign(form, { name: t.value.name ?? '', email: t.value.email ?? '', phone: toE164(t.value.phone) || '' })
  detailError.value = ''
  editDetails.value = true
}
// Opened from a tenant's page with "Edit" (?edit=1): the details form is already open
const route = useRoute()
watch(
  () => t.value?.id,
  (id) => {
    if (id && route.query.edit === '1' && !editDetails.value) startEdit()
  },
  { immediate: true },
)

const canEditPhone = computed(() => Boolean(t.value && (t.value.managedByLandlord || !t.value.userId)))

async function saveDetails() {
  detailError.value = ''
  const name = form.name.trim()
  const email = form.email.trim()
  if (name.length < 2) return (detailError.value = "Enter the tenant's name.")
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return (detailError.value = 'That email address does not look right.')
  if (canEditPhone.value && !isValidPhone(form.phone)) return (detailError.value = 'Enter their phone number: pick the country, then type the number.')
  const clash = rental.currentTenants.find((x) => x.id !== t.value.id && samePhone(x.phone, form.phone))
  if (clash) return (detailError.value = `${clash.name} already uses this phone number.`)
  detailSaving.value = true
  try {
    const phone = toE164(form.phone)
    // Login already created but never used: the number they sign in with changes too
    if (canEditPhone.value && t.value.userId && !samePhone(phone, t.value.phone)) await rental.changeManagedPhone(t.value.id, phone)
    await rental.updateTenantDetails(t.value.id, { name, email, phone: canEditPhone.value ? phone : t.value.phone })
    editDetails.value = false
  } catch (e) {
    detailError.value = e.code === '23505' ? 'A current tenant already uses this email.' : e.message
  } finally {
    detailSaving.value = false
  }
}

// ── Invite to the app (WhatsApp) ──
// The link opens the website → sign in with the number from the message → add their details. Nothing to install.
const hasAccess = computed(() => Boolean(t.value?.userId))
const accessBusy = ref(false)
const accessError = ref('')
async function giveAccess() {
  accessError.value = ''
  accessBusy.value = true
  try {
    await rental.giveAppAccess(t.value.id)
  } catch (e) {
    accessError.value = e.message
  } finally {
    accessBusy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <RouterLink to="/landlord/managed" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> Managed accounts
    </RouterLink>

    <div v-if="!t" class="sheet"><EmptyState kind="missing" title="Tenant not found" text="It may have been removed, or the link is old." to="/landlord/managed" action="Managed accounts" /></div>

    <template v-else>
      <!-- Account card -->
      <section class="page-hero rise px-5 py-6 sm:px-8">
        <div class="flex items-center gap-3.5">
          <span class="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-white/15 text-lg font-bold ring-1 ring-white/25">{{ initials(t.name) }}</span>
          <div class="min-w-0">
            <p class="truncate text-xl font-semibold">{{ t.name }}</p>
            <p class="truncate text-sm text-white/75">{{ t.phone ? prettyPhone(t.phone) : 'No phone number' }} · <Smartphone v-if="t.usesApp" class="-mt-0.5 inline size-3.5" aria-hidden="true" /> {{ t.usesApp ? 'uses the app' : hasAccess ? 'invited, not registered yet' : 'no smartphone' }}</p>
          </div>
        </div>
        <div class="mt-6 flex items-center gap-2">
          <span class="hero-pay rounded-full px-3 py-1 text-xs font-bold" :class="`hero-pay-${pay?.key}`">{{ pay?.label }}</span>
          <span class="text-sm text-white/80">{{ pay?.detail }}</span>
        </div>
        <p class="mt-2 text-sm text-white/75">{{ pay?.key === 'paid' ? 'Nothing to pay' : 'To pay now' }}</p>
        <p class="mt-0.5 text-4xl font-bold tracking-tight tabular-nums">{{ formatUGX(pay?.owed ?? owed) }}</p>
        <p class="mt-1 text-sm text-white/70">{{ pay?.key === 'paid' ? 'Paid' : t.leaseEnd || dues.length ? pay?.how : 'Not paid yet' }}</p>
        <div class="mt-6 grid grid-cols-2 gap-2.5 sm:max-w-md">
          <button class="hero-btn hero-btn-solid px-2! whitespace-nowrap" @click="recordPay(0)"><Banknote class="size-4" /> Record payment</button>
          <a v-if="t.phone" :href="`tel:${toE164(t.phone) || t.phone}`" class="hero-btn hero-btn-glass"><Phone class="size-4" /> Call</a>
          <RouterLink v-else :to="`/landlord/properties/${t.propertyId}`" class="hero-btn hero-btn-glass">Details</RouterLink>
        </div>
      </section>

      <p v-if="pendingCash.length" class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
        {{ formatUGX(pendingCash.reduce((s, c) => s + c.amount, 0)) }} in cash is waiting for confirmation.
      </p>

      <div class="mt-5 grid gap-5 lg:grid-cols-2">
        <!-- Last paid: when, how long, when it ends -->
        <section class="sheet rise" style="--d: 40ms">
          <h2 class="px-5 pt-4 text-xs font-semibold tracking-[0.12em] text-slate-500 uppercase">Last paid</h2>
          <dl v-if="last" class="divide-y divide-slate-100 text-sm">
            <div class="flex items-center gap-3 px-5 py-3.5">
              <span class="icon-disc disc-emerald size-9"><CalendarCheck class="size-4" /></span>
              <dt class="flex-1 text-slate-500">Paid on</dt>
              <dd class="text-right font-medium text-slate-900">{{ when(last.paidAt) }}</dd>
            </div>
            <div class="flex items-center gap-3 px-5 py-3.5">
              <span class="icon-disc disc-sky size-9"><Timer class="size-4" /></span>
              <dt class="flex-1 text-slate-500">Rental time</dt>
              <dd class="text-right font-medium text-slate-900">{{ rentalTime(last.days) }}</dd>
            </div>
            <div class="flex items-center gap-3 px-5 py-3.5">
              <span class="icon-disc size-9" :class="left !== null && left <= 7 ? 'disc-amber' : 'disc-slate'"><CalendarX class="size-4" /></span>
              <dt class="flex-1 text-slate-500">Rent ends</dt>
              <dd class="text-right">
                <p class="font-medium text-slate-900">{{ last.ends ? formatDate(last.ends) : '—' }}</p>
                <p v-if="left !== null" class="text-xs text-slate-500">{{ timeLeft(left) }}</p>
              </dd>
            </div>
          </dl>
          <EmptyState v-else compact kind="time" title="Not paid yet" text="Record the first payment to start their rental time." />
        </section>

        <!-- Their details (all editable) -->
        <section class="sheet rise" style="--d: 80ms">
          <div class="flex items-center justify-between px-5 pt-4">
            <h2 class="text-xs font-semibold tracking-[0.12em] text-slate-500 uppercase">Details</h2>
            <button v-if="!editDetails" type="button" class="inline-flex items-center gap-1 text-xs font-semibold text-brand-700" @click="startEdit"><Pencil class="size-3.5" /> Edit</button>
          </div>

          <dl v-if="!editDetails" class="divide-y divide-slate-100 text-sm">
            <div class="flex items-center gap-3 px-5 py-3.5"><span class="icon-disc disc-brand size-9"><User class="size-4" /></span><dt class="flex-1 text-slate-500">Name</dt><dd class="text-right font-medium text-slate-900">{{ t.name }}</dd></div>
            <div class="flex items-center gap-3 px-5 py-3.5"><span class="icon-disc disc-emerald size-9"><Phone class="size-4" /></span><dt class="flex-1 text-slate-500">Phone</dt><dd class="text-right font-medium text-slate-900">{{ t.phone ? prettyPhone(t.phone) : '—' }}</dd></div>
            <div class="flex items-center gap-3 px-5 py-3.5"><span class="icon-disc disc-sky size-9"><Mail class="size-4" /></span><dt class="flex-1 text-slate-500">Email</dt><dd class="max-w-[60%] truncate text-right font-medium text-slate-900">{{ t.email && !t.email.endsWith('@phone-signin.example.com') ? t.email : '—' }}</dd></div>
            <div class="flex items-center gap-3 px-5 py-3.5"><span class="icon-disc disc-brand size-9"><DoorOpen class="size-4" /></span><dt class="flex-1 text-slate-500">Room</dt><dd class="text-right font-medium text-slate-900">{{ rental.placeName(t.propertyId) }}</dd></div>
            <div class="flex items-center gap-3 px-5 py-3.5"><span class="icon-disc disc-emerald size-9"><Wallet class="size-4" /></span><dt class="flex-1 text-slate-500">Rent</dt><dd class="font-medium text-slate-900">{{ formatUGX(house?.rent) }} a month</dd></div>
            <div class="flex items-center gap-3 px-5 py-3.5"><span class="icon-disc disc-slate size-9"><CalendarClock class="size-4" /></span><dt class="flex-1 text-slate-500">Moved in</dt><dd class="text-right font-medium text-slate-900">{{ t.leaseStart ? formatDate(t.leaseStart) : 'When they first pay' }}</dd></div>
          </dl>

          <form v-else class="space-y-4 p-5" @submit.prevent="saveDetails">
            <div>
              <label class="label" for="md-name">Full name</label>
              <input id="md-name" v-model="form.name" class="input" data-cap="words" required />
            </div>
            <div>
              <label class="label" for="md-phone">Phone number</label>
              <PhoneInput v-if="canEditPhone" id="md-phone" v-model="form.phone" required />
              <p v-else class="text-sm text-slate-600">{{ prettyPhone(t.phone) }} <span class="text-xs text-slate-400">(the number they sign in with)</span></p>
            </div>
            <div>
              <label class="label" for="md-email">Email (optional)</label>
              <input id="md-email" v-model="form.email" type="email" class="input" placeholder="name@example.com" data-cap="off" />
            </div>
            <p v-if="detailError" class="form-error" role="alert">{{ detailError }}</p>
            <div class="grid grid-cols-2 gap-2">
              <button type="button" class="btn-secondary h-11" @click="editDetails = false"><X class="size-4" /> Cancel</button>
              <button type="submit" class="btn-primary h-11" :data-busy="detailSaving" :disabled="detailSaving"><Save class="size-4" /> {{ detailSaving ? 'Saving…' : 'Save' }}</button>
            </div>
          </form>
        </section>
      </div>

      <!-- Recent months: when paid, how long, when it ends -->
      <h2 class="section-title mt-6">Recent months</h2>
      <div class="sheet">
        <ul v-if="history.length" class="divide-y divide-slate-100">
          <li v-for="h in history" :key="h.p.id" class="px-5 py-3.5 text-sm">
            <div class="flex items-center justify-between gap-3">
              <span class="font-medium text-slate-900">{{ formatPeriod(h.p.period) }}</span>
              <span class="flex items-center gap-2">
                <span class="tabular-nums text-slate-700">{{ formatUGX(h.p.status === 'paid' ? h.p.amount : h.p.balance) }}</span>
                <span class="rounded-md px-2 py-0.5 text-xs font-semibold" :class="h.p.status === 'paid' ? 'bg-emerald-50 text-emerald-700' : h.p.status === 'overdue' ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">
                  {{ h.p.status === 'paid' ? 'Paid' : h.p.status === 'overdue' ? 'Overdue' : 'Due' }}
                </span>
              </span>
            </div>
            <p v-if="h.paidAt" class="mt-1 text-xs leading-relaxed text-slate-500">
              Paid {{ when(h.paidAt) }} · {{ rentalTime(h.days) }}<template v-if="h.ends"> · ends {{ formatDate(h.ends) }}</template>
            </p>
            <p v-else class="mt-1 text-xs text-slate-400">Not paid yet</p>
          </li>
        </ul>
        <EmptyState v-else compact kind="time" title="No rent months yet" text="They appear with the first payment." />
      </div>

      <!-- Every payment: receipt, WhatsApp, edit -->
      <div class="mt-6 flex items-baseline justify-between">
        <h2 class="section-title">Payments</h2>
        <button v-if="receipts.length > 5" type="button" class="mb-2.5 text-xs font-semibold text-brand-700" @click="showAll = !showAll">{{ showAll ? 'Show fewer' : `Show all ${receipts.length}` }}</button>
      </div>
      <div class="sheet">
        <ul v-if="receipts.length" class="divide-y divide-slate-100">
          <li v-for="r in shownReceipts" :key="r.id" class="px-5 py-3.5">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(r.amount) }}</p>
                <p class="mt-0.5 truncate text-xs text-slate-500">{{ when(r.receivedAt) }} · {{ r.method }}</p>
                <p v-if="windows.get(r.id)?.days" class="mt-0.5 text-xs text-slate-500">{{ rentalTime(windows.get(r.id).days) }} · ends {{ formatDate(windows.get(r.id).to) }}</p>
                <p v-if="r.note" class="mt-0.5 truncate text-xs text-slate-400">{{ r.note }}</p>
              </div>
              <div class="flex shrink-0 items-center gap-1.5">
                <button type="button" class="pay-ico-btn" :disabled="Boolean(saving)" title="Download receipt" :aria-label="`Download the receipt for ${formatUGX(r.amount)}`" @click="saveRevenue(forReceipt(r))">
                  <Loader2 v-if="saving === r.id" class="size-4 animate-spin" /><ImageDown v-else class="size-4" />
                </button>
                <button v-if="canShare" type="button" class="pay-ico-btn text-[#128c4a]" title="Share on WhatsApp" :aria-label="`Share the receipt for ${formatUGX(r.amount)} on WhatsApp`" @click="shareRevenue(forReceipt(r))">
                  <MessageCircle class="size-4" />
                </button>
                <button v-if="canEditPayments" type="button" class="pay-ico-btn" title="Edit payment" :aria-label="`Edit the payment of ${formatUGX(r.amount)}`" @click="editing = r">
                  <Pencil class="size-4" />
                </button>
              </div>
            </div>
          </li>
        </ul>
        <EmptyState v-else compact kind="money" title="No payments yet" text="Payments you record for them appear here." />
      </div>

      <!-- Invite to the app on WhatsApp -->
      <section class="sheet rise mt-6 p-5" style="--d: 120ms">
        <div class="flex items-start gap-3.5">
          <span class="icon-disc disc-sky size-11 shrink-0"><Smartphone class="size-5" /></span>
          <div class="min-w-0 flex-1">
            <p class="font-semibold text-slate-900">{{ t.usesApp ? 'On the app' : hasAccess ? 'App invite' : 'Got a smartphone?' }}</p>
            <p v-if="t.usesApp" class="mt-0.5 text-sm text-slate-500">They have registered and manage their own account.</p>
            <p v-else class="mt-0.5 text-sm text-slate-500">
              Send them the Renta UG link on WhatsApp, with the number they sign in with. It opens on any phone, with nothing to install. They become a smartphone tenant once they have registered.
            </p>
          </div>
        </div>

        <p v-if="!t.phone && !t.usesApp" class="mt-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">Add their phone number first (Details → Edit). They sign in with it.</p>
        <template v-else>
          <button v-if="!hasAccess" type="button" class="btn-primary mt-4 h-12 w-full" :data-busy="accessBusy" :disabled="accessBusy" @click="giveAccess">
            <KeyRound class="size-4.5" /> {{ accessBusy ? 'Setting up…' : 'Give app access' }}
          </button>
          <AppInvite v-else :tenant-id="t.id" class="mt-4" />
          <p v-if="accessError" class="form-error mt-3" role="alert">{{ accessError }}</p>
        </template>
      </section>

      <!-- Remove -->
      <div class="mt-5 grid gap-2.5 sm:grid-cols-2">
        <button type="button" class="btn-secondary h-12 rounded-2xl border-red-200 text-red-600 hover:bg-red-50" @click="endOpen = true"><LogOut class="size-4.5" /> End tenancy</button>
        <button type="button" class="btn h-12 rounded-2xl bg-red-600 text-white hover:bg-red-700" @click="deleteOpen = true"><Trash2 class="size-4.5" /> Delete tenant</button>
      </div>

      <RecordPaymentModal v-model="showCash" :tenant-id="t.id" :preset-amount="payAmount" />
      <EditPaymentModal v-model="editOpen" :receipt="editing" />
      <DeleteTenantModal v-model="deleteOpen" :tenant="t" @deleted="router.replace('/landlord/managed')" @end-instead="endOpen = true" />
      <EndTenancyModal v-model="endOpen" :tenant="t" @ended="router.replace('/landlord/managed')" @record="recordPay" />
    </template>
  </div>
</template>

<style scoped>
.hero-pay { --color-white: #fff; color: #fff; }
.hero-pay-paid { background: #059669; }
.hero-pay-part { background: #d97706; }
.hero-pay-unpaid { background: #dc2626; }
.pay-ico-btn { display: flex; width: 2.25rem; height: 2.25rem; align-items: center; justify-content: center; border-radius: 0.6rem; background: var(--color-slate-50); color: var(--color-brand-700); transition: transform 0.15s, background-color 0.15s; }
.pay-ico-btn:hover { background: var(--color-brand-50); }
.pay-ico-btn:active { transform: scale(0.93); }
.pay-ico-btn:disabled { opacity: 0.5; }
</style>
