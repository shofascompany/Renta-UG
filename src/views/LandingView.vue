<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  Smartphone, CalendarClock, Building2, Banknote, BellRing, BarChart3, ShieldCheck, Download, ChevronDown, ArrowRight, ArrowUp,
  Users, Home, Check, Menu, X, KeyRound, Wallet, Share, Plus, Phone, MessageSquareText, Lock, EyeOff, CircleCheck, Sparkles,
  LayoutDashboard, MapPin, Mail, MessageCircle,
} from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { SITE } from '@/lib/site'
import Logo from '@/components/Logo.vue'
import AppLink from '@/components/AppLink.vue'
import LQIP from '@/lib/heroPlaceholders'

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

// ── Photos of homes, inside and out (Unsplash licence, saved in /public/landing) ──
// They are pictures of homes in general, not listings on Renta UG.
const HOMES = [
  { file: 'kampala-homes', label: 'Homes in Kampala', kind: 'out', by: 'Yu Gu' },
  { file: 'home-08', label: 'A bright living room', kind: 'in', by: 'Nha Chill' },
  { file: 'home-01', label: 'Apartments in Nairobi', kind: 'out', by: 'Isaac Mugwe' },
  { file: 'home-13', label: 'Kitchen and dining', kind: 'in', by: 'Prydumano Design' },
  { file: 'home-02', label: 'A duplex in Lagos', kind: 'out', by: 'Ferdinand Asakome' },
  { file: 'home-15', label: 'A bedroom', kind: 'in', by: 'Andrea Davis' },
  { file: 'home-03', label: 'Apartments in Kigali', kind: 'out', by: 'Reagan M' },
  { file: 'home-09', label: 'A modern living room', kind: 'in', by: 'Home Makers Interior' },
  { file: 'home-04', label: 'A modern house', kind: 'out', by: 'Aalo Lens' },
  { file: 'home-10', label: 'A sunny sitting room', kind: 'in', by: 'Clay Banks' },
  { file: 'home-05', label: 'Apartments with balconies', kind: 'out', by: 'Denise Jans' },
  { file: 'home-14', label: 'An open-plan apartment', kind: 'in', by: 'Daegyu Bae' },
  { file: 'kampala-skyline', label: 'Kampala', kind: 'out', by: 'Keith Kasaija' },
  { file: 'home-16', label: 'A cosy bedroom', kind: 'in', by: 'Clay Banks' },
  { file: 'home-06', label: 'An apartment block', kind: 'out', by: 'MARCO' },
  { file: 'home-11', label: 'A family sitting room', kind: 'in', by: 'Collov Home Design' },
  { file: 'home-07', label: 'A family house', kind: 'out', by: 'ubeyonroad' },
  { file: 'home-12', label: 'A calm living room', kind: 'in', by: 'Alexey Aladashvili' },
  { file: 'home-17', label: 'A neat bedroom', kind: 'in', by: 'Annie Spratt' },
  { file: 'home-18', label: 'Keys to a new home', kind: 'in', by: 'Jakub Żerdzicki' },
]
// Footer contact details (WhatsApp uses the same number)
const CONTACT = { phone: '0726 128782', phoneIntl: '+256726128782', email: 'shofascompany@gmail.com' }
const photo = (file) => ({ src: `/landing/${file}.webp`, srcset: `/landing/${file}-sm.webp 760w, /landing/${file}.webp 1600w` })

// Hero background slideshow, built to load fast:
//  · a 24-px blurred preview of every photo is inside the page, so the hero shows a picture at once;
//    the sharp photo fades in over it when it arrives (first photo is also preloaded from index.html)
//  · photos are compressed (they sit under a dark wash) and phones get the small 760-px version
//  · only the current, previous and next photos are in the page, and the slideshow moves on only
//    once the next photo has fully downloaded, so it never fades into an empty frame
//  · on Data Saver or a 2G connection it stays on the first photo
const photoIndex = ref(0)
const prevIndex = ref(-1)
const ready = ref({}) // photo index → its <img> has loaded
const near = (n) => n === photoIndex.value || n === prevIndex.value || n === (photoIndex.value + 1) % HOMES.length
const conn = typeof navigator !== 'undefined' ? navigator.connection : null
const slowNet = Boolean(conn?.saveData || /(^|-)2g$/.test(conn?.effectiveType ?? ''))
let photoTimer = null
const warmed = new Set()
function warm(n) {
  if (warmed.has(n)) return Promise.resolve()
  const img = new Image()
  img.sizes = '100vw'
  const { src, srcset } = photo(HOMES[n].file)
  img.srcset = srcset
  img.src = src
  return img.decode().catch(() => {}).then(() => warmed.add(n))
}
let switching = false
async function showPhoto(n) {
  if (switching || n === photoIndex.value) return
  switching = true
  await warm(n)
  prevIndex.value = photoIndex.value
  photoIndex.value = n
  switching = false
  warm((n + 1) % HOMES.length) // fetch the one after in the background
}
function nextPhoto() {
  if (!document.hidden) showPhoto((photoIndex.value + 1) % HOMES.length)
}

// ── "Pay with mobile money" walkthrough (auto-plays, tap a step to jump) ──
const MOMO = [
  { icon: Smartphone, title: 'Choose your SIM', text: 'MTN or Airtel.' },
  { icon: Phone, title: 'Send the money', text: 'Follow the simple steps on your phone.' },
  { icon: CircleCheck, title: 'Your payment is verified', text: 'Your rent updates straight away.' },
  { icon: MessageSquareText, title: 'Get instant confirmation', text: 'A notification tells you the moment your payment is received.' },
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
onMounted(() => {
  document.documentElement.style.scrollBehavior = 'smooth'
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('beforeinstallprompt', onBeforeInstall)
  onScroll()
  if (reduced) return
  wordTimer = setInterval(() => (wordIndex.value = (wordIndex.value + 1) % words.length), 7000) // each word stays 7 s
  if (!slowNet) {
    setTimeout(() => warm(1), 1200) // after the first paint
    photoTimer = setInterval(nextPhoto, 6000)
  }
  pickStep(0)
})
onBeforeUnmount(() => {
  document.documentElement.style.scrollBehavior = ''
  window.removeEventListener('scroll', onScroll)
  window.removeEventListener('beforeinstallprompt', onBeforeInstall)
  clearInterval(wordTimer)
  clearInterval(photoTimer)
  clearInterval(momoTimer)
  io?.disconnect()
})

// ── Content (all true of the app today) ──
const marquee = [
  [Smartphone, 'MTN Mobile Money'], [Smartphone, 'Airtel Money'], [Banknote, 'Cash'], [MessageSquareText, 'Payment notifications'],
  [BellRing, 'Phone notifications'], [Building2, 'Houses & rooms'], [BarChart3, 'Clear records'],
]

const features = [
  { icon: Smartphone, title: 'Pay with MTN or Airtel', text: 'Send rent from your own phone straight to your landlord, with simple steps to follow.', tone: 'teal' },
  { icon: Banknote, title: 'Cash works too', text: 'Pay your landlord in cash. They record it and your rent updates.', tone: 'amber' },
  { icon: CalendarClock, title: 'Always know your time', text: 'See when your rent month started, when it ends and what you owe.', tone: 'sky' },
  { icon: MessageSquareText, title: 'Payment notifications', text: 'Get a notification from Renta UG every time your landlord confirms a payment.', tone: 'rose' },
  { icon: Building2, title: 'Houses and rooms', text: 'Landlords keep every house, room and tenant in one place.', tone: 'violet' },
  { icon: BarChart3, title: 'Clear records', text: 'Every confirmed payment is kept, so landlord and tenant see the same numbers.', tone: 'emerald' },
]

const tenantPoints = [
  [Wallet, 'See what you owe and when your month ends'],
  [Smartphone, 'Pay with MTN, Airtel or cash'],
  [MessageSquareText, 'Get a notification when your payment is confirmed'],
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
  { icon: Wallet, title: 'Pay and stay up to date', text: 'Pay by mobile money or cash and get a notification when it is confirmed.' },
]

const faq = [
  { q: 'Is Renta UG free?', a: 'Creating an account is free. MTN and Airtel may charge their normal fees when you send money.' },
  { q: 'Does Renta UG hold my money?', a: 'No. Your money goes straight to your landlord. Renta only keeps the record.' },
  { q: 'How do I know my payment worked?', a: 'Your landlord confirms it in the app, and you get a notification straight away.' },
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
    <header class="nav fixed inset-x-0 top-0 z-40 transition" :class="scrolled || menu ? 'nav-solid' : 'nav-over'">
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
          <button class="menu-btn flex size-10 items-center justify-center rounded-xl text-slate-700 md:hidden" :aria-label="menu ? 'Close menu' : 'Open menu'" @click="menu = !menu">
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

    <!-- Hero: photos of homes behind a deep teal wash with a soft light beam. Words on the left,
         a "rent journey" glass panel on the right, a glass ribbon of key points along the bottom. -->
    <section class="hero hero-dark relative flex min-h-[100svh] flex-col overflow-hidden pt-24 sm:pt-28 lg:min-h-[46rem]" :style="{ '--gx': `${glow.x}%`, '--gy': `${glow.y}%` }" @pointermove="onPointer">
      <div class="photos" aria-hidden="true">
        <!-- Blurred preview: inside the page, so it shows instantly -->
        <div class="photo-lqip" :style="{ backgroundImage: `url(${LQIP[HOMES[photoIndex].file]})` }" />
        <template v-for="(p, n) in HOMES" :key="p.file">
          <img
            v-if="near(n)"
            v-bind="photo(p.file)"
            sizes="100vw"
            alt=""
            :fetchpriority="n === 0 ? 'high' : 'low'"
            decoding="async"
            class="photo"
            :class="[photoIndex === n && ready[n] && 'photo-on', `drift-${n % 3}`]"
            @load="ready[n] = true"
          />
        </template>
        <div class="hero-shade" />
        <div class="hero-beam" />
        <div class="cine-grain" />
      </div>

      <div class="relative mx-auto grid w-full max-w-6xl flex-1 grid-cols-1 items-center px-4 pb-10 sm:px-6">
        <div class="min-w-0 max-w-3xl">
          <p class="hero-in hx-eyebrow flex items-center gap-3 text-xs font-semibold tracking-[0.22em] uppercase sm:text-[13px]" style="--d: 0ms">
            <span class="hx-eyebrow-line" /> Made for rent in Uganda <span class="live size-1.5 rounded-full bg-teal-300" />
          </p>
          <h1 class="hero-in hx-title mt-5 text-[2.6rem] leading-[1.04] font-extrabold tracking-tight sm:text-6xl lg:text-[4.6rem]" style="--d: 80ms">
            The easy way to
            <span class="word-wrap">
              <Transition name="word" mode="out-in">
                <span :key="wordIndex" class="hx-word block">{{ words[wordIndex] }}</span>
              </Transition>
            </span>
          </h1>
          <p class="hero-in mt-5 text-xs font-semibold tracking-[0.22em] text-teal-200 uppercase sm:text-sm" style="--d: 120ms">
            Convenience · Security · Accuracy
          </p>
          <p class="hero-in hx-lead mt-4 max-w-xl text-base leading-relaxed sm:text-lg" style="--d: 160ms">
            Renta UG brings rent collection and record-keeping together in one secure platform. Tenants pay through MTN Mobile Money, Airtel Money or cash, landlords confirm each payment, and both parties work from the same accurate, up-to-date account.
          </p>
          <div class="hero-in mt-8 flex flex-col items-stretch gap-3 sm:flex-row sm:items-center" style="--d: 240ms">
            <button v-if="signedIn" class="btn-primary hx-primary shine h-13 rounded-full px-7 text-base" @click="goApp">Open my dashboard <ArrowRight class="size-4.5" /></button>
            <template v-else>
              <RouterLink to="/signup" class="btn-primary hx-primary shine h-13 rounded-full px-7 text-base">Create free account <ArrowRight class="arrow size-4.5" /></RouterLink>
              <RouterLink to="/login" class="hx-ghost inline-flex h-13 items-center justify-center gap-2 rounded-full px-7 text-base font-semibold">I already have an account</RouterLink>
            </template>
          </div>
        </div>
      </div>
    </section>

    <!-- Moving strip -->
    <section class="marquee marquee-rule border-y border-slate-200/70 bg-white/60" aria-label="What Renta UG includes">
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
      <div class="photos" aria-hidden="true">
        <img v-bind="photo('kampala-homes')" sizes="100vw" alt="" loading="lazy" decoding="async" class="photo photo-on drift-slow" />
        <div class="photo-wash photo-wash-even" />
      </div>
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
                  <!-- 4 notification -->
                  <div v-else class="space-y-2.5 pt-2">
                    <div class="mock-note flex items-center gap-2 rounded-xl bg-white p-2 shadow-md ring-1 ring-slate-100">
                      <span class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-teal-400 to-teal-800 text-white"><BellRing class="size-3.5" /></span>
                      <div class="min-w-0"><p class="text-[10px] font-semibold text-slate-900">Renta UG · now</p><p class="truncate text-[10px] text-slate-600">Payment received</p></div>
                    </div>
                    <p class="pt-1 text-[10px] font-semibold text-slate-400">Notifications · Renta UG</p>
                    <div class="sms rounded-2xl rounded-tl-sm bg-slate-100 p-3 text-[11px] leading-relaxed text-slate-800">
                      Payment confirmation: your payment of UGX 300,000 has been received. Thank you!
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
    <section id="how" class="relative overflow-hidden py-16 sm:py-24">
      <div class="photos" aria-hidden="true">
        <img v-bind="photo('home-11')" sizes="100vw" alt="" loading="lazy" decoding="async" class="photo photo-on drift-slow" />
        <div class="photo-wash photo-wash-even" />
      </div>
      <div class="relative mx-auto max-w-6xl scroll-mt-20 px-4 sm:px-6">
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
        <div class="photos" aria-hidden="true">
          <img v-bind="photo('home-03')" sizes="(min-width: 1152px) 1152px, 100vw" alt="" loading="lazy" decoding="async" class="photo photo-on drift-slow" />
          <div class="photo-dark" />
        </div>
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
        <div class="photos" aria-hidden="true">
          <img v-bind="photo('kampala-skyline')" sizes="(min-width: 896px) 896px, 100vw" alt="" loading="lazy" decoding="async" class="photo photo-on drift-slow" />
          <div class="photo-dark" />
        </div>
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
      <div class="mx-auto flex max-w-6xl flex-col gap-8 px-4 py-10 text-sm sm:flex-row sm:items-start sm:justify-between sm:px-6">
        <div>
          <Logo />
          <p class="mt-3 max-w-xs leading-relaxed text-slate-500">Rent made simple in Uganda.</p>
        </div>
        <div>
          <p class="font-semibold text-slate-900">Contact us</p>
          <ul class="mt-3 space-y-2.5 text-slate-600">
            <li>
              <a :href="`tel:${CONTACT.phoneIntl}`" class="inline-flex items-center gap-2.5 hover:text-brand-700">
                <span class="flex size-8 items-center justify-center rounded-full bg-brand-50 text-brand-700"><Phone class="size-4" /></span>
                {{ CONTACT.phone }}
              </a>
            </li>
            <li>
              <AppLink :phone="CONTACT.phoneIntl" class="inline-flex items-center gap-2.5 hover:text-brand-700">
                <span class="flex size-8 items-center justify-center rounded-full bg-emerald-50 text-emerald-700"><MessageCircle class="size-4" /></span>
                WhatsApp {{ CONTACT.phone }}
              </AppLink>
            </li>
            <li>
              <a :href="`mailto:${CONTACT.email}`" class="inline-flex items-center gap-2.5 break-all hover:text-brand-700">
                <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-sky-50 text-sky-700"><Mail class="size-4" /></span>
                {{ CONTACT.email }}
              </a>
            </li>
          </ul>
        </div>
      </div>
      <div class="border-t border-slate-100 py-5 text-center text-xs text-slate-400">
        © {{ new Date().getFullYear() }} {{ SITE.name }}
        <span class="mx-1.5">·</span><RouterLink to="/privacy" class="hover:text-slate-700">Privacy</RouterLink>
        <span class="mx-1.5">·</span><RouterLink to="/terms" class="hover:text-slate-700">Terms</RouterLink>
        <span class="mx-1.5">·</span><RouterLink to="/delete-account" class="hover:text-slate-700">Delete account</RouterLink>
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
.nav-solid { background: color-mix(in srgb, var(--color-white) 88%, transparent); backdrop-filter: blur(14px); box-shadow: 0 1px 0 color-mix(in srgb, var(--color-brand-500) 35%, transparent), 0 10px 24px -18px rgb(15 118 110 / 0.35); }
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
/* Photos of Uganda behind sections: cross-fade + a slow drift (Ken Burns), under a wash that keeps text readable */
.photos { position: absolute; inset: 0; overflow: hidden; pointer-events: none; }
.photo {
  position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover;
  opacity: 0; transform: scale(1.06);
  transition: opacity 1.8s ease, transform 9s ease-out;
  will-change: opacity, transform;
}
.photo-on { opacity: 1; transform: scale(1.14); }
.drift-0.photo-on { transform: scale(1.14) translate(-1.5%, 1%); }
.drift-1.photo-on { transform: scale(1.14) translate(1.5%, -1%); }
.drift-2.photo-on { transform: scale(1.14) translate(-1%, -1.5%); }
.drift-slow { transition: none; animation: slow-drift 30s ease-in-out infinite alternate; }
@keyframes slow-drift {
  from { transform: scale(1.05) translate(0, 0); }
  to { transform: scale(1.16) translate(-2%, -1.5%); }
}
/* Light wash: strong where the words are, thinner where the photo shows through */
.photo-wash {
  position: absolute; inset: 0;
  background:
    radial-gradient(28rem circle at var(--gx, 50%) var(--gy, 40%), color-mix(in srgb, var(--color-brand-50) 45%, transparent), transparent 70%),
    linear-gradient(180deg, color-mix(in srgb, var(--color-white) 55%, transparent) 0%, color-mix(in srgb, var(--color-white) 80%, transparent) 70%, var(--color-white) 100%),
    linear-gradient(90deg, color-mix(in srgb, var(--color-white) 88%, transparent) 0%, color-mix(in srgb, var(--color-white) 70%, transparent) 55%, color-mix(in srgb, var(--color-white) 35%, transparent) 100%);
}
@media (max-width: 1023px) {
  .photo-wash {
    background: linear-gradient(180deg, color-mix(in srgb, var(--color-white) 72%, transparent), color-mix(in srgb, var(--color-white) 86%, transparent) 60%, var(--color-white));
  }
}
/* Hero: photos of homes under a deep teal wash (the brand's own dark teal), so white words read clearly.
   Colours are written out (#fff, teal rgb) because dark mode remaps the light tokens. */
.hero-dark { background: #0a3b38; color: #fff; }
.hero-dark ::selection { background: #14b8a6; color: #fff; }
.photo-lqip {
  position: absolute; inset: -2rem; background-size: cover; background-position: center;
  filter: blur(22px) saturate(1.1); transform: scale(1.08);
  transition: background-image 0.6s ease;
}
.hero-shade {
  position: absolute; inset: 0;
  background:
    radial-gradient(30rem circle at var(--gx, 30%) var(--gy, 40%), rgb(45 212 191 / 0.12), transparent 70%),
    linear-gradient(90deg, rgb(4 30 28 / 0.88) 0%, rgb(6 45 42 / 0.7) 45%, rgb(6 45 42 / 0.35) 100%),
    linear-gradient(180deg, rgb(4 30 28 / 0.35) 0%, transparent 30%, transparent 70%, rgb(4 30 28 / 0.75) 100%);
}
@media (max-width: 1023px) {
  .hero-shade {
    background:
      linear-gradient(180deg, rgb(4 30 28 / 0.7) 0%, rgb(6 45 42 / 0.78) 45%, rgb(4 30 28 / 0.92) 100%);
  }
}
.cine-grain {
  position: absolute; inset: 0; opacity: 0.07; mix-blend-mode: overlay;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
}

/* A soft diagonal light beam across the photo, drifting slowly */
.hero-beam {
  position: absolute; inset: -20% -10%;
  background: linear-gradient(115deg, transparent 35%, rgb(94 234 212 / 0.1) 47%, rgb(255 255 255 / 0.06) 50%, transparent 62%);
  animation: beam 14s ease-in-out infinite alternate;
}
@keyframes beam { from { transform: translateX(-8%); } to { transform: translateX(8%); } }

/* Words */
.hx-eyebrow { color: #99f6e4; }
.hx-eyebrow-line { width: 2.5rem; height: 2px; border-radius: 9999px; background: linear-gradient(90deg, transparent, #5eead4); }
.hx-title { color: #fff; text-shadow: 0 2px 24px rgb(0 0 0 / 0.35); }
.hx-title .word-wrap { height: 1.14em; }
.hx-word {
  background: linear-gradient(90deg, #99f6e4, #2dd4bf 45%, #7dd3fc); background-size: 200% 100%;
  -webkit-background-clip: text; background-clip: text; color: transparent;
  animation: hue 6s ease-in-out infinite alternate;
}
.hx-lead { color: rgb(255 255 255 / 0.84); }

/* Buttons: pill shaped */
.hx-primary { color: #042f2e; background: linear-gradient(135deg, #99f6e4, #5eead4 40%, #2dd4bf); box-shadow: 0 0 0 1px rgb(153 246 228 / 0.6), 0 14px 34px -10px rgb(45 212 191 / 0.7); }
.hx-primary:hover { background: linear-gradient(135deg, #ccfbf1, #99f6e4 40%, #5eead4); box-shadow: 0 0 0 1px rgb(204 251 241 / 0.8), 0 18px 42px -10px rgb(45 212 191 / 0.85); }
.hx-ghost { color: #fff; background: rgb(255 255 255 / 0.06); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.35); backdrop-filter: blur(8px); transition: background-color 0.2s ease, box-shadow 0.2s ease; }
.hx-ghost:hover { background: rgb(255 255 255 / 0.14); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.65); }


/* Top bar while it sits over the dark hero */
.nav-over .nav-link { color: rgb(255 255 255 / 0.85); }
.nav-over .nav-link:hover { color: #fff; }
.nav-over .nav-link::after { background: #5eead4; }
.nav-over :deep(.text-slate-900) { color: #fff; }
.nav-over :deep(.text-brand-600) { color: #5eead4; }
.nav-over .btn-secondary { color: #fff; background: rgb(255 255 255 / 0.08); border-color: rgb(255 255 255 / 0.4); box-shadow: none; }
.nav-over .btn-secondary:hover { background: rgb(255 255 255 / 0.16); }
.nav-over .btn-primary { color: #fff; background: linear-gradient(135deg, #2dd4bf, #14b8a6 45%, #0f766e); box-shadow: 0 8px 24px -8px rgb(20 184 166 / 0.8); }
.nav-over .menu-btn { color: #fff; }

/* Moving strip: a thin teal rule under it */
.marquee.marquee-rule { border-bottom-color: color-mix(in srgb, var(--color-brand-500) 40%, transparent); box-shadow: 0 10px 30px -22px rgb(15 118 110 / 0.5); }
.photo-wash-even {
  background: linear-gradient(180deg, var(--color-white), color-mix(in srgb, var(--color-white) 84%, transparent) 18%, color-mix(in srgb, var(--color-white) 84%, transparent) 82%, var(--color-white));
}
/* Dark teal wash for the white-text panels */
.photo-dark { position: absolute; inset: 0; background: linear-gradient(135deg, rgb(10 59 56 / 0.92), rgb(15 118 110 / 0.78) 50%, rgb(3 105 161 / 0.72)); }
.place-chip {
  position: absolute; z-index: 2; right: 1rem; bottom: 1rem;
  display: inline-flex; align-items: center; gap: 0.35rem;
  border-radius: 9999px; padding: 0.35rem 0.75rem;
  font-size: 0.72rem; font-weight: 600; color: var(--color-slate-700);
  background: color-mix(in srgb, var(--color-white) 75%, transparent);
  box-shadow: 0 0 0 1px var(--color-slate-200);
  backdrop-filter: blur(8px);
}
.place-enter-active, .place-leave-active { transition: opacity 0.6s ease, transform 0.6s ease; }
.place-enter-from { opacity: 0; transform: translateY(6px); }
.place-leave-to { opacity: 0; transform: translateY(-6px); }
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
.momo { background: var(--color-white); }
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
.install::before { content: ''; position: absolute; inset: 0; z-index: 1; pointer-events: none; background: radial-gradient(circle at 90% -10%, rgb(255 255 255 / 0.18), transparent 55%); }
.install > .relative { z-index: 2; }
.how { background: rgb(255 255 255 / 0.1); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18); transition: background-color 0.2s ease; }
.how:hover { background: rgb(255 255 255 / 0.16); }
.install-btn { display: inline-flex; align-items: center; gap: 0.6rem; height: 3.25rem; padding: 0 1.5rem; border-radius: 1rem; font-weight: 700; background: #fff; color: #0a3b38; box-shadow: 0 10px 24px -10px rgb(0 0 0 / 0.5); transition: transform 0.15s ease; }
.install-btn:hover { transform: translateY(-2px); }
.install-btn:active { transform: scale(0.98); }
.bounce { animation: dl 1.6s ease-in-out infinite; }
.cta { background: #0a3b38; --color-white: #fff; }
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
.momo > div:not(.photos) { position: relative; }

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

@media (prefers-reduced-motion: reduce) {
  .photo, .drift-slow { transition: none; animation: none; transform: none; }
  .photo-lqip { transition: none; }
  .hx-word, .hero-beam { animation: none; }
  .hero-in, .orb, .phone, .live, .shine::after, .grad-move, .scroll-cue, .marquee-track, .mock-copy, .dial, .pulse-amber,
  .tap, .sms, .verified, .mock-note, .point, .bounce, .cta, .cta-ring, .menu-link, .aurora, .blob, .eyebrow { animation: none; }
  .tilt, .feature.tilt:hover { transform: none; }
  .reveal { opacity: 1; transform: none; filter: none; transition: none; }
  .grow-bar { animation: none; width: var(--w); }
  .col { animation: none; height: var(--h); }
  .steps-line.reveal { transform: none; }
  .word-enter-active, .word-leave-active, .faq-body, .swap-enter-active, .swap-leave-active { transition: none; }
}
</style>
