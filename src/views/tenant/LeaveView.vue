<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Star, Send, DoorOpen, MapPinned, Wallet, Maximize2, Wrench, Heart, Briefcase, HelpCircle } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'

// Tenant: ask to leave the room. Rate the place, review it, say why — then wait for approval.
const { rental, property } = useTenant()
const router = useRouter()

const rating = ref(0)
const hover = ref(0)
const review = ref('')
const reason = ref('')
const details = ref('')
const busy = ref(false)
const error = ref('')

const REASONS = [
  ['Moving to another area', MapPinned],
  ['Found a cheaper place', Wallet],
  ['Need a bigger or smaller place', Maximize2],
  ['Problems with the house', Wrench],
  ['Work or school', Briefcase],
  ['Personal or family reasons', Heart],
  ['Something else', HelpCircle],
]
const words = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent']
const shown = computed(() => hover.value || rating.value)
const ready = computed(() => rating.value > 0 && reason.value && (reason.value !== 'Something else' || details.value.trim()))

async function send() {
  error.value = ''
  if (!rating.value) return (error.value = 'Rate the place first.')
  if (!reason.value) return (error.value = 'Choose why you are leaving.')
  if (reason.value === 'Something else' && !details.value.trim()) return (error.value = 'Tell us a little more about why you are leaving.')
  busy.value = true
  try {
    await rental.requestMoveOut({ rating: rating.value, review: review.value, reason: reason.value, details: details.value })
    router.replace('/tenant') // the waiting screen takes over from here
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-xl pb-4">
    <RouterLink to="/tenant/home" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> My home
    </RouterLink>

    <header class="leave-hero rise rounded-3xl px-6 py-7 text-white">
      <span class="flex size-12 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25"><DoorOpen class="size-6" /></span>
      <h1 class="mt-4 text-2xl font-bold tracking-tight">Request to leave</h1>
      <p class="mt-1 text-sm leading-relaxed text-white/80">
        {{ property ? `Leaving ${property.name}? ` : '' }}Before you go, tell us how your stay was. Your landlord will review your request.
      </p>
    </header>

    <form class="mt-6 space-y-6" @submit.prevent="send">
      <!-- Rating -->
      <section class="sheet rise p-5" style="--d: 60ms">
        <h2 class="text-base font-semibold text-slate-900">How was your stay?</h2>
        <div class="mt-4 flex items-center gap-1.5" role="radiogroup" aria-label="Rating" @mouseleave="hover = 0">
          <button
            v-for="n in 5"
            :key="n"
            type="button"
            role="radio"
            :aria-checked="rating === n"
            :aria-label="`${n} star${n === 1 ? '' : 's'}`"
            class="star rounded-xl p-1 transition-transform active:scale-90"
            @mouseenter="hover = n"
            @click="rating = n"
          >
            <Star class="size-9 transition-colors" :class="n <= shown ? 'fill-amber-400 text-amber-400' : 'text-slate-300'" stroke-width="1.5" />
          </button>
          <span class="ml-2 text-sm font-semibold text-amber-700">{{ words[shown] }}</span>
        </div>
        <label class="label mt-5" for="lv-review">Your review <span class="font-normal text-slate-400">(optional)</span></label>
        <textarea id="lv-review" v-model="review" rows="3" maxlength="600" class="input" placeholder="What did you like? What could be better?" />
      </section>

      <!-- Reason -->
      <section class="sheet rise p-5" style="--d: 120ms">
        <h2 class="text-base font-semibold text-slate-900">Why are you leaving?</h2>
        <div class="mt-4 grid gap-2 sm:grid-cols-2">
          <button
            v-for="r in REASONS"
            :key="r[0]"
            type="button"
            class="flex items-center gap-3 rounded-2xl border px-3.5 py-3 text-left text-sm font-medium transition"
            :class="reason === r[0] ? 'border-brand-500 bg-brand-50 text-brand-800 ring-1 ring-brand-500' : 'border-slate-200 text-slate-700 hover:border-slate-300'"
            :aria-pressed="reason === r[0]"
            @click="reason = r[0]"
          >
            <component :is="r[1]" class="size-[1.1rem] shrink-0" :class="reason === r[0] ? 'text-brand-600' : 'text-slate-400'" />
            {{ r[0] }}
          </button>
        </div>
        <label class="label mt-5" for="lv-details">More details <span v-if="reason !== 'Something else'" class="font-normal text-slate-400">(optional)</span></label>
        <textarea id="lv-details" v-model="details" rows="3" maxlength="600" class="input" placeholder="e.g. I'm moving out at the end of the month" />
      </section>

      <p v-if="error" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>

      <button type="submit" class="btn-primary h-13 w-full rounded-2xl text-[15px]" :data-busy="busy" :disabled="busy || !ready">
        <Send class="size-5" /> {{ busy ? 'Sending request…' : 'Send request' }}
      </button>
      <p class="text-center text-xs text-slate-500">You can cancel your request any time before it's approved.</p>
    </form>
  </div>
</template>

<style scoped>
.leave-hero {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
  box-shadow: 0 20px 45px -24px rgb(10 59 56 / 0.6);
}
.h-13 { height: 3.25rem; }
</style>
