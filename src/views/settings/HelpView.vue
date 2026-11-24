<script setup>
import { computed, ref } from 'vue'
import { LifeBuoy, Search, Phone, Mail, MessageCircle, ChevronDown, Rocket, Wallet, Building2, Users, CalendarClock, UserCog, Wrench, Crown, Home, ShieldCheck } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { useBillingStore } from '@/stores/billing'
import { formatUGX } from '@/utils/format'
import SettingsSubpage from '@/components/SettingsSubpage.vue'
import AppLink from '@/components/AppLink.vue'

// Help & support: step-by-step guides and answers for the signed-in kind of account, with a search
// box, plus the ways to reach Renta UG. Replaces the old welcome / guided tours.
const auth = useAuthStore()
const billing = useBillingStore()
const CONTACT = { phone: '0726 128782', phoneIntl: '+256726128782', email: 'shofascompany@gmail.com' }

const p = computed(() => billing.settings.prices)
const max = computed(() => billing.settings.smallMaxUnits)

// Each topic: { title, icon, tile, items: [{ q, a: [paragraphs] or steps: [..] }] }
const landlordTopics = computed(() => [
  {
    title: 'Getting started',
    icon: Rocket,
    tile: 'tile-teal',
    items: [
      {
        q: 'How do I sign in the first time?',
        steps: [
          'Open Renta UG and tap Sign in.',
          'Type the email (or phone number) that Renta UG registered for you and tap Continue.',
          'Create your own password. You will use it every time after that.',
        ],
      },
      {
        q: 'What should I do first?',
        steps: [
          'Say how many houses and rooms you will register. Renta UG picks the package that fits.',
          'Pay your subscription (by mobile money, or in cash to Renta UG). Your account opens as soon as Renta UG confirms it.',
          'Add your properties: houses, or a rental with its rooms, and the monthly rent of each.',
          'Add your MTN and Airtel numbers under Payments → Mobile money numbers, so tenants can pay you.',
          'Add your tenants and give each one their connection code.',
        ],
      },
      {
        q: 'Why can I only see Subscription, Inbox and Settings?',
        a: ['Your subscription is not active yet, or it has ended. Pay or renew on the Subscription page. Everything opens again as soon as Renta UG confirms the payment. Nothing you entered is lost.'],
      },
    ],
  },
  {
    title: 'Your subscription',
    icon: Crown,
    tile: 'tile-amber',
    items: [
      {
        q: 'What are the packages and prices?',
        a: [
          `Small scale: up to ${max.value} houses and rooms. ${formatUGX(p.value.small.monthly)} a month or ${formatUGX(p.value.small.yearly)} a year.`,
          `Big scale: any number of houses and rooms. ${formatUGX(p.value.big.monthly)} a month or ${formatUGX(p.value.big.yearly)} a year.`,
          'Paying for a year costs less than paying month by month.',
        ],
      },
      {
        q: 'How do I pay?',
        steps: [
          'Open Subscription and choose your package (Small or Big) and monthly or yearly.',
          'Choose the line to pay to: MTN or Airtel.',
          'Follow the instructions on screen to send the exact amount from your phone.',
          'Enter the full names registered on the line you paid from, and submit.',
          'Wait for Renta UG to check the money and confirm. You get a message in your Inbox.',
        ],
      },
      {
        q: 'What happens when I renew early?',
        a: ['The new period is added on top of the time you still have, so you never lose days. You get reminders 7, 3 and 1 days before the end, and on the last day.'],
      },
      {
        q: 'I have more houses and rooms than Small scale allows.',
        a: [`Small scale stops at ${max.value} houses and rooms. To add more, choose Big scale on the Subscription page.`],
      },
      {
        q: 'My payment was not confirmed.',
        a: ['Check you sent the exact amount to the number shown, and that the names you entered match the line you paid from. Then submit again, or contact Renta UG (details below) with the date and amount.'],
      },
    ],
  },
  {
    title: 'Properties and tenants',
    icon: Building2,
    tile: 'tile-sky',
    items: [
      {
        q: 'How do I add a property?',
        steps: [
          'Open Properties and tap Add property.',
          'Choose a single house, or a rental with several rooms.',
          'Give it a name, location and the monthly rent. Each room can have its own name and rent.',
        ],
      },
      {
        q: 'How do I add a tenant?',
        steps: [
          'Open the house or room and tap Add tenant.',
          'Type the tenant’s email or phone number. They add their own name and details later.',
          'Tap Get connection code and give the tenant the 6-character code. It works for 20 minutes.',
          'The tenant signs up in the app and enters the code. Their account is then linked to the room.',
        ],
      },
      {
        q: 'The connection code does not work.',
        a: ['Codes expire after 20 minutes: create a new one. The tenant must sign in with the same email or phone number you typed for them.'],
      },
      {
        q: 'My tenant has no smartphone.',
        a: ['Add them as managed by you. You record their payments and they still get their rent recorded. If they get a smartphone later, give them app access from their room: they sign in with their phone number and create a password.'],
      },
      {
        q: 'A tenant wants to leave.',
        a: ['Their request appears under Requests to leave with their reason and rating. Approve it to end the tenancy: the room becomes empty and the tenant moves to Records with all their history kept. Or decline it with a short note.'],
      },
    ],
  },
  {
    title: 'Payments and rent',
    icon: Wallet,
    tile: 'tile-violet',
    items: [
      {
        q: 'How do tenants pay me?',
        a: ['Tenants send mobile money straight to your MTN or Airtel number: Renta UG never holds the money. In the app they enter the amount and the names registered on the line they paid from. You then see it under Payments, waiting for you.'],
      },
      {
        q: 'How do I confirm a payment?',
        steps: [
          'Check on your phone that the money arrived.',
          'Open Payments and find it under Payments to confirm.',
          'Tap Confirm (you can correct the amount), or Reject with a reason.',
          'The tenant gets a notification, and their rental time extends straight away.',
        ],
      },
      {
        q: 'How do I record cash?',
        a: ['Open Payments → Record payment, choose the tenant, the amount and the date. It counts at once and the tenant is told.'],
      },
      {
        q: 'How does rental time work?',
        a: [
          'You choose the date of the first payment: the tenant’s first month starts that day. Each month paid adds one month from where the last one ended.',
          'If a tenant pays late, the late days are “debt days”: the new month still ends one month after the old end.',
          'Part payments buy days: half a month’s rent gives 15 days. The rest stays as a balance; once the month is paid in full it counts as the whole month.',
        ],
      },
      {
        q: 'Where do I see what I collected?',
        a: ['Your dashboard shows this month. Transactions lists every amount received, and Reports shows charts month by month.'],
      },
      {
        q: 'How do I send a notice to tenants?',
        a: ['Open Notifications (or the send button) and write to one tenant or all of them. They get it in the app at once.'],
      },
    ],
  },
])

const tenantTopics = computed(() => [
  {
    title: 'Getting started',
    icon: Rocket,
    tile: 'tile-teal',
    items: [
      {
        q: 'How do I create my account?',
        steps: [
          'Tap Sign up and enter your name, email and a password.',
          'We email you a 6-character code. Enter it to finish. Not there? Check your Spam or Promotions folder.',
        ],
      },
      {
        q: 'My landlord gave me app access with my phone number.',
        steps: ['On the sign-in page, type your phone number and tap Continue.', 'Add your email and create your password. That’s it.'],
      },
      {
        q: 'How do I connect to my house?',
        steps: [
          'Ask your landlord for your 6-character connection code.',
          'Enter it in the app. You only do this once.',
          'Codes work for 20 minutes, and only for the email or phone number your landlord registered for you.',
        ],
      },
    ],
  },
  {
    title: 'Paying rent',
    icon: Wallet,
    tile: 'tile-violet',
    items: [
      {
        q: 'How do I pay with mobile money?',
        steps: [
          'Tap Pay now and choose MTN or Airtel.',
          'Enter the amount you are paying.',
          'Follow the steps on screen to send the money to your landlord’s number.',
          'Enter the full names registered on the line you paid from, then submit.',
          'Your landlord checks the money and confirms. You get a notification.',
        ],
      },
      {
        q: 'Can I pay for several months at once?',
        a: ['Yes. Use Recharge to pay any unpaid rent plus up to 12 months ahead. Each month adds a full month to your rental time.'],
      },
      {
        q: 'Can I pay part of my rent?',
        a: [
          'Yes, any amount. Part of the rent buys part of the month in days: half the rent gives about 15 days. The pay page shows exactly how many days your money lasts.',
          'The rest stays as your balance. On the Payments page tap Complete payment to top it up whenever you can; once the month is paid in full it counts as the whole month.',
        ],
      },
      {
        q: 'I paid in cash.',
        a: ['Ask your landlord to record it. It appears in your payment history as soon as they do.'],
      },
      {
        q: 'My payment is still waiting.',
        a: ['Your landlord has not confirmed it yet. If it takes long, call them from your dashboard. If it was rejected, the message tells you why.'],
      },
    ],
  },
  {
    title: 'Your rental time',
    icon: CalendarClock,
    tile: 'tile-sky',
    items: [
      {
        q: 'What is rental time?',
        a: ['The period your rent covers. It starts on the day of your first payment and grows by one month for every month you pay. Your dashboard shows the days left.'],
      },
      {
        q: 'What are debt days?',
        a: ['If you pay after your month ended, the days in between are debt days. They are taken from your new month, so it still ends one month after the old end.'],
      },
      {
        q: 'Where are my receipts?',
        a: ['On the Payments page. Every confirmed payment has a receipt you can open and save as an image.'],
      },
    ],
  },
  {
    title: 'Your home',
    icon: Home,
    tile: 'tile-teal',
    items: [
      {
        q: 'How do I contact my landlord?',
        a: ['Your landlord’s phone number is on your dashboard: tap it to call or message.'],
      },
      {
        q: 'How do I move out?',
        steps: [
          'Open My home and tap the request to leave.',
          'Rate the place, write a short review and say why you are leaving.',
          'Your landlord approves or declines. Once approved, your history is kept and your account is free to join a new house.',
        ],
      },
    ],
  },
])

const commonTopics = [
  {
    title: 'Your account',
    icon: UserCog,
    tile: 'tile-slate',
    items: [
      { q: 'I forgot my password.', steps: ['On the sign-in page, tap Forgot password.', 'Enter your email. We send you a link to choose a new password.'] },
      { q: 'How do I change my password or details?', a: ['Settings → tap your name at the top. Change your details or your password there.'] },
      {
        q: 'How do I get notifications on my phone?',
        a: [
          'Settings → Notifications → turn them on and allow them when your phone asks.',
          'On an iPhone, first add Renta UG to your Home Screen (Share → Add to Home Screen), then open it from there.',
        ],
      },
      {
        q: 'How do I delete my account?',
        a: [
          'Contact Renta UG (details below) from the email or phone number on your account. Say “Delete my account” and give your full name. We check it is really you, then delete it, normally within 30 days.',
          'Rent and payment records a landlord needs, or that the law requires, may be kept. A landlord’s properties and tenant records are deleted with the account, so download any reports first.',
        ],
      },
    ],
  },
  {
    title: 'Something is not working',
    icon: Wrench,
    tile: 'tile-amber',
    items: [
      { q: 'A page shows old information.', a: ['Pull the page down or reopen the app. Check that your phone has internet: without it you see an offline page.'] },
      { q: 'I did not get the email.', a: ['Look in your Spam, Junk or Promotions folder and mark it as “Not spam”. Wait a minute, then try again.'] },
      { q: 'The app says my account is suspended.', a: ['Only Renta UG can suspend an account. Contact us using the details below.'] },
    ],
  },
]

const topics = computed(() => [...(auth.isLandlord ? landlordTopics.value : tenantTopics.value), ...commonTopics])

// Search across questions and answers
const query = ref('')
const shown = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return topics.value
  return topics.value
    .map((t) => ({ ...t, items: t.items.filter((i) => [i.q, ...(i.a ?? []), ...(i.steps ?? [])].join(' ').toLowerCase().includes(q)) }))
    .filter((t) => t.items.length)
})
</script>

<template>
  <SettingsSubpage title="Help & support" :subtitle="auth.isLandlord ? 'Guides for landlords: subscription, properties, tenants and payments.' : 'Guides for tenants: your account, paying rent and your rental time.'" :icon="LifeBuoy">
    <div class="relative">
      <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
      <input v-model="query" type="search" class="input pl-10" placeholder="Search help, e.g. “pay”, “code”, “password”" />
    </div>

    <section v-for="t in shown" :key="t.title">
      <h2 class="section-title flex items-center gap-2.5">
        <span class="icon-tile size-8! rounded-xl!" :class="t.tile"><component :is="t.icon" class="size-4" /></span>
        {{ t.title }}
      </h2>
      <div class="sheet divide-y divide-slate-100">
        <details v-for="i in t.items" :key="i.q" class="qa group" :open="Boolean(query.trim())">
          <summary class="flex cursor-pointer list-none items-center justify-between gap-3 px-5 py-4 text-[15px] font-medium text-slate-900">
            {{ i.q }}
            <ChevronDown class="size-4.5 shrink-0 text-slate-400 transition-transform group-open:rotate-180" />
          </summary>
          <div class="px-5 pb-5 text-sm leading-relaxed text-slate-600">
            <ol v-if="i.steps" class="space-y-2">
              <li v-for="(s, n) in i.steps" :key="n" class="flex gap-3">
                <span class="step-num">{{ n + 1 }}</span><span>{{ s }}</span>
              </li>
            </ol>
            <p v-for="(para, n) in i.a ?? []" :key="n" :class="n && 'mt-2'">{{ para }}</p>
          </div>
        </details>
      </div>
    </section>

    <p v-if="!shown.length" class="sheet p-6 text-center text-sm text-slate-500">Nothing matches “{{ query }}”. Try another word, or contact us below.</p>

    <!-- Contact -->
    <section>
      <h2 class="section-title">Still need help?</h2>
      <div class="sheet p-5">
        <p class="text-sm text-slate-600">Talk to the Renta UG team by phone, WhatsApp or email. Tell us your name, the email or phone on your account, and what happened.</p>
        <div class="mt-4 grid gap-2 sm:grid-cols-3">
          <a :href="`tel:${CONTACT.phoneIntl}`" class="contact"><Phone class="size-4.5" /> Call {{ CONTACT.phone }}</a>
          <AppLink :phone="CONTACT.phoneIntl" class="contact"><MessageCircle class="size-4.5" /> WhatsApp</AppLink>
          <a :href="`mailto:${CONTACT.email}`" class="contact"><Mail class="size-4.5" /> Email us</a>
        </div>
        <p class="mt-4 flex items-start gap-2 text-xs text-slate-500">
          <ShieldCheck class="mt-px size-4 shrink-0 text-brand-600" />
          Renta UG will never ask for your password or your mobile money PIN. Never share them with anyone.
        </p>
      </div>
    </section>

    <p class="text-center text-xs text-slate-400">
      <Users class="mr-1 inline size-3.5" /> Looking for app information?
      <RouterLink :to="`${auth.home}/settings/about`" class="font-medium text-brand-700 hover:underline">About Renta UG</RouterLink>
    </p>
  </SettingsSubpage>
</template>

<style scoped>
.qa summary::-webkit-details-marker { display: none; }
.qa[open] summary { color: var(--color-brand-700); }
.step-num {
  display: inline-flex;
  width: 1.4rem;
  height: 1.4rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  font-size: 0.72rem;
  font-weight: 700;
  color: var(--color-brand-700);
  background: var(--color-brand-50);
}
.contact {
  display: inline-flex;
  height: 2.75rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.9rem;
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-brand-700);
  background: var(--color-brand-50);
  transition: background-color 0.15s ease;
}
.contact:hover { background: var(--color-brand-100); }
</style>
