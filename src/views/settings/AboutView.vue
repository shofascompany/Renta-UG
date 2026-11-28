<script setup>
import { computed } from 'vue'
import {
  Info, ShieldCheck, Building2, Users, Wallet, BellRing, Smartphone, Lock, Phone, Mail, MessageCircle,
  FileText, ChevronRight, LifeBuoy, HandCoins, CalendarClock, Crown,
} from '@lucide/vue'
import { version } from '../../../package.json'
import { useAuthStore } from '@/stores/auth'
import { useBillingStore } from '@/stores/billing'
import { formatUGX } from '@/utils/format'
import { SITE } from '@/lib/site'
import Logo from '@/components/Logo.vue'
import SettingsSubpage from '@/components/SettingsSubpage.vue'
import AppLink from '@/components/AppLink.vue'

// About Renta UG: what it is, what it does for this kind of account, plans (landlords), how money
// and data are handled, installing, contacts and the legal pages.
const auth = useAuthStore()
const billing = useBillingStore()
const CONTACT = { phone: '0726 128782', phoneIntl: '+256726128782', email: 'rentaugcompany@gmail.com' }
const year = new Date().getFullYear()

const features = computed(() =>
  auth.isLandlord
    ? [
        { icon: Building2, title: 'Properties and rooms', text: 'Houses and rentals with their rooms, the rent of each, and which ones are empty.' },
        { icon: Users, title: 'Tenants', text: 'Every tenant, their rental time and balance. Former tenants stay in Records with their history.' },
        { icon: Wallet, title: 'Payments straight to you', text: 'Tenants send mobile money to your own MTN or Airtel number. You confirm it in one tap.' },
        { icon: HandCoins, title: 'Cash too', text: 'Record cash, and manage tenants who have no smartphone.' },
        { icon: BellRing, title: 'Notices and reminders', text: 'Send notices to tenants. Rent reminders and receipts go out automatically as notifications.' },
        { icon: CalendarClock, title: 'Reports', text: 'What you collected each month, every transaction, and who still owes.' },
      ]
    : [
        { icon: Wallet, title: 'Pay rent from your phone', text: 'Send MTN or Airtel Mobile Money straight to your landlord, then tell them in the app.' },
        { icon: CalendarClock, title: 'Know your rental time', text: 'The days left, when your month ends and any debt days, always up to date.' },
        { icon: FileText, title: 'Every receipt', text: 'Each confirmed payment is kept, with a receipt you can save as an image.' },
        { icon: BellRing, title: 'Reminders and notices', text: 'Rent reminders, confirmations and messages from your landlord, as notifications in the app.' },
      ],
)

const plans = computed(() => {
  const s = billing.settings
  return [
    { name: 'Small scale', covers: `Up to ${s.smallMaxUnits} houses and rooms`, monthly: s.prices.small.monthly, yearly: s.prices.small.yearly },
    { name: 'Big scale', covers: 'Any number of houses and rooms', monthly: s.prices.big.monthly, yearly: s.prices.big.yearly },
  ]
})

const base = computed(() => `${auth.home}/settings`)
</script>

<template>
  <SettingsSubpage title="About Renta UG" subtitle="What Renta UG is, how it handles your money and information, and how to reach us." :icon="Info">
    <!-- Identity -->
    <div class="card p-6">
      <div class="flex items-center justify-between gap-4">
        <Logo />
        <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600">Version {{ version }}</span>
      </div>
      <p class="mt-4 text-sm leading-relaxed text-slate-600">
        Renta UG is a rent management app made for Uganda. Landlords keep their properties, tenants and rent in one clear account,
        and tenants pay rent from their phone and always know where they stand. Payments are made with MTN Mobile Money and
        Airtel Money, or in cash.
      </p>
      <p class="mt-3 text-xs text-slate-500">Website: <a :href="SITE.url" target="_blank" rel="noopener" class="font-medium text-brand-700 hover:underline">{{ SITE.url.replace('https://', '') }}</a></p>
    </div>

    <!-- What it does for you -->
    <section>
      <h2 class="section-title">What Renta UG does for you</h2>
      <div class="grid gap-3 sm:grid-cols-2">
        <div v-for="f in features" :key="f.title" class="card flex gap-3 p-4">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-50 text-brand-600"><component :is="f.icon" class="size-4.5" /></span>
          <div>
            <p class="text-sm font-semibold text-slate-900">{{ f.title }}</p>
            <p class="mt-0.5 text-[13px] leading-relaxed text-slate-600">{{ f.text }}</p>
          </div>
        </div>
      </div>
    </section>

    <!-- Plans (landlords) -->
    <section v-if="auth.isLandlord">
      <h2 class="section-title">Subscription plans</h2>
      <div class="card p-5">
        <div class="grid gap-3 sm:grid-cols-2">
          <div v-for="pl in plans" :key="pl.name" class="rounded-2xl border border-slate-200 p-4">
            <p class="flex items-center gap-2 text-sm font-semibold text-slate-900"><Crown class="size-4 text-amber-600" /> {{ pl.name }}</p>
            <p class="mt-0.5 text-xs text-slate-500">{{ pl.covers }}</p>
            <p class="mt-3 text-sm text-slate-700"><strong class="text-slate-900">{{ formatUGX(pl.monthly) }}</strong> a month</p>
            <p class="text-sm text-slate-700"><strong class="text-slate-900">{{ formatUGX(pl.yearly) }}</strong> a year</p>
          </div>
        </div>
        <p class="mt-4 text-xs leading-relaxed text-slate-500">
          Your account opens once Renta UG confirms your payment. Renewing early adds the new period on top of the time you have left.
          <RouterLink to="/landlord/subscription" class="font-medium text-brand-700 hover:underline">Open Subscription</RouterLink>
        </p>
      </div>
    </section>

    <!-- Money and data -->
    <section>
      <h2 class="section-title">Your money and your information</h2>
      <div class="card space-y-4 p-5 text-sm leading-relaxed text-slate-600">
        <p class="flex gap-3"><Wallet class="mt-0.5 size-4.5 shrink-0 text-brand-600" />
          <span>Rent goes straight from the tenant to the landlord’s own mobile money number or by cash. Renta UG never holds tenants’ money.</span></p>
        <p class="flex gap-3"><Lock class="mt-0.5 size-4.5 shrink-0 text-brand-600" />
          <span>Everything travels over encrypted connections, and passwords are stored only in scrambled form. Each person sees only their own information: a landlord sees only their own tenants.</span></p>
        <p class="flex gap-3"><ShieldCheck class="mt-0.5 size-4.5 shrink-0 text-brand-600" />
          <span>Renta UG will never ask for your password or your mobile money PIN. Never share them with anyone, including people who say they are from Renta UG.</span></p>
      </div>
    </section>

    <!-- Install -->
    <section>
      <h2 class="section-title">Install the Android app</h2>
      <div class="card space-y-4 p-5 text-sm text-slate-600">
        <div class="flex gap-3">
          <Smartphone class="mt-0.5 size-4.5 shrink-0 text-brand-600" />
          <div>
            <p class="font-medium text-slate-900">Android (Chrome)</p>
            <p class="mt-0.5">Tap the <strong>⋮</strong> menu, then <strong>Install app</strong> or <strong>Add to Home screen</strong>.</p>
          </div>
        </div>
        <p class="text-xs text-slate-500">Optional. On any other phone or computer, Renta UG works in the browser.</p>
      </div>
    </section>

    <!-- Contact -->
    <section>
      <h2 class="section-title">Contact Renta UG</h2>
      <div class="card divide-y divide-slate-100">
        <a :href="`tel:${CONTACT.phoneIntl}`" class="contact-row"><Phone class="size-4.5 text-brand-600" /><span class="flex-1">Call {{ CONTACT.phone }}</span><ChevronRight class="size-4 text-slate-400" /></a>
        <AppLink :phone="CONTACT.phoneIntl" class="contact-row"><MessageCircle class="size-4.5 text-brand-600" /><span class="flex-1">WhatsApp {{ CONTACT.phone }}</span><ChevronRight class="size-4 text-slate-400" /></AppLink>
        <a :href="`mailto:${CONTACT.email}`" class="contact-row"><Mail class="size-4.5 text-brand-600" /><span class="flex-1 truncate">{{ CONTACT.email }}</span><ChevronRight class="size-4 text-slate-400" /></a>
        <RouterLink :to="`${base}/help`" class="contact-row"><LifeBuoy class="size-4.5 text-brand-600" /><span class="flex-1">Help & support guides</span><ChevronRight class="size-4 text-slate-400" /></RouterLink>
      </div>
    </section>

    <!-- Legal -->
    <section>
      <h2 class="section-title">Legal</h2>
      <div class="card divide-y divide-slate-100">
        <RouterLink :to="`${base}/terms`" class="contact-row"><FileText class="size-4.5 text-slate-500" /><span class="flex-1">Terms & conditions</span><ChevronRight class="size-4 text-slate-400" /></RouterLink>
        <RouterLink to="/privacy" class="contact-row"><ShieldCheck class="size-4.5 text-slate-500" /><span class="flex-1">Privacy policy</span><ChevronRight class="size-4 text-slate-400" /></RouterLink>
        <RouterLink to="/delete-account" class="contact-row"><Info class="size-4.5 text-slate-500" /><span class="flex-1">Delete your account</span><ChevronRight class="size-4 text-slate-400" /></RouterLink>
      </div>
    </section>

    <p class="pb-2 text-center text-xs text-slate-400">© {{ year }} Renta UG · Made in Uganda · Version {{ version }}</p>
  </SettingsSubpage>
</template>

<style scoped>
.contact-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.95rem 1.25rem;
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-slate-900);
  transition: background-color 0.15s ease;
}
.contact-row:hover { background: var(--color-slate-50); }
</style>
