import { fileURLToPath, URL } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

const root = fileURLToPath(new URL('.', import.meta.url))

export default defineConfig(({ mode }) => {
  // Local dev normally reads only .env / .env.development. Fall back to the public values in
  // .env.production (Supabase URL + anon key) so `npm run dev` works without copying them.
  const current = loadEnv(mode, root, 'VITE_')
  const production = loadEnv('production', root, 'VITE_')
  for (const [key, value] of Object.entries(production)) {
    if (!current[key]) process.env[key] = value
  }

  return {
    plugins: [vue(), tailwindcss()],
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
    server: {
      // Forward API calls to the Express server (npm run server)
      proxy: { '/api': 'http://localhost:4242' },
    },
  }
})
