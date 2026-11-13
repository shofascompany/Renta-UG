<script setup>
import { computed, reactive, ref } from 'vue'
import { Plus, Search, CheckCircle2 } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatDate } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import BaseModal from '@/components/BaseModal.vue'

const rental = useRentalStore()
const { rows } = useLandlordStats()
const query = ref('')
const flash = ref('')

const list = computed(() => {
  const q = query.value.trim().toLowerCase()
  return rows.value.filter((l) => !q || `${l.name} ${l.email} ${l.phone ?? ''}`.toLowerCase().includes(q))
})

function showFlash(msg) {
  flash.value = msg
  setTimeout(() => (flash.value = ''), 4000)
}

// ── Register / edit ──
const editing = ref(null) // null = closed, {} = new, landlord = edit
const form = reactive({ name: '', email: '', phone: '', resetPassword: false })
const busy = ref(false)
const error = ref('')
const isNew = computed(() => editing.value && !editing.value.id)

function openNew() {
  Object.assign(form, { name: '', email: '', phone: '', resetPassword: false })
  error.value = ''
  editing.value = {}
}

function openEdit(l) {
  Object.assign(form, { name: l.name ?? '', email: l.email, phone: l.phone ?? '', resetPassword: false })
  error.value = ''
  editing.value = l
}

async function save() {
  busy.value = true
  error.value = ''
  try {
    if (isNew.value) {
      await rental.createLandlord({ name: form.name, email: form.email.trim(), phone: form.phone })
      showFlash(`${form.name} is registered. They sign in at /login with ${form.email.trim()} and create their password.`)
    } else {
      await rental.updateLandlord(editing.value.id, {
        name: form.name,
        phone: form.phone,
        ...(form.resetPassword ? { resetPassword: true } : {}),
      })
      showFlash(form.resetPassword ? 'Landlord updated. They will create a new password at their next sign-in.' : 'Landlord updated.')
    }
    editing.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

async function remove(l) {
  const warning =
    `Permanently delete ${l.name} (${l.email})?\n\n` +
    `This also deletes their ${l.properties} propert${l.properties === 1 ? 'y' : 'ies'}, ${l.tenants} tenant record(s), ` +
    `all payments and notifications. This cannot be undone.`
  if (!confirm(warning)) return
  try {
    await rental.deleteUser(l.id)
    showFlash(`${l.name} was deleted.`)
  } catch (e) {
    alert(e.message)
  }
}

async function toggleActive(l) {
  const verb = l.active ? 'Suspend' : 'Reactivate'
  if (!confirm(`${verb} ${l.name}?${l.active ? ' They will not be able to sign in.' : ''}`)) return
  try {
    await rental.updateLandlord(l.id, { active: !l.active })
    showFlash(`${l.name} ${l.active ? 'suspended' : 'reactivated'}.`)
  } catch (e) {
    alert(e.message)
  }
}
</script>

<template>
  <PageHeader title="Landlords" :subtitle="`${rental.landlords.length} registered`">
    <button class="btn-primary" @click="openNew"><Plus class="size-4" /> Register landlord</button>
  </PageHeader>

  <p v-if="flash" class="card mb-6 flex items-center gap-2 border-emerald-200 p-4 text-sm text-slate-700">
    <CheckCircle2 class="size-5 text-emerald-600" /> {{ flash }}
  </p>

  <div class="relative mb-5 max-w-sm">
    <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
    <input v-model="query" class="input pl-9" placeholder="Search landlords" />
  </div>

  <section class="card overflow-hidden">
    <div class="overflow-x-auto">
      <table v-if="list.length" class="min-w-full divide-y divide-slate-100">
        <thead>
          <tr>
            <th class="table-head">Landlord</th>
            <th class="table-head">Phone</th>
            <th class="table-head">Properties</th>
            <th class="table-head">Tenants</th>
            <th class="table-head">Registered</th>
            <th class="table-head">Status</th>
            <th class="table-head"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="l in list" :key="l.id">
            <td class="table-cell">
              <RouterLink :to="`/admin2026/landlords/${l.id}`" class="font-medium text-slate-900 hover:text-brand-600">{{ l.name }}</RouterLink>
              <p class="text-xs text-slate-500">{{ l.email }}</p>
            </td>
            <td class="table-cell">{{ l.phone ?? '—' }}</td>
            <td class="table-cell">{{ l.properties }}</td>
            <td class="table-cell">{{ l.tenants }}</td>
            <td class="table-cell">{{ formatDate(l.createdAt) }}</td>
            <td class="table-cell"><StatusBadge :status="l.active ? 'active' : 'suspended'" /></td>
            <td class="table-cell text-right">
              <button class="btn-ghost px-2 py-1 text-xs" @click="openEdit(l)">Edit</button>
              <button class="btn-ghost px-2 py-1 text-xs" :class="l.active && 'text-red-600'" @click="toggleActive(l)">
                {{ l.active ? 'Suspend' : 'Reactivate' }}
              </button>
              <button v-if="!l.active" class="btn-ghost px-2 py-1 text-xs text-red-600" @click="remove(l)">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-else class="px-5 py-10 text-center text-sm text-slate-500">
        {{ rental.landlords.length ? 'No landlords match your search.' : 'No landlords yet. Click "Register landlord" to add one.' }}
      </p>
    </div>
  </section>

  <BaseModal :model-value="Boolean(editing)" :title="isNew ? 'Register landlord' : 'Edit landlord'" @update:model-value="!$event && (editing = null)">
    <form class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="lname">Full name</label>
        <input id="lname" v-model="form.name" class="input" required />
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label" for="lemail">Email (login)</label>
          <input id="lemail" v-model="form.email" type="email" class="input" placeholder="name@gmail.com" :disabled="!isNew" required />
        </div>
        <div>
          <label class="label" for="lphone">Phone</label>
          <input id="lphone" v-model="form.phone" type="tel" class="input" placeholder="+256…" />
        </div>
      </div>
      <p v-if="isNew" class="rounded-lg bg-slate-50 p-3 text-xs text-slate-600">
        The landlord signs in at <strong>/login</strong> with this email. The first time, they create their own password; after
        that they go straight to their dashboard.
      </p>
      <label v-else class="flex items-start gap-2 text-sm text-slate-700">
        <input v-model="form.resetPassword" type="checkbox" class="mt-0.5 size-4 accent-brand-600" />
        <span>
          Reset password
          <span class="block text-xs text-slate-500">Their current password stops working; they create a new one at next sign-in.</span>
        </span>
      </label>
      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn-secondary" @click="editing = null">Cancel</button>
        <button type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : isNew ? 'Register' : 'Save changes' }}</button>
      </div>
    </form>
  </BaseModal>
</template>
