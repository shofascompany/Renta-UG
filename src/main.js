import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './assets/main.css'
import { registerServiceWorker } from './lib/push'

registerServiceWorker() // enables phone notifications + "install app"

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.mount('#app')
