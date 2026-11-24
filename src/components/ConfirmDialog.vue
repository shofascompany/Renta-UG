<script setup>
import { computed, markRaw, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { CircleHelp, TriangleAlert } from '@lucide/vue'
import { answerConfirm, confirmState } from '@/composables/useConfirm'
import BaseModal from './BaseModal.vue'

// The one "are you sure?" card for the whole app (see composables/useConfirm.js).
const route = useRoute()
const busy = ref(false)
const error = ref('')
const o = computed(() => confirmState.opts)
const danger = computed(() => o.value.tone === 'danger')
const icon = computed(() => markRaw(o.value.icon ?? (danger.value ? TriangleAlert : CircleHelp)))

watch(() => confirmState.open, (v) => v && ((busy.value = false), (error.value = '')))
watch(() => route.path, () => confirmState.open && !busy.value && answerConfirm(false)) // the page it was about is gone

async function yes() {
  if (busy.value) return
  if (!o.value.action) return answerConfirm(true)
  busy.value = true
  error.value = ''
  try {
    await o.value.action()
    answerConfirm(true)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <BaseModal :model-value="confirmState.open" top center bare width="max-w-sm" :title="o.title" @update:model-value="!$event && !busy && answerConfirm(false)">
    <div class="pt-2 text-center">
      <span class="cf-ring mx-auto" :class="danger ? 'cf-danger' : 'cf-brand'"><span class="cf-ico"><component :is="icon" class="size-6" /></span></span>
      <h2 class="mt-4 text-lg font-semibold text-balance text-slate-900">{{ o.title }}</h2>
      <p v-if="o.text" class="mx-auto mt-1.5 max-w-xs text-sm leading-relaxed text-slate-600">{{ o.text }}</p>
      <p v-if="o.note" class="mt-4 rounded-2xl bg-slate-50 px-4 py-3 text-left text-sm leading-relaxed text-slate-700">{{ o.note }}</p>
      <p v-if="error" class="form-error mt-4 text-left" role="alert">{{ error }}</p>
      <div class="mt-6 grid grid-cols-2 gap-2">
        <button type="button" class="btn-secondary h-12 rounded-2xl" :disabled="busy" @click="answerConfirm(false)">{{ o.cancel }}</button>
        <button type="button" class="btn h-12 rounded-2xl font-semibold text-white" :class="danger ? 'bg-red-600 hover:bg-red-700' : 'btn-primary'" :data-busy="busy" :disabled="busy" @click="yes">
          {{ busy ? (o.working ?? 'Please wait…') : o.confirm }}
        </button>
      </div>
    </div>
  </BaseModal>
</template>

<style scoped>
.cf-ring { display: flex; width: 4.5rem; height: 4.5rem; align-items: center; justify-content: center; border-radius: 9999px; animation: cf-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1); }
.cf-ico { display: flex; width: 3.1rem; height: 3.1rem; align-items: center; justify-content: center; border-radius: 9999px; color: #fff; }
.cf-danger { background: var(--color-red-50); }
.cf-danger .cf-ico { background: linear-gradient(140deg, #f87171, #dc2626 60%, #991b1b); box-shadow: 0 10px 20px -10px rgb(220 38 38 / 0.8); }
.cf-brand { background: var(--color-brand-50); }
.cf-brand .cf-ico { background: linear-gradient(140deg, #2dd4bf, #0f766e 60%, #0a3b38); box-shadow: 0 10px 20px -10px rgb(15 118 110 / 0.8); }
@keyframes cf-pop { from { transform: scale(0.6); opacity: 0; } }
@media (prefers-reduced-motion: reduce) { .cf-ring { animation: none; } }
</style>
