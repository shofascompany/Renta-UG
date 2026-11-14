<script setup>
import { computed } from 'vue'
import { MapPin, BedDouble, Bath, Wallet, Phone, Mail, MessageCircle, Home, Building2, User, DoorOpen, ChevronRight } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX } from '@/utils/format'

// My home: information about the house and the landlord. Nothing else.
const { rental, property } = useTenant()
const owner = computed(() => rental.owner)

const facts = computed(() => [
  { icon: Building2, label: 'Type', value: property.value?.type, capitalize: true },
  { icon: BedDouble, label: 'Beds', value: property.value?.bedrooms },
  { icon: Bath, label: 'Baths', value: property.value?.bathrooms },
])

const ownerInitials = computed(() =>
  (owner.value?.full_name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase(),
)
const whatsapp = computed(() => {
  const d = String(owner.value?.phone ?? '').replace(/\D/g, '')
  if (d.length < 9) return null
  return `https://wa.me/${d.startsWith('0') ? `256${d.slice(1)}` : d.length === 9 ? `256${d}` : d}`
})
</script>

<template>
  <div v-if="property" class="mx-auto max-w-3xl">
    <!-- Banner -->
    <header class="rise banner relative overflow-hidden rounded-3xl px-6 py-8 text-white sm:px-8 sm:py-10" style="--d: 0ms">
      <div class="grid-pattern" aria-hidden="true" />
      <div class="glow" aria-hidden="true" />
      <div class="relative flex items-center gap-4 sm:gap-5">
        <span class="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/25 sm:size-16">
          <Home class="size-7" />
        </span>
        <div class="min-w-0">
          <p class="text-xs font-semibold tracking-[0.14em] text-white/70 uppercase">My home</p>
          <h1 class="mt-1 truncate text-2xl leading-tight font-bold tracking-tight sm:text-3xl">{{ property.name }}</h1>
          <p class="mt-1 flex items-center gap-1.5 truncate text-sm text-white/80">
            <MapPin class="size-4 shrink-0" /> {{ property.location }}
          </p>
        </div>
      </div>
    </header>

    <!-- House information -->
    <section class="rise mt-6" style="--d: 80ms">
      <h2 class="section-title">Property information</h2>
      <div class="sheet p-3 sm:p-4">
        <!-- Rent: the headline figure -->
        <div class="rent-tile flex items-center justify-between gap-3 rounded-2xl px-4 py-3.5">
          <div class="flex items-center gap-3">
            <span class="icon-tile icon-tile-solid"><Wallet class="size-4.5" /></span>
            <p class="text-sm font-medium text-slate-600">Monthly rent</p>
          </div>
          <p class="text-lg font-bold tracking-tight text-slate-900 tabular-nums">{{ formatUGX(property.rent) }}</p>
        </div>

        <!-- Compact facts -->
        <dl class="mt-2.5 grid grid-cols-3 gap-2.5">
          <div v-for="f in facts" :key="f.label" class="fact rounded-2xl px-3 py-3">
            <dt class="flex items-center gap-1.5 text-[11px] font-medium tracking-wide text-slate-500 uppercase">
              <component :is="f.icon" class="size-3.5 text-brand-600" /> {{ f.label }}
            </dt>
            <dd class="mt-1 truncate text-base font-semibold text-slate-900" :class="f.capitalize && 'capitalize'">{{ f.value ?? '—' }}</dd>
          </div>
        </dl>
      </div>
    </section>

    <!-- Landlord information -->
    <section v-if="owner" class="rise mt-6" style="--d: 160ms">
      <h2 class="section-title">Landlord information</h2>
      <div class="sheet">
        <div class="landlord-head flex items-center gap-4 px-5 py-5 sm:px-6">
          <div class="avatar flex size-14 shrink-0 items-center justify-center rounded-2xl text-base font-semibold text-white">
            {{ ownerInitials }}
          </div>
          <div class="min-w-0">
            <p class="truncate text-lg font-semibold text-slate-900">{{ owner.full_name }}</p>
            <p class="text-sm text-slate-500">Property owner</p>
          </div>
        </div>

        <dl class="divide-y divide-slate-100 border-t border-slate-100">
          <div class="flex items-center gap-4 px-5 py-4 sm:px-6">
            <span class="icon-tile"><User class="size-4.5" /></span>
            <dt class="flex-1 text-sm text-slate-500">Name</dt>
            <dd class="max-w-[60%] truncate text-right text-sm font-medium text-slate-900">{{ owner.full_name }}</dd>
          </div>
          <div class="flex items-center gap-4 px-5 py-4 sm:px-6">
            <span class="icon-tile"><Phone class="size-4.5" /></span>
            <dt class="flex-1 text-sm text-slate-500">Phone</dt>
            <dd class="max-w-[60%] truncate text-right text-sm font-medium text-slate-900">{{ owner.phone || '—' }}</dd>
          </div>
          <div class="flex items-center gap-4 px-5 py-4 sm:px-6">
            <span class="icon-tile"><Mail class="size-4.5" /></span>
            <dt class="flex-1 text-sm text-slate-500">Email</dt>
            <dd class="max-w-[60%] truncate text-right text-sm font-medium text-slate-900">{{ owner.email }}</dd>
          </div>
        </dl>

        <div
          class="grid gap-3 border-t border-slate-100 p-5 sm:p-6"
          :class="['grid-cols-1', 'grid-cols-2', 'grid-cols-3'][(owner.phone ? 1 : 0) + (whatsapp ? 1 : 0)]"
        >
          <a v-if="owner.phone" :href="`tel:${owner.phone}`" class="action action-primary"><Phone class="size-4.5" /> Call</a>
          <a v-if="whatsapp" :href="whatsapp" target="_blank" rel="noopener" class="action"><MessageCircle class="size-4.5 text-emerald-600" /> WhatsApp</a>
          <a :href="`mailto:${owner.email}`" class="action"><Mail class="size-4.5 text-sky-600" /> Email</a>
        </div>
      </div>
    </section>

    <!-- Moving out -->
    <RouterLink to="/tenant/leave" class="leave-row rise mt-6 flex items-center gap-4 rounded-2xl border border-slate-200 bg-white px-5 py-4 transition hover:border-red-200 hover:bg-red-50/40" style="--d: 200ms">
      <span class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-red-50 text-red-600"><DoorOpen class="size-5" /></span>
      <span class="min-w-0 flex-1">
        <span class="block font-semibold text-slate-900">Request to leave this room</span>
        <span class="block text-xs text-slate-500">Your landlord approves it. Your history is kept.</span>
      </span>
      <ChevronRight class="size-5 shrink-0 text-slate-300" />
    </RouterLink>
  </div>
</template>

<style scoped>
/* Banner: fixed colours, the same in light and dark mode */
.banner {
  --color-white: #fff;
  background: linear-gradient(120deg, #0284c7 0%, #0f766e 55%, #0a3b38 100%);
  box-shadow: 0 18px 40px -22px rgb(2 84 120 / 0.55);
}
.grid-pattern {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgb(255 255 255 / 0.06) 1px, transparent 1px),
    linear-gradient(90deg, rgb(255 255 255 / 0.06) 1px, transparent 1px);
  background-size: 28px 28px;
  mask-image: linear-gradient(90deg, transparent 0%, #000 70%);
}
.glow {
  position: absolute;
  top: -60%;
  right: -10%;
  width: 20rem;
  height: 20rem;
  border-radius: 9999px;
  background: radial-gradient(circle, rgb(255 255 255 / 0.18), transparent 65%);
  animation: drift 16s ease-in-out infinite alternate;
}

/* Information sheets */
.section-title {
  margin: 0 0.25rem 0.625rem;
  font-size: 0.75rem;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--color-slate-500);
}
.sheet {
  overflow: hidden;
  border-radius: 1.25rem;
  border: 1px solid var(--color-slate-200);
  background: var(--color-white);
  box-shadow: 0 1px 2px rgb(15 23 42 / 0.04);
}
.icon-tile {
  display: flex;
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.75rem;
  color: var(--color-brand-700);
  background: linear-gradient(135deg, var(--color-brand-50), var(--color-sky-50));
  box-shadow: inset 0 0 0 1px var(--color-brand-100);
}
.icon-tile-solid {
  color: #fff;
  background: linear-gradient(135deg, #14b8a6, #0f766e);
  box-shadow: none;
}
.rent-tile {
  background:
    radial-gradient(120% 140% at 100% 0%, var(--color-sky-50) 0%, transparent 60%),
    linear-gradient(120deg, var(--color-brand-50), var(--color-white));
  box-shadow: inset 0 0 0 1px var(--color-brand-100);
}
.fact {
  background: linear-gradient(180deg, var(--color-slate-50), var(--color-white));
  box-shadow: inset 0 0 0 1px var(--color-slate-200);
}
.landlord-head {
  background: linear-gradient(120deg, var(--color-brand-50) 0%, var(--color-white) 75%);
}
.avatar {
  background: linear-gradient(135deg, #14918a, #0a3b38);
}
.action {
  display: inline-flex;
  height: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  border: 1px solid var(--color-slate-200);
  background: linear-gradient(180deg, var(--color-white), var(--color-slate-50));
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-slate-700);
  transition: transform 0.15s ease, border-color 0.15s ease;
}
.action:hover {
  border-color: var(--color-brand-200);
  transform: translateY(-1px);
}
.action:active {
  transform: scale(0.98);
}
.action-primary {
  border: 0;
  color: #fff;
  background: linear-gradient(135deg, #14918a, #0f766e);
  box-shadow: 0 6px 16px -8px rgb(15 118 110 / 0.7);
}

/* Entrance */
.rise {
  animation: rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards;
  animation-delay: var(--d, 0ms);
}
@keyframes rise {
  from { opacity: 0; transform: translateY(10px); }
}
@keyframes drift {
  to { transform: translate(-2rem, 1.5rem) scale(1.1); }
}
@media (prefers-reduced-motion: reduce) {
  .rise, .glow { animation: none; }
}
</style>
