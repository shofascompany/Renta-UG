import { reactive } from 'vue'

// "Are you sure?" in the app's own design, instead of the browser's grey popup. The card itself is
// ConfirmDialog.vue, mounted once in App.vue.
//
//   await askConfirm({ title, text, confirm, cancel, tone, icon, action })
//     tone    'danger' (red) or 'brand' (teal)
//     action  async work to do on "yes". The card shows it working and keeps any error on screen.
//   → true when confirmed (and the action, if any, worked), false when they backed out
export const confirmState = reactive({ open: false, opts: {}, resolve: null })

export function askConfirm(opts) {
  confirmState.resolve?.(false) // only one question at a time
  return new Promise((resolve) => {
    confirmState.opts = { tone: 'danger', confirm: 'Yes', cancel: 'Cancel', ...opts }
    confirmState.resolve = resolve
    confirmState.open = true
  })
}

export function answerConfirm(yes) {
  const { resolve } = confirmState
  confirmState.resolve = null
  confirmState.open = false
  resolve?.(yes)
}
