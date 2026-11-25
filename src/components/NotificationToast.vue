<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Bell, Bug, CalendarClock, Clock, Crown, DoorOpen, Megaphone, ShieldAlert, Sparkles, UserPlus, Wallet, Wrench, X } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import { playChime, unlockSound } from '@/lib/sound'

// Like a phone: a new notification drops down from the top with a sound, stays a few seconds,
// then slides back up and waits in the notification centre (the bell). Tap it to open it,
// swipe it up to dismiss it.
const auth = useAuthStore()
const rental = useRentalStore()
const router = useRouter()

const SHOW_MS = 5500
const FRESH_MS = 3 * 60 * 1000 // only things that have just arrived

// Tenant: their notifications. Landlord / main admin: their inbox.
const items = computed(() => {
  if (auth.isTenant) {
    const t = rental.tenantForUser(auth.user?.id)
    return t ? rental.notificationsForTenant(t.id).filter((n) => !n.tenantHidden) : []
  }
  return rental.staff_notifications
})

const seen = new Set()
let primed = false
const queue = ref([])
const current = ref(null)
let timer = null

watch(
  () => [rental.loaded, items.value.map((n) => n.id).join(',')],
  () => {
    if (!rental.loaded) return
    const list = items.value
    if (!primed) {
      list.forEach((n) => seen.add(n.id)) // what was there at sign-in is not "new"
      primed = true
      return
    }
    const fresh = list
      .filter((n) => !seen.has(n.id))
      .filter((n) => !n.read && Date.now() - new Date(n.createdAt).getTime() < FRESH_MS)
      .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))
    list.forEach((n) => seen.add(n.id))
    if (!fresh.length) return
    queue.value.push(...fresh)
    if (!current.value) next()
  },
  { immediate: true },
)

function next() {
  clearTimeout(timer)
  current.value = queue.value.shift() ?? null
  if (!current.value) return
  playChime()
  if (navigator.vibrate) navigator.vibrate([90, 60, 90])
  timer = setTimeout(hide, SHOW_MS)
}
function hide() {
  clearTimeout(timer)
  current.value = null
  setTimeout(next, 450) // let it slide away before the next one drops
}
function open() {
  const n = current.value
  hide()
  if (!n) return
  router.push({ path: auth.isTenant ? '/tenant/notifications' : auth.isSuperadmin ? '/admin2026/inbox' : '/landlord/inbox', query: { open: n.id } })
}

// Swipe up to dismiss
const dragY = ref(0)
let startY = null
const down = (e) => {
  startY = e.clientY
  held.value = true
  clearTimeout(timer)
}
const move = (e) => {
  if (startY !== null) dragY.value = Math.min(0, e.clientY - startY)
}
const up = () => {
  if (startY === null) return
  const swiped = dragY.value < -35
  const tapped = Math.abs(dragY.value) < 4
  startY = null
  held.value = false
  dragY.value = 0
  if (swiped) hide()
  else if (tapped) open()
  else timer = setTimeout(hide, 2500)
}

// Icon and colour by kind, the same meaning as in the notification lists
const KINDS = {
  payment: [Wallet, 'emerald'], cash: [Wallet, 'amber'], status: [Clock, 'sky'], reminder: [CalendarClock, 'amber'], rent_due: [CalendarClock, 'red'],
  general: [Megaphone, 'brand'], admin: [Megaphone, 'brand'], maintenance: [Wrench, 'amber'], security: [ShieldAlert, 'red'], error: [Bug, 'red'],
  welcome: [Sparkles, 'brand'], tenant: [UserPlus, 'brand'], move_out: [DoorOpen, 'amber'], subscription: [Crown, 'amber'],
}
const look = computed(() => KINDS[current.value?.type] ?? [Bell, 'brand'])
const held = ref(false) // finger on it: the timer waits
const ago = computed(() => {
  const s = (Date.now() - new Date(current.value?.createdAt ?? Date.now()).getTime()) / 1000
  return s < 60 ? 'now' : `${Math.floor(s / 60)}m ago`
})

onMounted(() => {
  window.addEventListener('pointerdown', unlockSound, { once: true, capture: true })
})
onBeforeUnmount(() => clearTimeout(timer))
</script>

<template>
  <Teleport to="body">
    <Transition name="drop">
      <div
        v-if="current"
        :key="current.id"
        class="toast-wrap pointer-events-none fixed inset-x-0 top-0 z-[95] flex justify-center px-3 pt-[max(0.6rem,env(safe-area-inset-top))]"
      >
        <div
          class="toast pointer-events-auto flex w-full max-w-md cursor-pointer touch-none items-start gap-3 rounded-[1.4rem] p-3.5 select-none"
          :class="[`toast-${look[1]}`, held && 'toast-held']"
          :style="dragY ? { transform: `translateY(${dragY}px)`, transition: 'none' } : null"
          role="status"
          aria-live="polite"
          @pointerdown="down"
          @pointermove="move"
          @pointerup="up"
          @pointercancel="up"
        >
          <span class="app-icon"><component :is="look[0]" class="size-5" /></span>
          <div class="min-w-0 flex-1">
            <div class="flex items-baseline justify-between gap-2">
              <p class="truncate text-[11px] font-bold tracking-[0.1em] text-slate-500 uppercase">Renta UG</p>
              <p class="shrink-0 text-[11px] font-medium text-slate-400">{{ ago }}</p>
            </div>
            <p class="mt-0.5 truncate text-[15px] font-semibold text-slate-900">{{ current.title }}</p>
            <p class="mt-0.5 line-clamp-2 text-[13px] leading-snug text-slate-600">{{ current.body }}</p>
          </div>
          <button type="button" class="toast-x" aria-label="Dismiss" @pointerdown.stop @pointerup.stop @click.stop="hide"><X class="size-3.5" stroke-width="2.5" /></button>
          <span class="life" :style="{ animationDuration: `${SHOW_MS}ms` }" aria-hidden="true" />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.toast {
  --tone: #14b8a6;
  --tone-deep: #0a3b38;
  position: relative;
  overflow: hidden;
  background: var(--menu-bg);
  box-shadow: 0 22px 48px -18px rgb(15 23 42 / 0.5), 0 0 0 1px var(--menu-line);
  transition: transform 0.25s ease;
}
/* A soft wash of the kind's colour from the icon's corner */
.toast::before { content: ''; position: absolute; inset: 0; pointer-events: none; background: radial-gradient(14rem 7rem at 0% 0%, color-mix(in srgb, var(--tone) 16%, transparent), transparent 70%); }
.toast > * { position: relative; }
.toast-emerald { --tone: #10b981; --tone-deep: #065f46; }
.toast-amber { --tone: #f59e0b; --tone-deep: #92400e; }
.toast-red { --tone: #ef4444; --tone-deep: #7f1d1d; }
.toast-sky { --tone: #0ea5e9; --tone-deep: #0c4a6e; }
.app-icon {
  display: flex;
  width: 2.6rem;
  height: 2.6rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.9rem;
  color: #fff;
  background: linear-gradient(140deg, var(--tone), var(--tone-deep));
  box-shadow: 0 8px 16px -8px var(--tone);
}
.toast-x {
  display: flex;
  width: 1.75rem;
  height: 1.75rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  margin: -0.15rem -0.15rem 0 0;
  border-radius: 9999px;
  color: var(--color-slate-500);
  background: var(--color-slate-100);
}
.toast-x:hover { color: var(--color-slate-900); background: var(--color-slate-200); }
/* Time left before it slides away */
.toast > .life { position: absolute; bottom: 0; left: 0; width: 100%; height: 3px; transform-origin: left; background: linear-gradient(90deg, var(--tone-deep), var(--tone)); animation: toast-life linear forwards; }
.toast-held .life { animation-play-state: paused; }
@keyframes toast-life { to { transform: scaleX(0); } }
.drop-enter-active { transition: transform 0.5s cubic-bezier(0.2, 1.2, 0.35, 1), opacity 0.3s ease; }
.drop-leave-active { transition: transform 0.35s cubic-bezier(0.55, 0, 0.75, 0.2), opacity 0.3s ease; }
.drop-enter-from, .drop-leave-to { transform: translateY(-120%); opacity: 0; }
@media (prefers-reduced-motion: reduce) {
  .drop-enter-active, .drop-leave-active { transition: opacity 0.2s ease; }
  .drop-enter-from, .drop-leave-to { transform: none; }
}
</style>
