<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { Check, Copy, LockKeyhole, MessageCircle, Smartphone } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { copyText } from '@/lib/clipboard'
import { prettyPhone } from '@/lib/phone'
import AppLink from './AppLink.vue'

// Landlord: "Send on WhatsApp" + "Copy the link" for a tenant who has been given app access. Both buttons are
// always there. Each link is one-time and carries nothing about the tenant: their number is written in the message.
// A link is made ahead, so one tap opens WhatsApp, where the landlord picks who to send it to; the next send then
// gets a fresh one.
// Once the tenant has registered (recorded in the database) both buttons go, and the app icon takes their place.
const props = defineProps({ tenantId: { type: String, required: true } })
const rental = useRentalStore()

const t = computed(() => rental.tenantById(props.tenantId))
const invite = ref(null)
const busy = ref(false)
const error = ref('')
const done = ref(false) // they have registered: no link needed
const copied = ref(false)
const waLink = ref(null)
let making = null
let nextTimer = null

function make() {
  const id = props.tenantId
  making ??= (async () => {
    busy.value = true
    error.value = ''
    try {
      const res = await rental.createInvite(id)
      if (id === props.tenantId && !registered.value) invite.value = res
    } catch (e) {
      if (id !== props.tenantId) return
      invite.value = null
      done.value = /already set up/i.test(e.message)
      if (done.value) rental.reload('tenants').catch(() => {}) // the server has just recorded it
      else error.value = `The link could not be made. ${e.message}`
    } finally {
      busy.value = false
      making = null
    }
  })()
  return making
}
// Registered: the database says so (managed_by_landlord is off), or the server just did
const registered = computed(() => done.value || Boolean(t.value?.usesApp && t.value.email))
// Off in the database but no email on record: an account from an older version. Ask the server before showing buttons.
const showButtons = computed(() => Boolean(t.value?.userId) && !registered.value && (!t.value.usesApp || Boolean(invite.value)))

watch(() => [props.tenantId, t.value?.userId, t.value?.phone, t.value?.usesApp], () => {
  clearTimeout(nextTimer)
  invite.value = null
  error.value = ''
  done.value = false
  if (t.value?.userId && !registered.value) make()
}, { immediate: true })

const fresh = () => invite.value && invite.value.expiresAt > Date.now() + 60_000
// The link wasn't ready yet: make it, then carry on with the same tap
async function send() {
  if (!fresh()) await make()
  await nextTick()
  waLink.value?.$el?.click()
}
async function copy() {
  if (!fresh()) await make()
  if (!invite.value || !(await copyText(invite.value.url))) return
  copied.value = true
  setTimeout(() => (copied.value = false), 2000)
  next()
}
// This link has gone out: have another ready for the next time (after WhatsApp has taken this one)
function next() {
  clearTimeout(nextTimer)
  nextTimer = setTimeout(() => !registered.value && make(), 2500)
}
onBeforeUnmount(() => clearTimeout(nextTimer))

const until = computed(() =>
  invite.value ? new Date(invite.value.expiresAt).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '',
)
// The whole message: a welcome, what Renta UG is for, the link, and the number to log in with
const text = computed(() =>
  [
    'Welcome',
    '',
    'Get started with Renta UG to ease your rental experience.',
    '',
    'Click on the link and explore Renta UG:',
    invite.value?.url ?? '',
    '',
    `Phone number to log in with: ${prettyPhone(t.value?.phone)}`,
  ].join('\n'),
)
</script>

<template>
  <div v-if="showButtons">
    <div class="grid gap-2.5 sm:grid-cols-2">
      <AppLink v-if="invite" ref="waLink" :text="text" @click="next" class="btn h-12 bg-[#25D366] text-white hover:bg-[#1fb957]"><MessageCircle class="size-5" /> Send on WhatsApp</AppLink>
      <button v-else type="button" class="btn h-12 bg-[#25D366] text-white hover:bg-[#1fb957]" :data-busy="busy" @click="send"><MessageCircle class="size-5" /> Send on WhatsApp</button>
      <button type="button" class="btn-secondary h-12" @click="copy"><Check v-if="copied" class="size-4.5 text-emerald-600" /><Copy v-else class="size-4.5" /> {{ copied ? 'Link copied' : 'Copy the link' }}</button>
    </div>
    <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>
    <p v-else-if="invite" class="mt-2.5 flex items-start gap-1.5 text-xs leading-relaxed text-slate-500">
      <LockKeyhole class="mt-0.5 size-3.5 shrink-0" />
      <span>One-time link: it works on the first phone that opens it, until {{ until }}. Every send gets a fresh one. Their number is in the message, not in the link.</span>
    </p>
  </div>
  <p v-else-if="t?.userId" class="flex items-center gap-3 rounded-2xl bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-800">
    <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-emerald-600"><Smartphone class="size-5 text-[#fff]" /></span>
    Uses the Renta app
  </p>
</template>
