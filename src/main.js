import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './assets/main.css'
import { registerServiceWorker } from './lib/push'
import { initTheme } from './lib/theme'
import { installAutoCapitalize } from './lib/autoCapitalize'
import { installNoZoom } from './lib/noZoom'
import { startCounting } from './lib/installs'
import { useAuthStore } from './stores/auth'
import { installErrorReporting } from './lib/errorReporter'
import { clearAppOnly, watchInstall } from './lib/installApp'

initTheme() // light / dark mode follows the device automatically
installNoZoom() // pages stay at the phone's size: scroll up/down only, no zooming
installAutoCapitalize() // capital first letters; names get a capital on every word
registerServiceWorker() // enables phone notifications + "install app"
watchInstall() // catches "the app can be installed" / "the app was installed"
clearAppOnly() // no phone has to use the app instead of the website any more

const app = createApp(App)
app.use(createPinia())
app.use(router)
installErrorReporting(app, router) // errors fix themselves where possible, the rest go to the main admin
app.mount('#app')
startCounting(router, useAuthStore()) // visits and downloads, for the main admin
