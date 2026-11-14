<script setup>
import { computed, onMounted, ref } from 'vue'
import {
  Smartphone, Database, Bell, ShieldCheck, LogOut, RefreshCw, CircleCheck, CircleAlert, CircleX, Server, Users, Building2, Receipt,
  Trash2, ChevronRight, Archive as ArchiveIcon,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { useSignOut } from '@/composables/useSignOut'
import { supabase } from '@/lib/supabase'
import { api } from '@/lib/api'
import SuperHero from '@/components/super/SuperHero.vue'
import BaseModal from '@/components/BaseModal.vue'

// Main admin: is everything working? Payments, database, phone notifications, your account.
const rental = useRentalStore()
const auth = useAuthStore()
const signOut = useSignOut()

const pay = ref(null)
const db = ref(null) // { ok, missing: [] }
const checking = ref(false)

async function check() {
  checking.value = true
  try {
    pay.value = await api('/api/payments/info')
  } catch (e) {
    pay.value = { error: e.message }
  }
  // Newer parts of the database: if any is missing, update_existing.sql hasn't been run
  const parts = [
    ['rentals', 'Rental businesses'],
    ['move_out_requests', 'Requests to leave'],
    ['admin_audit', 'Activity log'],
    ['cash_payments', 'Cash confirmation'],
  ]
  const missing = []
  for (const [table, label] of parts) {
    const { error } = await supabase.from(table).select('id', { head: true, count: 'exact' }).limit(1)
    if (error) missing.push(label)
  }
  db.value = { ok: missing.length === 0, missing }
  checking.value = false
}
onMounted(check)

const payState = computed(() => {
  const v = pay.value
  if (!v) return { tone: 'wait', text: 'Checking…', sub: '' }
  if (v.error) return { tone: 'bad', text: 'Payment server not reachable', sub: v.error }
  if (!v.enabled) return { tone: 'bad', text: 'Online payments are off', sub: 'Add the Relworx key and account number to the server settings.' }
  if (v.testMode) return { tone: 'warn', text: 'Test mode', sub: 'No real money moves. Switch PAYMENTS_TEST_MODE off for real payments.' }
  return { tone: 'ok', text: `Live · ${v.provider === 'relworx' ? 'Relworx' : 'Flutterwave'}`, sub: `MTN & Airtel · ${Number(v.minAmount).toLocaleString()}–${Number(v.maxAmount).toLocaleString()} UGX per payment` }
})
const dbState = computed(() => {
  if (!db.value) return { tone: 'wait', text: 'Checking…', sub: '' }
  return db.value.ok
    ? { tone: 'ok', text: 'Up to date', sub: 'All features are available.' }
    : { tone: 'warn', text: 'Needs an update', sub: `Missing: ${db.value.missing.join(', ')}. Run database/update_existing.sql in Supabase → SQL Editor.` }
})
const pushOn = Boolean(import.meta.env.VITE_VAPID_PUBLIC_KEY)
const ICON = { ok: CircleCheck, warn: CircleAlert, bad: CircleX, wait: RefreshCw }
const TONE = { ok: 'text-emerald-600', warn: 'text-amber-600', bad: 'text-red-600', wait: 'text-slate-400' }

const confirmOut = ref(false)

// ── Archives + delete all users ──
const archives = ref(null)
onMounted(async () => {
  try {
    archives.value = await rental.loadArchives()
  } catch {
    archives.value = []
  }
})
const PHRASE = 'DELETE ALL USERS'
const clearOpen = ref(false)
const clearConfirm = ref('')
const clearNote = ref('')
const clearing = ref(false)
const clearError = ref('')
const cleared = ref(null)
function openClear() {
  clearConfirm.value = ''
  clearNote.value = ''
  clearError.value = ''
  cleared.value = null
  clearOpen.value = true
}
async function clearAll() {
  clearing.value = true
  clearError.value = ''
  try {
    cleared.value = await rental.clearPlatform({ confirm: clearConfirm.value, note: clearNote.value })
    archives.value = await rental.loadArchives().catch(() => archives.value)
  } catch (e) {
    clearError.value = e.message
  } finally {
    clearing.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <SuperHero eyebrow="System" title="Health & settings" subtitle="Check that payments, the database and notifications are working.">
      <button class="btn-secondary" :data-busy="checking" :disabled="checking" @click="check"><RefreshCw class="size-4" /> {{ checking ? 'Checking…' : 'Check again' }}</button>
    </SuperHero>

    <h2 class="section-title">Services</h2>
    <div class="sheet divide-y divide-slate-100">
      <div v-for="row in [
        { icon: Smartphone, tile: 'tile-amber', title: 'Mobile money payments', s: payState },
        { icon: Database, tile: 'tile-sky', title: 'Database', s: dbState },
        { icon: Bell, tile: 'tile-violet', title: 'Phone notifications', s: pushOn ? { tone: 'ok', text: 'Set up', sub: 'People who allow notifications get them on their phones.' } : { tone: 'warn', text: 'Not set up', sub: 'Add the VAPID keys to switch on phone pop-ups.' } },
        { icon: Server, tile: 'tile-teal', title: 'Live data', s: rental.error ? { tone: 'bad', text: 'Problem loading', sub: rental.error } : { tone: 'ok', text: 'Connected', sub: 'Changes appear instantly on every device.' } },
      ]" :key="row.title" class="flex items-start gap-3.5 px-4 py-4 sm:px-5">
        <span class="icon-tile" :class="row.tile"><component :is="row.icon" class="size-[1.3rem]" /></span>
        <div class="min-w-0 flex-1">
          <p class="font-medium text-slate-900">{{ row.title }}</p>
          <p class="mt-0.5 flex items-center gap-1.5 text-sm font-semibold" :class="TONE[row.s.tone]">
            <component :is="ICON[row.s.tone]" class="size-4" :class="row.s.tone === 'wait' && 'animate-spin'" /> {{ row.s.text }}
          </p>
          <p v-if="row.s.sub" class="mt-0.5 text-xs leading-relaxed text-slate-500">{{ row.s.sub }}</p>
        </div>
      </div>
    </div>

    <h2 class="section-title mt-6">Data on the platform</h2>
    <div class="grid grid-cols-3 gap-3">
      <div v-for="x in [
        { icon: Users, n: rental.tenants.length, label: 'Tenant records' },
        { icon: Building2, n: rental.properties.length, label: 'Properties' },
        { icon: Receipt, n: rental.payment_receipts.length, label: 'Payments' },
      ]" :key="x.label" class="sheet p-4 text-center">
        <component :is="x.icon" class="mx-auto size-5 text-brand-600" />
        <p class="mt-2 text-xl font-bold text-slate-900 tabular-nums">{{ x.n }}</p>
        <p class="text-xs text-slate-500">{{ x.label }}</p>
      </div>
    </div>

    <!-- Archives -->
    <div class="mt-6 flex items-center justify-between">
      <h2 class="section-title">Archives</h2>
      <RouterLink to="/admin2026/archives" class="mb-2.5 text-xs font-semibold text-brand-700">Open archives</RouterLink>
    </div>
    <RouterLink to="/admin2026/archives" class="sheet flex items-center gap-3.5 px-4 py-4 transition-colors hover:bg-slate-50 sm:px-5">
      <span class="icon-tile tile-slate"><ArchiveIcon class="size-[1.3rem]" /></span>
      <div class="min-w-0 flex-1">
        <p class="font-medium text-slate-900">Saved history</p>
        <p class="text-xs text-slate-500">{{ archives === null ? 'Loading…' : archives.length ? `${archives.length} archive${archives.length === 1 ? '' : 's'} · only you can see them` : 'Nothing archived yet' }}</p>
      </div>
      <ChevronRight class="size-4 text-slate-300" />
    </RouterLink>

    <!-- Danger zone -->
    <h2 class="section-title mt-6 !text-red-600">Danger zone</h2>
    <div class="danger rounded-[1.375rem] border border-red-200 p-5">
      <div class="flex items-start gap-3.5">
        <span class="icon-tile tile-red"><Trash2 class="size-[1.3rem]" /></span>
        <div class="min-w-0">
          <p class="font-semibold text-slate-900">Delete all users</p>
          <p class="mt-1 text-sm leading-relaxed text-slate-600">
            Deletes every landlord and tenant: their accounts, properties, tenants, payments, messages and everything else they entered.
            A full copy is saved in <strong>Archives</strong> first, and only you can view it. Your admin account and the activity log stay.
          </p>
          <p class="mt-2 text-xs text-slate-500">
            Right now: {{ rental.landlords.length }} landlords · {{ rental.tenants.length }} tenant records · {{ rental.properties.length }} properties · {{ rental.payment_receipts.length }} payments
          </p>
        </div>
      </div>
      <button type="button" class="btn mt-4 h-12 w-full rounded-2xl bg-red-600 text-white hover:bg-red-700" @click="openClear"><Trash2 class="size-4" /> Delete all users</button>
    </div>

    <h2 class="section-title mt-6">Your account</h2>
    <div class="sheet divide-y divide-slate-100">
      <div class="flex items-center gap-3.5 px-4 py-4 sm:px-5">
        <span class="icon-tile tile-teal"><ShieldCheck class="size-[1.3rem]" /></span>
        <div class="min-w-0">
          <p class="truncate font-medium text-slate-900">{{ auth.user?.name }}</p>
          <p class="truncate text-xs text-slate-500">{{ auth.user?.email }} · Main admin</p>
        </div>
      </div>
      <button type="button" class="flex w-full items-center gap-3.5 px-4 py-4 text-left transition-colors hover:bg-red-50 sm:px-5" @click="confirmOut = true">
        <span class="icon-disc disc-red"><LogOut class="size-5" /></span>
        <div>
          <p class="font-medium text-red-600">Sign out</p>
          <p class="text-xs text-slate-500">Leave the admin console on this device</p>
        </div>
      </button>
    </div>

    <!-- Delete all users: archive first, typed confirmation -->
    <BaseModal v-model="clearOpen" :title="cleared ? 'Done' : 'Delete all users?'" width="max-w-md">
      <div v-if="cleared" class="text-center">
        <CircleCheck class="mx-auto size-12 text-emerald-600" />
        <p class="mt-3 font-semibold text-slate-900">Everything was archived and cleared</p>
        <p class="mt-1 text-sm text-slate-600">
          {{ cleared.counts?.landlords ?? 0 }} landlords, {{ cleared.counts?.tenant_accounts ?? 0 }} tenant accounts, {{ cleared.counts?.tenants ?? 0 }} tenant records and
          {{ cleared.counts?.payment_receipts ?? 0 }} payments were saved to the archive and removed.
          <template v-if="cleared.failed"> {{ cleared.failed }} login account(s) could not be removed; try again.</template>
        </p>
        <RouterLink :to="`/admin2026/archives/${cleared.archiveId}`" class="btn-primary mt-5 w-full">View the archive</RouterLink>
      </div>
      <form v-else class="space-y-4" @submit.prevent="clearAll">
        <div class="flex items-start gap-3 rounded-2xl bg-red-50 p-4 text-sm text-red-900">
          <CircleAlert class="mt-0.5 size-5 shrink-0 text-red-600" />
          <p>All landlords and tenants will be signed out and deleted. They will need new accounts to use Renta UG again. <strong>This cannot be undone</strong>, but a full copy is kept in Archives.</p>
        </div>
        <div>
          <label class="label" for="clear-note">Note for the archive <span class="font-normal text-slate-400">(optional)</span></label>
          <input id="clear-note" v-model="clearNote" class="input" maxlength="200" placeholder="e.g. Test data before launch" />
        </div>
        <div>
          <label class="label" for="clear-confirm">Type <strong class="text-red-600">{{ PHRASE }}</strong> to confirm</label>
          <input id="clear-confirm" v-model="clearConfirm" class="input tracking-wide" autocomplete="off" data-cap="off" :placeholder="PHRASE" />
        </div>
        <p v-if="clearError" class="text-sm text-red-600">{{ clearError }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="clearOpen = false">Cancel</button>
          <button :data-busy="Boolean(clearing)" type="submit" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="clearing || clearConfirm.trim().toUpperCase() !== PHRASE">
            {{ clearing ? 'Archiving & deleting…' : 'Delete all users' }}
          </button>
        </div>
      </form>
    </BaseModal>

    <BaseModal v-model="confirmOut" title="Sign out?" width="max-w-sm">
      <p class="text-sm text-slate-600">You'll need your email and password to come back in at /admin2026.</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="confirmOut = false">Cancel</button>
        <button class="btn bg-red-600 text-white hover:bg-red-700" @click="signOut">Sign out</button>
      </div>
    </BaseModal>
  </div>
</template>

<style scoped>
.danger { background: radial-gradient(120% 90% at 100% 0%, var(--color-red-50) 0%, transparent 60%), var(--color-white); }
.tile-red { background: linear-gradient(140deg, #f87171 0%, #b91c1c 100%); --tile-shadow: rgb(185 28 28 / 0.6); }
</style>
