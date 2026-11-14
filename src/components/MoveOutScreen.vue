<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Hourglass, Star, CheckCircle2, Heart, LogOut, X, ShieldCheck, Bell, History } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useSignOut } from '@/composables/useSignOut'
import { formatDate } from '@/utils/format'

// Full-screen tenant screens for a move-out request, over a blurred app:
//   waiting  → "Waiting for approval", thanks, what happens next, cancel
//   approved → farewell, then the app signs the tenant out
const props = defineProps({
  request: { type: Object, required: true },
  mode: { type: String, default: 'waiting' }, // waiting | approved
  house: { type: String, default: '' },
})
const emit = defineEmits(['done'])
const rental = useRentalStore()
const signOut = useSignOut()

const cancelling = ref(false)
const error = ref('')
async function cancel() {
  cancelling.value = true
  error.value = ''
  try {
    await rental.cancelMoveOut()
  } catch (e) {
    error.value = e.message
  } finally {
    cancelling.value = false
  }
}

// Approved: sign out automatically after a short goodbye
const seconds = ref(12)
let timer = null
async function leave() {
  clearInterval(timer)
  emit('done')
  await rental.finishMoveOut() // the account becomes free: next sign-in is a fresh start
  await signOut()
}
onMounted(() => {
  if (props.mode !== 'approved') return
  timer = setInterval(() => {
    seconds.value -= 1
    if (seconds.value <= 0) leave()
  }, 1000)
})
onBeforeUnmount(() => clearInterval(timer))

const stars = computed(() => props.request.rating ?? 0)
</script>

<template>
  <div class="screen fixed inset-0 z-[60] flex items-center justify-center overflow-y-auto px-4 py-8" role="dialog" aria-modal="true">
    <div class="card relative w-full max-w-md overflow-hidden rounded-[2rem] bg-white text-center shadow-2xl">
      <!-- Waiting -->
      <template v-if="mode === 'waiting'">
        <div class="top relative px-6 pt-9 pb-7 text-white">
          <span class="pulse mx-auto flex size-20 items-center justify-center rounded-full bg-white/15 ring-1 ring-white/30">
            <Hourglass class="spin size-9" />
          </span>
          <h1 class="mt-5 text-2xl font-bold tracking-tight">Waiting for approval</h1>
          <p class="mt-1.5 text-sm leading-relaxed text-white/85">Your request to leave{{ house ? ` ${house}` : '' }} has been sent to your landlord.</p>
        </div>

        <div class="space-y-5 px-6 py-6 text-left">
          <div class="flex items-start gap-3 rounded-2xl bg-brand-50 p-4">
            <Heart class="mt-0.5 size-5 shrink-0 text-brand-600" />
            <p class="text-sm leading-relaxed text-slate-700"><strong class="text-slate-900">Thank you for staying with us.</strong> We hope you enjoyed your home, and we wish you all the best wherever you go next.</p>
          </div>

          <div class="rounded-2xl border border-slate-200 p-4">
            <p class="text-xs font-semibold tracking-wider text-slate-400 uppercase">Your request</p>
            <div class="mt-2 flex items-center gap-1">
              <Star v-for="n in 5" :key="n" class="size-4.5" :class="n <= stars ? 'fill-amber-400 text-amber-400' : 'text-slate-200'" stroke-width="1.5" />
            </div>
            <p class="mt-2 text-sm font-medium text-slate-900">{{ request.reason }}</p>
            <p v-if="request.review" class="mt-1 line-clamp-3 text-sm text-slate-500">“{{ request.review }}”</p>
            <p class="mt-2 text-xs text-slate-400">Sent {{ formatDate(request.createdAt) }}</p>
          </div>

          <ol class="space-y-3 text-sm text-slate-600">
            <li class="flex gap-3"><ShieldCheck class="size-5 shrink-0 text-brand-600" /> Your landlord reviews your request.</li>
            <li class="flex gap-3"><Bell class="size-5 shrink-0 text-brand-600" /> You'll see the answer here as soon as it's made.</li>
            <li class="flex gap-3"><History class="size-5 shrink-0 text-brand-600" /> All your payments and receipts are kept safely.</li>
          </ol>

          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="grid grid-cols-2 gap-2.5">
            <button type="button" class="btn-secondary h-12 rounded-2xl" :data-busy="cancelling" :disabled="cancelling" @click="cancel">
              <X class="size-4" /> {{ cancelling ? 'Cancelling…' : 'Cancel request' }}
            </button>
            <button type="button" class="btn-secondary h-12 rounded-2xl" @click="signOut"><LogOut class="size-4" /> Sign out</button>
          </div>
        </div>
      </template>

      <!-- Approved -->
      <template v-else>
        <div class="top relative px-6 pt-9 pb-7 text-white">
          <span class="mx-auto flex size-20 items-center justify-center rounded-full bg-white/15 ring-1 ring-white/30"><CheckCircle2 class="size-10" /></span>
          <h1 class="mt-5 text-2xl font-bold tracking-tight">You've moved out</h1>
          <p class="mt-1.5 text-sm leading-relaxed text-white/85">Your request to leave{{ house ? ` ${house}` : '' }} was approved.</p>
        </div>
        <div class="space-y-5 px-6 py-6">
          <p class="text-sm leading-relaxed text-slate-600">
            Thank you for being part of Renta. When you sign out, your account becomes free: sign in again any time and connect to a new landlord with their code.
          </p>
          <button type="button" class="btn-primary h-12 w-full rounded-2xl" @click="leave"><LogOut class="size-4" /> Sign out now</button>
          <p class="text-xs text-slate-400">Signing you out in {{ seconds }} s…</p>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* The app behind stays visible but blurred */
.screen {
  background: rgb(15 23 42 / 0.35);
  backdrop-filter: blur(14px) saturate(1.1);
  -webkit-backdrop-filter: blur(14px) saturate(1.1);
  animation: fade 0.35s ease;
}
.card { animation: up 0.45s cubic-bezier(0.22, 1, 0.36, 1); }
.top {
  --color-white: #fff;
  background: linear-gradient(140deg, #2dd4bf 0%, #0f766e 50%, #0a3b38 100%);
}
.pulse { animation: pulse 2.4s ease-in-out infinite; }
.spin { animation: tip 3s ease-in-out infinite; }
@keyframes fade { from { opacity: 0; } }
@keyframes up { from { opacity: 0; transform: translateY(24px) scale(0.97); } }
@keyframes pulse {
  0%, 100% { box-shadow: 0 0 0 0 rgb(255 255 255 / 0.35); }
  50% { box-shadow: 0 0 0 14px rgb(255 255 255 / 0); }
}
@keyframes tip {
  0%, 40% { transform: rotate(0deg); }
  50%, 90% { transform: rotate(180deg); }
  100% { transform: rotate(360deg); }
}
@media (prefers-reduced-motion: reduce) {
  .screen, .card, .pulse, .spin { animation: none; }
}
</style>
