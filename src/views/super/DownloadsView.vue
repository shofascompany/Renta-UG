<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Smartphone, Apple, Download, TriangleAlert } from '@lucide/vue'
import { supabase } from '@/lib/supabase'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'

// Main admin: live count of the phones using the Google Play app, the App Store app and the web app
// added to a home screen. Each phone registers itself the first time the app opens (see lib/installs.js),
// so the numbers come from the database and update by themselves. Nothing is typed in.
const PLATFORMS = {
  android: { label: 'Android', store: 'Google Play', icon: Smartphone, tile: 'tile-teal' },
  ios: { label: 'iPhone & iPad', store: 'App Store', icon: Apple, tile: 'tile-sky' },
}

const counts = ref({}) // { android: { total, active }, … }
const loading = ref(true)
const missing = ref(false) // database/40_app_installs.sql not run yet
const error = ref('')

async function load() {
  const since = new Date(Date.now() - 30 * 86400_000).toISOString()
  const next = {}
  try {
    for (const key of Object.keys(PLATFORMS)) {
      const [all, active] = await Promise.all([
        supabase.from('app_installs').select('*', { count: 'exact', head: true }).eq('platform', key),
        supabase.from('app_installs').select('*', { count: 'exact', head: true }).eq('platform', key).gte('last_seen', since),
      ])
      const err = all.error || active.error
      if (err) throw err
      next[key] = { total: all.count ?? 0, active: active.count ?? 0 }
    }
    counts.value = next
    missing.value = false
    error.value = ''
  } catch (err) {
    missing.value = /schema cache|does not exist|could not find the table/i.test(err.message)
    error.value = missing.value ? '' : err.message
  }
  loading.value = false
}

let channel
let timer
let pending
const soon = () => { clearTimeout(pending); pending = setTimeout(load, 600) }
onMounted(() => {
  load()
  channel = supabase.channel('installs-live').on('postgres_changes', { event: '*', schema: 'public', table: 'app_installs' }, soon).subscribe()
  timer = setInterval(load, 60_000) // backup in case the live connection drops
})
onBeforeUnmount(() => {
  clearTimeout(pending)
  clearInterval(timer)
  if (channel) supabase.removeChannel(channel)
})

const total = computed(() => Object.values(counts.value).reduce((n, c) => n + c.total, 0))
const fmt = (n) => Number(n || 0).toLocaleString()
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <SuperHero eyebrow="Growth" title="App downloads" subtitle="Live from the database: Google Play and the App Store." />

    <p v-if="missing" class="mb-4 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
      <TriangleAlert class="mt-0.5 size-4 shrink-0" />
      <span>Downloads aren't set up yet. Run <strong>database/40_app_installs.sql</strong> in Supabase → SQL Editor, then refresh.</span>
    </p>
    <p v-else-if="error" class="mb-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>

    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <StatTile label="Total installs" :value="loading ? '…' : fmt(total)" hint="Android + iPhone" :icon="Download" tile="tile-violet" />
      <StatTile v-for="(p, key) in PLATFORMS" :key="key" :label="p.label" :value="loading ? '…' : fmt(counts[key]?.total)" :hint="p.store" :icon="p.icon" :tile="p.tile" />
    </div>

    <h2 class="section-title mt-6">By store</h2>
    <div class="sheet divide-y divide-slate-100">
      <div v-for="(p, key) in PLATFORMS" :key="key" class="flex items-center gap-3.5 px-4 py-4 sm:px-5">
        <span class="icon-tile" :class="p.tile"><component :is="p.icon" class="size-[1.3rem]" /></span>
        <div class="min-w-0 flex-1">
          <p class="font-medium text-slate-900">{{ p.store }}</p>
          <p class="text-xs text-slate-500">{{ p.label }}</p>
        </div>
        <div class="text-right">
          <p class="text-lg font-bold text-slate-900 tabular-nums">{{ fmt(counts[key]?.total) }}</p>
          <p class="text-xs text-slate-500">{{ fmt(counts[key]?.active) }} active this month</p>
        </div>
      </div>
    </div>

    <p class="mt-4 text-xs leading-relaxed text-slate-500">
      A phone is counted once, the first time its app opens. "Active this month" means it was opened in the last 30 days.
      Opening the website in a normal browser tab is not counted. Google Play Console and App Store Connect may show
      slightly different totals, because they also count downloads that were never opened.
    </p>
  </div>
</template>
