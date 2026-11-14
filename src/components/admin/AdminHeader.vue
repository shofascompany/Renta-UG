<script setup>
// Console page header. Computers: plain title row with actions on the right.
// Phones: a gradient banner with roomy, full-width action buttons.
// compact = one small action button on phones instead of a full-width one
defineProps({ eyebrow: String, title: String, subtitle: String, compact: Boolean })
</script>

<template>
  <header class="admin-hero mb-6 flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between lg:gap-4">
    <div class="relative min-w-0" :class="$slots.corner && 'pr-16 lg:pr-0'">
      <p v-if="eyebrow" class="eyebrow text-xs font-semibold tracking-[0.12em] text-brand-700 uppercase">{{ eyebrow }}</p>
      <h1 class="title mt-1 text-[1.65rem] leading-tight font-bold tracking-tight text-slate-900 lg:text-[1.75rem]">{{ title }}</h1>
      <p v-if="subtitle" class="sub mt-1.5 text-sm leading-relaxed text-slate-500">{{ subtitle }}</p>
    </div>
    <div v-if="$slots.default || $slots.corner" class="contents lg:flex lg:items-center lg:gap-2">
      <div
        v-if="$slots.default"
        class="actions relative gap-2.5 lg:flex lg:flex-wrap lg:gap-2"
        :class="compact ? 'compact flex' : 'grid grid-cols-[repeat(auto-fit,minmax(0,1fr))]'"
      >
        <slot />
      </div>
      <!-- corner: phones → top-right of the gradient card; computers → with the other actions -->
      <div v-if="$slots.corner" class="absolute top-4 right-4 z-10 lg:static">
        <slot name="corner" />
      </div>
    </div>
  </header>
</template>

<style scoped>
@media (max-width: 1023.98px) {
  .admin-hero {
    --color-white: #fff;
    position: relative;
    overflow: hidden;
    isolation: isolate;
    border-radius: 1.5rem;
    padding: 1.5rem 1.25rem 1.25rem;
    color: #fff;
    background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
    box-shadow: 0 18px 40px -24px rgb(10 59 56 / 0.6);
  }
  /* faint grid + soft light */
  .admin-hero::before {
    content: '';
    position: absolute;
    inset: 0;
    z-index: -1;
    background-image:
      linear-gradient(rgb(255 255 255 / 0.06) 1px, transparent 1px),
      linear-gradient(90deg, rgb(255 255 255 / 0.06) 1px, transparent 1px);
    background-size: 26px 26px;
    mask-image: linear-gradient(180deg, #000, transparent 85%);
  }
  .admin-hero::after {
    content: '';
    position: absolute;
    z-index: -1;
    top: -50%;
    right: -25%;
    width: 18rem;
    height: 18rem;
    border-radius: 9999px;
    background: radial-gradient(circle, rgb(255 255 255 / 0.2), transparent 65%);
  }
  .eyebrow {
    display: inline-flex;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    border-radius: 9999px;
    padding: 0.3rem 0.7rem;
    font-size: 0.6875rem;
    color: #fff;
    background: rgb(255 255 255 / 0.14);
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.2);
  }
  .title { margin-top: 0.75rem; font-size: 1.75rem; color: #fff; }
  .sub { color: rgb(255 255 255 / 0.85); font-size: 0.9rem; }
  .actions { margin-top: 0.25rem; }

  /* Action buttons on the gradient */
  .actions :slotted(*) {
    height: 2.875rem;
    width: 100%;
    border-radius: 0.875rem;
    font-weight: 600;
  }
  .actions :slotted(.btn-primary) {
    background: #fff;
    color: #0a3b38;
    box-shadow: 0 6px 16px -6px rgb(0 0 0 / 0.35);
  }
  .actions :slotted(.btn-secondary) {
    background: rgb(255 255 255 / 0.12);
    border-color: rgb(255 255 255 / 0.25);
    color: #fff;
  }
  .actions :slotted(.btn-secondary:hover) { background: rgb(255 255 255 / 0.2); }

  /* Compact: a neat pill sized to its words, not the full width */
  .actions.compact :slotted(*) {
    width: auto;
    height: 2.75rem;
    padding: 0 1.25rem 0 1rem;
    border-radius: 9999px;
    font-size: 0.9rem;
  }
}

/* Compact pill also on computers */
@media (min-width: 1024px) {
  .actions.compact :slotted(*) { border-radius: 9999px; padding-inline: 1.1rem; }
}
</style>
