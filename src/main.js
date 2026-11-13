import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './assets/main.css'
import { registerServiceWorker } from './lib/push'
import { initTheme } from './lib/theme'

initTheme() // light / dark mode follows the device automatically
registerServiceWorker() // enables phone notifications + "install app"

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.mount('#app')
