import { onBeforeUnmount, onMounted, ref } from 'vue'
import { supabase } from '@/lib/supabase'

// Main admin: visits, downloads and ratings, live from the database (database/58 + 59).
//   fn      the database function to read: site_stats | site_details | admin_ratings
//   tables  read again the moment one of these changes
// Live in three ways, so a number is never old: the database tells the page (under a second), the page asks again
// every 20 seconds, and it asks when the internet or the tab comes back.
let opened = 0 // every page has its own live channel
export function useSiteStats(fn, tables) {
  const data = ref(null)
  const missing = ref(false) // database/update_existing.sql not run yet
  const error = ref('')
  const live = ref(false) // the database is connected and telling us about changes
  const updatedAt = ref(null)

  let asked = 0
  async function load() {
    const mine = ++asked
    const res = await supabase.rpc(fn)
    if (mine !== asked) return // a newer answer is on its way
    if (!res.error) {
      data.value = res.data
      updatedAt.value = new Date()
      missing.value = false
      error.value = ''
      return
    }
    missing.value = /schema cache|does not exist|could not find/i.test(res.error.message)
    error.value = missing.value ? '' : /fetch|network/i.test(res.error.message) ? 'No internet connection. The numbers update when it is back.' : res.error.message
  }

  let channel
  let timer
  let pending
  const soon = () => {
    clearTimeout(pending)
    pending = setTimeout(load, 500)
  }
  const onReturn = () => document.visibilityState === 'visible' && soon()
  const onOffline = () => (live.value = false)
  onMounted(() => {
    load()
    channel = supabase.channel(`live-${fn}-${++opened}`)
    for (const table of tables) channel.on('postgres_changes', { event: '*', schema: 'public', table }, soon)
    channel.subscribe((status) => {
      const was = live.value
      live.value = status === 'SUBSCRIBED'
      if (live.value && !was) soon() // whatever happened while it was not connected
    })
    timer = setInterval(() => document.visibilityState === 'visible' && load(), 20_000)
    document.addEventListener('visibilitychange', onReturn)
    window.addEventListener('online', soon)
    window.addEventListener('offline', onOffline)
  })
  onBeforeUnmount(() => {
    clearTimeout(pending)
    clearInterval(timer)
    document.removeEventListener('visibilitychange', onReturn)
    window.removeEventListener('online', soon)
    window.removeEventListener('offline', onOffline)
    if (channel) supabase.removeChannel(channel)
  })
  return { data, missing, error, live, updatedAt, load }
}
