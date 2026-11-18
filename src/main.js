import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './assets/main.css'
import { registerServiceWorker } from './lib/push'
import { initTheme } from './lib/theme'
import { installAutoCapitalize } from './lib/autoCapitalize'
import { installNoZoom } from './lib/noZoom'
import { trackInstall } from './lib/installs'
import { installErrorReporting } from './lib/errorReporter'

initTheme() // light / dark mode follows the device automatically
installNoZoom() // pages stay at the phone's size: scroll up/down only, no zooming
installAutoCapitalize() // capital first letters; names get a capital on every word
registerServiceWorker() // enables phone notifications + "install app"

const app = createApp(App)
app.use(createPinia())
app.use(router)
installErrorReporting(app, router) // errors fix themselves where possible, the rest go to the main admin
app.mount('#app')
trackInstall() // counts this phone once for the main admin's Downloads page
