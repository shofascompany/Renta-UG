<script setup>
import { computed } from 'vue'

// A link that opens a social app (WhatsApp) straight in the app on phones, not in the browser.
//   Android: an intent link → opens WhatsApp (or WhatsApp Business) directly; the browser only as a
//            fallback when WhatsApp isn't installed.
//   iPhone:  the whatsapp:// link opens the app; if nothing opens within a moment, the web page does.
//   Computer: wa.me, which hands over to WhatsApp Desktop when it's installed.
// Usage: <AppLink app="whatsapp" phone="256772123456" text="Hello" class="…">WhatsApp</AppLink>
const props = defineProps({
  app: { type: String, default: 'whatsapp' },
  phone: { type: String, default: '' }, // international digits, e.g. 256772123456 (empty = choose a chat)
  text: { type: String, default: '' },
})

const ua = typeof navigator !== 'undefined' ? navigator.userAgent : ''
const isAndroid = /Android/i.test(ua)
const isIOS = /iP(hone|ad|od)/.test(ua) || (typeof navigator !== 'undefined' && navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)

const digits = computed(() => String(props.phone ?? '').replace(/\D/g, ''))
const query = computed(() => [digits.value && `phone=${digits.value}`, props.text && `text=${encodeURIComponent(props.text)}`].filter(Boolean).join('&'))
const web = computed(() => `https://wa.me/${digits.value}${props.text ? `?text=${encodeURIComponent(props.text)}` : ''}`)

const href = computed(() => {
  if (isAndroid) return `intent://send?${query.value}#Intent;scheme=whatsapp;S.browser_fallback_url=${encodeURIComponent(web.value)};end`
  if (isIOS) return `whatsapp://send?${query.value}`
  return web.value
})
const opensApp = computed(() => isAndroid || isIOS)

// iPhone: if WhatsApp isn't installed the app link does nothing, so fall back to the web page
function onClick() {
  if (!isIOS) return
  const started = Date.now()
  const timer = setTimeout(() => {
    if (document.visibilityState === 'visible' && Date.now() - started < 2500) window.location.href = web.value
  }, 1500)
  const left = () => {
    if (document.visibilityState === 'hidden') clearTimeout(timer)
  }
  document.addEventListener('visibilitychange', left, { once: true })
}
</script>

<template>
  <a :href="href" :target="opensApp ? undefined : '_blank'" :rel="opensApp ? undefined : 'noopener'" @click="onClick"><slot /></a>
</template>
