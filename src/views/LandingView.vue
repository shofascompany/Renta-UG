<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  Smartphone, CalendarClock, Building2, Banknote, BellRing, BarChart3, ShieldCheck, Download, ChevronDown, ArrowRight, ArrowUp,
  Users, Home, Check, Menu, X, KeyRound, Wallet, Share, Plus, Phone, MessageSquareText, Lock, EyeOff, CircleCheck, Sparkles,
  LayoutDashboard,
} from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { SITE } from '@/lib/site'
import Logo from '@/components/Logo.vue'

// Public landing page. Everything said here must be TRUE of the app as it works today
// (no invented user numbers or reviews). Check this page whenever a feature changes.
const auth = useAuthStore()
const router = useRouter()
const signedIn = computed(() => auth.isAuthenticated)
const goApp = () => router.push(signedIn.value ? auth.home : { name: 'login' })
const reduced = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

// ── Top bar, scroll progress, back to top ──
const menu = ref(false)
const scrolled = ref(false)
const progress = ref(0)
function onScroll() {
  const y = window.scrollY
  scrolled.value = y > 12
  const max = document.documentElement.scrollHeight - window.innerHeight
  progress.value = max > 0 ? Math.min(1, y / max) : 0
}
const toTop = () => window.scrollTo({ top: 0, behavior: 'smooth' })

// ── Hero: soft light that follows the pointer ──
const glow = ref({ x: 70, y: 20 })
function onPointer(e) {
  const r = e.currentTarget.getBoundingClientRect()
  glow.value = { x: ((e.clientX - r.left) / r.width) * 100, y: ((e.clientY - r.top) / r.height) * 100 }
}

// ── "Install the app" (Android Chrome offers it; iPhones get the steps) ──
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

// ── Reveal on scroll + count-up numbers ──
let io = null
if (typeof IntersectionObserver !== 'undefined') {
  io = new IntersectionObserver(
    (entries) =>
      entries.forEach((e) => {
        if (!e.isIntersecting) return
        e.target.classList.add('in')
        e.target.__onShow?.()
        io.unobserve(e.target)
      }),
    { threshold: 0.15 },
  )
}
const vReveal = {
  mounted(el, binding) {
    el.classList.add('reveal')
    if (binding.value) el.style.setProperty('--d', `${binding.value}ms`)
    if (!io) return el.classList.add('in')
    io.observe(el)
  },
}
const vCount = {
  mounted(el, binding) {
    const target = Number(binding.value)
    const run = () => {
      if (reduced) return (el.textContent = target.toLocaleString())
      const start = performance.now()
      const step = (t) => {
        const k = Math.min(1, (t - start) / 1400)
        el.textContent = Math.round(target * (1 - Math.pow(1 - k, 3))).toLocaleString()
        if (k < 1) requestAnimationFrame(step)
      }
      requestAnimationFrame(step)
    }
    el.textContent = '0'
    if (!io) return run()
    el.__onShow = run
    io.observe(el)
  },
}

// ── Cards lean gently toward the pointer (computers only) ──
const vTilt = {
  mounted(el) {
    if (reduced || !window.matchMedia?.('(hover: hover)').matches) return
    el.classList.add('tilt')
    el.addEventListener('pointermove', (e) => {
      const r = el.getBoundingClientRect()
      const x = (e.clientX - r.left) / r.width - 0.5
      const y = (e.clientY - r.top) / r.height - 0.5
      el.style.setProperty('--rx', `deg`)
      el.style.setProperty('--ry', `deg`)
      el.style.setProperty('--mx', `%`)
      el.style.setProperty('--my', `%`)
    })
    el.addEventListener('pointerleave', () => {
      el.style.setProperty('--rx', '0deg')
      el.style.setProperty('--ry', '0deg')
    })
  },
}

// ── Rotating word in the headline ──
const words = ['pay rent', 'track rent', 'confirm rent', 'manage homes']
const wordIndex = ref(0)

// ── Hero phone: a notification drops in, again and again ──
const toastOn = ref(false)

// ── "Pay with mobile money" walkthrough (auto-plays, tap a step to jump) ──
const MOMO = [
  { icon: Smartphone, title: 'Choose your SIM', text: 'MTN or Airtel.' },
  { icon: Phone, title: 'Send the money', text: 'Follow the simple steps on your phone.' },
  { icon: CircleCheck, title: 'Your payment is verified', text: 'Your rent updates straight away.' },
  { icon: MessageSquareText, title: 'Get instant confirmation', text: 'A notification and an SMS tell you your payment was received.' },
]
const momoStep = ref(0)
let momoTimer = null
function pickStep(i) {
  momoStep.value = i
  clearInterval(momoTimer)
  momoTimer = setInterval(() => (momoStep.value = (momoStep.value + 1) % MOMO.length), 3200)
}

// ── Tenants / landlords tabs ──
const audience = ref('tenant')

let wordTimer = null
let toastTimer = null
onMounted(() => {
  document.documentElement.style.scrollBehavior = 'smooth'
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('beforeinstallprompt', onBeforeInstall)
  onScroll()
  if (reduced) return
  wordTimer = setInterval(() => (wordIndex.value = (wordIndex.value + 1) % words.length), 7000) // each word stays 7 s
  const loop = () => {
    toastOn.value = true
    setTimeout(() => (toastOn.value = false), 3400)
  }
  setTimeout(loop, 1400)
  toastTimer = setInterval(loop, 7000)
  pickStep(0)
})
onBeforeUnmount(() => {
  document.documentElement.style.scrollBehavior = ''
  window.removeEventListener('scroll', onScroll)
  window.removeEventListener('beforeinstallprompt', onBeforeInstall)
  clearInterval(wordTimer)
  clearInterval(toastTimer)
  clearInterval(momoTimer)
  io?.disconnect()
})

// ── Content (all true of the app today) ──
const marquee = [
  [Smartphone, 'MTN Mobile Money'], [Smartphone, 'Airtel Money'], [Banknote, 'Cash'], [MessageSquareText, 'SMS confirmations'],
  [BellRing, 'Phone notifications'], [Building2, 'Houses & rooms'], [BarChart3, 'Clear records'],
]

const features = [
  { icon: Smartphone, title: 'Pay with MTN or Airtel', text: 'Send rent from your own phone straight to your landlord, with simple steps to follow.', tone: 'teal' },
  { icon: Banknote, title: 'Cash works too', text: 'Pay your landlord in cash. They record it and your rent updates.', tone: 'amber' },
  { icon: CalendarClock, title: 'Always know your time', text: 'See when your rent month started, when it ends and what you owe.', tone: 'sky' },
  { icon: MessageSquareText, title: 'SMS confirmations', text: 'Get a text from Renta UG every time your landlord confirms a payment.', tone: 'rose' },
  { icon: Building2, title: 'Houses and rooms', text: 'Landlords keep every house, room and tenant in one place.', tone: 'violet' },
  { icon: BarChart3, title: 'Clear records', text: 'Every confirmed payment is kept, so landlord and tenant see the same numbers.', tone: 'emerald' },
]

const tenantPoints = [
  [Wallet, 'See what you owe and when your month ends'],
  [Smartphone, 'Pay with MTN, Airtel or cash'],
  [MessageSquareText, 'Get an SMS when your payment is confirmed'],
  [BellRing, 'Receive notices from your landlord'],
]
const landlordPoints = [
  [LayoutDashboard, 'All your houses and rooms in one place'],
  [CircleCheck, 'Confirm payments in one tap'],
  [Users, 'Add tenants and send them notices'],
  [BarChart3, 'See who has paid and who has not'],
]

const security = [
  { icon: Lock, title: 'Your PIN stays yours', text: 'Renta never asks for your mobile money PIN. You send money on your own phone.' },
  { icon: EyeOff, title: 'Only your own data', text: 'Tenants see only their own records. Landlords see only their own houses.' },
  { icon: ShieldCheck, title: 'Your privacy respected', text: 'We do not sell your information. Read our Privacy policy any time.' },
]

const steps = [
  { icon: KeyRound, title: 'Create your account', text: 'Sign up with your email. We send a 6-character code to confirm it is you.' },
  { icon: Home, title: 'Connect to your home', text: 'Tenants connect with the code from their landlord. Landlords add houses, rooms and tenants.' },
  { icon: Wallet, title: 'Pay and stay up to date', text: 'Pay by mobile money or cash and get an SMS when it is confirmed.' },
]

const faq = [
  { q: 'Is Renta UG free?', a: 'Creating an account is free. MTN and Airtel may charge their normal fees when you send money.' },
  { q: 'Does Renta UG hold my money?', a: 'No. Your money goes straight to your landlord. Renta only keeps the record.' },
  { q: 'How do I know my payment worked?', a: 'Your landlord confirms it in the app, and you get a notification and an SMS.' },
  { q: 'Can I pay in cash?', a: 'Yes. Your landlord records it and your rent updates straight away.' },
  { q: 'I am a landlord. How do I join?', a: 'Landlord accounts are set up by the Renta UG team. Contact us and we will get you started.' },
]
const open = ref(0)

const tones = {
  teal: 'bg-brand-50 text-brand-700',
  sky: 'bg-sky-50 text-sky-700',
  violet: 'bg-violet-50 text-violet-700',
  amber: 'bg-amber-50 text-amber-700',
  rose: 'bg-rose-50 text-rose-700',
  emerald: 'bg-emerald-50 text-emerald-700',
  slate: 'bg-slate-100 text-slate-700',
  indigo: 'bg-indigo-50 text-indigo-700',
  cyan: 'bg-cyan-50 text-cyan-700',
}
</script>

<template>
  <div class="landing">
    <!-- Scroll progress -->
    <div class="progress" :style="{ transform: `scaleX(${progress})` }" aria-hidden="true" />

    <!-- Top bar -->
    <header class="nav fixed inset-x-0 top-0 z-40 transition" :class="scrolled || menu ? 'nav-solid' : ''">
      <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-3 px-4 sm:px-6">
        <Logo />
        <nav class="hidden items-center gap-7 text-sm font-medium text-slate-600 md:flex">
          <a href="#features" class="nav-link">Features</a>
          <a href="#momo" class="nav-link">How to pay</a>
          <a href="#install" class="nav-link">Get the app</a>
          <a href="#faq" class="nav-link">Questions</a>
        </nav>
        <div class="flex items-center gap-2">
          <button v-if="signedIn" class="btn-primary hidden h-10 rounded-xl px-4 text-sm sm:inline-flex" @click="goApp">Open my dashboard</button>
          <template v-else>
            <RouterLink to="/login" class="btn-secondary hidden h-10 rounded-xl px-4 text-sm sm:inline-flex">Sign in</RouterLink>
            <RouterLink to="/signup" class="btn-primary shine hidden h-10 rounded-xl px-4 text-sm sm:inline-flex">Get started</RouterLink>
          </template>
          <button class="flex size-10 items-center justify-center rounded-xl text-slate-700 md:hidden" :aria-label="menu ? 'Close menu' : 'Open menu'" @click="menu = !menu">
            <X v-if="menu" class="size-5" /><Menu v-else class="size-5" />
          </button>
        </div>
      </div>
      <Transition name="drop">
        <div v-if="menu" class="border-t border-slate-200/70 px-4 pt-2 pb-5 md:hidden">
          <a v-for="(l, i) in [['Features', '#features'], ['How to pay', '#momo'], ['Get the app', '#install'], ['Questions', '#faq']]" :key="l[1]" :href="l[1]" class="menu-link block py-3 text-base font-medium text-slate-700" :style="{ '--d': `${i * 40}ms` }" @click="menu = false">{{ l[0] }}</a>
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
    <section class="hero relative overflow-hidden pt-28 pb-16 sm:pt-36 sm:pb-24" :style="{ '--gx': `${glow.x}%`, '--gy': `${glow.y}%` }" @pointermove="onPointer">
      <div class="aurora" aria-hidden="true" />
      <div class="grid-lines" aria-hidden="true" />
      <div class="orb orb-1" aria-hidden="true" />
      <div class="orb orb-2" aria-hidden="true" />
      <div class="orb orb-3" aria-hidden="true" />
      <div class="relative mx-auto grid max-w-6xl items-center gap-12 px-4 sm:px-6 lg:grid-cols-[1.1fr_0.9fr]">
        <div class="text-center lg:text-left">
          <p class="hero-in mx-auto inline-flex items-center gap-2 rounded-full bg-white/70 px-3.5 py-1.5 text-xs font-semibold text-brand-700 ring-1 ring-brand-200/70 backdrop-blur lg:mx-0" style="--d: 0ms">
            <span class="live size-2 rounded-full bg-emerald-500" /> Made for rent in Uganda
          </p>
          <h1 class="hero-in mt-5 text-[2.35rem] leading-[1.08] font-extrabold tracking-tight text-slate-900 sm:text-6xl" style="--d: 80ms">
            The easy way to
            <span class="word-wrap">
              <Transition name="word" mode="out-in">
                <span :key="wordIndex" class="grad grad-move block">{{ words[wordIndex] }}</span>
              </Transition>
            </span>
          </h1>
          <p class="hero-in mx-auto mt-5 max-w-xl text-base leading-relaxed text-slate-600 sm:text-lg lg:mx-0" style="--d: 160ms">
            A simple, secure platform for rent payments. Tenants pay by MTN Mobile Money, Airtel Money or cash, and every payment is verified and recorded in one transparent account.
          </p>
          <div class="hero-in mt-8 flex flex-col items-stretch justify-center gap-3 sm:flex-row lg:justify-start" style="--d: 240ms">
            <button v-if="signedIn" class="btn-primary shine h-13 rounded-2xl px-7 text-base" @click="goApp">Open my dashboard <ArrowRight class="size-4.5" /></button>
            <template v-else>
              <RouterLink to="/signup" class="btn-primary shine h-13 rounded-2xl px-7 text-base">Create free account <ArrowRight class="arrow size-4.5" /></RouterLink>
              <RouterLink to="/login" class="btn-secondary h-13 rounded-2xl px-7 text-base">I already have an account</RouterLink>
            </template>
          </div>
          <ul class="hero-in mt-7 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-sm text-slate-500 lg:justify-start" style="--d: 320ms">
            <li class="flex items-center gap-1.5"><Check class="size-4 text-emerald-600" /> MTN &amp; Airtel</li>
            <li class="flex items-center gap-1.5"><Check class="size-4 text-emerald-600" /> Confirmed by your landlord</li>
            <li class="flex items-center gap-1.5"><Check class="size-4 text-emerald-600" /> SMS for every confirmation</li>
          </ul>
        </div>

        <!-- Phone preview, built in CSS -->
        <div class="hero-in relative mx-auto w-full max-w-[19rem]" style="--d: 200ms">
          <div class="float-chip chip-a"><span class="size-2 rounded-full bg-emerald-500" /> Payment confirmed</div>
          <div class="float-chip chip-b"><CalendarClock class="size-3.5 text-brand-600" /> 28 days left</div>
          <div class="float-chip chip-c"><MessageSquareText class="size-3.5 text-sky-600" /> SMS sent</div>
          <div class="phone">
            <div class="screen relative overflow-hidden">
              <!-- Notification dropping in -->
              <Transition name="toast">
                <div v-if="toastOn" class="mock-toast">
                  <span class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-teal-400 to-teal-800 text-white"><Wallet class="size-3.5" /></span>
                  <div class="min-w-0">
                    <p class="text-[10px] font-semibold text-slate-900">Renta UG · now</p>
                    <p class="truncate text-[10px] text-slate-600">Payment confirmation: UGX 300,000 received</p>
                  </div>
                </div>
              </Transition>
              <p class="text-[10px] font-semibold tracking-[0.14em] text-slate-400 uppercase">Good morning</p>
              <p class="mt-1 text-lg leading-tight font-bold text-slate-900">Welcome, <span class="grad">Grace</span></p>
              <div class="mock-card">
                <p class="flex items-center gap-1.5 text-[11px] font-medium text-white/85"><Wallet class="size-3.5" /> Rent account</p>
                <div class="mt-3 grid grid-cols-2 overflow-hidden rounded-xl bg-white/12 ring-1 ring-white/15">
                  <div class="p-2.5"><p class="text-[9px] tracking-wide text-white/70 uppercase">Paid</p><p class="mt-0.5 text-[13px] font-semibold">UGX 300,000</p></div>
                  <div class="border-l border-white/15 p-2.5"><p class="text-[9px] tracking-wide text-white/70 uppercase">Balance due</p><p class="mt-0.5 text-[13px] font-semibold">UGX 0</p></div>
                </div>
                <div class="mt-3 rounded-lg bg-white py-2 text-center text-[12px] font-semibold text-teal-900">Recharge</div>
              </div>
              <div class="mt-3 rounded-2xl border border-slate-200 bg-slate-50 p-3">
                <p class="text-[10px] text-slate-500">This rent month</p>
                <p class="text-xl font-bold text-slate-900">28 <span class="text-xs font-medium text-slate-500">days left</span></p>
                <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-200"><div class="mock-bar h-full rounded-full" /></div>
              </div>
              <div class="mt-3 flex items-center gap-2.5 rounded-xl border border-slate-200 p-2.5">
                <span class="flex size-8 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><Check class="size-4" /></span>
                <div class="min-w-0 flex-1"><p class="truncate text-[11px] font-semibold text-slate-900">Rent received</p><p class="text-[10px] text-slate-500">MTN Mobile Money</p></div>
                <p class="text-[11px] font-semibold text-emerald-700">UGX 300,000</p>
              </div>
            </div>
          </div>
        </div>
      </div>
      <a href="#features" class="scroll-cue" aria-label="Scroll down"><ChevronDown class="size-5" /></a>
    </section>

    <!-- Moving strip -->
    <section class="marquee border-y border-slate-200/70 bg-white/60" aria-label="What Renta UG includes">
      <div class="marquee-track">
        <template v-for="copy in 2" :key="copy">
          <span v-for="m in marquee" :key="`${copy}-${m[1]}`" class="marquee-item" :aria-hidden="copy === 2">
            <component :is="m[0]" class="size-4 text-brand-600" /> {{ m[1] }}
          </span>
        </template>
      </div>
    </section>

    <!-- Features -->
    <section id="features" class="mx-auto max-w-6xl scroll-mt-20 px-4 pb-16 sm:px-6 sm:pb-24">
      <div v-reveal class="mx-auto max-w-2xl text-center">
        <p class="eyebrow">Everything in one place</p>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Built around how rent really works</h2>
        <p class="mt-3 text-slate-600">Simple for tenants. Clear for landlords.</p>
      </div>
      <div class="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <article v-for="(f, i) in features" :key="f.title" v-reveal="(i % 3) * 90" v-tilt class="feature group rounded-3xl border border-slate-200 bg-white p-6">
          <span class="feature-ico flex size-12 items-center justify-center rounded-2xl" :class="tones[f.tone]"><component :is="f.icon" class="size-6" /></span>
          <h3 class="mt-4 text-lg font-bold text-slate-900">{{ f.title }}</h3>
          <p class="mt-1.5 text-sm leading-relaxed text-slate-600">{{ f.text }}</p>
        </article>
      </div>
    </section>

    <!-- Mobile money walkthrough -->
    <section id="momo" class="momo relative scroll-mt-16 overflow-hidden py-16 sm:py-24">
      <span class="blob blob-a" aria-hidden="true" /><span class="blob blob-b" aria-hidden="true" />
      <div class="mx-auto grid max-w-6xl items-center gap-10 px-4 sm:px-6 lg:grid-cols-[1fr_0.9fr]">
        <div>
          <div v-reveal>
            <p class="eyebrow">Pay with mobile money</p>
            <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Pay rent in four easy steps</h2>
            <p class="mt-3 text-slate-600">Quick, simple and safe.</p>
          </div>
          <ol class="mt-8 space-y-2">
            <li v-for="(s, i) in MOMO" :key="s.title" v-reveal="i * 60">
              <button type="button" class="momo-step flex w-full items-start gap-3.5 rounded-2xl p-3.5 text-left" :class="momoStep === i && 'momo-on'" @click="pickStep(i)">
                <span class="momo-num">{{ i + 1 }}</span>
                <span class="min-w-0 flex-1">
                  <span class="block font-semibold text-slate-900">{{ s.title }}</span>
                  <span class="momo-text block text-sm leading-relaxed text-slate-600">{{ s.text }}</span>
                </span>
                <component :is="s.icon" class="mt-0.5 size-5 shrink-0" :class="momoStep === i ? 'text-brand-600' : 'text-slate-300'" />
              </button>
            </li>
          </ol>
        </div>

        <!-- Phone showing the current step -->
        <div v-reveal="120" class="relative mx-auto w-full max-w-[18rem]">
          <div class="phone phone-still">
            <div class="screen min-h-[25rem]">
              <div class="mb-3 h-1 overflow-hidden rounded-full bg-slate-100"><div class="h-full rounded-full bg-gradient-to-r from-teal-400 to-sky-500 transition-all duration-500" :style="{ width: `${((momoStep + 1) / MOMO.length) * 100}%` }" /></div>
              <Transition name="swap" mode="out-in">
                <div :key="momoStep">
                  <!-- 1 SIM -->
                  <div v-if="momoStep === 0" class="space-y-2.5">
                    <p class="text-sm font-bold text-slate-900">Select the SIM you're going to use</p>
                    <div class="flex items-center gap-2.5 rounded-xl p-2.5 ring-2 ring-[#ffcc00]"><span class="sim bg-[#ffcc00] text-[#1f1a00]">MTN</span><span class="text-xs font-semibold text-slate-800">MTN Mobile Money</span></div>
                    <div class="flex items-center gap-2.5 rounded-xl p-2.5 ring-1 ring-slate-200"><span class="sim bg-[#e40000] text-white">AIRTEL</span><span class="text-xs font-semibold text-slate-800">Airtel Money</span></div>
                  </div>
                  <!-- 3 dial -->
                  <div v-else-if="momoStep === 1" class="space-y-2">
                    <p class="text-sm font-bold text-slate-900">Steps</p>
                    <p v-for="(t, k) in ['Dial *165#', 'Send Money', 'Enter the landlord number', 'Enter the amount', 'Enter your PIN']" :key="t" class="flex items-center gap-2 text-[11px] text-slate-700"><span class="mini-num">{{ k + 1 }}</span>{{ t }}</p>
                    <div class="dial mt-2"><Phone class="size-4" /> Dial *165#</div>
                  </div>
                  <!-- 3 verified -->
                  <div v-else-if="momoStep === 2" class="flex flex-col items-center pt-6 text-center">
                    <span class="verified flex size-16 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><CircleCheck class="size-9" /></span>
                    <p class="mt-3 text-sm font-bold text-slate-900">Payment verified</p>
                    <p class="mt-1 text-[11px] text-slate-600">UGX 300,000 · MTN Mobile Money</p>
                    <p class="mt-3 rounded-full bg-emerald-50 px-3 py-1 text-[10px] font-semibold text-emerald-700">Rent updated</p>
                  </div>
                  <!-- 4 notification + SMS -->
                  <div v-else class="space-y-2.5 pt-2">
                    <div class="mock-note flex items-center gap-2 rounded-xl bg-white p-2 shadow-md ring-1 ring-slate-100">
                      <span class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-teal-400 to-teal-800 text-white"><BellRing class="size-3.5" /></span>
                      <div class="min-w-0"><p class="text-[10px] font-semibold text-slate-900">Renta UG · now</p><p class="truncate text-[10px] text-slate-600">Payment received</p></div>
                    </div>
                    <p class="pt-1 text-[10px] font-semibold text-slate-400">Messages · Renta UG</p>
                    <div class="sms rounded-2xl rounded-tl-sm bg-slate-100 p-3 text-[11px] leading-relaxed text-slate-800">
                      Renta UG: Your payment of UGX 300,000 has been received. Thank you!
                    </div>
                  </div>
                </div>
              </Transition>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Tenants / landlords -->
    <section class="bg-slate-50/70 py-16 sm:py-24">
      <div class="mx-auto max-w-6xl px-4 sm:px-6">
        <div v-reveal class="mx-auto max-w-2xl text-center">
          <p class="eyebrow">Made for both sides</p>
          <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">One app, two clear views</h2>
          <div class="seg mx-auto mt-6 inline-grid grid-cols-2 rounded-2xl bg-white p-1 ring-1 ring-slate-200" role="tablist">
            <span class="seg-pill" :class="audience === 'landlord' && 'seg-right'" aria-hidden="true" />
            <button v-for="a in [['tenant', 'For tenants'], ['landlord', 'For landlords']]" :key="a[0]" role="tab" :aria-selected="audience === a[0]" class="relative z-10 h-11 rounded-xl px-5 text-sm font-semibold transition-colors" :class="audience === a[0] ? 'text-white' : 'text-slate-600'" @click="audience = a[0]">{{ a[1] }}</button>
          </div>
        </div>
        <Transition name="swap" mode="out-in">
          <div :key="audience" v-tilt class="split mt-8 grid gap-6 rounded-3xl p-6 text-white sm:p-10 lg:grid-cols-[1fr_0.8fr]" :class="audience === 'tenant' ? 'split-tenant' : 'split-landlord'">
            <div>
              <span class="flex size-12 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25"><component :is="audience === 'tenant' ? Users : Building2" class="size-6" /></span>
              <h3 class="mt-5 text-2xl font-bold">{{ audience === 'tenant' ? 'Always know where you stand' : 'Your whole rental business, live' }}</h3>
              <ul class="mt-5 space-y-3.5">
                <li v-for="(p, i) in audience === 'tenant' ? tenantPoints : landlordPoints" :key="p[1]" class="point flex items-start gap-3 text-[0.95rem] text-white/90" :style="{ '--d': `${i * 70}ms` }">
                  <span class="flex size-8 shrink-0 items-center justify-center rounded-xl bg-white/12"><component :is="p[0]" class="size-4" /></span>
                  <span class="pt-1">{{ p[1] }}</span>
                </li>
              </ul>
            </div>
            <!-- Mini preview -->
            <div class="mini rounded-2xl p-4">
              <template v-if="audience === 'tenant'">
                <p class="text-xs text-white/70">This rent month</p>
                <p class="mt-1 text-4xl font-extrabold">21 <span class="text-base font-medium text-white/70">days left</span></p>
                <div class="mt-3 h-2 overflow-hidden rounded-full bg-white/15"><div class="grow-bar h-full rounded-full bg-white" style="--w: 30%" /></div>
                <div class="mt-4 grid grid-cols-2 gap-2 text-xs">
                  <div class="rounded-xl bg-white/10 p-3"><p class="text-white/70">Paid on</p><p class="mt-0.5 font-semibold">12 Nov</p></div>
                  <div class="rounded-xl bg-white/10 p-3"><p class="text-white/70">Ends</p><p class="mt-0.5 font-semibold">12 Dec</p></div>
                </div>
              </template>
              <template v-else>
                <p class="text-xs text-white/70">Collected by month</p>
                <div class="mt-3 flex h-32 items-end gap-2">
                  <span v-for="(h, i) in [45, 62, 54, 78, 70, 92]" :key="i" class="col flex-1 rounded-t-md bg-white/80" :style="{ '--h': `${h}%`, '--i': i }" />
                </div>
                <div class="mt-4 grid grid-cols-2 gap-2 text-xs">
                  <div class="rounded-xl bg-white/10 p-3"><p class="text-white/70">To confirm</p><p class="mt-0.5 font-semibold">2 payments</p></div>
                  <div class="rounded-xl bg-white/10 p-3"><p class="text-white/70">Rooms full</p><p class="mt-0.5 font-semibold">11 of 12</p></div>
                </div>
              </template>
              <p class="mt-3 text-[10px] text-white/50">Example data</p>
            </div>
          </div>
        </Transition>
      </div>
    </section>

    <!-- Security -->
    <section class="mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-24">
      <div v-reveal class="mx-auto max-w-2xl text-center">
        <p class="eyebrow">Safe by design</p>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Your money and data stay yours</h2>
      </div>
      <div class="mt-12 grid gap-4 sm:grid-cols-3">
        <div v-for="(s, i) in security" :key="s.title" v-reveal="i * 80" class="sec rounded-3xl border border-slate-200 bg-white p-6">
          <span class="sec-ico flex size-12 items-center justify-center rounded-2xl text-white"><component :is="s.icon" class="size-6" /></span>
          <h3 class="mt-4 font-bold text-slate-900">{{ s.title }}</h3>
          <p class="mt-1.5 text-sm leading-relaxed text-slate-600">{{ s.text }}</p>
        </div>
      </div>
    </section>

    <!-- How it works -->
    <section id="how" class="bg-slate-50/70 py-16 sm:py-24">
      <div class="mx-auto max-w-6xl scroll-mt-20 px-4 sm:px-6">
        <div v-reveal class="mx-auto max-w-2xl text-center">
          <p class="eyebrow">How it works</p>
          <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Up and running in three steps</h2>
        </div>
        <ol class="steps relative mt-12 grid gap-4 md:grid-cols-3">
          <span v-reveal class="steps-line hidden md:block" aria-hidden="true" />
          <li v-for="(s, i) in steps" :key="s.title" v-reveal="i * 120" class="step relative rounded-3xl border border-slate-200 bg-white p-6">
            <span class="num">{{ i + 1 }}</span>
            <span class="flex size-12 items-center justify-center rounded-2xl bg-brand-50 text-brand-700"><component :is="s.icon" class="size-6" /></span>
            <h3 class="mt-4 text-lg font-bold text-slate-900">{{ s.title }}</h3>
            <p class="mt-1.5 text-sm leading-relaxed text-slate-600">{{ s.text }}</p>
          </li>
        </ol>
      </div>
    </section>

    <!-- Install -->
    <section id="install" class="scroll-mt-20 px-4 py-16 sm:px-6 sm:py-24">
      <div v-reveal class="install mx-auto max-w-6xl overflow-hidden rounded-[2rem] p-7 text-white sm:p-12">
        <div class="relative text-center">
          <div>
            <p class="text-xs font-bold tracking-[0.16em] text-white/70 uppercase">Get the app</p>
            <h2 class="mt-3 text-3xl font-extrabold tracking-tight sm:text-4xl">Put Renta UG on your phone</h2>
            <p class="mx-auto mt-3 max-w-lg text-white/85">It opens like any other app and sends you rent notices.</p>
            <button class="install-btn mt-6" @click="install"><Download class="bounce size-5" /> Install the app</button>
          </div>
        </div>
      </div>
    </section>

    <!-- FAQ -->
    <section id="faq" class="mx-auto max-w-3xl scroll-mt-20 px-4 pb-16 sm:px-6 sm:pb-24">
      <div v-reveal class="text-center">
        <p class="eyebrow">Questions</p>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">Good to know</h2>
      </div>
      <div class="mt-10 space-y-3">
        <div v-for="(f, i) in faq" :key="f.q" v-reveal="(i % 5) * 50" class="faq rounded-2xl border bg-white" :class="open === i ? 'border-brand-200 faq-active' : 'border-slate-200'">
          <button class="flex w-full items-center justify-between gap-4 px-5 py-4 text-left font-semibold text-slate-900" :aria-expanded="open === i" @click="open = open === i ? -1 : i">
            {{ f.q }}
            <span class="flex size-8 shrink-0 items-center justify-center rounded-full transition" :class="open === i ? 'rotate-180 bg-brand-50 text-brand-700' : 'bg-slate-100 text-slate-500'"><ChevronDown class="size-4" /></span>
          </button>
          <div class="faq-body" :class="open === i && 'faq-open'"><div><p class="px-5 pb-5 text-sm leading-relaxed text-slate-600">{{ f.a }}</p></div></div>
        </div>
      </div>
    </section>

    <!-- Final call -->
    <section class="px-4 pb-16 sm:px-6 sm:pb-24">
      <div v-reveal class="cta relative mx-auto max-w-4xl overflow-hidden rounded-[2rem] px-6 py-12 text-center text-white sm:py-16">
        <span class="cta-ring cta-ring-1" aria-hidden="true" /><span class="cta-ring cta-ring-2" aria-hidden="true" />
        <Sparkles class="relative mx-auto size-8 text-white/80" />
        <h2 class="relative mt-3 text-3xl font-extrabold tracking-tight sm:text-4xl">Ready to make rent easy?</h2>
        <p class="relative mx-auto mt-3 max-w-md text-white/85">Create your account in a minute. It only takes a minute.</p>
        <div class="relative mt-7 flex flex-col justify-center gap-3 sm:flex-row">
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
      <div class="mx-auto grid max-w-6xl gap-8 px-4 py-10 text-sm sm:grid-cols-[1.4fr_1fr_1fr] sm:px-6">
        <div>
          <Logo />
          <p class="mt-3 max-w-xs leading-relaxed text-slate-500">Rent made simple in Uganda.</p>
        </div>
        <div>
          <p class="font-semibold text-slate-900">Product</p>
          <ul class="mt-3 space-y-2 text-slate-500">
            <li><a href="#features" class="hover:text-slate-900">Features</a></li>
            <li><a href="#momo" class="hover:text-slate-900">How to pay</a></li>

            <li><a href="#install" class="hover:text-slate-900">Get the app</a></li>
          </ul>
        </div>
        <div>
          <p class="font-semibold text-slate-900">Legal & account</p>
          <ul class="mt-3 space-y-2 text-slate-500">
            <li><RouterLink to="/privacy" class="hover:text-slate-900">Privacy policy</RouterLink></li>
            <li><RouterLink to="/terms" class="hover:text-slate-900">Terms and conditions</RouterLink></li>
            <li><RouterLink to="/delete-account" class="hover:text-slate-900">Delete account</RouterLink></li>
            <li><RouterLink to="/login" class="hover:text-slate-900">Sign in</RouterLink></li>
          </ul>
        </div>
      </div>
      <div class="border-t border-slate-100 py-5 text-center text-xs text-slate-400">
        © {{ new Date().getFullYear() }} {{ SITE.name }}. Renta UG does not hold or transfer money; payments go directly between tenants and landlords.
      </div>
    </footer>

    <!-- Back to top -->
    <Transition name="pop">
      <button v-if="progress > 0.15" class="to-top" aria-label="Back to top" @click="toTop"><ArrowUp class="size-5" /></button>
    </Transition>
  </div>
</template>

<style scoped>
.landing {
  position: relative;
  overflow-x: clip;
  background:
    radial-gradient(60% 40% at 10% 10%, color-mix(in srgb, #ccfbf1 70%, transparent), transparent 70%),
    radial-gradient(50% 40% at 90% 30%, color-mix(in srgb, #e0f2fe 80%, transparent), transparent 70%),
    radial-gradient(50% 40% at 20% 80%, color-mix(in srgb, #fef3c7 60%, transparent), transparent 70%),
    var(--color-white);
  background-attachment: fixed;
}
/* Page content sits above the cartoon background */
.landing > section, .landing > footer { position: relative; z-index: 1; }
.eyebrow {
  display: inline-block; border-radius: 9999px; padding: 0.35rem 0.9rem;
  font-size: 0.72rem; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase;
  color: var(--color-brand-700);
  background: linear-gradient(100deg, var(--color-brand-50) 30%, color-mix(in srgb, var(--color-brand-100) 90%, white) 50%, var(--color-brand-50) 70%);
  background-size: 250% 100%;
  box-shadow: inset 0 0 0 1px var(--color-brand-100);
  animation: shimmer 4s ease-in-out infinite;
}

/* Scroll progress */
.progress { position: fixed; inset: 0 0 auto; z-index: 60; height: 3px; transform-origin: left; background: linear-gradient(90deg, #14b8a6, #0ea5e9, #8b5cf6); }

/* Top bar */
.nav { background: transparent; }
.nav-solid { background: color-mix(in srgb, var(--color-white) 88%, transparent); backdrop-filter: blur(14px); box-shadow: 0 1px 0 var(--color-slate-200); }
.nav-link { position: relative; transition: color 0.2s ease; }
.nav-link:hover { color: var(--color-slate-900); }
.nav-link::after { content: ''; position: absolute; left: 0; right: 0; bottom: -6px; height: 2px; border-radius: 2px; background: var(--color-brand-500); transform: scaleX(0); transition: transform 0.25s ease; }
.nav-link:hover::after { transform: scaleX(1); }
.drop-enter-active, .drop-leave-active { transition: opacity 0.2s ease, transform 0.2s ease; }
.drop-enter-from, .drop-leave-to { opacity: 0; transform: translateY(-6px); }
.menu-link { animation: rise 0.4s cubic-bezier(0.22, 1, 0.36, 1) backwards; animation-delay: var(--d); }

/* Buttons with a light sweep */
.shine { position: relative; overflow: hidden; }
.shine::after { content: ''; position: absolute; inset: 0; background: linear-gradient(110deg, transparent 30%, rgb(255 255 255 / 0.35) 50%, transparent 70%); transform: translateX(-120%); animation: sweep 3.6s ease-in-out infinite; }
.shine:hover .arrow { transform: translateX(3px); }
.arrow { transition: transform 0.2s ease; }

/* Hero */
.hero {
  background:
    radial-gradient(28rem circle at var(--gx) var(--gy), color-mix(in srgb, var(--color-brand-100) 70%, transparent), transparent 70%),
    radial-gradient(70% 55% at 85% 0%, color-mix(in srgb, var(--color-brand-100) 90%, transparent), transparent 70%),
    radial-gradient(55% 45% at 0% 30%, color-mix(in srgb, var(--color-sky-100) 80%, transparent), transparent 70%);
}
.grid-lines {
  position: absolute; inset: 0; pointer-events: none;
  background-image: linear-gradient(var(--color-slate-200) 1px, transparent 1px), linear-gradient(90deg, var(--color-slate-200) 1px, transparent 1px);
  background-size: 44px 44px; opacity: 0.35;
  mask-image: radial-gradient(70% 60% at 50% 30%, #000, transparent 75%);
}
.orb { position: absolute; border-radius: 9999px; filter: blur(60px); opacity: 0.5; pointer-events: none; animation: drift 16s ease-in-out infinite alternate; }
.orb-1 { width: 20rem; height: 20rem; top: 4rem; left: -6rem; background: #5eead4; }
.orb-2 { width: 18rem; height: 18rem; bottom: -4rem; right: -4rem; background: #7dd3fc; animation-duration: 20s; }
.orb-3 { width: 12rem; height: 12rem; top: 40%; left: 45%; background: #c4b5fd; opacity: 0.3; animation-duration: 24s; }
.grad { background: linear-gradient(90deg, #0f766e, #14b8a6 55%, #0284c7); -webkit-background-clip: text; background-clip: text; color: transparent; }
.grad-move { background-size: 200% 100%; animation: hue 6s ease-in-out infinite alternate; }
.word-wrap { display: block; height: 1.2em; overflow: hidden; }
.word-enter-active, .word-leave-active { transition: opacity 0.7s ease, transform 0.7s cubic-bezier(0.16, 1, 0.3, 1), filter 0.7s ease; }
.word-enter-from { opacity: 0; transform: translateY(70%); filter: blur(6px); }
.word-leave-to { opacity: 0; transform: translateY(-70%); filter: blur(6px); }
.live { box-shadow: 0 0 0 0 rgb(16 185 129 / 0.5); animation: ping 2.4s ease-out infinite; }
.hero-in { animation: rise 0.7s cubic-bezier(0.22, 1, 0.36, 1) backwards; animation-delay: var(--d, 0ms); }
.scroll-cue { position: absolute; left: 50%; bottom: 1rem; display: none; width: 2.5rem; height: 2.5rem; margin-left: -1.25rem; align-items: center; justify-content: center; border-radius: 9999px; color: var(--color-slate-500); background: color-mix(in srgb, var(--color-white) 70%, transparent); box-shadow: 0 0 0 1px var(--color-slate-200); animation: nudge 2s ease-in-out infinite; }
@media (min-width: 1024px) { .scroll-cue { display: flex; } }

/* Phone */
.phone {
  --color-white: #fff; --color-slate-50: #f8fafc; --color-slate-100: #f1f5f9; --color-slate-200: #e2e8f0;
  --color-slate-300: #cbd5e1; --color-slate-400: #94a3b8; --color-slate-500: #64748b; --color-slate-600: #475569;
  --color-slate-700: #334155; --color-slate-800: #1e293b; --color-slate-900: #0f172a;
  position: relative; border-radius: 2.6rem; padding: 0.6rem;
  background: linear-gradient(160deg, #1e293b, #0f172a);
  box-shadow: 0 40px 70px -25px rgb(15 23 42 / 0.5), 0 0 0 1.5px rgb(255 255 255 / 0.08) inset;
  animation: bob 6s ease-in-out infinite;
}
.phone-still { animation: none; }
.phone::before { content: ''; position: absolute; top: 0.95rem; left: 50%; width: 4.2rem; height: 1.1rem; transform: translateX(-50%); border-radius: 9999px; background: #0f172a; z-index: 4; }
.screen { border-radius: 2.1rem; background: #fff; padding: 2.4rem 1rem 1.1rem; color: #0f172a; }
.mock-card { margin-top: 0.8rem; border-radius: 1.1rem; padding: 0.9rem; color: #fff; background: linear-gradient(135deg, #14918a, #0f766e 50%, #0a3b38); }
.mock-bar { width: 0; background: linear-gradient(90deg, #14b8a6, #0284c7); animation: fill 2.4s 0.8s cubic-bezier(0.22, 1, 0.36, 1) forwards; }
.mock-toast { position: absolute; z-index: 3; top: 2.1rem; left: 0.5rem; right: 0.5rem; display: flex; align-items: center; gap: 0.5rem; border-radius: 0.9rem; padding: 0.5rem; background: rgb(255 255 255 / 0.95); box-shadow: 0 12px 26px -12px rgb(15 23 42 / 0.5), 0 0 0 1px rgb(15 23 42 / 0.06); }
.toast-enter-active { transition: transform 0.5s cubic-bezier(0.2, 1.3, 0.35, 1), opacity 0.3s ease; }
.toast-leave-active { transition: transform 0.35s ease-in, opacity 0.3s ease; }
.toast-enter-from, .toast-leave-to { transform: translateY(-140%); opacity: 0; }
.float-chip { position: absolute; z-index: 5; display: inline-flex; align-items: center; gap: 0.4rem; border-radius: 9999px; padding: 0.45rem 0.8rem; font-size: 0.72rem; font-weight: 600; color: #0f172a; background: #fff; box-shadow: 0 12px 28px -10px rgb(15 23 42 / 0.35); animation: bob 5s ease-in-out infinite; }
.chip-a { top: 18%; left: -1.2rem; }
.chip-b { bottom: 16%; right: -1rem; animation-delay: 1.2s; }
.chip-c { top: 46%; right: -1.6rem; animation-delay: 2.2s; }

/* Moving strip */
.marquee { overflow: hidden; mask-image: linear-gradient(90deg, transparent, #000 8%, #000 92%, transparent); }
.marquee-track { display: flex; width: max-content; gap: 2.5rem; padding: 1.15rem 1.25rem; animation: scroll-x 40s linear infinite; }
.marquee:hover .marquee-track { animation-play-state: paused; }
.marquee-item { display: inline-flex; align-items: center; gap: 0.5rem; white-space: nowrap; font-size: 0.875rem; font-weight: 600; color: var(--color-slate-600); }

/* Cards */
.feature { transition: transform 0.3s ease, box-shadow 0.3s ease, border-color 0.3s ease; }
.feature:hover { transform: translateY(-5px); box-shadow: 0 22px 44px -22px rgb(15 118 110 / 0.4); border-color: var(--color-brand-200); }
.feature-ico { transition: transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1); }
.feature:hover .feature-ico { transform: rotate(-8deg) scale(1.12); }

/* Mobile money walkthrough */
.momo { background: radial-gradient(60% 50% at 100% 50%, color-mix(in srgb, var(--color-brand-50) 90%, transparent), transparent 70%), color-mix(in srgb, var(--color-slate-50) 70%, transparent); }
.momo-step { transition: background-color 0.25s ease, box-shadow 0.25s ease; }
.momo-step:hover { background: var(--color-white); }
.momo-on { background: var(--color-white); box-shadow: 0 14px 30px -20px rgb(15 118 110 / 0.5), 0 0 0 1px var(--color-brand-200); }
.momo-text { max-height: 0; overflow: hidden; opacity: 0; transition: max-height 0.35s ease, opacity 0.3s ease, margin 0.3s ease; }
.momo-on .momo-text { max-height: 6rem; opacity: 1; margin-top: 0.15rem; }
.momo-num { display: flex; width: 1.9rem; height: 1.9rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; font-size: 0.8rem; font-weight: 700; color: var(--color-slate-500); background: var(--color-slate-100); transition: all 0.25s ease; }
.momo-on .momo-num { color: #fff; background: linear-gradient(140deg, #14b8a6, #0f766e); transform: scale(1.08); }
.sim { display: flex; height: 2rem; min-width: 3rem; align-items: center; justify-content: center; border-radius: 0.6rem; padding: 0 0.4rem; font-size: 0.6rem; font-weight: 800; }
.mock-copy { display: inline-block; margin-top: 0.4rem; border-radius: 0.5rem; padding: 0.2rem 0.55rem; font-size: 0.6rem; font-weight: 700; color: #0f766e; background: #ccfbf1; animation: blink 1.6s ease-in-out infinite; }
.mini-num { display: flex; width: 1.1rem; height: 1.1rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; font-size: 0.55rem; font-weight: 700; color: #5c4a00; background: #fff7cc; }
.dial { display: flex; height: 2.4rem; align-items: center; justify-content: center; gap: 0.4rem; border-radius: 0.8rem; font-size: 0.8rem; font-weight: 800; color: #1f1a00; background: linear-gradient(135deg, #ffd84d, #ffcc00 45%, #e0a800); animation: press 1.8s ease-in-out infinite; }
.pulse-amber { animation: ring-amber 1.8s ease-out infinite; }
.verified { animation: pop-in 0.6s cubic-bezier(0.34, 1.56, 0.64, 1), ring-green 1.8s 0.6s ease-out infinite; }
.mock-note { animation: note-drop 0.5s cubic-bezier(0.2, 1.3, 0.35, 1); }
.tap { animation: press 1.4s ease-in-out infinite; }
.sms { animation: rise 0.5s 0.15s cubic-bezier(0.22, 1, 0.36, 1) backwards; }
.swap-enter-active, .swap-leave-active { transition: opacity 0.3s ease, transform 0.3s ease; }
.swap-enter-from { opacity: 0; transform: translateX(14px); }
.swap-leave-to { opacity: 0; transform: translateX(-14px); }

/* Tenants / landlords */
.seg { position: relative; }
.seg-pill { position: absolute; top: 0.25rem; bottom: 0.25rem; left: 0.25rem; width: calc(50% - 0.25rem); border-radius: 0.75rem; background: linear-gradient(140deg, #14b8a6, #0f766e); transition: transform 0.35s cubic-bezier(0.22, 1, 0.36, 1); }
.seg-right { transform: translateX(100%); }
.split-tenant { background: linear-gradient(140deg, #14918a, #0f766e 55%, #0a3b38); --color-white: #fff; }
.split-landlord { background: linear-gradient(140deg, #0369a1, #1d4ed8 55%, #1e1b4b); --color-white: #fff; }
.point { animation: rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards; animation-delay: var(--d); }
.mini { background: rgb(255 255 255 / 0.1); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18); }
.grow-bar { width: 0; animation: grow 1.4s 0.3s cubic-bezier(0.22, 1, 0.36, 1) forwards; }
.col { height: 0; animation: rise-col 0.9s cubic-bezier(0.22, 1, 0.36, 1) forwards; animation-delay: calc(var(--i) * 90ms + 200ms); }

/* Security */
.sec { transition: transform 0.3s ease, box-shadow 0.3s ease; }
.sec:hover { transform: translateY(-4px); box-shadow: 0 22px 44px -24px rgb(30 64 175 / 0.4); }
.sec-ico { background: linear-gradient(140deg, #22d3ee, #0f766e 55%, #1e3a8a); box-shadow: 0 10px 20px -10px rgb(15 118 110 / 0.8); }
.sec:hover .sec-ico { animation: wiggle 0.5s ease; }

/* Steps */
.steps-line { position: absolute; top: 3rem; left: 16%; right: 16%; height: 2px; background: linear-gradient(90deg, #14b8a6, #0ea5e9); transform-origin: left; }
.steps-line.reveal { opacity: 1; transform: scaleX(0); transition: transform 1.2s cubic-bezier(0.22, 1, 0.36, 1); }
.steps-line.reveal.in { transform: scaleX(1); }
.step { z-index: 1; transition: transform 0.25s ease; }
.step:hover { transform: translateY(-4px); }
.step .num { position: absolute; top: 1.2rem; right: 1.4rem; font-size: 3rem; line-height: 1; font-weight: 800; color: var(--color-slate-100); }

/* Install + CTA */
.install { background: linear-gradient(135deg, #0f766e, #0a3b38 60%, #082f2d); --color-white: #fff; position: relative; }
.install::before { content: ''; position: absolute; inset: 0; background: radial-gradient(circle at 90% -10%, rgb(255 255 255 / 0.18), transparent 55%); }
.how { background: rgb(255 255 255 / 0.1); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18); transition: background-color 0.2s ease; }
.how:hover { background: rgb(255 255 255 / 0.16); }
.install-btn { display: inline-flex; align-items: center; gap: 0.6rem; height: 3.25rem; padding: 0 1.5rem; border-radius: 1rem; font-weight: 700; background: #fff; color: #0a3b38; box-shadow: 0 10px 24px -10px rgb(0 0 0 / 0.5); transition: transform 0.15s ease; }
.install-btn:hover { transform: translateY(-2px); }
.install-btn:active { transform: scale(0.98); }
.bounce { animation: dl 1.6s ease-in-out infinite; }
.cta { background: linear-gradient(135deg, #14b8a6, #0f766e 40%, #0369a1 80%, #4f46e5); background-size: 200% 200%; animation: pan 10s ease-in-out infinite alternate; --color-white: #fff; }
.cta-ring { position: absolute; border-radius: 9999px; border: 1.5px solid rgb(255 255 255 / 0.2); animation: spin 30s linear infinite; }
.cta-ring-1 { width: 26rem; height: 26rem; top: -13rem; right: -8rem; }
.cta-ring-2 { width: 18rem; height: 18rem; bottom: -10rem; left: -6rem; animation-direction: reverse; }
.cta-btn, .cta-ghost { display: inline-flex; align-items: center; justify-content: center; height: 3.25rem; padding: 0 1.75rem; border-radius: 1rem; font-weight: 700; transition: transform 0.15s ease; }
.cta-btn { background: #fff; color: #0a3b38; box-shadow: 0 10px 24px -10px rgb(0 0 0 / 0.45); }
.cta-ghost { color: #fff; box-shadow: inset 0 0 0 1.5px rgb(255 255 255 / 0.6); }
.cta-btn:hover, .cta-ghost:hover { transform: translateY(-2px); }

/* FAQ */
.faq { transition: border-color 0.2s ease, box-shadow 0.2s ease; }
.faq-active { box-shadow: 0 14px 30px -24px rgb(15 118 110 / 0.6); }
.faq-body { display: grid; grid-template-rows: 0fr; transition: grid-template-rows 0.3s ease; }
.faq-body > div { overflow: hidden; }
.faq-open { grid-template-rows: 1fr; }

/* Back to top */
.to-top { position: fixed; right: 1rem; bottom: max(1rem, env(safe-area-inset-bottom)); z-index: 40; display: flex; width: 2.9rem; height: 2.9rem; align-items: center; justify-content: center; border-radius: 9999px; color: #fff; background: linear-gradient(140deg, #14b8a6, #0f766e); box-shadow: 0 12px 26px -10px rgb(15 118 110 / 0.8); transition: transform 0.15s ease; }
.to-top:hover { transform: translateY(-2px); }
.pop-enter-active, .pop-leave-active { transition: opacity 0.25s ease, transform 0.25s ease; }
.pop-enter-from, .pop-leave-to { opacity: 0; transform: scale(0.6); }

/* Hero aurora */
.aurora {
  position: absolute; inset: -40% -20% auto; height: 120%; pointer-events: none; opacity: 0.45;
  background: conic-gradient(from 0deg at 50% 50%, #5eead4, #7dd3fc, #c4b5fd, #fbcfe8, #5eead4);
  filter: blur(90px);
  animation: spin 40s linear infinite;
  mask-image: radial-gradient(60% 50% at 50% 40%, #000, transparent 75%);
}

/* Mobile money section: drifting colour */
.blob { position: absolute; border-radius: 9999px; filter: blur(70px); opacity: 0.35; pointer-events: none; }
.blob-a { width: 22rem; height: 22rem; top: -6rem; left: -6rem; background: #5eead4; animation: drift 18s ease-in-out infinite alternate; }
.blob-b { width: 18rem; height: 18rem; bottom: -6rem; right: -4rem; background: #93c5fd; animation: drift 22s ease-in-out infinite alternate-reverse; }
.momo > div { position: relative; }

/* Cards lean toward the pointer, with a soft light under it */
.tilt { transform: perspective(900px) rotateX(var(--rx, 0deg)) rotateY(var(--ry, 0deg)); transition: transform 0.35s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.3s ease, border-color 0.3s ease; }
.feature.tilt:hover { transform: perspective(900px) rotateX(var(--rx, 0deg)) rotateY(var(--ry, 0deg)) translateY(-6px); }
.feature { position: relative; overflow: hidden; }
.feature::before { content: ''; position: absolute; inset: 0; opacity: 0; pointer-events: none; background: radial-gradient(14rem circle at var(--mx, 50%) var(--my, 50%), color-mix(in srgb, var(--color-brand-100) 80%, transparent), transparent 70%); transition: opacity 0.3s ease; }
.feature:hover::before { opacity: 1; }
.feature > * { position: relative; }

/* Phone screens in "How to pay" */
.verified { animation: verified 0.7s cubic-bezier(0.34, 1.56, 0.64, 1) both, ring-green 1.8s 0.7s ease-out infinite; }
.mock-note { animation: note-in 0.6s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
.momo-step { transition: background-color 0.35s ease, box-shadow 0.35s ease, transform 0.35s cubic-bezier(0.16, 1, 0.3, 1); }
.momo-on { transform: translateX(4px); }

/* Scroll reveal */
.reveal { opacity: 0; transform: translateY(30px) scale(0.97); filter: blur(6px); transition: opacity 0.9s cubic-bezier(0.16, 1, 0.3, 1), transform 0.9s cubic-bezier(0.16, 1, 0.3, 1), filter 0.9s cubic-bezier(0.16, 1, 0.3, 1); transition-delay: var(--d, 0ms); will-change: transform, opacity; }
.reveal.in { opacity: 1; transform: none; filter: none; }

@keyframes rise { from { opacity: 0; transform: translateY(16px); } }
@keyframes drift { to { transform: translate(2.5rem, 1.5rem) scale(1.12); } }
@keyframes bob { 50% { transform: translateY(-8px); } }
@keyframes fill { to { width: 78%; } }
@keyframes grow { to { width: var(--w); } }
@keyframes rise-col { to { height: var(--h); } }
@keyframes ping { 70% { box-shadow: 0 0 0 7px rgb(16 185 129 / 0); } 100% { box-shadow: 0 0 0 0 rgb(16 185 129 / 0); } }
@keyframes ring-amber { 0% { box-shadow: 0 0 0 0 rgb(245 158 11 / 0.4); } 100% { box-shadow: 0 0 0 16px rgb(245 158 11 / 0); } }
@keyframes sweep { 0%, 60% { transform: translateX(-120%); } 100% { transform: translateX(120%); } }
@keyframes hue { to { background-position: 100% 0; } }
@keyframes nudge { 50% { transform: translateY(5px); } }
@keyframes scroll-x { to { transform: translateX(-50%); } }
@keyframes blink { 50% { opacity: 0.55; } }
@keyframes press { 0%, 70%, 100% { transform: scale(1); } 80% { transform: scale(0.94); } }
@keyframes wiggle { 25% { transform: rotate(-10deg); } 75% { transform: rotate(10deg); } }
@keyframes dl { 50% { transform: translateY(3px); } }
@keyframes pan { to { background-position: 100% 100%; } }
@keyframes spin { to { transform: rotate(360deg); } }
@keyframes shimmer { 0%, 100% { background-position: 100% 0; } 50% { background-position: 0 0; } }
@keyframes verified { from { transform: scale(0.3); opacity: 0; } }
@keyframes ring-green { 0% { box-shadow: 0 0 0 0 rgb(16 185 129 / 0.4); } 100% { box-shadow: 0 0 0 18px rgb(16 185 129 / 0); } }
@keyframes note-in { from { transform: translateY(-16px) scale(0.95); opacity: 0; } }
@keyframes pop-in { from { transform: scale(0.4); opacity: 0; } }
@keyframes ring-green { 0% { box-shadow: 0 0 0 0 rgb(16 185 129 / 0.4); } 100% { box-shadow: 0 0 0 18px rgb(16 185 129 / 0); } }
@keyframes note-drop { from { transform: translateY(-120%); opacity: 0; } }

@media (max-width: 380px) {
  .chip-a { left: -0.2rem; }
  .chip-b, .chip-c { right: -0.2rem; }
}
@media (prefers-reduced-motion: reduce) {
  .hero-in, .orb, .phone, .float-chip, .live, .shine::after, .grad-move, .scroll-cue, .marquee-track, .mock-copy, .dial, .pulse-amber,
  .tap, .sms, .verified, .mock-note, .point, .bounce, .cta, .cta-ring, .menu-link, .aurora, .blob, .eyebrow { animation: none; }
  .tilt, .feature.tilt:hover { transform: none; }
  .reveal { opacity: 1; transform: none; filter: none; transition: none; }
  .mock-bar { animation: none; width: 78%; }
  .grow-bar { animation: none; width: var(--w); }
  .col { animation: none; height: var(--h); }
  .steps-line.reveal { transform: none; }
  .word-enter-active, .word-leave-active, .faq-body, .toast-enter-active, .toast-leave-active, .swap-enter-active, .swap-leave-active { transition: none; }
}
</style>
