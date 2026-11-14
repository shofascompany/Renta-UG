<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import {
  Bell, BellOff, Copy, Share2, Trash2, X, MessageCircle, MessageSquare, Mail, Check, Clock, ArrowLeft, AlertCircle,
  Wallet, ShieldCheck, Sparkles, Info, Wrench, Megaphone, CalendarClock,
} from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { timeAgo } from '@/utils/format'

// Tenant inbox: a clean list (no cards), grouped by day. Tap → detail sheet with Copy / Share / Delete.
const { rental, notifications, unread } = useTenant()
const list = notifications

const sender = (n) => (n?.title ?? '').replace(/^[\p{Extended_Pictographic}️\s]+/u, '') || 'Renta UG'
const fullDate = (iso) =>
  new Date(iso).toLocaleString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
const shortTime = (iso) => {
  const d = new Date(iso)
  const today = new Date().toDateString() === d.toDateString()
  return today ? d.toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', hour12: true }) : timeAgo(iso)
}

// One icon + colour per kind of notification
const kinds = {
  payment: { label: 'Payment', icon: Wallet, cls: 'k-emerald' },
  reminder: { label: 'Reminder', icon: CalendarClock, cls: 'k-amber' },
  rent_due: { label: 'Rent due', icon: AlertCircle, cls: 'k-red' },
  status: { label: 'Rent status', icon: Info, cls: 'k-sky' },
  security: { label: 'Security', icon: ShieldCheck, cls: 'k-slate' },
  welcome: { label: 'Welcome', icon: Sparkles, cls: 'k-brand' },
  maintenance: { label: 'Maintenance', icon: Wrench, cls: 'k-amber' },
  general: { label: 'Notice', icon: Megaphone, cls: 'k-brand' },
}
const kind = (n) => kinds[n?.type] ?? kinds.general
const asText = (n) => `Renta UG · ${sender(n)}\n\n${n.body}\n\n${fullDate(n.createdAt)}`

// Grouped by day: Today, Yesterday, This week, then by month
const groups = computed(() => {
  const startOf = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const today = startOf(new Date())
  const label = (iso) => {
    const d = new Date(iso)
    const days = Math.round((today - startOf(d)) / 86400000)
    if (days <= 0) return 'Today'
    if (days === 1) return 'Yesterday'
    if (days < 7) return 'This week'
    return d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
  }
  const out = []
  for (const n of list.value) {
    const l = label(n.createdAt)
    if (out.at(-1)?.label !== l) out.push({ label: l, items: [] })
    out.at(-1).items.push(n)
  }
  return out
})

// ── Detail sheet ──
const viewing = ref(null)
const mode = ref('view') // view | share | delete
const busy = ref(false)
const error = ref('')

function open(n) {
  viewing.value = n
  mode.value = 'view'
  error.value = ''
  if (!n.read) rental.markNotificationRead(n.id).catch(() => {})
}
function close() {
  viewing.value = null
}

// ── Toast ──
const toast = ref('')
let toastTimer = null
function showToast(text) {
  toast.value = text
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => (toast.value = ''), 2200)
}

// ── Copy ──
function copyFallback(text) {
  // Works on plain http too (e.g. the app opened over Wi-Fi at 192.168…)
  const el = document.createElement('textarea')
  el.value = text
  el.setAttribute('readonly', '')
  el.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0'
  document.body.appendChild(el)
  el.focus()
  el.select()
  el.setSelectionRange(0, text.length)
  let ok = false
  try {
    ok = document.execCommand('copy')
  } catch {
    ok = false
  }
  el.remove()
  return ok
}
async function copy() {
  const text = asText(viewing.value)
  let ok = false
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text)
      ok = true
    } catch {
      ok = false
    }
  }
  if (!ok) ok = copyFallback(text)
  showToast(ok ? 'Copied to clipboard' : 'Copying is not supported on this device')
}

// ── Share ──
async function share() {
  const n = viewing.value
  if (navigator.share && window.isSecureContext) {
    try {
      await navigator.share({ title: 'Renta UG', text: asText(n) })
      return
    } catch (e) {
      if (e?.name === 'AbortError') return
    }
  }
  mode.value = 'share' // no system share menu: pick an app
}
const shareLinks = computed(() => {
  if (!viewing.value) return []
  const text = encodeURIComponent(asText(viewing.value))
  return [
    { label: 'WhatsApp', icon: MessageCircle, cls: 'text-emerald-600', href: `https://wa.me/?text=${text}` },
    { label: 'SMS', icon: MessageSquare, cls: 'text-sky-600', href: `sms:?&body=${text}` },
    { label: 'Email', icon: Mail, cls: 'text-brand-700', href: `mailto:?subject=${encodeURIComponent('Renta UG notification')}&body=${text}` },
  ]
})

// ── Delete ──
async function remove() {
  busy.value = true
  error.value = ''
  try {
    await rental.hideNotification(viewing.value.id)
    close()
    showToast('Notification deleted')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

function onKey(e) {
  if (e.key === 'Escape') close()
}
watch(viewing, (v) => {
  document.body.style.overflow = v ? 'hidden' : ''
  window[v ? 'addEventListener' : 'removeEventListener']('keydown', onKey)
})
onBeforeUnmount(() => {
  document.body.style.overflow = ''
  window.removeEventListener('keydown', onKey)
  clearTimeout(toastTimer)
})
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <!-- Header -->
    <header class="hero relative overflow-hidden rounded-3xl px-6 py-7 text-white sm:px-8">
      <div class="glow" aria-hidden="true" />
      <div class="relative flex items-center gap-4">
        <span class="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25">
          <Bell class="size-6" />
        </span>
        <div class="min-w-0">
          <h1 class="text-2xl leading-tight font-bold tracking-tight sm:text-3xl">Notifications</h1>
          <p class="mt-0.5 text-sm text-white/80">
            {{ unread.length ? `${unread.length} new` : "You're all caught up" }}
          </p>
        </div>
      </div>
    </header>

    <!-- List -->
    <div v-if="list.length" class="mt-2">
      <section v-for="g in groups" :key="g.label">
        <h2 class="sticky top-16 z-10 -mx-4 bg-white/95 px-4 pt-5 pb-2 text-[11px] font-bold tracking-[0.14em] text-slate-400 uppercase backdrop-blur sm:mx-0 sm:px-0">
          {{ g.label }}
        </h2>
        <ul class="-mx-4 sm:mx-0">
          <li v-for="n in g.items" :key="n.id">
            <button
              type="button"
              class="row group flex w-full items-start gap-3.5 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:-mx-3 sm:w-[calc(100%+1.5rem)] sm:rounded-2xl sm:px-3"
              :class="!n.read && 'row-unread'"
              @click="open(n)"
            >
              <span class="kind-icon" :class="kind(n).cls">
                <component :is="kind(n).icon" class="size-[1.15rem]" />
              </span>
              <span class="row-body min-w-0 flex-1">
                <span class="flex items-baseline justify-between gap-3">
                  <span class="truncate text-[15px]" :class="n.read ? 'font-medium text-slate-700' : 'font-semibold text-slate-900'">{{ sender(n) }}</span>
                  <span class="shrink-0 text-xs" :class="n.read ? 'text-slate-400' : 'font-semibold text-brand-700'">{{ shortTime(n.createdAt) }}</span>
                </span>
                <span class="mt-0.5 flex items-start gap-3">
                  <span class="line-clamp-2 flex-1 text-sm leading-relaxed" :class="n.read ? 'text-slate-500' : 'text-slate-700'">{{ n.body }}</span>
                  <span v-if="!n.read" class="mt-1.5 size-2 shrink-0 rounded-full bg-brand-600" aria-label="Unread" />
                </span>
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <!-- Empty -->
    <div v-else class="flex flex-col items-center px-6 py-20 text-center">
      <span class="flex size-14 items-center justify-center rounded-full bg-slate-100 text-slate-400">
        <BellOff class="size-6" />
      </span>
      <p class="mt-4 font-semibold text-slate-900">No notifications yet</p>
      <p class="mt-1 max-w-xs text-sm text-slate-500">Rent reminders, receipts and messages from your landlord will appear here.</p>
    </div>
  </div>

  <Teleport to="body">
    <Transition enter-active-class="transition-opacity duration-200" leave-active-class="transition-opacity duration-150" enter-from-class="opacity-0" leave-to-class="opacity-0">
      <div v-if="viewing" class="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-[2px]" @click="close" />
    </Transition>

    <!-- Detail sheet -->
    <Transition name="sheet">
      <div
        v-if="viewing"
        class="fixed inset-x-0 bottom-0 z-50 mx-auto w-full max-w-lg sm:inset-y-0 sm:flex sm:items-center sm:p-4"
        role="dialog"
        aria-modal="true"
        aria-label="Notification"
        @click.self="close"
      >
        <div class="w-full overflow-hidden rounded-t-3xl bg-white shadow-2xl sm:rounded-3xl">
          <div class="mx-auto mt-3 h-1 w-10 rounded-full bg-slate-200 sm:hidden" />

          <!-- Header -->
          <div class="flex items-start gap-3.5 px-6 pt-5">
            <span class="kind-icon kind-icon-lg" :class="kind(viewing).cls">
              <component :is="kind(viewing).icon" class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <p class="text-xs font-semibold tracking-[0.12em] text-slate-400 uppercase">{{ kind(viewing).label }}</p>
              <p class="mt-0.5 text-lg leading-snug font-semibold text-slate-900">{{ sender(viewing) }}</p>
              <p class="mt-1 flex items-center gap-1.5 text-xs text-slate-500"><Clock class="size-3.5" /> {{ fullDate(viewing.createdAt) }}</p>
            </div>
            <button class="-mt-1 -mr-2 rounded-full p-2 text-slate-400 transition hover:bg-slate-100 hover:text-slate-700" aria-label="Close" @click="close">
              <X class="size-5" />
            </button>
          </div>

          <!-- Message -->
          <div class="mx-6 mt-5 max-h-[45vh] overflow-y-auto border-t border-slate-100 pt-5 pb-6">
            <p class="text-[15px] leading-relaxed whitespace-pre-line text-slate-700 select-text">{{ viewing.body }}</p>
          </div>

          <!-- Actions -->
          <div class="border-t border-slate-100 px-4 pt-3 pb-[max(1rem,env(safe-area-inset-bottom))]">
            <div v-if="mode === 'view'" class="grid grid-cols-3">
              <button class="action" @click="copy"><span class="action-icon"><Copy class="size-[1.1rem]" /></span> Copy</button>
              <button class="action" @click="share"><span class="action-icon"><Share2 class="size-[1.1rem]" /></span> Share</button>
              <button class="action action-danger" @click="mode = 'delete'"><span class="action-icon"><Trash2 class="size-[1.1rem]" /></span> Delete</button>
            </div>

            <div v-else-if="mode === 'share'" class="px-2 pb-1">
              <div class="mb-3 flex items-center gap-2">
                <button class="rounded-full p-1.5 text-slate-500 hover:bg-slate-100" aria-label="Back" @click="mode = 'view'"><ArrowLeft class="size-4" /></button>
                <p class="text-sm font-semibold text-slate-700">Share with</p>
              </div>
              <div class="grid grid-cols-3">
                <a v-for="s in shareLinks" :key="s.label" :href="s.href" target="_blank" rel="noopener" class="action" @click="mode = 'view'">
                  <span class="action-icon"><component :is="s.icon" class="size-[1.1rem]" :class="s.cls" /></span> {{ s.label }}
                </a>
              </div>
            </div>

            <div v-else class="px-2 pb-1">
              <p class="font-semibold text-slate-900">Delete this notification?</p>
              <p class="mt-0.5 text-sm text-slate-500">It will be removed from your notifications.</p>
              <p v-if="error" class="mt-3 flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700">
                <AlertCircle class="mt-0.5 size-4 shrink-0" /> {{ error }}
              </p>
              <div class="mt-4 grid grid-cols-2 gap-2.5">
                <button class="confirm-btn" :disabled="busy" @click="mode = 'view'; error = ''">Cancel</button>
                <button :data-busy="Boolean(busy)" class="confirm-btn confirm-btn-danger" :disabled="busy" @click="remove">
                  <Trash2 class="size-4" /> {{ busy ? 'Deleting…' : 'Delete' }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Toast -->
    <Transition name="toast">
      <div
        v-if="toast"
        class="fixed inset-x-0 bottom-24 z-[60] mx-auto flex w-max max-w-[90vw] items-center gap-2 rounded-full px-4 py-2.5 text-sm font-medium shadow-lg lg:bottom-8"
        style="background: #0f172a; color: #fff"
        role="status"
      >
        <Check class="size-4" style="color: #34d399" /> {{ toast }}
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
/* Header: fixed colours, the same in light and dark mode */
.hero {
  --color-white: #fff;
  background: linear-gradient(120deg, #0284c7 0%, #0f766e 55%, #0a3b38 100%);
  box-shadow: 0 18px 40px -24px rgb(2 84 120 / 0.6);
}
.glow {
  position: absolute;
  top: -70%;
  right: -10%;
  width: 18rem;
  height: 18rem;
  border-radius: 9999px;
  background: radial-gradient(circle, rgb(255 255 255 / 0.2), transparent 65%);
  animation: drift 16s ease-in-out infinite alternate;
}
@keyframes drift {
  to { transform: translate(-2rem, 1.5rem) scale(1.1); }
}
@media (prefers-reduced-motion: reduce) {
  .glow { animation: none; }
}

/* Unread rows: soft gradient wash */
.row-unread {
  background: linear-gradient(90deg, var(--color-brand-50) 0%, transparent 85%);
}

/* Hairline between rows, starting after the icon (inbox style) */
li + li {
  position: relative;
}
li + li::before {
  content: '';
  position: absolute;
  top: 0;
  left: 4.375rem;
  right: 1rem;
  height: 1px;
  background: var(--color-slate-100);
}
@media (min-width: 640px) {
  li + li::before { left: 3.375rem; right: 0; }
}

/* Kind icons: soft gradient discs */
.kind-icon {
  display: flex;
  width: 2.5rem;
  height: 2.5rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
}
.kind-icon-lg {
  width: 2.875rem;
  height: 2.875rem;
}
/* Theme colours, so they also work in dark mode */
.k-emerald { color: var(--color-emerald-700); background: var(--color-emerald-50); box-shadow: inset 0 0 0 1px var(--color-emerald-200); }
.k-amber { color: var(--color-amber-700); background: var(--color-amber-50); box-shadow: inset 0 0 0 1px var(--color-amber-200); }
.k-red { color: var(--color-red-700); background: var(--color-red-50); box-shadow: inset 0 0 0 1px var(--color-red-200); }
.k-sky { color: var(--color-sky-700); background: var(--color-sky-50); box-shadow: inset 0 0 0 1px var(--color-sky-200, #bae6fd); }
.k-slate { color: var(--color-slate-700); background: var(--color-slate-100); box-shadow: inset 0 0 0 1px var(--color-slate-200); }
.k-brand { color: var(--color-brand-700); background: var(--color-brand-50); box-shadow: inset 0 0 0 1px var(--color-brand-100); }

/* Sheet actions: icon above label, no boxes */
.action {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.375rem;
  border-radius: 1rem;
  padding: 0.5rem 0;
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--color-slate-700);
  transition: background-color 0.15s ease;
}
.action:hover { background: var(--color-slate-50); }
.action:active .action-icon { transform: scale(0.94); }
.action-icon {
  display: flex;
  width: 2.75rem;
  height: 2.75rem;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  background: var(--color-slate-100);
  transition: transform 0.15s ease;
}
.action-danger { color: #dc2626; }
.action-danger .action-icon { background: #fee2e2; color: #dc2626; }

.confirm-btn {
  display: inline-flex;
  height: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  background: var(--color-slate-100);
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-slate-700);
  transition: transform 0.15s ease;
}
.confirm-btn:active { transform: scale(0.98); }
.confirm-btn:disabled { opacity: 0.6; }
.confirm-btn-danger {
  color: #fff;
  background: linear-gradient(135deg, #ef4444, #b91c1c);
}

.sheet-enter-active, .sheet-leave-active { transition: transform 0.28s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.2s ease; }
.sheet-enter-from, .sheet-leave-to { transform: translateY(100%); }
@media (min-width: 640px) {
  .sheet-enter-from, .sheet-leave-to { transform: scale(0.96); opacity: 0; }
}
.toast-enter-active, .toast-leave-active { transition: transform 0.25s ease, opacity 0.2s ease; }
.toast-enter-from, .toast-leave-to { transform: translateY(8px); opacity: 0; }
@media (prefers-reduced-motion: reduce) {
  .sheet-enter-active, .sheet-leave-active, .toast-enter-active, .toast-leave-active { transition: none; }
}
</style>
