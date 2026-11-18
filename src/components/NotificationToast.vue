<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Bell, Wallet, Megaphone, ShieldAlert, Bug, Clock } from '@lucide/vue'
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
  if (auth.isTenant) router.push(n.type === 'payment' || n.type === 'status' ? '/tenant/payments' : '/tenant/notifications')
  else router.push(n.url || (auth.isSuperadmin ? '/admin2026/inbox' : '/landlord/inbox'))
}

// Swipe up to dismiss
const dragY = ref(0)
let startY = null
const down = (e) => {
  startY = e.clientY
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
  dragY.value = 0
  if (swiped) hide()
  else if (tapped) open()
  else timer = setTimeout(hide, 2500)
}

const ICONS = { payment: Wallet, status: Clock, general: Megaphone, security: ShieldAlert, error: Bug, cash: Wallet }
const icon = computed(() => ICONS[current.value?.type] ?? Bell)
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
        class="toast-wrap pointer-events-none fixed inset-x-0 top-0 z-[70] flex justify-center px-3 pt-[max(0.6rem,env(safe-area-inset-top))]"
      >
        <div
          class="toast pointer-events-auto flex w-full max-w-md cursor-pointer touch-none items-start gap-3 rounded-[1.4rem] p-3.5 select-none"
          :style="dragY ? { transform: `translateY(${dragY}px)`, transition: 'none' } : null"
          role="status"
          aria-live="polite"
          @pointerdown="down"
          @pointermove="move"
          @pointerup="up"
          @pointercancel="up"
        >
          <span class="app-icon flex size-10 shrink-0 items-center justify-center rounded-xl text-white">
            <component :is="icon" class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex items-baseline justify-between gap-2">
              <p class="truncate text-[13px] font-semibold text-slate-900">Renta UG</p>
              <p class="shrink-0 text-[11px] text-slate-400">{{ ago }}</p>
            </div>
            <p class="truncate text-[13px] font-medium text-slate-800">{{ current.title }}</p>
            <p class="line-clamp-2 text-[13px] leading-snug text-slate-600">{{ current.body }}</p>
          </div>
          <span class="grabber" aria-hidden="true" />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.toast {
  position: relative;
  background: rgb(255 255 255 / 0.92);
  backdrop-filter: blur(18px) saturate(1.6);
  -webkit-backdrop-filter: blur(18px) saturate(1.6);
  box-shadow: 0 18px 40px -16px rgb(15 23 42 / 0.45), 0 0 0 1px rgb(15 23 42 / 0.06);
  transition: transform 0.25s ease;
}
:global(.dark) .toast { background: rgb(30 41 59 / 0.92); }
.app-icon { background: linear-gradient(140deg, #14b8a6, #0f766e 60%, #0a3b38); box-shadow: 0 6px 14px -8px rgb(15 118 110 / 0.9); }
.grabber {
  position: absolute;
  bottom: 0.35rem;
  left: 50%;
  width: 2.25rem;
  height: 0.25rem;
  margin-left: -1.125rem;
  border-radius: 9999px;
  background: rgb(100 116 139 / 0.3);
}
.drop-enter-active { transition: transform 0.5s cubic-bezier(0.2, 1.2, 0.35, 1), opacity 0.3s ease; }
.drop-leave-active { transition: transform 0.35s cubic-bezier(0.55, 0, 0.75, 0.2), opacity 0.3s ease; }
.drop-enter-from, .drop-leave-to { transform: translateY(-120%); opacity: 0; }
@media (prefers-reduced-motion: reduce) {
  .drop-enter-active, .drop-leave-active { transition: opacity 0.2s ease; }
  .drop-enter-from, .drop-leave-to { transform: none; }
}
</style>
