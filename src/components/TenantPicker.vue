<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { ChevronDown, Search, Check, UserCog, Smartphone } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'

// A well-designed dropdown to choose one tenant: avatar, house, what they owe. Searchable.
//   <TenantPicker v-model="tenantId" :tenants="list" />
const model = defineModel({ type: String, default: '' })
const props = defineProps({
  tenants: { type: Array, required: true }, // tenant objects from the store
  placeholder: { type: String, default: 'Choose a tenant' },
  empty: { type: String, default: 'No tenants to show.' },
})
const rental = useRentalStore()

const open = ref(false)
const query = ref('')
const root = ref(null)
const searchBox = ref(null)

const owes = (t) => rental.duesForTenant(t.id).reduce((s, p) => s + p.balance, 0)
const initials = (name) => (name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()
const selected = computed(() => props.tenants.find((t) => t.id === model.value) ?? null)
const shown = computed(() => {
  const q = query.value.trim().toLowerCase()
  return props.tenants.filter((t) => !q || `${t.name} ${rental.placeName(t.propertyId)} ${t.phone ?? ''}`.toLowerCase().includes(q))
})

function pick(t) {
  model.value = t.id
  open.value = false
}
function outside(e) {
  if (root.value && !root.value.contains(e.target)) open.value = false
}
watch(open, async (v) => {
  if (v) {
    query.value = ''
    document.addEventListener('pointerdown', outside, true)
    await nextTick()
    if (props.tenants.length > 6) searchBox.value?.focus()
  } else document.removeEventListener('pointerdown', outside, true)
})
onBeforeUnmount(() => document.removeEventListener('pointerdown', outside, true))
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="picker flex w-full items-center gap-3 rounded-2xl bg-white px-3 py-2.5 text-left ring-1 ring-slate-200 transition"
      :class="open ? 'ring-2 ring-brand-500' : 'hover:ring-slate-300'"
      :aria-expanded="open"
      aria-haspopup="listbox"
      @click="open = !open"
    >
      <template v-if="selected">
        <span class="avatar">{{ initials(selected.name) }}</span>
        <span class="min-w-0 flex-1">
          <span class="block truncate font-semibold text-slate-900">{{ selected.name }}</span>
          <span class="block truncate text-xs text-slate-500">{{ rental.placeName(selected.propertyId) }}</span>
        </span>
      </template>
      <span v-else class="flex min-h-10 flex-1 items-center text-slate-400">{{ tenants.length ? placeholder : empty }}</span>
      <ChevronDown class="size-5 shrink-0 text-slate-400 transition" :class="open && 'rotate-180'" />
    </button>

    <Transition enter-active-class="transition duration-150 ease-out" enter-from-class="opacity-0 -translate-y-1 scale-[0.98]" leave-active-class="transition duration-100" leave-to-class="opacity-0">
      <div v-if="open" class="panel absolute inset-x-0 top-full z-50 mt-2 overflow-hidden rounded-2xl border border-slate-200 bg-white" role="listbox">
        <div v-if="tenants.length > 6" class="border-b border-slate-100 p-2">
          <div class="relative">
            <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
            <input ref="searchBox" v-model="query" class="input h-10 rounded-xl pl-9 text-sm" placeholder="Search name, house or phone" data-cap="off" />
          </div>
        </div>
        <ul class="max-h-72 overflow-y-auto overscroll-contain p-1.5">
          <li v-for="t in shown" :key="t.id">
            <button
              type="button"
              role="option"
              :aria-selected="t.id === model"
              class="flex w-full items-center gap-3 rounded-xl px-2.5 py-2.5 text-left transition-colors hover:bg-slate-50"
              :class="t.id === model && 'bg-brand-50 hover:bg-brand-50'"
              @click="pick(t)"
            >
              <span class="avatar">{{ initials(t.name) }}</span>
              <span class="min-w-0 flex-1">
                <span class="flex items-center gap-1.5 truncate font-medium text-slate-900">
                  {{ t.name }}
                  <UserCog v-if="t.managedByLandlord && !t.userId" class="size-3.5 shrink-0 text-slate-400" aria-label="No smartphone" />
                  <Smartphone v-else-if="t.userId" class="size-3.5 shrink-0 text-emerald-500" aria-label="Uses the app" />
                </span>
                <span class="block truncate text-xs text-slate-500">{{ rental.placeName(t.propertyId) }}</span>
              </span>
              <span class="shrink-0 text-right text-xs">
                <span v-if="owes(t)" class="font-semibold text-amber-700 tabular-nums">owes {{ formatUGX(owes(t)) }}</span>
                <span v-else class="font-medium text-emerald-700">paid up</span>
              </span>
              <Check v-if="t.id === model" class="size-4 shrink-0 text-brand-600" />
            </button>
          </li>
          <li v-if="!shown.length" class="px-3 py-6 text-center text-sm text-slate-500">{{ tenants.length ? 'Nobody matches.' : empty }}</li>
        </ul>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.picker { min-height: 3.6rem; box-shadow: 0 1px 2px rgb(15 23 42 / 0.04); }
.panel { box-shadow: 0 22px 48px -18px rgb(15 23 42 / 0.4); }
.avatar {
  display: flex;
  width: 2.5rem;
  height: 2.5rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.85rem;
  font-size: 0.8rem;
  font-weight: 700;
  color: #fff;
  background: linear-gradient(140deg, #14b8a6, #0f766e 60%, #0a3b38);
}
</style>
