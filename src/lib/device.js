// A readable name for this device, used in the "New sign-in" notification,
// e.g. "Samsung SM-A515F (Android) · Chrome", "iPhone · Safari", "Windows computer · Edge".

function browserName(ua) {
  if (/Edg(e|A|iOS)?\//.test(ua)) return 'Edge'
  if (/OPR\/|Opera/.test(ua)) return 'Opera'
  if (/SamsungBrowser/.test(ua)) return 'Samsung Internet'
  if (/Firefox|FxiOS/.test(ua)) return 'Firefox'
  if (/CriOS|Chrome/.test(ua)) return 'Chrome'
  if (/Safari/.test(ua)) return 'Safari'
  return 'a browser'
}

function prettyModel(model) {
  if (!model || model === 'K') return ''
  if (/^SM-/i.test(model)) return `Samsung ${model}`
  return model
}

export async function deviceName() {
  try {
    const ua = navigator.userAgent
    let model = ''
    try {
      // Chrome on Android hides the phone model in the user agent but shares it here
      const hints = await navigator.userAgentData?.getHighEntropyValues?.(['model'])
      model = hints?.model ?? ''
    } catch {
      /* not supported */
    }

    let device
    if (/iPhone/.test(ua)) device = 'iPhone'
    else if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) device = 'iPad'
    else if (/Android/.test(ua)) {
      const fromUa = ua.match(/Android [\d.]+; ([^;)]+?)(?: Build|\))/)?.[1]
      const name = prettyModel(model) || prettyModel(fromUa)
      device = name ? `${name} (Android)` : 'Android phone'
    } else if (/Windows/.test(ua)) device = 'Windows computer'
    else if (/CrOS/.test(ua)) device = 'Chromebook'
    else if (/Macintosh|Mac OS/.test(ua)) device = 'Mac'
    else if (/Linux/.test(ua)) device = 'Linux computer'
    else device = 'a device'

    return `${device} · ${browserName(ua)}`
  } catch {
    return ''
  }
}
