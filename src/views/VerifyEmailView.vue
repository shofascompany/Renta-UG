<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { MailCheck, CheckCircle2, RotateCw, ArrowLeft, Timer } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { clearVerification, loadVerification, saveVerification } from '@/lib/verification'
import Logo from '@/components/Logo.vue'

const auth = useAuthStore()
const router = useRouter()

const LENGTH = 6
const waiting = ref(loadVerification())
const chars = ref(Array(LENGTH).fill(''))
const boxes = ref([])
const error = ref('')
const busy = ref(false)
const done = ref(false)
const info = ref('')
const now = ref(Date.now())
let tick = null

const code = computed(() => chars.value.join(''))
const secondsLeft = computed(() => Math.max(0, Math.ceil(((waiting.value?.expiresAt ?? 0) - now.value) / 1000)))
const expired = computed(() => secondsLeft.value <= 0)
const clock = computed(() => `${Math.floor(secondsLeft.value / 60)}:${String(secondsLeft.value % 60).padStart(2, '0')}`)
const resendIn = computed(() => Math.max(0, Math.ceil(((waiting.value?.resendAt ?? 0) - now.value) / 1000)))

onMounted(() => {
  if (!waiting.value) return router.replace({ name: 'signup' })
  tick = setInterval(() => (now.value = Date.now()), 500)
  nextTick(() => boxes.value[0]?.focus())
})
onBeforeUnmount(() => clearInterval(tick))

const clean = (v) => String(v).toUpperCase().replace(/[^A-Z0-9]/g, '')

function focusBox(i) {
  boxes.value[Math.max(0, Math.min(LENGTH - 1, i))]?.focus()
}

// Type or paste: letters and numbers only, shown in capitals; fills the boxes and moves on
function onInput(i, e) {
  error.value = ''
  const typed = clean(e.target.value)
  if (!typed) {
    chars.value[i] = ''
    e.target.value = ''
    return
  }
  for (let k = 0; k < typed.length && i + k < LENGTH; k++) chars.value[i + k] = typed[k]
  for (let k = 0; k < LENGTH; k++) if (boxes.value[k]) boxes.value[k].value = chars.value[k]
  focusBox(Math.min(LENGTH - 1, i + typed.length))
  if (code.value.length === LENGTH) submit()
}
function onKey(i, e) {
  if (e.key === 'Backspace' && !chars.value[i]) {
    focusBox(i - 1)
    chars.value[i - 1] = ''
    if (boxes.value[i - 1]) boxes.value[i - 1].value = ''
  } else if (e.key === 'ArrowLeft') focusBox(i - 1)
  else if (e.key === 'ArrowRight') focusBox(i + 1)
}
function onPaste(e) {
  const text = clean(e.clipboardData?.getData('text') ?? '')
  if (!text) return
  e.preventDefault()
  chars.value = Array.from({ length: LENGTH }, (_, k) => text[k] ?? '')
  boxes.value.forEach((b, k) => b && (b.value = chars.value[k]))
  focusBox(Math.min(LENGTH - 1, text.length))
  if (code.value.length === LENGTH) submit()
}

function reset() {
  chars.value = Array(LENGTH).fill('')
  boxes.value.forEach((b) => b && (b.value = ''))
  focusBox(0)
}

// Right code → the account is created, they are signed in and taken to their own dashboard
async function submit() {
  if (busy.value || done.value || code.value.length !== LENGTH) return
  if (expired.value) {
    error.value = 'This code has expired. Ask for a new one below.'
    return
  }
  busy.value = true
  error.value = ''
  try {
    await auth.verifySignUp(waiting.value.email, code.value)
    done.value = true
    clearVerification()
    setTimeout(() => router.replace(auth.home), 1400)
  } catch (e) {
    error.value = e.message
    reset()
  } finally {
    busy.value = false
  }
}

async function resend() {
  if (resendIn.value > 0 || busy.value) return
  busy.value = true
  error.value = ''
  info.value = ''
  try {
    const res = await auth.resendSignUpCode(waiting.value.email)
    waiting.value = { ...waiting.value, expiresAt: Date.now() + res.expiresInMinutes * 60_000, resendAt: Date.now() + res.resendAfterSeconds * 1000 }
    saveVerification(waiting.value)
    now.value = Date.now()
    info.value = 'A new code is on its way. The old one no longer works.'
    reset()
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

function startAgain() {
  clearVerification()
  router.replace({ name: 'signup' })
}
</script>

<template>
  <div class="auth-bg flex min-h-dvh items-center justify-center px-4 py-10">
    <div class="w-full max-w-sm">
      <div class="mb-8 flex justify-center"><Logo /></div>

      <div class="card-in overflow-hidden rounded-3xl border border-slate-200/80 bg-white shadow-xl shadow-slate-900/5">
        <!-- Verified -->
        <div v-if="done" class="px-6 py-12 text-center">
          <div class="done-ring mx-auto flex size-20 items-center justify-center rounded-full bg-emerald-50 text-emerald-600">
            <CheckCircle2 class="size-11" />
          </div>
          <h1 class="mt-5 text-2xl font-semibold tracking-tight text-slate-900">You are verified</h1>
          <p class="mt-2 text-sm text-slate-500">Welcome to Renta UG. Taking you to your dashboard…</p>
          <div class="mx-auto mt-6 h-1 w-32 overflow-hidden rounded-full bg-slate-100"><div class="go h-full rounded-full bg-brand-500" /></div>
        </div>

        <template v-else-if="waiting">
          <div class="head relative px-6 pt-8 pb-7 text-center text-white">
            <div class="mx-auto flex size-14 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25"><MailCheck class="size-7" /></div>
            <h1 class="mt-4 text-2xl font-semibold tracking-tight">Check your email</h1>
            <p class="mt-1.5 text-sm text-white/80">We sent a 6-character code to</p>
            <p class="mt-0.5 truncate text-sm font-semibold">{{ waiting.email }}</p>
          </div>

          <div class="px-5 pt-6 pb-6 sm:px-6">
            <p class="mb-3 text-center text-xs font-semibold tracking-wide text-slate-500 uppercase">Enter your code</p>
            <div class="flex justify-center gap-2" @paste="onPaste">
              <input
                v-for="(_, i) in LENGTH"
                :key="i"
                :ref="(el) => (boxes[i] = el)"
                type="text"
                maxlength="6"
                autocapitalize="characters"
                :autocomplete="i === 0 ? 'one-time-code' : 'off'"
                spellcheck="false"
                :aria-label="`Code character ${i + 1}`"
                class="code-box"
                :class="{ filled: chars[i], bad: error }"
                :disabled="busy || expired"
                data-cap="off"
                @input="onInput(i, $event)"
                @keydown="onKey(i, $event)"
                @focus="$event.target.select()"
              />
            </div>

            <p class="mt-4 flex items-center justify-center gap-1.5 text-sm" :class="expired ? 'text-red-600' : secondsLeft < 120 ? 'text-amber-600' : 'text-slate-500'">
              <Timer class="size-4" />
              <template v-if="expired">This code has expired</template>
              <template v-else>Code works for <strong class="tabular-nums">{{ clock }}</strong></template>
            </p>

            <p v-if="error" class="mt-4 rounded-xl bg-red-50 p-3 text-center text-sm text-red-700" role="alert">{{ error }}</p>
            <p v-else-if="info" class="mt-4 rounded-xl bg-emerald-50 p-3 text-center text-sm text-emerald-700">{{ info }}</p>

            <button :data-busy="Boolean(busy)" type="button" class="btn-primary mt-5 h-12 w-full rounded-2xl" :disabled="busy || expired || code.length !== LENGTH" @click="submit">
              {{ busy ? 'Checking…' : 'Verify and continue' }}
            </button>
            <p class="mt-3 text-center text-xs leading-relaxed text-slate-500">
              By creating your account you agree to the
              <RouterLink to="/terms" target="_blank" class="font-medium text-brand-700">Terms</RouterLink> and
              <RouterLink to="/privacy" target="_blank" class="font-medium text-brand-700">Privacy policy</RouterLink>.
            </p>

            <div class="mt-4 flex items-center justify-between gap-3 text-sm">
              <button type="button" class="inline-flex items-center gap-1.5 font-medium text-brand-700 disabled:text-slate-400" :disabled="resendIn > 0 || busy" @click="resend">
                <RotateCw class="size-4" /> {{ resendIn > 0 ? `Send again in ${resendIn}s` : 'Send a new code' }}
              </button>
              <button type="button" class="inline-flex items-center gap-1.5 text-slate-500 hover:text-slate-700" @click="startAgain">
                <ArrowLeft class="size-4" /> Wrong email?
              </button>
            </div>
            <p class="mt-5 text-center text-xs text-slate-400">Can't see it? Look in your spam or promotions folder.</p>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.auth-bg {
  background:
    radial-gradient(60% 40% at 90% 0%, var(--color-brand-50), transparent 70%),
    radial-gradient(50% 35% at 0% 100%, var(--color-sky-50), transparent 70%),
    var(--color-white);
}
.head {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 50%, #0a3b38 100%);
}
.head::after {
  content: '';
  position: absolute;
  inset: 0;
  background: radial-gradient(circle at 85% -10%, rgb(255 255 255 / 0.22), transparent 55%);
  pointer-events: none;
}
.code-box {
  width: 2.6rem;
  height: 3.3rem;
  min-width: 0;
  flex: 1 1 0;
  max-width: 2.9rem;
  border-radius: 0.875rem;
  border: 1.5px solid var(--color-slate-200);
  background: var(--color-slate-50);
  text-align: center;
  font-size: 1.4rem;
  font-weight: 700;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  text-transform: uppercase;
  color: var(--color-slate-900);
  transition: border-color 0.15s ease, box-shadow 0.15s ease, transform 0.15s ease, background-color 0.15s ease;
}
.code-box:focus {
  outline: none;
  border-color: var(--color-brand-500);
  background: var(--color-white);
  box-shadow: 0 0 0 4px var(--color-brand-100);
  transform: translateY(-2px);
}
.code-box.filled { border-color: var(--color-brand-400); background: var(--color-brand-50); }
.code-box.bad { border-color: #f87171; animation: shake 0.35s ease; }
.code-box:disabled { opacity: 0.6; }

.card-in { animation: card-in 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards; }
.done-ring { animation: pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1); box-shadow: 0 0 0 10px rgb(16 185 129 / 0.08); }
.go { animation: go 1.4s linear forwards; }
@keyframes card-in { from { opacity: 0; transform: translateY(12px); } }
@keyframes pop { from { transform: scale(0.5); opacity: 0; } }
@keyframes go { from { width: 0; } to { width: 100%; } }
@keyframes shake { 20%, 60% { transform: translateX(-4px); } 40%, 80% { transform: translateX(4px); } }
@media (prefers-reduced-motion: reduce) {
  .card-in, .done-ring, .go, .code-box.bad { animation: none; }
  .go { width: 100%; }
}
</style>
