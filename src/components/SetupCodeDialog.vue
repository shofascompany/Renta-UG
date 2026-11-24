<script setup>
import { ref } from 'vue'
import { KeyRound, Copy, Check, ShieldCheck } from '@lucide/vue'
import BaseModal from './BaseModal.vue'

// Shows a one-time setup code once, right after an account was created or reset.
// The person needs it for their first sign-in (with their email or phone number).
const props = defineProps({
  code: { type: String, default: '' },
  name: { type: String, default: '' }, // who it is for
  signInWith: { type: String, default: '' }, // their email or phone number
  sentNote: { type: String, default: '' }, // e.g. "We also emailed it to them."
})
const open = defineModel({ type: Boolean, default: false })
const copied = ref(false)

async function copy() {
  try {
    await navigator.clipboard.writeText(props.code)
    copied.value = true
    setTimeout(() => (copied.value = false), 2000)
  } catch {
    /* clipboard blocked: the code is on screen */
  }
}
</script>

<template>
  <BaseModal v-model="open" center width="max-w-sm" title="Setup code">
    <div class="text-center">
      <span class="mx-auto flex size-12 items-center justify-center rounded-2xl bg-brand-50 text-brand-700"><KeyRound class="size-6" /></span>
      <p class="mt-3 text-sm text-slate-600">
        Give this code to <strong class="text-slate-900">{{ name || 'them' }}</strong>. They need it for their first sign-in<template v-if="signInWith"> with <strong class="text-slate-900">{{ signInWith }}</strong></template>.
      </p>
      <p class="code mt-4 select-all rounded-2xl py-3 font-mono text-3xl font-bold tracking-[0.35em] text-brand-700">{{ code }}</p>
      <button type="button" class="btn-secondary mt-3 h-10 w-full rounded-xl text-sm" @click="copy">
        <component :is="copied ? Check : Copy" class="size-4" /> {{ copied ? 'Copied' : 'Copy code' }}
      </button>
      <p v-if="sentNote" class="mt-3 text-xs text-emerald-700">{{ sentNote }}</p>
      <p class="mt-3 flex items-start gap-2 rounded-xl bg-slate-50 p-3 text-left text-xs leading-relaxed text-slate-600">
        <ShieldCheck class="mt-0.5 size-4 shrink-0 text-brand-600" />
        It works once, for 7 days, and is shown only now. If it's lost, reset their access to get a new one.
      </p>
      <button type="button" class="btn-primary mt-4 h-11 w-full rounded-xl" @click="open = false">Done</button>
    </div>
  </BaseModal>
</template>

<style scoped>
.code { background: var(--color-brand-50); box-shadow: inset 0 0 0 1px var(--color-brand-100); }
</style>
