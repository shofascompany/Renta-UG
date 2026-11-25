<script setup>
import { computed, ref, watch } from 'vue'
import { Phone } from '@lucide/vue'
import { COUNTRIES, composePhone, countryByIso, splitPhone } from '@/lib/phone'
import BaseSelect from './BaseSelect.vue'

// A phone number from any country: pick the country (its code is added for you), type the rest.
// v-model is the full international number, "+256772123456", or '' while nothing is typed.
// An older number such as 0772 123 456 is read as Uganda.
const model = defineModel({ type: String, default: '' })
defineProps({
  id: String,
  required: Boolean,
  placeholder: { type: String, default: '772 123 456' },
})

const start = splitPhone(model.value)
const iso = ref(start.iso)
const typed = ref(start.local)
let last = model.value

// The country list: flag + name, with the code on the right (search by name or code)
const options = COUNTRIES.map((c) => ({ value: c.iso, label: `${c.flag} ${c.name}`, hint: `+${c.dial}`, short: `${c.flag} ${c.iso}` }))
const dial = computed(() => countryByIso(iso.value).dial)

function push() {
  last = composePhone(dial.value, typed.value)
  model.value = last
}
watch([iso, typed], push)

// Changed from outside (e.g. a form opened with a saved number): show it
watch(model, (v) => {
  if (v === last) return
  last = v
  const s = splitPhone(v)
  iso.value = s.iso
  typed.value = s.local
})
</script>

<template>
  <div class="flex gap-2">
    <BaseSelect v-model="iso" :options="options" class="w-[6.75rem] shrink-0" placeholder="Country" :search-from="1" wide />
    <div class="relative min-w-0 flex-1">
      <Phone class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
      <span class="pointer-events-none absolute top-1/2 left-10 -translate-y-1/2 text-sm font-medium text-slate-500 tabular-nums">+{{ dial }}</span>
      <input
        :id="id"
        v-model="typed"
        type="tel"
        inputmode="tel"
        class="input h-12 text-base tabular-nums"
        :style="{ paddingLeft: `${2.9 + dial.length * 0.55}rem` }"
        :placeholder="placeholder"
        :required="required"
        autocomplete="tel-national"
        data-cap="off"
      />
    </div>
  </div>
</template>
