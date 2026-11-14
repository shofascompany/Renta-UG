<script setup>
// Main admin page header: a deep gradient banner on every screen size.
//   eyebrow / title / subtitle, actions in the default slot, an optional #stats row underneath,
//   and #back for a back link above the title.
defineProps({ eyebrow: String, title: String, subtitle: String, tone: { type: String, default: 'teal' } }) // teal | violet | amber | sky
</script>

<template>
  <header class="super-hero rise relative mb-6 overflow-hidden rounded-[1.75rem] p-5 text-white sm:p-7" :class="`tone-${tone}`">
    <div class="grid-bg" aria-hidden="true" />
    <div class="orb" aria-hidden="true" />
    <div class="orb orb-2" aria-hidden="true" />
    <div class="relative">
      <slot name="back" />
      <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div class="min-w-0">
          <p v-if="eyebrow" class="chip inline-flex max-w-full items-center gap-1.5 truncate rounded-full px-3 py-1 text-[11px] font-semibold tracking-[0.14em] uppercase">
            <span class="dot" /> {{ eyebrow }}
          </p>
          <h1 class="mt-3 text-[1.75rem] leading-tight font-bold tracking-tight sm:text-[2rem]">{{ title }}</h1>
          <p v-if="subtitle" class="mt-1.5 max-w-2xl text-sm leading-relaxed text-white/80">{{ subtitle }}</p>
        </div>
        <div v-if="$slots.default" class="actions flex flex-wrap gap-2.5">
          <slot />
        </div>
      </div>
      <div v-if="$slots.stats" class="mt-6"><slot name="stats" /></div>
    </div>
  </header>
</template>

<style scoped>
.super-hero {
  --color-white: #fff;
  box-shadow: 0 24px 50px -28px rgb(2 6 23 / 0.75);
}
.tone-teal { background: linear-gradient(135deg, #0b1324 0%, #0a3b38 45%, #0f766e 80%, #14b8a6 120%); }
.tone-violet { background: linear-gradient(135deg, #0b1324 0%, #2e1065 50%, #6d28d9 100%); }
.tone-amber { background: linear-gradient(135deg, #1c1407 0%, #78350f 50%, #d97706 110%); }
.tone-sky { background: linear-gradient(135deg, #0b1324 0%, #0c4a6e 50%, #0284c7 100%); }
.grid-bg {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgb(255 255 255 / 0.05) 1px, transparent 1px),
    linear-gradient(90deg, rgb(255 255 255 / 0.05) 1px, transparent 1px);
  background-size: 30px 30px;
  mask-image: linear-gradient(180deg, #000, transparent 85%);
}
.orb {
  position: absolute;
  top: -55%;
  right: -12%;
  width: 24rem;
  height: 24rem;
  border-radius: 9999px;
  background: radial-gradient(circle, rgb(45 212 191 / 0.35), transparent 65%);
  animation: drift 16s ease-in-out infinite alternate;
}
.tone-violet .orb { background: radial-gradient(circle, rgb(167 139 250 / 0.35), transparent 65%); }
.tone-amber .orb { background: radial-gradient(circle, rgb(251 191 36 / 0.35), transparent 65%); }
.tone-sky .orb { background: radial-gradient(circle, rgb(56 189 248 / 0.35), transparent 65%); }
.orb-2 {
  top: auto;
  right: auto;
  bottom: -70%;
  left: -15%;
  width: 20rem;
  height: 20rem;
  background: radial-gradient(circle, rgb(255 255 255 / 0.1), transparent 65%);
  animation-duration: 20s;
}
.chip {
  background: rgb(255 255 255 / 0.12);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18);
}
.dot {
  width: 0.4rem;
  height: 0.4rem;
  border-radius: 9999px;
  background: #5eead4;
  box-shadow: 0 0 0 3px rgb(94 234 212 / 0.25);
}
.actions :slotted(.btn-primary) {
  background: #fff;
  color: #0a3b38;
  box-shadow: 0 8px 18px -8px rgb(0 0 0 / 0.45);
}
.actions :slotted(.btn-secondary) {
  background: rgb(255 255 255 / 0.12);
  border-color: rgb(255 255 255 / 0.25);
  color: #fff;
}
.actions :slotted(.btn-secondary:hover) { background: rgb(255 255 255 / 0.2); }
.actions :slotted(*) { height: 2.75rem; border-radius: 0.95rem; font-weight: 600; }
@keyframes drift {
  to { transform: translate(-2.5rem, 1.5rem) scale(1.1); }
}
.rise { animation: rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards; }
@keyframes rise { from { opacity: 0; transform: translateY(10px); } }
@media (prefers-reduced-motion: reduce) {
  .orb, .rise { animation: none; }
}
</style>
