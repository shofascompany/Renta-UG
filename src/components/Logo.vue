<script setup>
import LogoMark from './LogoMark.vue'

// `link` (default): the logo is a link to the home page.
// `:link="false"`: a plain picture, for when the logo sits inside a button (e.g. the one that opens the side menu),
// so tapping it does that job instead of following a link.
defineProps({ link: { type: Boolean, default: true } })
</script>

<template>
  <component :is="link ? 'RouterLink' : 'span'" :to="link ? '/' : undefined" class="flex items-center gap-2">
    <LogoMark class="size-7" />
    <span class="text-[17px] font-semibold tracking-tight text-slate-900">Renta<span class="text-brand-600"> UG</span></span>
  </component>
</template>
