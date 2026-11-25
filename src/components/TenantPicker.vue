<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { ChevronDown, Search, Check, UserCog, Smartphone } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { searcher } from '@/lib/search'
import { useAnchoredMenu } from '@/composables/useAnchoredMenu'
import { formatUGX } from '@/utils/format'
import PayStatus from './PayStatus.vue'
import EmptyState from '@/components/EmptyState.vue'

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
const panel = ref(null)
const { style, upwards, place } = useAnchoredMenu(open, root, panel, { match: true })

const initials = (name) => (name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()
const selected = computed(() => props.tenants.find((t) => t.id === model.value) ?? null)
const shown = computed(() => {
  const hit = searcher(query.value)
  return props.tenants.filter((t) => hit(t.name, rental.placeName(t.propertyId), t.phone))
})

function pick(t) {
  model.value = t.id
  open.value = false
}
watch(open, async (v) => {
  if (!v) return
  query.value = ''
  await nextTick()
  if (props.tenants.length > 6) searchBox.value?.focus()
})
watch(shown, () => open.value && nextTick(place))
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
      <span class="select-chev" :class="open && 'select-chev-open'"><ChevronDown class="size-4" /></span>
    </button>

    <Teleport to="body">
    <Transition name="menu-pop">
      <div v-if="open" ref="panel" class="menu-panel menu-from-left" :class="upwards && 'menu-up'" :style="style">
        <div v-if="tenants.length > 6" class="menu-search">
          <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
          <input ref="searchBox" v-model="query" class="input h-10 rounded-xl pl-10 text-sm" placeholder="Search name, house or phone" data-cap="off" aria-label="Search" />
        </div>
        <ul class="menu-scroll" role="listbox">
          <li v-for="t in shown" :key="t.id">
            <button
              type="button"
              role="option"
              :aria-selected="t.id === model"
              class="menu-item text-left"
              :class="t.id === model && 'menu-item-on'"
              @click="pick(t)"
            >
              <span class="avatar">{{ initials(t.name) }}</span>
              <span class="min-w-0 flex-1">
                <span class="flex items-center gap-1.5 truncate font-medium text-slate-900">
                  {{ t.name }}
                  <UserCog v-if="t.managedByLandlord" class="size-3.5 shrink-0 text-slate-400" aria-label="No smartphone" />
                  <Smartphone v-else-if="t.usesApp" class="size-3.5 shrink-0 text-emerald-500" aria-label="Uses the app" />
                </span>
                <span class="block truncate text-xs text-slate-500">{{ rental.placeName(t.propertyId) }}</span>
              </span>
              <span class="shrink-0 text-right text-xs">
                <PayStatus :tenant-id="t.id" />
                <span v-if="rental.payStateFor(t.id)?.owed" class="mt-0.5 block font-semibold text-slate-600 tabular-nums">{{ formatUGX(rental.payStateFor(t.id).owed) }}</span>
              </span>
              <span v-if="t.id === model" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
            </button>
          </li>
          <li v-if="!shown.length"><EmptyState compact :kind="tenants.length ? 'search' : 'people'" :title="tenants.length ? 'Nobody matches' : empty" /></li>
        </ul>
      </div>
    </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.picker { min-height: 3.6rem; box-shadow: 0 1px 2px rgb(15 23 42 / 0.04); }
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
