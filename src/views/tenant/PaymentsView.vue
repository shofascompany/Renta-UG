<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import {
  CheckCircle2, Receipt, Wallet, X, Zap, ArrowDownLeft, Clock, AlertCircle, Smartphone, Banknote, ChevronRight, Copy, Check, CalendarDays,
} from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import ListRow from '@/components/admin/ListRow.vue'
import BaseModal from '@/components/BaseModal.vue'
import PayRentForm from '@/components/PayRentForm.vue'

const { rental, id, property, payments, dues, balance } = useTenant()

// ── Cash paid to the landlord (confirmed by the landlord or Renta UG before it counts) ──
const todayISO = () => new Date().toLocaleDateString('en-CA')
const myCash = computed(() => rental.cashForTenant(id.value))
const cashStyle = {
  pending: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  confirmed: 'bg-emerald-50 text-emerald-700 ring-emerald-600/15',
  rejected: 'bg-red-50 text-red-700 ring-red-600/15',
}
const cashOpen = ref(false)
const cashSent = ref(false)
const cashBusy = ref(false)
const cashError = ref('')
const cash = reactive({ amount: '', paidOn: todayISO(), note: '' })
const cashValue = computed(() => Math.round(Number(String(cash.amount).replace(/[^\d]/g, '')) || 0))

function openCash() {
  Object.assign(cash, { amount: '', paidOn: todayISO(), note: '' })
  cashSent.value = false
  cashError.value = ''
  cashOpen.value = true
}
async function sendCash() {
  cashError.value = ''
  cashBusy.value = true
  try {
    await rental.submitCash({ amount: cashValue.value, paidOn: cash.paidOn, note: cash.note })
    cashSent.value = true
  } catch (e) {
    cashError.value = e.message
  } finally {
    cashBusy.value = false
  }
}

const paying = ref(null)
const justPaid = ref(false)
const filter = ref('all') // all | paid | unpaid

const overdue = computed(() => dues.value.some((d) => d.status === 'overdue'))

// History: newest month first
const history = computed(() =>
  [...payments.value]
    .sort((a, b) => b.period.localeCompare(a.period))
    .filter((p) => (filter.value === 'paid' ? p.status === 'paid' : filter.value === 'unpaid' ? p.status !== 'paid' : true)),
)

// ── Payment details (tap a history row) ──
const detail = ref(null)
const detailReceipts = computed(() =>
  detail.value
    ? rental.payment_receipts.filter((r) => r.paymentId === detail.value.id).sort((a, b) => b.receivedAt.localeCompare(a.receivedAt))
    : [],
)
const periodRange = (period) => {
  const [y, m] = period.split('-').map(Number)
  const opts = { day: 'numeric', month: 'short', year: 'numeric' }
  return `${new Date(y, m - 1, 1).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} – ${new Date(y, m, 0).toLocaleDateString('en-GB', opts)}`
}
const copied = ref(false)
function copyRef(text) {
  const done = () => {
    copied.value = true
    setTimeout(() => (copied.value = false), 1500)
  }
  if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text).then(done).catch(() => {})
  const el = document.createElement('textarea')
  el.value = text
  el.style.cssText = 'position:fixed;opacity:0'
  document.body.appendChild(el)
  el.select()
  try {
    if (document.execCommand('copy')) done()
  } catch {
    /* not supported */
  }
  el.remove()
}
watch(detail, (v) => (document.body.style.overflow = v ? 'hidden' : ''))
onBeforeUnmount(() => (document.body.style.overflow = ''))

const paidOn = (iso) =>
  new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
const methodIcon = (m) => (/cash/i.test(m ?? '') ? Banknote : Smartphone)

// ── Rotating tips in the banner (change every 4 s) ──
const tips = computed(() => {
  const list = []
  if (dues.value.length) list.push({ icon: AlertCircle, text: `You have ${formatUGX(balance.value)} to pay. Pay now to keep your rental time running.` })
  else list.push({ icon: CheckCircle2, text: 'You are all paid up. Recharge any time to pay months ahead.' })
  list.push(
    { icon: Zap, text: 'Recharge early: each payment adds a full month on top of the time you already have.' },
    { icon: Smartphone, text: 'Pay with MTN or Airtel Mobile Money. Your rent updates as soon as the payment goes through.' },
    { icon: Receipt, text: 'Every payment gets a receipt. Tap any month below to see its details.' },
    { icon: CalendarDays, text: 'Your rental time starts the day you pay and runs one month for every month paid.' },
  )
  return list
})
const tipIndex = ref(0)
const tipTimer = setInterval(() => (tipIndex.value = (tipIndex.value + 1) % tips.value.length), 4000)
onBeforeUnmount(() => clearInterval(tipTimer))

async function onPaid() {
  paying.value = null
  justPaid.value = true
  await Promise.all([rental.reload('payments'), rental.reload('notifications')])
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <!-- Summary banner -->
    <header class="rise banner relative overflow-hidden rounded-3xl p-6 text-white sm:p-8" :class="overdue && 'banner-overdue'" style="--d: 0ms">
      <div class="grid-pattern" aria-hidden="true" />
      <div class="glow" aria-hidden="true" />

      <div class="relative">
        <!-- 1. The house's rent per month -->
        <p class="text-xs font-semibold tracking-[0.14em] text-white/70 uppercase">Monthly rent</p>
        <p class="mt-1.5 flex items-baseline gap-2">
          <span class="text-3xl font-bold tracking-tight tabular-nums sm:text-4xl">{{ formatUGX(property?.rent) }}</span>
          <span class="text-sm text-white/70">/ month</span>
        </p>
        <p v-if="property" class="mt-1 truncate text-sm text-white/70">{{ property.name }}</p>

        <div class="mt-6 grid gap-2.5" :class="dues.length ? 'grid-cols-2' : 'grid-cols-1'">
          <button v-if="dues.length" class="hero-btn hero-btn-solid" @click="paying = dues[0]">
            <Wallet class="size-4" /> Pay now
          </button>
          <RouterLink to="/tenant/recharge" class="hero-btn" :class="dues.length ? 'hero-btn-glass' : 'hero-btn-solid'">
            <Zap class="size-4" /> Recharge
          </RouterLink>
        </div>

        <!-- Rotating tips -->
        <div class="mt-4 min-h-[2.5rem] overflow-hidden" aria-live="polite">
          <Transition name="tip" mode="out-in">
            <p :key="tipIndex" class="text-center text-[13px] leading-snug text-white/85">{{ tips[tipIndex].text }}</p>
          </Transition>
        </div>
      </div>
    </header>

    <!-- Cash reported by the tenant -->
    <section v-if="myCash.length" class="rise mt-6" style="--d: 60ms">
      <h2 class="section-title">Cash payments</h2>
      <div class="sheet">
        <ul class="divide-y divide-slate-100">
          <ListRow
            v-for="c in myCash"
            :key="c.id"
            :chevron="false"
            title="Cash"
            :subtitle="`${formatDate(c.paidOn)}${c.status === 'rejected' && c.rejectReason ? ` · ${c.rejectReason}` : ''}`"
            :value="formatUGX(c.status === 'confirmed' ? c.confirmedAmount : c.amount)"
            :value-sub="c.status === 'pending' ? 'waiting' : c.status === 'confirmed' ? 'confirmed' : 'not confirmed'"
            :value-class="c.status === 'confirmed' ? 'text-emerald-700' : c.status === 'rejected' ? 'text-red-600' : 'text-amber-700'"
          >
            <template #icon><span class="icon-disc disc-amber"><Banknote class="size-5" /></span></template>
          </ListRow>
        </ul>
      </div>
    </section>

    <!-- Report cash -->
    <BaseModal v-model="cashOpen" title="Paid in cash" width="max-w-md">
      <div v-if="cashSent" class="py-2 text-center">
        <CheckCircle2 class="mx-auto size-10 text-emerald-600" />
        <p class="mt-3 font-medium text-slate-900">Sent for confirmation</p>
        <p class="mt-1 text-sm text-slate-600">Your landlord will confirm the amount. You'll get a notification once it's added to your rent.</p>
        <button class="btn-primary mt-6 w-full" @click="cashOpen = false">Done</button>
      </div>
      <form v-else class="space-y-4" @submit.prevent="sendCash">
        <p class="rounded-xl bg-slate-50 p-3 text-sm text-slate-600">
          Tell us how much cash you gave your landlord. Once they confirm it, it tops up your rent: first anything unpaid, then the next months ahead.
          <template v-if="balance"> Unpaid rent: <strong class="text-slate-900">{{ formatUGX(balance) }}</strong></template>
        </p>
        <div>
          <label class="label" for="cash-amt">Amount paid (UGX)</label>
          <input id="cash-amt" v-model="cash.amount" class="input" inputmode="numeric" placeholder="e.g. 300000" required />
          <button v-if="balance" type="button" class="mt-1 text-xs font-medium text-brand-600 hover:text-brand-700" @click="cash.amount = String(balance)">
            Full balance ({{ formatUGX(balance) }})
          </button>
          <button v-else-if="property?.rent" type="button" class="mt-1 text-xs font-medium text-brand-600 hover:text-brand-700" @click="cash.amount = String(property.rent)">
            One month ({{ formatUGX(property.rent) }})
          </button>
        </div>
        <div>
          <p class="label">Date paid</p>
          <p class="flex h-[2.875rem] items-center gap-2 rounded-[0.875rem] bg-slate-50 px-3 text-sm font-medium text-slate-700 ring-1 ring-slate-200 ring-inset">
            <CalendarDays class="size-4 text-slate-400" /> Today, {{ formatDate(new Date()) }}
          </p>
        </div>
        <div>
          <label class="label" for="cash-note">Note <span class="font-normal text-slate-400">(optional)</span></label>
          <input id="cash-note" v-model="cash.note" class="input" maxlength="200" placeholder="e.g. Given to the caretaker" />
        </div>
        <p v-if="cashError" class="text-sm text-red-600">{{ cashError }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="cashOpen = false">Cancel</button>
          <button :data-busy="Boolean(cashBusy)" type="submit" class="btn-primary" :disabled="cashBusy || !cashValue">
            <Banknote class="size-4" /> {{ cashBusy ? 'Sending…' : 'Send' }}
          </button>
        </div>
      </form>
    </BaseModal>

    <!-- Payment received -->
    <div v-if="justPaid" class="mt-4 flex items-center gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-4">
      <CheckCircle2 class="size-5 shrink-0 text-emerald-600" />
      <p class="flex-1 text-sm text-emerald-800">Payment received. A confirmation has been sent to your notifications.</p>
      <button class="rounded-lg p-1.5 text-emerald-700 hover:bg-emerald-100" aria-label="Dismiss" @click="justPaid = false"><X class="size-4" /></button>
    </div>

    <!-- To pay -->
    <section v-if="dues.length" class="rise mt-6" style="--d: 80ms">
      <h2 class="section-title">To pay</h2>
      <div class="sheet divide-y divide-slate-100">
        <div v-for="d in dues" :key="d.id" class="flex items-center gap-3.5 px-4 py-4 sm:px-5">
          <span class="icon-disc rounded-full" :class="d.status === 'overdue' ? 'disc-red' : 'disc-amber'">
            <AlertCircle v-if="d.status === 'overdue'" class="size-5" />
            <Clock v-else class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate font-medium text-slate-900">{{ formatPeriod(d.period) }}</p>
            <p class="truncate text-xs text-slate-500">
              <span :class="d.status === 'overdue' && 'font-medium text-red-600'">{{ d.status === 'overdue' ? 'Overdue since' : 'Due' }} {{ formatDate(d.dueDate) }}</span>
              <template v-if="d.amountPaid"> · {{ formatUGX(d.amountPaid) }} paid</template>
            </p>
          </div>
          <div class="flex shrink-0 flex-col items-end gap-1.5 sm:flex-row sm:items-center sm:gap-3">
            <p class="font-semibold text-slate-900 tabular-nums">{{ formatUGX(d.balance) }}</p>
            <button class="pay-btn" @click="paying = d">Pay</button>
          </div>
        </div>
      </div>
    </section>

    <!-- History -->
    <section class="rise mt-6" style="--d: 140ms">
      <div class="mb-2.5 flex items-center justify-between gap-3 px-1">
        <h2 class="section-title !m-0">Payment history</h2>
        <div class="flex rounded-xl border border-slate-200 bg-slate-50 p-0.5 text-xs" role="tablist">
          <button
            v-for="f in [['all', 'All'], ['paid', 'Paid'], ['unpaid', 'Unpaid']]"
            :key="f[0]"
            role="tab"
            :aria-selected="filter === f[0]"
            class="h-8 rounded-lg px-3 font-medium transition-colors"
            :class="filter === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
            @click="filter = f[0]"
          >{{ f[1] }}</button>
        </div>
      </div>

      <div class="sheet">
        <ul v-if="history.length" class="divide-y divide-slate-100">
          <ListRow
            v-for="p in history"
            :key="p.id"
            :title="`${formatPeriod(p.period)} rent`"
            :subtitle="p.paidAt ? `${/cash/i.test(p.method ?? '') ? 'Cash' : p.method || 'Mobile money'} · ${formatDate(p.paidAt)}` : `Due ${formatDate(p.dueDate)}`"
            :value="formatUGX(p.status === 'paid' ? p.amount : p.balance)"
            :value-sub="p.status === 'paid' ? 'paid' : p.status === 'overdue' ? 'overdue' : 'to pay'"
            :value-class="p.status === 'paid' ? 'text-emerald-700' : p.status === 'overdue' ? 'text-red-600' : 'text-amber-700'"
            @click="detail = p"
          >
            <template #icon>
              <span class="icon-disc" :class="p.status !== 'paid' ? (p.status === 'overdue' ? 'disc-red' : 'disc-slate') : /cash/i.test(p.method ?? '') ? 'disc-amber' : 'disc-emerald'">
                <template v-if="p.status === 'paid'">
                  <Banknote v-if="/cash/i.test(p.method ?? '')" class="size-5" />
                  <ArrowDownLeft v-else class="size-5" />
                </template>
                <Clock v-else class="size-5" />
              </span>
            </template>
          </ListRow>
        </ul>
        <div v-else class="flex flex-col items-center px-6 py-12 text-center">
          <span class="flex size-12 items-center justify-center rounded-2xl bg-slate-100 text-slate-400"><Receipt class="size-6" /></span>
          <p class="mt-3 font-medium text-slate-900">{{ filter === 'all' ? 'No payments yet' : `No ${filter} months` }}</p>
          <p class="mt-1 text-sm text-slate-500">Your rent payments will appear here.</p>
        </div>
      </div>
    </section>

    <!-- Payment details -->
    <Teleport to="body">
      <Transition enter-active-class="transition-opacity duration-200" leave-active-class="transition-opacity duration-150" enter-from-class="opacity-0" leave-to-class="opacity-0">
        <div v-if="detail" class="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-[2px]" @click="detail = null" />
      </Transition>
      <Transition name="sheet">
        <div
          v-if="detail"
          class="fixed inset-x-0 bottom-0 z-50 mx-auto w-full max-w-lg sm:inset-y-0 sm:flex sm:items-center sm:p-4"
          role="dialog"
          aria-modal="true"
          :aria-label="`${formatPeriod(detail.period)} rent`"
          @click.self="detail = null"
        >
          <div class="w-full overflow-hidden rounded-t-3xl bg-white shadow-2xl sm:rounded-3xl">
            <!-- Header -->
            <div class="detail-head relative px-6 pt-5 pb-6 text-white" :class="detail.status === 'overdue' && 'detail-head-overdue'">
              <div class="mx-auto mb-4 h-1 w-10 rounded-full bg-white/40 sm:hidden" />
              <button class="absolute top-4 right-4 rounded-full bg-white/15 p-2 transition hover:bg-white/25" aria-label="Close" @click="detail = null">
                <X class="size-4" />
              </button>
              <p class="text-xs font-semibold tracking-[0.12em] text-white/70 uppercase">Rent · {{ formatPeriod(detail.period) }}</p>
              <p class="mt-2 text-3xl font-bold tracking-tight tabular-nums">{{ formatUGX(detail.amount) }}</p>
              <span class="mt-3 inline-flex items-center gap-1.5 rounded-full bg-white/15 px-2.5 py-1 text-xs font-medium ring-1 ring-white/25">
                <CheckCircle2 v-if="detail.status === 'paid'" class="size-3.5" />
                <AlertCircle v-else-if="detail.status === 'overdue'" class="size-3.5" />
                <Clock v-else class="size-3.5" />
                {{ detail.status === 'paid' ? 'Paid in full' : detail.status === 'overdue' ? 'Overdue' : 'Not paid yet' }}
              </span>
            </div>

            <div class="max-h-[55vh] overflow-y-auto px-6 py-5">
              <!-- Facts -->
              <dl class="divide-y divide-slate-100 text-sm">
                <div class="flex justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Rent period</dt>
                  <dd class="text-right font-medium text-slate-900">{{ periodRange(detail.period) }}</dd>
                </div>
                <div class="flex justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Due date</dt>
                  <dd class="font-medium text-slate-900">{{ formatDate(detail.dueDate) }}</dd>
                </div>
                <div class="flex justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Amount paid</dt>
                  <dd class="font-medium text-emerald-700 tabular-nums">{{ formatUGX(detail.amountPaid) }}</dd>
                </div>
                <div v-if="detail.status !== 'paid'" class="flex justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Still to pay</dt>
                  <dd class="font-semibold tabular-nums" :class="detail.status === 'overdue' ? 'text-red-600' : 'text-slate-900'">{{ formatUGX(detail.balance) }}</dd>
                </div>
                <div v-if="detail.paidAt" class="flex justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Paid on</dt>
                  <dd class="text-right font-medium text-slate-900">{{ paidOn(detail.paidAt) }}</dd>
                </div>
                <div v-if="detail.method" class="flex justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Method</dt>
                  <dd class="flex items-center gap-1.5 font-medium text-slate-900"><component :is="methodIcon(detail.method)" class="size-4 text-slate-400" /> {{ detail.method }}</dd>
                </div>
                <div v-if="detail.reference" class="flex items-center justify-between gap-4 py-2.5">
                  <dt class="text-slate-500">Reference</dt>
                  <dd class="flex min-w-0 items-center gap-2">
                    <span class="truncate font-mono text-xs text-slate-900">{{ detail.reference }}</span>
                    <button class="shrink-0 rounded-md p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700" aria-label="Copy reference" @click="copyRef(detail.reference)">
                      <Check v-if="copied" class="size-3.5 text-emerald-600" />
                      <Copy v-else class="size-3.5" />
                    </button>
                  </dd>
                </div>
              </dl>

              <!-- Each amount received for this month -->
              <div v-if="detailReceipts.length" class="mt-5">
                <p class="text-xs font-semibold tracking-[0.12em] text-slate-400 uppercase">Payments received</p>
                <ul class="mt-2 space-y-2">
                  <li v-for="r in detailReceipts" :key="r.id" class="flex items-center gap-3 rounded-xl bg-slate-50 px-3 py-2.5">
                    <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-white text-slate-500 shadow-sm">
                      <component :is="methodIcon(r.method)" class="size-4" />
                    </span>
                    <div class="min-w-0 flex-1">
                      <p class="truncate text-sm font-medium text-slate-900">{{ r.method }}</p>
                      <p class="truncate text-xs text-slate-500">{{ paidOn(r.receivedAt) }}</p>
                    </div>
                    <p class="shrink-0 text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(r.amount) }}</p>
                  </li>
                </ul>
              </div>
            </div>

            <div v-if="detail.status !== 'paid'" class="border-t border-slate-100 p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
              <button class="btn-primary h-12 w-full text-base" @click="paying = detail; detail = null">
                <Wallet class="size-4.5" /> Pay {{ formatUGX(detail.balance) }}
              </button>
            </div>
            <div v-else class="pb-[env(safe-area-inset-bottom)]" />
          </div>
        </div>
      </Transition>
    </Teleport>

    <BaseModal :model-value="Boolean(paying)" title="Pay rent" @update:model-value="!$event && (paying = null)">
      <PayRentForm v-if="paying" :payment="paying" @paid="onPaid" @cancel="paying = null" />
    </BaseModal>
  </div>
</template>

<style scoped>
/* Rotating tips: plain words that slide and fade */
.tip-enter-active, .tip-leave-active { transition: opacity 0.35s ease, transform 0.35s cubic-bezier(0.22, 1, 0.36, 1); }
.tip-enter-from { opacity: 0; transform: translateY(10px); }
.tip-leave-to { opacity: 0; transform: translateY(-10px); }
@media (prefers-reduced-motion: reduce) {
  .tip-enter-active, .tip-leave-active { transition: opacity 0.2s; transform: none; }
}

/* Banner: fixed colours, the same in light and dark mode */
.banner {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
  box-shadow: 0 20px 45px -22px rgb(10 59 56 / 0.6);
}
.banner-overdue {
  background: linear-gradient(135deg, #e0564b 0%, #b42318 50%, #6e1610 100%);
}
.grid-pattern {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgb(255 255 255 / 0.06) 1px, transparent 1px),
    linear-gradient(90deg, rgb(255 255 255 / 0.06) 1px, transparent 1px);
  background-size: 28px 28px;
  mask-image: linear-gradient(180deg, #000 0%, transparent 80%);
}
.glow {
  position: absolute;
  top: -45%;
  right: -15%;
  width: 22rem;
  height: 22rem;
  border-radius: 9999px;
  background: radial-gradient(circle, rgb(255 255 255 / 0.2), transparent 65%);
  animation: drift 16s ease-in-out infinite alternate;
}
.hero-btn {
  display: inline-flex;
  height: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  font-size: 0.9375rem;
  font-weight: 600;
  transition: transform 0.15s ease, background-color 0.15s ease;
}
.hero-btn:hover { transform: translateY(-1px); }
.hero-btn:active { transform: scale(0.98); }
.hero-btn-solid {
  background: #fff;
  color: #0a3b38;
  box-shadow: 0 6px 16px -6px rgb(0 0 0 / 0.35);
}
.banner-overdue .hero-btn-solid { color: #7a1a12; }
.hero-btn-glass {
  color: #fff;
  background: rgb(255 255 255 / 0.12);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.25);
}
.hero-btn-glass:hover { background: rgb(255 255 255 / 0.2); }

/* Payment detail sheet */
.detail-head {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 50%, #0a3b38 100%);
}
.detail-head-overdue {
  background: linear-gradient(135deg, #e0564b 0%, #b42318 50%, #6e1610 100%);
}
.sheet-enter-active, .sheet-leave-active { transition: transform 0.28s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.2s ease; }
.sheet-enter-from, .sheet-leave-to { transform: translateY(100%); }
@media (min-width: 640px) {
  .sheet-enter-from, .sheet-leave-to { transform: scale(0.96); opacity: 0; }
}
@media (prefers-reduced-motion: reduce) {
  .sheet-enter-active, .sheet-leave-active { transition: none; }
}

/* Lists: same .section-title / .sheet / .icon-disc as the landlord pages (main.css) */
.pay-btn {
  height: 2.25rem;
  padding: 0 1rem;
  border-radius: 0.625rem;
  font-size: 0.8125rem;
  font-weight: 600;
  color: #fff;
  background: linear-gradient(135deg, #14918a, #0f766e);
  box-shadow: 0 4px 12px -6px rgb(15 118 110 / 0.7);
  transition: transform 0.15s ease;
}
.pay-btn:hover { transform: translateY(-1px); }
.pay-btn:active { transform: scale(0.97); }

/* Entrance */
.rise {
  animation: rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards;
  animation-delay: var(--d, 0ms);
}
@keyframes rise {
  from { opacity: 0; transform: translateY(10px); }
}
@keyframes drift {
  to { transform: translate(-2.5rem, 1.5rem) scale(1.1); }
}
@media (prefers-reduced-motion: reduce) {
  .rise, .glow { animation: none; }
}
</style>
