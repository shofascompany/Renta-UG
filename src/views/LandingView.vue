<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  Smartphone, CalendarClock, Building2, Banknote, BellRing, BarChart3, ShieldCheck, Zap, Download, ChevronDown, ArrowRight,
  Users, Home, Check, Menu, X, KeyRound, Wallet, Share, Plus, MapPin,
} from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { SITE } from '@/lib/site'
import Logo from '@/components/Logo.vue'

const auth = useAuthStore()
const router = useRouter()
const signedIn = computed(() => auth.isAuthenticated)

// ── Menu (phones) ──
const menu = ref(false)
const scrolled = ref(false)
const onScroll = () => (scrolled.value = window.scrollY > 12)

// ── "Install the app" button (Android Chrome offers it; iPhones get the steps below) ──
const installEvent = ref(null)
const onBeforeInstall = (e) => {
  e.preventDefault()
  installEvent.value = e
}
async function install() {
  if (!installEvent.value) return document.getElementById('install')?.scrollIntoView({ behavior: 'smooth' })
  installEvent.value.prompt()
  await installEvent.value.userChoice.catch(() => {})
  installEvent.value = null
}

// ── Reveal on scroll ──
let io = null
const vReveal = {
  mounted(el, binding) {
    el.classList.add('reveal')
    if (binding.value) el.style.setProperty('--d', `${binding.value}ms`)
    if (!io) return el.classList.add('in')
    io.observe(el)
  },
}

// ── Rotating line under the headline (words only) ──
const words = ['pay rent', 'track rent', 'collect rent', 'manage homes']
const wordIndex = ref(0)
let wordTimer = null

onMounted(() => {
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('beforeinstallprompt', onBeforeInstall)
  wordTimer = setInterval(() => (wordIndex.value = (wordIndex.value + 1) % words.length), 2400)
})
onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScroll)
  window.removeEventListener('beforeinstallprompt', onBeforeInstall)
  clearInterval(wordTimer)
  io?.disconnect()
})
if (typeof IntersectionObserver !== 'undefined') {
  io = new IntersectionObserver(
    (entries) =>
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add('in')
          io.unobserve(e.target)
        }
      }),
    { threshold: 0.12 },
  )
}

const goApp = () => router.push(signedIn.value ? auth.home : { name: 'login' })

const features = [
  { icon: Smartphone, title: 'Pay with MTN or Airtel', text: 'Tenants pay rent from their phone. Every payment is confirmed with the network before the rent is updated.', tone: 'teal' },
  { icon: CalendarClock, title: 'Rental time that is fair', text: 'A tenant’s month starts counting the moment they pay. Pay 60% or more to start, and the balance goes down as they pay.', tone: 'sky' },
  { icon: Building2, title: 'Houses, rentals and rooms', text: 'Add single houses or whole rentals with rooms. See who stays where, and what each room earns.', tone: 'violet' },
  { icon: Banknote, title: 'Cash, recorded properly', text: 'Landlords record cash in seconds. It counts at once and the tenant gets a receipt.', tone: 'amber' },
  { icon: BellRing, title: 'Few, useful notifications', text: 'Only what matters: payments, reminders before time ends, and notices from your landlord.', tone: 'rose' },
  { icon: BarChart3, title: 'Reports that add up', text: 'Income, who has paid, who is late and how full your rooms are, always calculated from real payments.', tone: 'emerald' },
]

const steps = [
  { icon: KeyRound, title: 'Create your account', text: 'Sign up with your email. We send a 6-character code to confirm it is you.' },
  { icon: Home, title: 'Connect to your home', text: 'Tenants connect with the code from their landlord. Landlords add their houses and tenants.' },
  { icon: Wallet, title: 'Pay and stay up to date', text: 'Pay by mobile money, watch the days count down, and get a receipt for every payment.' },
]

const faq = [
  { q: 'Is Renta UG free?', a: 'Creating an account is free. Mobile money providers may charge their normal network fees when you pay.' },
  { q: 'How do I know my payment worked?', a: 'We confirm every payment with MTN or Airtel before your rent changes. You then get one clear confirmation with a receipt.' },
  { q: 'When does my rental month start?', a: 'The day you pay. Pay at least 60% of the month’s rent and the month starts. You can pay the rest later.' },
  { q: 'Can I pay in cash?', a: 'Yes. Your landlord records cash in the app and it is added to your rent straight away.' },
  { q: 'I am a landlord. How do I join?', a: 'Landlord accounts are set up by the Renta UG team. Once you are added, sign in and add your properties.' },
]
const open = ref(0)

const tones = {
  teal: 'bg-brand-50 text-brand-700',
  sky: 'bg-sky-50 text-sky-700',
  violet: 'bg-violet-50 text-violet-700',
  amber: 'bg-amber-50 text-amber-700',
  rose: 'bg-rose-50 text-rose-700',
  emerald: 'bg-emerald-50 text-emerald-700',
}
</script>

<template>
  <div class="landing">
    <!-- Top bar -->
    <header class="nav fixed inset-x-0 top-0 z-40 transition" :class="scrolled || menu ? 'nav-solid' : ''">
      <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-3 px-4 sm:px-6">
        <Logo />
        <nav class="hidden items-center gap-7 text-sm font-medium text-slate-600 md:flex">
          <a href="#features" class="hover:text-slate-900">Features</a>
          <a href="#how" class="hover:text-slate-900">How it works</a>
          <a href="#install" class="hover:text-slate-900">Get the app</a>
          <a href="#faq" class="hover:text-slate-900">Questions</a>
        </nav>
        <div class="flex items-center gap-2">
          <button v-if="signedIn" class="btn-primary hidden h-10 rounded-xl px-4 text-sm sm:inline-flex" @click="goApp">Open my dashboard</button>
          <template v-else>
            <RouterLink to="/login" class="btn-secondary hidden h-10 rounded-xl px-4 text-sm sm:inline-flex">Sign in</RouterLink>
            <RouterLink to="/signup" class="btn-primary hidden h-10 rounded-xl px-4 text-sm sm:inline-flex">Get started</RouterLink>
          </template>
          <button class="flex size-10 items-center justify-center rounded-xl text-slate-700 md:hidden" :aria-label="menu ? 'Close menu' : 'Open menu'" @click="menu = !menu">
            <X v-if="menu" class="size-5" /><Menu v-else class="size-5" />
          </button>
        </div>
      </div>
      <Transition name="drop">
        <div v-if="menu" class="border-t border-slate-200/70 px-4 pt-2 pb-5 md:hidden">
          <a v-for="l in [['Features', '#features'], ['How it works', '#how'], ['Get the app', '#install'], ['Questions', '#faq']]" :key="l[1]" :href="l[1]" class="block py-3 text-base font-medium text-slate-700" @click="menu = false">{{ l[0] }}</a>
          <div class="mt-3 grid grid-cols-2 gap-2.5">
            <template v-if="signedIn"><button class="btn-primary col-span-2 h-12 rounded-2xl" @click="goApp">Open my dashboard</button></template>
            <template v-else>
              <RouterLink to="/login" class="btn-secondary h-12 rounded-2xl">Sign in</RouterLink>
              <RouterLink to="/signup" class="btn-primary h-12 rounded-2xl">Get started</RouterLink>
            </template>
          </div>
        </div>
      </Transition>
    </header>

    <!-- Hero -->
    <section class="hero relative overflow-hidden pt-28 pb-16 sm:pt-36 sm:pb-24">
      <div class="orb orb-1" aria-hidden="true" />
      <div class="orb orb-2" aria-hidden="true" />
      <div class="relative mx-auto grid max-w-6xl items-center gap-12 px-4 sm:px-6 lg:grid-cols-[1.1fr_0.9fr]">
        <div class="text-center lg:text-left">
          <p class="hero-in mx-auto inline-flex items-center gap-2 rounded-full bg-white/70 px-3.5 py-1.5 text-xs font-semibold text-brand-700 ring-1 ring-brand-200/70 backdrop-blur lg:mx-0" style="--d: 0ms">
            <span class="live size-2 rounded-full bg-emerald-500" /> Made for rent in Uganda
          </p>
          <h1 class="hero-in mt-5 text-[2.35rem] leading-[1.08] font-extrabold tracking-tight text-slate-900 sm:text-6xl" style="--d: 80ms">
            The easy way to
            <span class="word-wrap">
              <Transition name="word" mode="out-in">
                <span :key="wordIndex" class="grad block">{{ words[wordIndex] }}</span>
              </Transition>
            </span>
          </h1>
          <p class="hero-in mx-auto mt-5 max-w-xl text-base leading-relaxed text-slate-600 sm:text-lg lg:mx-0" style="--d: 160ms">
            Tenants pay rent with MTN or Airtel and watch their days count down. Landlords see every house, room and payment in one place.
          </p>
          <div class="hero-in mt-8 flex flex-col items-stretch justify-center gap-3 sm:flex-row lg:justify-start" style="--d: 240ms">
            <button v-if="signedIn" class="btn-primary h-13 rounded-2xl px-7 text-base" @click="goApp">Open my dashboard <ArrowRight class="size-4.5" /></button>
            <template v-else>
              <RouterLink to="/signup" class="btn-primary h-13 rounded-2xl px-7 text-base">Create free account <ArrowRight class="size-4.5" /></RouterLink>
              <RouterLink to="/login" class="btn-secondary h-13 rounded-2xl px-7 text-base">I already have an account</RouterLink>
            </template>
          </div>
          <ul class="hero-in mt-7 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-sm text-slate-500 lg:justify-start" style="--d: 320ms">
            <li class="flex items-center gap-1.5"><Check class="size-4 text-emerald-600" /> MTN &amp; Airtel</li>
            <li class="flex items-center gap-1.5"><Check class="size-4 text-emerald-600" /> Confirmed automatically</li>
            <li class="flex items-center gap-1.5"><Check class="size-4 text-emerald-600" /> Works on any phone</li>
          </ul>
        </div>

        <!-- Phone preview, built in CSS -->
        <div class="hero-in relative mx-auto w-full max-w-[19rem]" style="--d: 200ms">
          <div class="float-chip chip-a"><span class="size-2 rounded-full bg-emerald-500" /> Payment confirmed</div>
          <div class="float-chip chip-b"><Zap class="size-3.5 text-amber-500" /> 28 days left</div>
          <div class="phone">
            <div class="screen">
              <p class="text-[10px] font-semibold tracking-[0.14em] text-slate-400 uppercase">Good morning</p>
              <p class="mt-1 text-lg leading-tight font-bold text-slate-900">Welcome, <span class="grad">Grace</span></p>
              <div class="mock-card">
                <p class="flex items-center gap-1.5 text-[11px] font-medium text-white/85"><Wallet class="size-3.5" /> Rent account</p>
                <div class="mt-3 grid grid-cols-2 overflow-hidden rounded-xl bg-white/12 ring-1 ring-white/15">
                  <div class="p-2.5"><p class="text-[9px] tracking-wide text-white/70 uppercase">Paid</p><p class="mt-0.5 text-[13px] font-semibold">UGX 300,000</p></div>
                  <div class="border-l border-white/15 p-2.5"><p class="text-[9px] tracking-wide text-white/70 uppercase">Balance due</p><p class="mt-0.5 text-[13px] font-semibold">UGX 200,000</p></div>
                </div>
                <div class="mt-3 rounded-lg bg-white py-2 text-center text-[12px] font-semibold text-teal-900">Pay now</div>
              </div>
              <div class="mt-3 rounded-2xl border border-slate-200 bg-slate-50 p-3">
                <p class="text-[10px] text-slate-500">Rental time</p>
                <p class="text-xl font-bold text-slate-900">28 <span class="text-xs font-medium text-slate-500">days left</span></p>
                <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-200"><div class="mock-bar h-full rounded-full" /></div>
              </div>
              <div class="mt-3 flex items-center gap-2.5 rounded-xl border border-slate-200 p-2.5">
                <span class="flex size-8 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><Check class="size-4" /></span>
                <div class="min-w-0 flex-1"><p class="truncate text-[11px] font-semibold text-slate-900">Rent received</p><p class="text-[10px] text-slate-500">MTN MoMo</p></div>
                <p class="text-[11px] font-semibold text-emerald-700">UGX 300,000</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Networks strip -->
    <section class="border-y border-slate-200/70 bg-white/60">
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-center gap-x-10 gap-y-3 px-4 py-5 text-sm font-semibold text-slate-500 sm:px-6">
        <span class="flex items-center gap-2"><span class="size-3 rounded-full bg-[#ffcc00]" /> MTN Mobile Money</span>
        <span class="flex items-center gap-2"><span class="size-3 rounded-full bg-[#e40000]" /> Airtel Money</span>
        <span class="flex items-center gap-2"><ShieldCheck class="size-4 text-brand-600" /> Confirmed before rent updates</span>
      </div>
    </section>

    <!-- Features -->
    <section id="features" class="mx-auto max-w-6xl scroll-mt-20 px-4 py-16 sm:px-6 sm:py-24">
      <div v-reveal class="mx-auto max-w-2xl text-center">
        <p class="text-xs font-bold tracking-[0.16em] text-brand-600 uppercase">Everything in one place</p>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Built around how rent really works</h2>
        <p class="mt-3 text-slate-600">Simple for tenants. Clear for landlords. Every number comes from real payments.</p>
      </div>
      <div class="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <article v-for="(f, i) in features" :key="f.title" v-reveal="i * 70" class="feature rounded-3xl border border-slate-200 bg-white p-6">
          <span class="flex size-12 items-center justify-center rounded-2xl" :class="tones[f.tone]"><component :is="f.icon" class="size-6" /></span>
          <h3 class="mt-4 text-lg font-bold text-slate-900">{{ f.title }}</h3>
          <p class="mt-1.5 text-sm leading-relaxed text-slate-600">{{ f.text }}</p>
        </article>
      </div>
    </section>

    <!-- Tenants / landlords -->
    <section class="bg-slate-50/70 py-16 sm:py-24">
      <div class="mx-auto grid max-w-6xl gap-5 px-4 sm:px-6 lg:grid-cols-2">
        <div v-reveal class="split split-tenant rounded-3xl p-7 text-white sm:p-9">
          <span class="flex size-12 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25"><Users class="size-6" /></span>
          <h3 class="mt-5 text-2xl font-bold">For tenants</h3>
          <ul class="mt-4 space-y-3 text-[0.95rem] text-white/90">
            <li v-for="t in ['See what you owe and when your time ends', 'Pay part or all of your rent, from 60%', 'Recharge months ahead in one payment', 'A receipt for every payment', 'Message-free: only the notices that matter']" :key="t" class="flex gap-2.5"><Check class="mt-0.5 size-4.5 shrink-0" /> {{ t }}</li>
          </ul>
        </div>
        <div v-reveal="90" class="split split-landlord rounded-3xl p-7 text-white sm:p-9">
          <span class="flex size-12 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25"><Building2 class="size-6" /></span>
          <h3 class="mt-5 text-2xl font-bold">For landlords</h3>
          <ul class="mt-4 space-y-3 text-[0.95rem] text-white/90">
            <li v-for="t in ['Houses, rentals and rooms in one console', 'Add tenants and share their connection code', 'Payments arrive and are verified for you', 'Record cash and confirm move-outs', 'Reports on income, arrears and occupancy']" :key="t" class="flex gap-2.5"><Check class="mt-0.5 size-4.5 shrink-0" /> {{ t }}</li>
          </ul>
        </div>
      </div>
    </section>

    <!-- How it works -->
    <section id="how" class="mx-auto max-w-6xl scroll-mt-20 px-4 py-16 sm:px-6 sm:py-24">
      <div v-reveal class="mx-auto max-w-2xl text-center">
        <p class="text-xs font-bold tracking-[0.16em] text-brand-600 uppercase">How it works</p>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Up and running in three steps</h2>
      </div>
      <ol class="mt-12 grid gap-4 md:grid-cols-3">
        <li v-for="(s, i) in steps" :key="s.title" v-reveal="i * 90" class="step relative rounded-3xl border border-slate-200 bg-white p-6">
          <span class="num">{{ i + 1 }}</span>
          <span class="flex size-12 items-center justify-center rounded-2xl bg-brand-50 text-brand-700"><component :is="s.icon" class="size-6" /></span>
          <h3 class="mt-4 text-lg font-bold text-slate-900">{{ s.title }}</h3>
          <p class="mt-1.5 text-sm leading-relaxed text-slate-600">{{ s.text }}</p>
        </li>
      </ol>
    </section>

    <!-- Install -->
    <section id="install" class="scroll-mt-20 px-4 pb-16 sm:px-6 sm:pb-24">
      <div v-reveal class="install mx-auto max-w-6xl overflow-hidden rounded-[2rem] p-7 text-white sm:p-12">
        <div class="relative grid items-center gap-8 lg:grid-cols-[1.2fr_0.8fr]">
          <div>
            <p class="text-xs font-bold tracking-[0.16em] text-white/70 uppercase">Get the app</p>
            <h2 class="mt-3 text-3xl font-extrabold tracking-tight sm:text-4xl">Put Renta UG on your phone</h2>
            <p class="mt-3 max-w-lg text-white/85">It opens like any other app, works full screen, and sends you rent notices. No store download needed.</p>
            <button class="install-btn mt-6" @click="install"><Download class="size-5" /> Install the app</button>
          </div>
          <div class="grid gap-3 text-sm">
            <div class="how rounded-2xl p-4">
              <p class="font-semibold">Android (Chrome)</p>
              <p class="mt-1 text-white/80">Tap <strong>Install the app</strong>, or open the browser menu <span class="font-mono">⋮</span> and choose <strong>Install app</strong>.</p>
            </div>
            <div class="how rounded-2xl p-4">
              <p class="font-semibold">iPhone (Safari)</p>
              <p class="mt-1 text-white/80">Tap <Share class="inline size-4 align-text-bottom" /> <strong>Share</strong>, then <Plus class="inline size-4 align-text-bottom" /> <strong>Add to Home Screen</strong>.</p>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- FAQ -->
    <section id="faq" class="mx-auto max-w-3xl scroll-mt-20 px-4 pb-16 sm:px-6 sm:pb-24">
      <div v-reveal class="text-center">
        <p class="text-xs font-bold tracking-[0.16em] text-brand-600 uppercase">Questions</p>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Good to know</h2>
      </div>
      <div class="mt-10 space-y-3">
        <div v-for="(f, i) in faq" :key="f.q" v-reveal="i * 50" class="rounded-2xl border border-slate-200 bg-white">
          <button class="flex w-full items-center justify-between gap-4 px-5 py-4 text-left font-semibold text-slate-900" :aria-expanded="open === i" @click="open = open === i ? -1 : i">
            {{ f.q }}
            <ChevronDown class="size-5 shrink-0 text-slate-400 transition-transform" :class="open === i && 'rotate-180'" />
          </button>
          <div class="faq-body" :class="open === i && 'faq-open'"><div><p class="px-5 pb-5 text-sm leading-relaxed text-slate-600">{{ f.a }}</p></div></div>
        </div>
      </div>
    </section>

    <!-- Final call -->
    <section class="px-4 pb-16 sm:px-6 sm:pb-24">
      <div v-reveal class="cta mx-auto max-w-4xl rounded-[2rem] px-6 py-12 text-center text-white sm:py-16">
        <h2 class="text-3xl font-extrabold tracking-tight sm:text-4xl">Ready to make rent easy?</h2>
        <p class="mx-auto mt-3 max-w-md text-white/85">Create your account in a minute. Your rental month starts the day you pay.</p>
        <div class="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
          <button v-if="signedIn" class="cta-btn" @click="goApp">Open my dashboard</button>
          <template v-else>
            <RouterLink to="/signup" class="cta-btn">Create free account</RouterLink>
            <RouterLink to="/login" class="cta-ghost">Sign in</RouterLink>
          </template>
        </div>
      </div>
    </section>

    <!-- Footer -->
    <footer class="border-t border-slate-200 bg-white">
      <div class="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-4 py-8 text-sm text-slate-500 sm:flex-row sm:px-6">
        <div class="flex items-center gap-3"><Logo /><span class="hidden sm:inline">· Rent made simple in Uganda</span></div>
        <nav class="flex flex-wrap items-center justify-center gap-x-5 gap-y-2">
          <RouterLink to="/privacy" class="hover:text-slate-900">Privacy</RouterLink>
          <RouterLink to="/terms" class="hover:text-slate-900">Terms</RouterLink>
          <RouterLink to="/delete-account" class="hover:text-slate-900">Delete account</RouterLink>
          <RouterLink to="/login" class="hover:text-slate-900">Sign in</RouterLink>
        </nav>
        <p>© {{ new Date().getFullYear() }} {{ SITE.name }}</p>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.landing { background: var(--color-white); overflow-x: clip; }

/* Top bar */
.nav { background: transparent; }
.nav-solid { background: color-mix(in srgb, var(--color-white) 88%, transparent); backdrop-filter: blur(14px); box-shadow: 0 1px 0 var(--color-slate-200); }
.drop-enter-active, .drop-leave-active { transition: opacity 0.2s ease, transform 0.2s ease; }
.drop-enter-from, .drop-leave-to { opacity: 0; transform: translateY(-6px); }

/* Hero */
.hero {
  background:
    radial-gradient(70% 55% at 85% 0%, color-mix(in srgb, var(--color-brand-100) 90%, transparent), transparent 70%),
    radial-gradient(55% 45% at 0% 30%, color-mix(in srgb, var(--color-sky-100) 80%, transparent), transparent 70%),
    var(--color-white);
}
.orb { position: absolute; border-radius: 9999px; filter: blur(60px); opacity: 0.5; pointer-events: none; animation: drift 16s ease-in-out infinite alternate; }
.orb-1 { width: 20rem; height: 20rem; top: 4rem; left: -6rem; background: #5eead4; }
.orb-2 { width: 18rem; height: 18rem; bottom: -4rem; right: -4rem; background: #7dd3fc; animation-duration: 20s; }
.grad {
  background: linear-gradient(90deg, #0f766e, #14b8a6 55%, #0284c7);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.word-wrap { display: block; height: 1.2em; overflow: hidden; }
.word-enter-active, .word-leave-active { transition: opacity 0.4s ease, transform 0.4s cubic-bezier(0.22, 1, 0.36, 1); }
.word-enter-from { opacity: 0; transform: translateY(70%); }
.word-leave-to { opacity: 0; transform: translateY(-70%); }
.live { box-shadow: 0 0 0 0 rgb(16 185 129 / 0.5); animation: ping 2.4s ease-out infinite; }
.hero-in { animation: rise 0.7s cubic-bezier(0.22, 1, 0.36, 1) backwards; animation-delay: var(--d, 0ms); }

/* Phone */
.phone {
  --color-white: #fff;
  --color-slate-50: #f8fafc;
  --color-slate-200: #e2e8f0;
  --color-slate-400: #94a3b8;
  --color-slate-500: #64748b;
  --color-slate-900: #0f172a;
  position: relative;
  border-radius: 2.6rem;
  padding: 0.6rem;
  background: linear-gradient(160deg, #1e293b, #0f172a);
  box-shadow: 0 40px 70px -25px rgb(15 23 42 / 0.5), 0 0 0 1.5px rgb(255 255 255 / 0.08) inset;
  animation: bob 6s ease-in-out infinite;
}
.phone::before { content: ''; position: absolute; top: 0.95rem; left: 50%; width: 4.2rem; height: 1.1rem; transform: translateX(-50%); border-radius: 9999px; background: #0f172a; z-index: 2; }
.screen { border-radius: 2.1rem; background: #fff; padding: 2.4rem 1rem 1.1rem; color: #0f172a; }
.mock-card {
  margin-top: 0.8rem;
  border-radius: 1.1rem;
  padding: 0.9rem;
  color: #fff;
  background: linear-gradient(135deg, #14918a, #0f766e 50%, #0a3b38);
}
.mock-bar { width: 0; background: linear-gradient(90deg, #14b8a6, #0284c7); animation: fill 2.4s 0.8s cubic-bezier(0.22, 1, 0.36, 1) forwards; }
.float-chip {
  position: absolute;
  z-index: 3;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  border-radius: 9999px;
  padding: 0.45rem 0.8rem;
  font-size: 0.72rem;
  font-weight: 600;
  color: #0f172a;
  background: #fff;
  box-shadow: 0 12px 28px -10px rgb(15 23 42 / 0.35);
  animation: bob 5s ease-in-out infinite;
}
.chip-a { top: 18%; left: -1.2rem; }
.chip-b { bottom: 16%; right: -1rem; animation-delay: 1.2s; }

/* Cards */
.feature { transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease; }
.feature:hover { transform: translateY(-4px); box-shadow: 0 20px 40px -22px rgb(15 118 110 / 0.35); border-color: var(--color-brand-200); }
.split-tenant { background: linear-gradient(140deg, #14918a, #0f766e 55%, #0a3b38); --color-white: #fff; }
.split-landlord { background: linear-gradient(140deg, #0369a1, #1d4ed8 55%, #1e1b4b); --color-white: #fff; }
.step .num {
  position: absolute; top: 1.2rem; right: 1.4rem;
  font-size: 3rem; line-height: 1; font-weight: 800;
  color: var(--color-slate-100);
}
.install { background: linear-gradient(135deg, #0f766e, #0a3b38 60%, #082f2d); --color-white: #fff; position: relative; }
.install::before { content: ''; position: absolute; inset: 0; background: radial-gradient(circle at 90% -10%, rgb(255 255 255 / 0.18), transparent 55%); }
.how { background: rgb(255 255 255 / 0.1); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18); }
.install-btn { display: inline-flex; align-items: center; gap: 0.6rem; height: 3.25rem; padding: 0 1.5rem; border-radius: 1rem; font-weight: 700; background: #fff; color: #0a3b38; box-shadow: 0 10px 24px -10px rgb(0 0 0 / 0.5); transition: transform 0.15s ease; }
.install-btn:hover { transform: translateY(-2px); }
.install-btn:active { transform: scale(0.98); }
.cta { background: linear-gradient(135deg, #14b8a6, #0f766e 50%, #0369a1); --color-white: #fff; }
.cta-btn, .cta-ghost { display: inline-flex; align-items: center; justify-content: center; height: 3.25rem; padding: 0 1.75rem; border-radius: 1rem; font-weight: 700; transition: transform 0.15s ease; }
.cta-btn { background: #fff; color: #0a3b38; box-shadow: 0 10px 24px -10px rgb(0 0 0 / 0.45); }
.cta-ghost { color: #fff; box-shadow: inset 0 0 0 1.5px rgb(255 255 255 / 0.6); }
.cta-btn:hover, .cta-ghost:hover { transform: translateY(-2px); }

/* FAQ open/close */
.faq-body { display: grid; grid-template-rows: 0fr; transition: grid-template-rows 0.3s ease; }
.faq-body > div { overflow: hidden; }
.faq-open { grid-template-rows: 1fr; }

/* Scroll reveal */
.reveal { opacity: 0; transform: translateY(18px); transition: opacity 0.7s cubic-bezier(0.22, 1, 0.36, 1), transform 0.7s cubic-bezier(0.22, 1, 0.36, 1); transition-delay: var(--d, 0ms); }
.reveal.in { opacity: 1; transform: none; }

@keyframes rise { from { opacity: 0; transform: translateY(16px); } }
@keyframes drift { to { transform: translate(2.5rem, 1.5rem) scale(1.12); } }
@keyframes bob { 50% { transform: translateY(-8px); } }
@keyframes fill { to { width: 78%; } }
@keyframes ping { 70% { box-shadow: 0 0 0 7px rgb(16 185 129 / 0); } 100% { box-shadow: 0 0 0 0 rgb(16 185 129 / 0); } }

@media (max-width: 380px) {
  .chip-a { left: -0.2rem; }
  .chip-b { right: -0.2rem; }
}
@media (prefers-reduced-motion: reduce) {
  .hero-in, .orb, .phone, .float-chip, .live { animation: none; }
  .reveal { opacity: 1; transform: none; transition: none; }
  .mock-bar { animation: none; width: 78%; }
  .word-enter-active, .word-leave-active, .faq-body { transition: none; }
}
</style>
