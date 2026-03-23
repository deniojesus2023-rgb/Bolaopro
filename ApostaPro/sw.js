const CACHE = 'apostapro-v1'
const STATIC = [
  '/',
  '/index.html',
  '/auth.html',
  '/dashboard.html',
  '/deposito.html',
  '/bolao.html',
  '/app.css',
  '/config.js',
  '/manifest.json'
]

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC)).then(() => self.skipWaiting())
  )
})

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  )
})

self.addEventListener('fetch', e => {
  // Só cacheia GET
  if (e.request.method !== 'GET') return

  // Supabase e CDN: network first
  if (e.request.url.includes('supabase') || e.request.url.includes('cdn.jsdelivr') || e.request.url.includes('fonts.')) {
    e.respondWith(
      fetch(e.request).catch(() => caches.match(e.request))
    )
    return
  }

  // Assets locais: cache first
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached
      return fetch(e.request).then(res => {
        if (res.ok) {
          const clone = res.clone()
          caches.open(CACHE).then(c => c.put(e.request, clone))
        }
        return res
      })
    })
  )
})
