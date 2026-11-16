<script setup>
// Soft animated gradient backdrop shared by the sign-in and sign-up pages.
// Sits behind the page content and never takes clicks.
</script>

<template>
  <div class="auth-bg" aria-hidden="true">
    <span class="blob blob-1" />
    <span class="blob blob-2" />
    <span class="blob blob-3" />
  </div>
</template>

<style scoped>
.auth-bg {
  position: fixed;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
  background: linear-gradient(135deg, var(--color-white), color-mix(in srgb, var(--color-brand-50) 45%, white) 50%, var(--color-white));
  background-size: 200% 200%;
  animation: shift 18s ease-in-out infinite;
}
.blob {
  position: absolute;
  border-radius: 9999px;
  filter: blur(80px);
  opacity: 0.18;
}
.blob-1 {
  width: 26rem; height: 26rem; top: -8rem; right: -6rem;
  background: var(--color-brand-100);
  animation: float-a 16s ease-in-out infinite;
}
.blob-2 {
  width: 22rem; height: 22rem; bottom: -7rem; left: -6rem;
  background: var(--color-sky-100);
  animation: float-b 20s ease-in-out infinite;
}
.blob-3 {
  width: 16rem; height: 16rem; top: 40%; left: 55%;
  background: var(--color-brand-50);
  animation: float-c 24s ease-in-out infinite;
}
@keyframes shift { 0%, 100% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } }
@keyframes float-a { 50% { transform: translate(-60px, 70px) scale(1.12); } }
@keyframes float-b { 50% { transform: translate(80px, -60px) scale(1.15); } }
@keyframes float-c { 50% { transform: translate(-90px, -50px) scale(0.9); } }
@media (prefers-reduced-motion: reduce) {
  .auth-bg, .blob { animation: none; }
}
</style>
