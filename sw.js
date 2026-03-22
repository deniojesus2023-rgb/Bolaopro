const CACHE = 'bolaopro-v2'
const ASSETS = ['/', '/index.html', '/shared.css', '/design-system.css', '/app.js', '/config.js']

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)))
  self.skipWaiting()
})

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ))
  self.clients.claim()
})

self.addEventListener('fetch', e => {
  if (e.request.url.includes('supabase.co')) return // deixa Supabase passar direto
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request, { redirect: 'follow' }).then(res => {
      // Não cacheia redirects nem respostas opacas (Safari rejeita redirects vindos do SW)
      if (res.ok && res.type !== 'opaqueredirect' && e.request.method === 'GET') {
        const clone = res.clone()
        caches.open(CACHE).then(c => c.put(e.request, clone))
      }
      return res
    }))
  )
})
