<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Check, ChevronDown, Search } from '@lucide/vue'

// The one dropdown used across the whole site.
//   options: [{ value, label, sub?, hint?, group? }]   sub = second line, hint = shown on the right of the field, group = heading
//   placeholder: shown while nothing is chosen. `required` blocks form submit until something is picked.
const model = defineModel({ default: '' })
const props = defineProps({
  options: { type: Array, default: () => [] },
  placeholder: { type: String, default: 'Choose' },
  id: String,
  icon: [Object, Function],
  disabled: Boolean,
  required: Boolean,
  searchFrom: { type: Number, default: 6 }, // show the search box from this many options
  emptyText: { type: String, default: 'Nothing to choose from' },
})

const open = ref(false)
const search = ref('')
const root = ref(null)

const selected = computed(() => props.options.find((o) => o.value === model.value))
const groups = computed(() => {
  const q = search.value.trim().toLowerCase()
  const map = new Map()
  for (const o of props.options) {
    if (q && !`${o.label} ${o.group ?? ''}`.toLowerCase().includes(q)) continue
    const key = o.group ?? ''
    if (!map.has(key)) map.set(key, { key: key || '_', title: key, items: [] })
    map.get(key).items.push(o)
  }
  return [...map.values()]
})

function toggle() {
  if (props.disabled || !props.options.length) return
  open.value = !open.value
  search.value = ''
}
function pick(o) {
  model.value = o.value
  open.value = false
}
function outside(e) {
  if (open.value && root.value && !root.value.contains(e.target)) open.value = false
}
onMounted(() => document.addEventListener('pointerdown', outside))
onBeforeUnmount(() => document.removeEventListener('pointerdown', outside))
</script>

<template>
  <div ref="root" class="relative">
    <button
      :id="id"
      type="button"
      class="input flex w-full items-center gap-3 pr-3 text-left"
      :class="[icon ? 'pl-3.5' : '', open && 'border-brand-500 ring-2 ring-brand-500/20', (disabled || !options.length) && 'cursor-not-allowed opacity-60']"
      :disabled="disabled || !options.length"
      aria-haspopup="listbox"
      :aria-expanded="open"
      @click="toggle"
      @keydown.esc.stop="open = false"
    >
      <component :is="icon" v-if="icon" class="size-4.5 shrink-0" :class="selected ? 'text-brand-600' : 'text-slate-400'" />
      <span class="min-w-0 flex-1 truncate" :class="!selected && 'text-slate-400'">{{ selected ? selected.label : options.length ? placeholder : emptyText }}</span>
      <span v-if="selected?.hint" class="shrink-0 text-xs font-medium text-slate-500">{{ selected.hint }}</span>
      <ChevronDown class="size-4.5 shrink-0 text-slate-400 transition-transform" :class="open && 'rotate-180'" />
    </button>
    <!-- Lets the browser's own "please fill this in" check work -->
    <input v-if="required" :value="model" required tabindex="-1" aria-hidden="true" class="pointer-events-none absolute inset-x-0 bottom-0 h-px opacity-0" @focus="toggle" />

    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="-translate-y-1 opacity-0"
      leave-active-class="transition duration-100 ease-in"
      leave-to-class="-translate-y-1 opacity-0"
    >
      <div v-if="open" class="absolute inset-x-0 top-full z-30 mt-2 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xl shadow-slate-900/10">
        <div v-if="options.length >= searchFrom" class="relative border-b border-slate-100 p-2">
          <Search class="pointer-events-none absolute top-1/2 left-5 size-4 -translate-y-1/2 text-slate-400" />
          <input v-model="search" type="search" class="input h-10 pl-9 text-sm" placeholder="Search…" autocomplete="off" />
        </div>
        <div class="max-h-56 overflow-y-auto p-1.5" role="listbox">
          <p v-if="!groups.length" class="px-3 py-4 text-center text-sm text-slate-500">No match for “{{ search }}”.</p>
          <div v-for="g in groups" :key="g.key">
            <p v-if="g.title" class="px-3 pt-2 pb-1 text-[0.68rem] font-semibold tracking-wide text-slate-400 uppercase">{{ g.title }}</p>
            <button
              v-for="o in g.items"
              :key="o.value"
              type="button"
              role="option"
              :aria-selected="model === o.value"
              class="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition"
              :class="model === o.value ? 'bg-brand-50' : 'hover:bg-slate-50'"
              @click="pick(o)"
            >
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium text-slate-900">{{ o.label }}</span>
                <span v-if="o.sub" class="block truncate text-xs text-slate-500">{{ o.sub }}</span>
              </span>
              <Check v-if="model === o.value" class="size-4.5 shrink-0 text-brand-600" />
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>
