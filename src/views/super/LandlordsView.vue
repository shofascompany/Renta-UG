<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Plus, Search, CheckCircle2, Briefcase, Building2, Users, Wallet, ShieldOff } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatUGX } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import BaseModal from '@/components/BaseModal.vue'

const rental = useRentalStore()
const route = useRoute()
const router = useRouter()
const { rows } = useLandlordStats()
const query = ref('')
const show = ref(route.query.show === 'suspended' ? 'suspended' : 'all') // all | active | suspended
const flash = ref('')

const list = computed(() => {
  const q = query.value.trim().toLowerCase()
  return rows.value
    .filter((l) => (show.value === 'all' ? true : show.value === 'active' ? l.active : !l.active))
    .filter((l) => !q || `${l.name} ${l.email} ${l.phone ?? ''}`.toLowerCase().includes(q))
})
const totals = computed(() => ({
  active: rows.value.filter((l) => l.active).length,
  properties: rows.value.reduce((s, l) => s + l.properties, 0),
  tenants: rows.value.reduce((s, l) => s + l.tenants, 0),
  collected: rows.value.reduce((s, l) => s + l.collected, 0),
}))
const initials = (n) => (n ?? '?').split(' ').map((x) => x[0]).slice(0, 2).join('').toUpperCase()

function showFlash(msg) {
  flash.value = msg
  setTimeout(() => (flash.value = ''), 5000)
}

// ── Register ──
const open = ref(false)
const form = reactive({ name: '', email: '', phone: '' })
const busy = ref(false)
const error = ref('')
function openNew() {
  Object.assign(form, { name: '', email: '', phone: '' })
  error.value = ''
  open.value = true
}
onMounted(() => {
  if (route.query.new) {
    openNew()
    router.replace({ query: {} })
  }
})
async function save() {
  busy.value = true
  error.value = ''
  try {
    await rental.createLandlord({ name: form.name, email: form.email.trim(), phone: form.phone })
    rental.adminNote('landlord.create', 'landlord', null, `Registered landlord ${form.name} (${form.email.trim()})`)
    showFlash(`${form.name} is registered. They sign in with ${form.email.trim()} and create their own password.`)
    open.value = false
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div>
    <SuperHero eyebrow="People" title="Landlords" :subtitle="`${rental.landlords.length} registered · ${totals.active} active`">
      <button class="btn-primary" @click="openNew"><Plus class="size-4" /> Register landlord</button>
      <template #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Active" :value="totals.active" :hint="`${rental.landlords.length - totals.active} suspended`" :icon="Briefcase" />
          <StatTile glass label="Properties" :value="totals.properties" hint="Across all landlords" :icon="Building2" tile="tile-sky" />
          <StatTile glass label="Tenants" :value="totals.tenants" hint="Renting now" :icon="Users" tile="tile-violet" />
          <StatTile glass label="This month" :value="formatUGX(totals.collected)" hint="Collected" :icon="Wallet" tile="tile-amber" />
        </div>
      </template>
    </SuperHero>

    <p v-if="flash" class="sheet mb-5 flex items-center gap-2.5 border-emerald-200 p-4 text-sm text-slate-700">
      <CheckCircle2 class="size-5 shrink-0 text-emerald-600" /> {{ flash }}
    </p>

    <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
      <div class="relative flex-1 sm:max-w-sm">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search name, email or phone" />
      </div>
      <div class="grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm sm:w-80">
        <button v-for="f in [['all', 'All'], ['active', 'Active'], ['suspended', 'Suspended']]" :key="f[0]" type="button" class="h-9 rounded-xl font-medium transition" :class="show === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="show = f[0]">{{ f[1] }}</button>
      </div>
    </div>

    <div class="sheet">
      <ul v-if="list.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="l in list"
          :key="l.id"
          :to="`/admin2026/landlords/${l.id}`"
          :title="l.name || l.email"
          :subtitle="`${l.properties} propert${l.properties === 1 ? 'y' : 'ies'} · ${l.tenants} tenant${l.tenants === 1 ? '' : 's'} · ${l.email}`"
          :value="formatUGX(l.collected)"
          :value-sub="l.active ? 'this month' : 'suspended'"
          :value-class="l.active ? 'text-slate-900' : 'text-slate-400'"
        >
          <template #icon>
            <span class="avatar relative flex size-11 shrink-0 items-center justify-center rounded-2xl text-sm font-bold text-white" :class="!l.active && 'grayscale'">
              {{ initials(l.name) }}
              <ShieldOff v-if="!l.active" class="absolute -right-1 -bottom-1 size-4.5 rounded-full bg-white p-0.5 text-red-600" />
            </span>
          </template>
        </ListRow>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">
        {{ rental.landlords.length ? 'No landlords match.' : 'No landlords yet. Tap "Register landlord" to add one.' }}
      </p>
    </div>

    <BaseModal v-model="open" title="Register landlord">
      <form class="space-y-4" @submit.prevent="save">
        <div>
          <label class="label" for="lname">Full name</label>
          <input id="lname" v-model="form.name" class="input" data-cap="words" autocomplete="off" required />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="label" for="lemail">Email (login)</label>
            <input id="lemail" v-model="form.email" type="email" class="input" placeholder="name@gmail.com" data-cap="off" required />
          </div>
          <div>
            <label class="label" for="lphone">Phone</label>
            <input id="lphone" v-model="form.phone" type="tel" class="input" placeholder="0772 123456" />
          </div>
        </div>
        <p class="rounded-xl bg-slate-50 p-3 text-xs text-slate-600">They sign in with this email (or phone). The first time, they create their own password.</p>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <div class="flex justify-end gap-2 pt-1">
          <button type="button" class="btn-secondary" @click="open = false">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Registering…' : 'Register' }}</button>
        </div>
      </form>
    </BaseModal>
  </div>
</template>

<style scoped>
.avatar {
  --color-white: #fff;
  background: linear-gradient(140deg, #2dd4bf, #0f766e 55%, #0a3b38);
  box-shadow: 0 6px 14px -8px rgb(15 118 110 / 0.8);
}
</style>
