<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import {
  Smartphone, Database, Bell, ShieldCheck, LogOut, RefreshCw, CircleCheck, CircleAlert, CircleX, Server, Users, Building2, Receipt,
  Trash2, ChevronRight, Archive as ArchiveIcon, Activity, Bug, Search, UserX, Wand2,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { useSignOut } from '@/composables/useSignOut'
import { supabase } from '@/lib/supabase'
import { api } from '@/lib/api'
import SuperHero from '@/components/super/SuperHero.vue'
import BaseModal from '@/components/BaseModal.vue'
import EmptyState from '@/components/EmptyState.vue'

// Main admin: is everything working? Payments, database, phone notifications, your account.
const rental = useRentalStore()
const auth = useAuthStore()
const signOut = useSignOut()

const pay = ref(null) // { landlords: n } with mobile money numbers
const db = ref(null) // { ok, missing: [] }
const checking = ref(false)

async function check() {
  checking.value = true
  const { data: accts, error: aErr } = await supabase.from('landlord_pay_accounts').select('landlord_id')
  pay.value = aErr ? { error: aErr.message } : { landlords: new Set((accts ?? []).map((a) => a.landlord_id)).size }
  // Newer parts of the database: if any is missing, update_existing.sql hasn't been run
  const parts = [
    ['rentals', 'Rental businesses'],
    ['move_out_requests', 'Requests to leave'],
    ['admin_audit', 'Activity log'],
    ['cash_payments', 'Payment confirmation'],
    ['landlord_pay_accounts', 'Mobile money numbers'],
    ['error_reports', 'Error reports'],
    ['health_checks', 'Health checks'],
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
  if (v.error) return { tone: 'warn', text: 'Needs a database update', sub: v.error }
  const total = rental.landlords.filter((l) => l.active).length
  return v.landlords
    ? { tone: 'ok', text: `Direct to landlords · ${v.landlords} of ${total} set up`, sub: 'Tenants send MTN or Airtel Mobile Money to their landlord, who confirms it.' }
    : { tone: 'warn', text: 'No landlord has added a number yet', sub: 'Landlords add them in Payments → Mobile money numbers.' }
})

// ── Automatic checks (every 20 minutes, on the server) ──
const checks = ref([]) // newest first
const lastCheck = computed(() => checks.value[0] ?? null)
const running = ref(false)
const runError = ref('')
async function loadChecks() {
  const { data } = await supabase.from('health_checks').select('*').order('run_at', { ascending: false }).limit(24)
  checks.value = data ?? []
}
async function runNow() {
  running.value = true
  runError.value = ''
  try {
    await api('/api/admin/health')
    await loadChecks()
  } catch (e) {
    runError.value = e.message
  } finally {
    running.value = false
  }
}
const STATUS_TONE = { ok: 'ok', warn: 'warn', fail: 'bad' }
const when = (iso) => new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true })

// ── Errors reported by the app and the server ──
const errors = ref([])
const errorFilter = ref('open') // open | all
const openError = ref(null)
async function loadErrors() {
  let q = supabase.from('error_reports').select('*').order('last_seen', { ascending: false }).limit(100)
  if (errorFilter.value === 'open') q = q.eq('status', 'open')
  const { data } = await q
  errors.value = data ?? []
}
async function setErrorStatus(e, status) {
  const { error } = await supabase.from('error_reports').update({ status }).eq('id', e.id)
  if (!error) {
    openError.value = null
    await loadErrors()
  }
}
const SOURCE = { app: 'App', server: 'Server', health: 'System check' }
watch(errorFilter, loadErrors)

let live = null
onMounted(() => {
  loadChecks()
  loadErrors()
  live = supabase
    .channel('admin-health')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'error_reports' }, () => loadErrors())
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'health_checks' }, () => loadChecks())
    .subscribe()
})
onBeforeUnmount(() => live && supabase.removeChannel(live))

// ── Danger zone: delete one account ──
const accounts = ref([])
const delOpen = ref(false)
const delQuery = ref('')
const delTarget = ref(null)
const delConfirm = ref('')
const delBusy = ref(false)
const delError = ref('')
const delDone = ref('')
async function openDelete() {
  delQuery.value = ''
  delTarget.value = null
  delConfirm.value = ''
  delError.value = ''
  delDone.value = ''
  delOpen.value = true
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .in('role', ['landlord', 'tenant'])
    .order('created_at', { ascending: false })
  accounts.value = data ?? []
}
const shownAccounts = computed(() => {
  const q = delQuery.value.trim().toLowerCase()
  return accounts.value
    .filter((a) => !q || `${a.full_name ?? ''} ${a.email ?? ''} ${a.phone ?? ''}`.toLowerCase().includes(q))
    .slice(0, 50)
})
// The permanent landlord account (and nothing else) can never be deleted
const isProtected = (a) => a.subscription_exempt === true || String(a.email ?? '').toLowerCase() === 'ngumisiriza@gmail.com'
const renting = (a) => a.role === 'tenant' && rental.tenants.some((t) => t.userId === a.id && t.propertyId)
const ownsCount = (a) => rental.properties.filter((x) => x.landlordId === a.id).length
const shownEmail = (e) => (String(e ?? '').endsWith('@phone-signin.example.com') ? 'Signs in with phone' : e)
async function deleteAccount() {
  delBusy.value = true
  delError.value = ''
  try {
    const a = delTarget.value
    await rental.deleteUser(a.id, { force: true })
    rental.adminNote('delete_account', a.role, a.id, `Deleted the ${a.role} account of ${a.full_name || a.email}`)
    delDone.value = `${a.full_name || a.email} was deleted.`
    accounts.value = accounts.value.filter((x) => x.id !== a.id)
    delTarget.value = null
    delConfirm.value = ''
  } catch (e) {
    delError.value = e.message
  } finally {
    delBusy.value = false
  }
}
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
        { icon: Smartphone, tile: 'tile-amber', title: 'Mobile money', s: payState },
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

    <!-- Automatic checks -->
    <div class="mt-6 flex items-end justify-between gap-3">
      <h2 class="section-title">Automatic checks · every 20 minutes</h2>
      <button type="button" class="mb-2.5 inline-flex items-center gap-1.5 text-xs font-semibold text-brand-700 disabled:opacity-50" :disabled="running" @click="runNow">
        <RefreshCw class="size-3.5" :class="running && 'animate-spin'" /> {{ running ? 'Checking…' : 'Run checks now' }}
      </button>
    </div>
    <div class="sheet overflow-hidden">
      <div class="flex items-center gap-3.5 border-b border-slate-100 px-4 py-4 sm:px-5" :class="!lastCheck ? '' : lastCheck.ok ? 'bg-emerald-50/60' : 'bg-amber-50/60'">
        <span class="icon-tile" :class="!lastCheck ? 'tile-slate' : lastCheck.ok ? 'tile-teal' : 'tile-amber'"><Activity class="size-[1.3rem]" /></span>
        <div class="min-w-0 flex-1">
          <p class="font-semibold text-slate-900">{{ !lastCheck ? 'No check has run yet' : lastCheck.ok ? 'Everything is working' : 'Something needs attention' }}</p>
          <p class="text-xs text-slate-500">{{ lastCheck ? `Last checked ${when(lastCheck.run_at)}${lastCheck.trigger === 'manual' ? ' (by you)' : ''}` : 'The server checks every part of Renta UG every 20 minutes. Tap “Run checks now”.' }}</p>
        </div>
        <!-- Last runs, oldest → newest -->
        <div v-if="checks.length > 1" class="hidden items-end gap-1 sm:flex" aria-label="Recent checks">
          <span v-for="c in [...checks].reverse()" :key="c.id" class="h-5 w-1.5 rounded-full" :class="c.ok ? 'bg-emerald-400' : 'bg-amber-400'" :title="when(c.run_at)" />
        </div>
      </div>
      <p v-if="runError" class="form-error m-4" role="alert">{{ runError }}</p>
      <ul v-if="lastCheck" class="divide-y divide-slate-100">
        <li v-for="r in lastCheck.results" :key="r.key" class="flex items-start gap-3 px-4 py-3 sm:px-5">
          <component :is="ICON[STATUS_TONE[r.status]]" class="mt-0.5 size-4.5 shrink-0" :class="TONE[STATUS_TONE[r.status]]" />
          <div class="min-w-0 flex-1">
            <p class="text-sm font-medium text-slate-900">{{ r.label }}</p>
            <p class="text-xs leading-relaxed text-slate-500">{{ r.detail }}</p>
          </div>
          <span v-if="r.ms != null" class="shrink-0 text-[11px] text-slate-400 tabular-nums">{{ r.ms }} ms</span>
        </li>
      </ul>
    </div>

    <!-- Errors from anywhere in the app or the server -->
    <div class="mt-6 flex items-end justify-between gap-3">
      <h2 class="section-title">Errors reported</h2>
      <div class="mb-2.5 flex rounded-xl border border-slate-200 bg-slate-50 p-0.5 text-xs">
        <button v-for="f in [['open', 'Open'], ['all', 'All']]" :key="f[0]" class="h-7 rounded-lg px-3 font-medium" :class="errorFilter === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="errorFilter = f[0]">{{ f[1] }}</button>
      </div>
    </div>
    <div class="sheet">
      <ul v-if="errors.length" class="max-h-[28rem] divide-y divide-slate-100 overflow-y-auto">
        <li v-for="e in errors" :key="e.id">
          <button type="button" class="flex w-full items-start gap-3 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 sm:px-5" @click="openError = e">
            <span class="icon-disc shrink-0" :class="e.status !== 'open' ? 'disc-slate' : e.source === 'health' ? 'disc-amber' : 'disc-red'"><Bug class="size-5" /></span>
            <div class="min-w-0 flex-1">
              <p class="line-clamp-2 text-sm font-medium text-slate-900">{{ e.message }}</p>
              <p class="mt-0.5 truncate text-xs text-slate-500">{{ SOURCE[e.source] }}<template v-if="e.area"> · {{ e.area }}</template> · {{ when(e.last_seen) }}</p>
              <p class="mt-1 flex flex-wrap gap-1.5">
                <span v-if="e.count > 1" class="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-600">{{ e.count }} times</span>
                <span v-if="e.auto_fixed" class="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[11px] font-semibold text-emerald-700"><Wand2 class="size-3" /> Fixed itself</span>
                <span v-if="e.status !== 'open'" class="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-500 capitalize">{{ e.status }}</span>
              </p>
            </div>
            <ChevronRight class="mt-1 size-4 shrink-0 text-slate-300" />
          </button>
        </li>
      </ul>
      <div v-else class="flex flex-col items-center px-6 py-10 text-center">
        <CircleCheck class="size-9 text-emerald-500" />
        <p class="mt-2 font-medium text-slate-900">{{ errorFilter === 'open' ? 'No open errors' : 'No errors reported' }}</p>
        <p class="mt-0.5 text-xs text-slate-500">Errors from any page or the server appear here straight away.</p>
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
        <p class="text-xs text-slate-500"><span v-if="archives === null" class="skeleton inline-block h-3 w-32 align-middle" /><template v-else>{{ archives.length ? `${archives.length} archive${archives.length === 1 ? '' : 's'} · only you can see them` : 'Nothing archived yet' }}</template></p>
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
            A full copy is saved in <strong>Archives</strong> first, and only you can view it. Your admin account and the activity log stay,
            and so does the permanent landlord account (ngumisiriza@gmail.com) with all its data and its tenants.
          </p>
          <p class="mt-2 text-xs text-slate-500">
            Right now: {{ rental.landlords.length }} landlords · {{ rental.tenants.length }} tenant records · {{ rental.properties.length }} properties · {{ rental.payment_receipts.length }} payments
          </p>
        </div>
      </div>
      <button type="button" class="btn mt-4 h-12 w-full rounded-2xl bg-red-600 text-white hover:bg-red-700" @click="openClear"><Trash2 class="size-4" /> Delete all users</button>

      <div class="mt-5 flex items-start gap-3.5 border-t border-red-100 pt-5">
        <span class="icon-tile tile-red"><UserX class="size-[1.3rem]" /></span>
        <div class="min-w-0">
          <p class="font-semibold text-slate-900">Delete an account</p>
          <p class="mt-1 text-sm leading-relaxed text-slate-600">
            Delete one landlord or tenant. A landlord's houses, tenants and payments go with them. A renting tenant's tenancy is ended first, so their house becomes vacant and their history stays in Records.
          </p>
        </div>
      </div>
      <button type="button" class="btn mt-4 h-12 w-full rounded-2xl border border-red-300 bg-white text-red-700 hover:bg-red-50" @click="openDelete"><UserX class="size-4" /> Choose an account to delete</button>
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
          <p>All landlords and tenants will be signed out and deleted, except the permanent landlord account and the tenants renting from it. They will need new accounts to use Renta UG again. <strong>This cannot be undone</strong>, but a full copy is kept in Archives.</p>
        </div>
        <div>
          <label class="label" for="clear-note">Note for the archive <span class="font-normal text-slate-400">(optional)</span></label>
          <input id="clear-note" v-model="clearNote" class="input" maxlength="200" placeholder="e.g. Test data before launch" />
        </div>
        <div>
          <label class="label" for="clear-confirm">Type <strong class="text-red-600">{{ PHRASE }}</strong> to confirm</label>
          <input id="clear-confirm" v-model="clearConfirm" class="input tracking-wide" autocomplete="off" data-cap="off" :placeholder="PHRASE" />
        </div>
        <p v-if="clearError" class="form-error" role="alert">{{ clearError }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="clearOpen = false">Cancel</button>
          <button :data-busy="Boolean(clearing)" type="submit" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="clearing || clearConfirm.trim().toUpperCase() !== PHRASE">
            {{ clearing ? 'Archiving & deleting…' : 'Delete all users' }}
          </button>
        </div>
      </form>
    </BaseModal>

    <!-- One error -->
    <BaseModal :model-value="Boolean(openError)" center title="Error details" width="max-w-lg" @update:model-value="!$event && (openError = null)">
      <div v-if="openError" class="space-y-4">
        <div class="rounded-2xl bg-red-50 p-4">
          <p class="text-sm font-semibold text-red-900">{{ openError.message }}</p>
          <p class="mt-1 text-xs text-red-800/80">{{ SOURCE[openError.source] }}<template v-if="openError.area"> · {{ openError.area }}</template></p>
        </div>
        <dl class="grid grid-cols-2 gap-3 text-sm">
          <div><dt class="text-xs text-slate-500">First seen</dt><dd class="font-medium text-slate-900">{{ when(openError.first_seen) }}</dd></div>
          <div><dt class="text-xs text-slate-500">Last seen</dt><dd class="font-medium text-slate-900">{{ when(openError.last_seen) }}</dd></div>
          <div><dt class="text-xs text-slate-500">Times</dt><dd class="font-medium text-slate-900">{{ openError.count }}</dd></div>
          <div><dt class="text-xs text-slate-500">Who</dt><dd class="font-medium text-slate-900 capitalize">{{ openError.user_role || 'Signed out' }}</dd></div>
          <div v-if="openError.url" class="col-span-2"><dt class="text-xs text-slate-500">Page</dt><dd class="truncate font-mono text-xs text-slate-900">{{ openError.url }}</dd></div>
          <div v-if="openError.user_agent" class="col-span-2"><dt class="text-xs text-slate-500">Device</dt><dd class="truncate text-xs text-slate-700">{{ openError.user_agent }}</dd></div>
        </dl>
        <p v-if="openError.auto_fixed" class="flex items-center gap-2 rounded-xl bg-emerald-50 p-3 text-xs text-emerald-800"><Wand2 class="size-4" /> The app recovered from this by itself (it reloaded or retried). Kept here so you know it happened.</p>
        <details v-if="openError.detail" class="disclosure rounded-xl bg-slate-50 p-3">
          <summary class="cursor-pointer text-xs font-semibold text-slate-700">Technical details</summary>
          <pre class="mt-2 max-h-56 overflow-auto text-[11px] leading-relaxed whitespace-pre-wrap text-slate-600">{{ openError.detail }}</pre>
        </details>
        <div v-if="openError.status === 'open'" class="grid grid-cols-2 gap-2">
          <button class="btn-secondary h-11" @click="setErrorStatus(openError, 'ignored')">Ignore</button>
          <button class="btn-primary h-11" @click="setErrorStatus(openError, 'fixed')"><CircleCheck class="size-4" /> Mark fixed</button>
        </div>
        <button v-else class="btn-secondary h-11 w-full" @click="setErrorStatus(openError, 'open')">Open again</button>
      </div>
    </BaseModal>

    <!-- Delete one account -->
    <BaseModal v-model="delOpen" center :title="delTarget ? 'Delete this account?' : 'Delete an account'" width="max-w-md">
      <div v-if="!delTarget" class="space-y-3">
        <p v-if="delDone" class="flex items-center gap-2 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800"><CircleCheck class="size-4" /> {{ delDone }}</p>
        <div class="relative">
          <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
          <input v-model="delQuery" class="input h-11 pl-10" placeholder="Search name, email or phone" data-cap="off" />
        </div>
        <ul class="max-h-[50dvh] space-y-1.5 overflow-y-auto overscroll-contain">
          <li v-for="a in shownAccounts" :key="a.id">
            <div v-if="isProtected(a)" class="flex w-full items-center gap-3 rounded-2xl bg-slate-50 px-3 py-2.5 ring-1 ring-slate-200" title="Permanent account: it can't be deleted">
              <span class="icon-disc disc-brand shrink-0"><ShieldCheck class="size-5" /></span>
              <span class="min-w-0 flex-1">
                <span class="block truncate font-medium text-slate-900">{{ a.full_name || 'No name' }}</span>
                <span class="block truncate text-xs text-slate-500">{{ a.email }}</span>
              </span>
              <span class="shrink-0 rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-700">Permanent · can't be deleted</span>
            </div>
            <button v-else type="button" class="flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left ring-1 ring-slate-200 transition hover:bg-red-50 hover:ring-red-200" @click="delTarget = a; delConfirm = ''; delError = ''">
              <span class="icon-disc shrink-0" :class="a.role === 'landlord' ? 'disc-brand' : 'disc-slate'"><component :is="a.role === 'landlord' ? Building2 : Users" class="size-5" /></span>
              <span class="min-w-0 flex-1">
                <span class="block truncate font-medium text-slate-900">{{ a.full_name || 'No name' }}</span>
                <span class="block truncate text-xs text-slate-500">{{ shownEmail(a.email) }}{{ a.phone ? ` · ${a.phone}` : '' }}</span>
              </span>
              <span class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold capitalize" :class="a.role === 'landlord' ? 'bg-brand-50 text-brand-700' : 'bg-slate-100 text-slate-600'">{{ a.role }}</span>
            </button>
          </li>
          <li v-if="!shownAccounts.length && accounts.length"><EmptyState compact kind="search" title="Nobody matches" text="Try another name, email or phone." /></li>
          <template v-else-if="!shownAccounts.length"><li v-for="i in 4" :key="`load-${i}`" class="skeleton h-14 rounded-2xl" /></template>
        </ul>
      </div>
      <form v-else class="space-y-4" @submit.prevent="deleteAccount">
        <div class="rounded-2xl bg-red-50 p-4 text-sm text-red-900">
          <p class="font-semibold">{{ delTarget.full_name || delTarget.email }} <span class="font-normal capitalize">· {{ delTarget.role }}</span></p>
          <p class="mt-1 text-red-800">
            <template v-if="delTarget.role === 'landlord'">Their account and {{ ownsCount(delTarget) }} house{{ ownsCount(delTarget) === 1 ? '' : 's' }}/room{{ ownsCount(delTarget) === 1 ? '' : 's' }}, with all tenants, payments and messages, are deleted.</template>
            <template v-else-if="renting(delTarget)">They are renting now: their tenancy ends first and the house becomes vacant. Their history stays with the landlord.</template>
            <template v-else>Their login is deleted. Records their landlord kept stay.</template>
            <strong> This cannot be undone.</strong>
          </p>
        </div>
        <div>
          <label class="label" for="del-confirm">Type <strong class="text-red-600">DELETE</strong> to confirm</label>
          <input id="del-confirm" v-model="delConfirm" class="input tracking-wide" autocomplete="off" data-cap="off" placeholder="DELETE" />
        </div>
        <p v-if="delError" class="form-error" role="alert">{{ delError }}</p>
        <div class="grid grid-cols-2 gap-2">
          <button type="button" class="btn-secondary h-11" @click="delTarget = null">Back</button>
          <button type="submit" class="btn h-11 bg-red-600 text-white hover:bg-red-700" :data-busy="delBusy" :disabled="delBusy || delConfirm.trim().toUpperCase() !== 'DELETE'">
            {{ delBusy ? 'Deleting…' : 'Delete account' }}
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
