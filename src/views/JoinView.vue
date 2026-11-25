<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { Download, CheckCircle2, Loader2, ExternalLink, ShieldCheck, Check } from '@lucide/vue'
import {
  allowOtherAccount, canInstallNow, clearAppOnly, confirmedInstalled, insideApp, isAndroid, onInstallEvent, openInAppUrl,
  promptInstall, rememberedInstalled, setAppOnly, waitForInstallable,
} from '@/lib/installApp'
import Logo from '@/components/Logo.vue'
import LogoMark from '@/components/LogoMark.vue'
import AuthBackground from '@/components/AuthBackground.vue'

// Signing in on Android needs the app for tenants who came from their landlord's link:
//   • Android browser → install, with a live status bar, then "Open in app" → sign in there.
//   • Android browser that cannot install apps, the app itself, and every other device → straight to sign-in.
const router = useRouter()

const state = ref('checking') // checking | install | installing | ready
const note = ref('')

const appLink = openInAppUrl('/login')

const continueToSignIn = () => router.replace({ name: 'login' })

function otherAccount() {
  allowOtherAccount()
  router.push({ name: 'login' })
}

async function decide() {
  if (!isAndroid() || insideApp()) {
    clearAppOnly()
    return continueToSignIn()
  }
  if ((await confirmedInstalled()) === true) return showReady()
  if (canInstallNow() || (await waitForInstallable())) {
    setAppOnly()
    state.value = 'install'
    return
  }
  if (rememberedInstalled()) return showReady()
  // This Android browser cannot install the app: the website is allowed
  clearAppOnly()
  continueToSignIn()
}

function showReady() {
  clearInterval(stepTimer)
  clearInterval(readyTimer)
  setAppOnly()
  progress.value = 100
  state.value = 'ready'
}

// ── Live status bar ──
// Real moments: confirmed → downloading → the browser says it was added → the phone confirms it is ready.
// Browsers don't report bytes, so between those moments the bar only creeps forward and never fills by itself.
const STEPS = ['Waiting for you to tap Install', 'Downloading Renta UG', 'Adding it to your phone']
const step = ref(0)
const progress = ref(0)
const slow = ref(false)
let stepTimer = null
let readyTimer = null
let stopEvents = () => {}
let gone = false

function creepTo(limit) {
  clearInterval(stepTimer)
  stepTimer = setInterval(() => (progress.value += Math.max(0, limit - progress.value) * 0.04), 200)
}

async function install() {
  note.value = ''
  slow.value = false
  step.value = 0
  progress.value = 4
  state.value = 'installing'
  let outcome = 'unavailable'
  try {
    outcome = await promptInstall()
  } catch {
    /* the browser refused to show its question */
  }
  if (gone || state.value === 'ready') return
  if (outcome !== 'accepted') {
    // The browser gives its question once; it offers a fresh one shortly after a "no"
    const again = await waitForInstallable(4000)
    if (gone) return
    state.value = 'install'
    note.value = again ? 'Tap Install to continue. Your account opens in the app.' : 'Reload this page, then tap Install again.'
    return
  }
  if (step.value < 1) step.value = 1
  creepTo(step.value > 1 ? 96 : 80)
  checkUntilReady()
}

// Asks the phone every 1.5 s whether the app is really there
let added = false
function checkUntilReady() {
  clearInterval(readyTimer)
  const started = Date.now()
  let addedAt = 0
  readyTimer = setInterval(async () => {
    const answer = await confirmedInstalled()
    if (gone || state.value !== 'installing') return
    if (answer === true) return showReady()
    if (added && !addedAt) addedAt = Date.now()
    // The browser said it was added, but can't (or doesn't) confirm it: allow a short moment to finish
    if (addedAt && Date.now() - addedAt > (answer === null ? 4000 : 20_000)) return showReady()
    if (Date.now() - started > 60_000) slow.value = true
  }, 1500)
}

onMounted(() => {
  stopEvents = onInstallEvent((what) => {
    if (what === 'installed') {
      added = true
      if (state.value !== 'installing') state.value = 'installing' // installed from the browser's own menu
      step.value = 2
      progress.value = Math.max(progress.value, 82)
      creepTo(96)
      checkUntilReady()
    } else if (what === 'available') {
      note.value = ''
      // It can be installed, so it isn't on the phone any more
      if (state.value === 'ready') state.value = 'install'
    }
  })
  decide()
})
onBeforeUnmount(() => {
  gone = true
  stopEvents()
  clearInterval(stepTimer)
  clearInterval(readyTimer)
})
</script>

<template>
  <div class="relative flex min-h-screen items-center justify-center px-4 py-12">
    <AuthBackground />
    <div class="relative z-10 w-full max-w-sm text-center">
      <div class="mb-8 flex justify-center"><Logo :link="false" /></div>

      <div v-if="state === 'checking'">
        <Loader2 class="mx-auto size-8 animate-spin text-brand-600" />
        <h1 class="mt-4 text-xl font-semibold text-slate-900">Getting your account ready…</h1>
      </div>

      <!-- Android: install → live status → open -->
      <div v-else class="rounded-3xl border border-slate-200/80 bg-white p-5 text-left shadow-xl shadow-slate-900/5">
        <div class="flex items-center gap-3.5">
          <LogoMark class="size-14 shrink-0" />
          <div class="min-w-0">
            <p class="text-lg font-semibold text-slate-900">Renta UG</p>
            <p class="text-sm text-slate-500">
              {{ state === 'ready' ? 'Installed on your phone' : state === 'installing' ? 'Installing' : 'Sign in with the app' }}
            </p>
          </div>
          <CheckCircle2 v-if="state === 'ready'" class="ml-auto size-7 shrink-0 text-emerald-600" />
        </div>

        <template v-if="state === 'install'">
          <p class="mt-4 text-sm leading-relaxed text-slate-600">To sign in, install the Renta app. It is free, small and takes a few seconds. Then sign in with the number in your landlord's message.</p>
          <button type="button" class="btn-primary mt-4 h-12 w-full text-base" @click="install"><Download class="size-5" /> Install the app</button>
          <p v-if="note" class="mt-3 text-center text-sm text-amber-700">{{ note }}</p>
        </template>

        <div v-else-if="state === 'installing'" class="mt-4" role="status" aria-live="polite">
          <div class="join-bar"><span :style="{ width: `${progress}%` }" /></div>
          <ul class="mt-4 space-y-2.5 text-sm">
            <li v-for="(label, i) in STEPS" :key="label" class="flex items-center gap-2.5" :class="i > step ? 'text-slate-400' : 'font-medium text-slate-900'">
              <span class="flex size-5 items-center justify-center rounded-full" :class="i < step ? 'bg-emerald-600 text-white' : i === step ? 'text-brand-600' : 'bg-slate-100'">
                <Check v-if="i < step" class="size-3" stroke-width="3" /><Loader2 v-else-if="i === step" class="size-4.5 animate-spin" />
              </span>
              {{ label }}
            </li>
          </ul>
          <p v-if="slow" class="mt-3 text-xs text-slate-500">Still working. On a slow connection this can take a minute or two; keep this page open.</p>
        </div>

        <template v-else>
          <div class="join-bar join-done mt-4"><span style="width: 100%" /></div>
          <a :href="appLink" class="btn-primary mt-4 h-12 w-full text-base"><ExternalLink class="size-5" /> Open in app</a>
          <p class="mt-3 text-center text-xs leading-relaxed text-slate-500">
            If the app doesn't open, tap <strong class="text-slate-700">Renta UG</strong> on your home screen. Then sign in with the number in your landlord's message.
          </p>
          <button v-if="canInstallNow()" type="button" class="btn-secondary mt-3 h-11 w-full" @click="install"><Download class="size-4" /> Install it again</button>
        </template>
      </div>

      <p v-if="['install', 'installing', 'ready'].includes(state)" class="mt-4 flex items-center justify-center gap-1.5 text-xs text-slate-500"><ShieldCheck class="size-3.5" /> Renta never asks for your PIN or password by message</p>
      <button v-if="['install', 'ready'].includes(state)" type="button" class="mt-3 text-xs font-medium text-slate-500 underline" @click="otherAccount">Landlord? Sign in to a different account</button>
    </div>
  </div>
</template>

<style scoped>
.join-bar { position: relative; height: 0.6rem; overflow: hidden; border-radius: 9999px; background: var(--color-slate-100); }
.join-bar span { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, #14b8a6, #0f766e); transition: width 0.25s linear; }
.join-bar:not(.join-done) span::after {
  content: ''; position: absolute; inset: 0; width: 35%;
  background: linear-gradient(90deg, transparent, rgb(255 255 255 / 0.55), transparent);
  animation: join-sweep 1.3s linear infinite;
}
.join-done span { background: #059669; }
@keyframes join-sweep { from { transform: translateX(-100%); } to { transform: translateX(320%); } }
@media (prefers-reduced-motion: reduce) { .join-bar span::after { animation: none; } }
</style>
