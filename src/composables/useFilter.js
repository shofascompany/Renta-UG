import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'

// One filter (or search box) of a page.
//   const show = useFilter('show', 'all', ['all', 'vacant'])   a fixed set of choices
//   const query = useFilter('q', '')                           free text / any value
// • A link can choose it (?show=vacant), also when the page is already open.
// • Opening something from the list and going Back brings the filter back as it was.
const kept = new Map() // this tab only, never saved
let popped = false
let cameBack = false

// Started once by the router
export function watchBack(router) {
  router.options.history.listen(() => (popped = true)) // the browser's or phone's Back / Forward
  router.afterEach((to) => {
    cameBack = popped
    popped = false
    if (to.meta.guest || to.meta.public) kept.clear() // signed out: nothing is remembered for the next person
  })
}

export function useFilter(key, fallback, allowed = null) {
  const route = useRoute()
  const path = route.path
  const id = `${path}|${key}`
  const linked = () => {
    const v = route.query[key]
    return typeof v === 'string' && allowed?.includes(v) ? v : undefined
  }
  const value = ref((cameBack ? kept.get(id) : undefined) ?? linked() ?? fallback)
  watch(value, (v) => kept.set(id, v), { immediate: true })
  if (allowed) watch(() => route.query[key], () => route.path === path && (value.value = linked() ?? fallback))
  return value
}
