<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { Check, ChevronDown, Search } from '@lucide/vue'
import { useAnchoredMenu } from '@/composables/useAnchoredMenu'
import { searcher } from '@/lib/search'
import EmptyState from './EmptyState.vue'

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
  wide: Boolean, // the menu is wider than a narrow button (e.g. the country code)
})

const open = ref(false)
const search = ref('')
const root = ref(null)
const panel = ref(null)
const { style, upwards, place } = useAnchoredMenu(open, root, panel, { match: !props.wide })

const selected = computed(() => props.options.find((o) => o.value === model.value))
const groups = computed(() => {
  const hit = searcher(search.value.replace(/^\s*\+/, ''))
  const map = new Map()
  for (const o of props.options) {
    if (!hit(o.label, o.group, o.hint, o.sub)) continue
    const key = o.group ?? ''
    if (!map.has(key)) map.set(key, { key: key || '_', title: key, items: [] })
    map.get(key).items.push(o)
  }
  return [...map.values()]
})
watch(groups, () => open.value && nextTick(place))

function toggle() {
  if (props.disabled || !props.options.length) return
  open.value = !open.value
  search.value = ''
  // Start at the chosen option
  if (open.value) nextTick(() => panel.value?.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' }))
}
function pick(o) {
  model.value = o.value
  open.value = false
  root.value?.querySelector('button')?.focus()
}
</script>

<template>
  <div ref="root" class="relative">
    <button
      :id="id"
      type="button"
      class="input select-btn flex w-full items-center gap-3 pr-3 text-left"
      :class="[icon ? 'pl-3.5' : '', open && 'select-open', (disabled || !options.length) && 'cursor-not-allowed opacity-60']"
      :disabled="disabled || !options.length"
      aria-haspopup="listbox"
      :aria-expanded="open"
      @click="toggle"
    >
      <component :is="icon" v-if="icon" class="size-4.5 shrink-0" :class="selected ? 'text-brand-600' : 'text-slate-400'" />
      <span class="min-w-0 flex-1 truncate" :class="selected ? 'font-medium text-slate-900' : 'text-slate-400'">{{ selected ? selected.short ?? selected.label : options.length ? placeholder : emptyText }}</span>
      <span v-if="selected?.hint && selected.short === undefined" class="shrink-0 text-xs font-medium text-slate-500">{{ selected.hint }}</span>
      <span class="select-chev" :class="open && 'select-chev-open'"><ChevronDown class="size-4" /></span>
    </button>
    <!-- Lets the browser's own "please fill this in" check work -->
    <input v-if="required" :value="model" required tabindex="-1" aria-hidden="true" class="pointer-events-none absolute inset-x-0 bottom-0 h-px opacity-0" @focus="toggle" />

    <Teleport to="body">
      <Transition name="menu-pop">
        <div v-if="open" ref="panel" class="menu-panel menu-from-left" :class="upwards && 'menu-up'" :style="[style, wide && { minWidth: '17rem', maxWidth: 'calc(100vw - 20px)' }]">
          <div v-if="options.length >= searchFrom" class="menu-search">
            <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
            <input v-model="search" type="search" class="input h-10 rounded-xl pl-10 text-sm" placeholder="Search…" autocomplete="off" data-cap="off" aria-label="Search" />
          </div>
          <div class="menu-scroll" role="listbox">
            <EmptyState v-if="!groups.length" compact kind="search" :title="`No match for “${search}”`" />
            <div v-for="g in groups" :key="g.key">
              <p v-if="g.title" class="menu-title">{{ g.title }}</p>
              <button
                v-for="o in g.items"
                :key="o.value"
                type="button"
                role="option"
                :aria-selected="model === o.value"
                class="menu-item"
                :class="model === o.value && 'menu-item-on'"
                @click="pick(o)"
              >
                <span class="min-w-0 flex-1 text-left">
                  <span class="block truncate">{{ o.label }}</span>
                  <span v-if="o.sub" class="menu-sub truncate">{{ o.sub }}</span>
                </span>
                <span v-if="wide && o.hint" class="shrink-0 text-xs font-medium text-slate-500 tabular-nums">{{ o.hint }}</span>
                <span v-if="model === o.value" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
