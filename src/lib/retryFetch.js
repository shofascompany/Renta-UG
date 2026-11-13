// A fetch wrapper that survives flaky connections (used by the browser and the server).
//
// - Every attempt has a timeout, so requests can't hang forever.
// - Reads (GET/HEAD) are retried on any network error.
// - Writes are retried only when the request provably never reached the server
//   (connect timeout / refused / DNS failure), so nothing is ever saved twice.

const NEVER_SENT = new Set(['UND_ERR_CONNECT_TIMEOUT', 'ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'ENETUNREACH', 'EHOSTUNREACH'])

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

export function retryFetch({ retries = 3, timeoutMs = 20000, baseFetch } = {}) {
  return async function fetchWithRetry(input, init = {}) {
    const doFetch = baseFetch ?? globalThis.fetch
    const method = (init.method ?? (typeof Request !== 'undefined' && input instanceof Request ? input.method : 'GET')).toUpperCase()
    const isRead = method === 'GET' || method === 'HEAD'

    for (let attempt = 0; ; attempt++) {
      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(new Error('Request timed out')), timeoutMs)
      const forwardAbort = () => controller.abort(init.signal.reason)
      init.signal?.addEventListener('abort', forwardAbort)

      try {
        return await doFetch(input, { ...init, signal: controller.signal })
      } catch (err) {
        if (init.signal?.aborted) throw err // cancelled by the caller
        const neverSent = NEVER_SENT.has(err?.cause?.code)
        if (!(isRead || neverSent) || attempt >= retries) throw err
        await sleep(400 * 2 ** attempt) // 0.4s, 0.8s, 1.6s
      } finally {
        clearTimeout(timer)
        init.signal?.removeEventListener('abort', forwardAbort)
      }
    }
  }
}

// True for "couldn't reach the server" errors from fetch / supabase-js.
export function isNetworkError(err) {
  const msg = `${err?.message ?? ''} ${err?.name ?? ''}`
  return (
    err?.status === 0 ||
    /failed to fetch|fetch failed|networkerror|network request failed|load failed|timed out|AuthRetryableFetchError/i.test(msg)
  )
}

export const NETWORK_MESSAGE = 'Connection problem. Please check your internet and try again.'
