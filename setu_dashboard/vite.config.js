import { readFileSync } from 'node:fs'
import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// The security headers are defined ONCE, in vercel.json (what the production host serves), and
// applied here to `vite preview` too, so the exact production header set can be tested locally
// against the real built output (tests/headers.test.mjs).
function vercelHeaders() {
  const config = JSON.parse(readFileSync(new URL('./vercel.json', import.meta.url), 'utf8'))
  const out = {}
  for (const rule of config.headers || []) {
    if (rule.source === '/(.*)') for (const h of rule.headers) out[h.key] = h.value
  }
  return out
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'VITE_')
  return {
    plugins: [react()],
    // Only these three values are compiled in -- individually. The source never touches the whole
    // `import.meta.env` object, because Vite inlines EVERY VITE_* variable when it does (which
    // would publish any secret someone mistakenly put in a VITE_ variable).
    define: {
      __DEMO_MODE__: JSON.stringify(env.VITE_DEMO_MODE === 'true'),
      __BACKEND_URL__: JSON.stringify((env.VITE_BACKEND_URL || '').trim()),
      __PROD_BUILD__: JSON.stringify(mode === 'production'),
    },
    preview: { headers: vercelHeaders() },
  }
})
