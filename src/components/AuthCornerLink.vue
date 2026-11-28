<script setup>
import { isInstalledApp } from '@/lib/runtime'

// Small pill link in the top-left corner of the sign-in and sign-up pages:
//   sign in → "Home" (the landing site) · sign up → "← Sign in" (back to the sign-in page)
// Browser only: inside the installed app (home-screen app, Play Store / App Store app) it isn't shown. There is no
// landing site there anyway: "/" goes straight to sign in (router/index.js, same check).
defineProps({ to: { type: [String, Object], required: true } })
const show = !isInstalledApp()
</script>

<template>
  <RouterLink
    v-if="show"
    :to="to"
    class="corner-link absolute z-20 inline-flex h-9 items-center gap-1.5 rounded-full border border-slate-200 bg-white/90 pr-3.5 pl-3 text-sm font-medium text-slate-600 shadow-sm transition-colors hover:bg-white hover:text-slate-900"
  >
    <slot />
  </RouterLink>
</template>

<style scoped>
/* Top-left corner, clear of a phone's notch. Ends where the page content starts (py-12), so it never covers the logo. */
.corner-link {
  top: max(0.75rem, env(safe-area-inset-top));
  left: max(0.75rem, env(safe-area-inset-left));
}
@media (min-width: 640px) {
  .corner-link {
    top: max(1.25rem, env(safe-area-inset-top));
    left: max(1.25rem, env(safe-area-inset-left));
  }
}
/* Pressed feedback on touch, like the other buttons */
@media (hover: none) {
  .corner-link:active { transform: scale(0.98); }
}
</style>
