<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { CircleCheckBig, Star, X } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import BaseModal from './BaseModal.vue'

// "Rate Renta UG": stars only, shown after 7 days of use and filled in once (the database decides and remembers,
// on every phone of the account). "Not now" asks again a week later. Only the main admin sees the ratings.
// allowed = a normal page is on screen (not paying, setting up, connecting…)
const props = defineProps({ allowed: Boolean })

const open = ref(false)
const stars = ref(0)
const hover = ref(0)
const busy = ref(false)
const sent = ref(false)
const error = ref('')
const shown = computed(() => hover.value || stars.value)

let due = false
let checkedAt = 0
let timer = null
async function check() {
  if (!props.allowed || open.value || due || Date.now() - checkedAt < 6 * 3_600_000) return
  checkedAt = Date.now()
  try {
    const { data } = await supabase.rpc('rating_state')
    due = data === 'ask'
  } catch {
    /* offline: the next visit asks */
  }
}
// Shows when nothing else is open, so it never covers a form or a payment
async function tick() {
  await check()
  if (due && props.allowed && document.visibilityState === 'visible' && !document.querySelector('[role=dialog]')) {
    due = false
    stars.value = 0
    open.value = true
  }
}
onMounted(() => (timer = setInterval(tick, 5000)))
onBeforeUnmount(() => {
  clearInterval(timer)
  clearTimeout(closing)
})

async function send() {
  if (!stars.value || busy.value) return
  busy.value = true
  error.value = ''
  try {
    const { error: e } = await supabase.rpc('submit_rating', { p_stars: stars.value })
    if (e) throw e
    sent.value = true
    closing = setTimeout(() => (open.value = false), 2200)
  } catch (e) {
    error.value = /fetch|network/i.test(e.message) ? 'No internet connection. Try again.' : e.message
  } finally {
    busy.value = false
  }
}
let closing = null
// Closed without stars → asked again later
watch(open, async (v) => {
  if (v || sent.value) return
  try {
    await supabase.rpc('rating_later')
  } catch {
    /* offline */
  }
})
</script>

<template>
  <BaseModal v-model="open" center bare width="max-w-sm" title="Rate Renta UG">
    <div v-if="sent" class="py-6 text-center" role="status">
      <CircleCheckBig class="mx-auto size-12 text-emerald-600" />
      <p class="mt-3 text-lg font-bold text-slate-900">Thank you</p>
    </div>
    <div v-else class="relative pt-3 text-center">
      <button type="button" class="absolute -top-1 -right-1 flex size-9 items-center justify-center rounded-full bg-slate-100 text-slate-600 hover:bg-slate-200" aria-label="Close" @click="open = false"><X class="size-4.5" /></button>
      <span class="rate-ico mx-auto flex size-14 items-center justify-center rounded-2xl"><Star class="size-7" fill="currentColor" /></span>
      <h2 class="mt-4 text-xl font-bold text-slate-900">Rate Renta UG</h2>
      <p class="mt-1 text-sm text-slate-500">Tap the stars.</p>

      <div class="mt-5 flex justify-center gap-1" role="radiogroup" aria-label="Stars" @mouseleave="hover = 0">
        <button
          v-for="n in 5"
          :key="n"
          type="button"
          role="radio"
          :aria-checked="stars === n"
          :aria-label="`${n} star${n === 1 ? '' : 's'}`"
          class="rounded-xl p-1 transition-transform active:scale-90"
          @mouseenter="hover = n"
          @click="stars = n"
        >
          <Star class="size-10 transition-colors" :class="n <= shown ? 'fill-amber-400 text-amber-400' : 'text-slate-300'" stroke-width="1.5" />
        </button>
      </div>

      <p v-if="error" class="form-error mt-4" role="alert">{{ error }}</p>
      <button type="button" class="btn-primary mt-6 h-12 w-full" :data-busy="busy" :disabled="!stars || busy" @click="send">Send</button>
      <button type="button" class="mt-1 h-11 w-full text-sm font-medium text-slate-500 hover:text-slate-700" @click="open = false">Not now</button>
    </div>
  </BaseModal>
</template>

<style scoped>
.rate-ico { color: #fff; background: linear-gradient(140deg, #fbbf24, #d97706); box-shadow: 0 12px 26px -12px rgb(217 119 6 / 0.8); }
</style>
