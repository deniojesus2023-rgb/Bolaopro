const CACHE = 'bolaopro-v3'
const ASSETS = [
  '/', '/index.html', '/login.html', '/bolao.html', '/comunidade.html',
  '/configuracoes.html', '/jogos.html', '/meus-boloes.html', '/perfil.html',
  '/ranking.html', '/404.html',
  '/shared.css', '/design-system.css', '/app.js', '/config.js'
]

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c =>
      // Cacheia cada asset individualmente para falhas individuais não bloquearem o install
      Promise.all(ASSETS.map(url => c.add(url).catch(() => {})))
    )
  )
  self.skipWaiting()
})

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ))
  self.clients.claim()
})

self.addEventListener('fetch', e => {
  // Deixa Supabase e CDNs passarem direto (sem cache do SW)
  if (e.request.url.includes('supabase.co')) return
  if (e.request.url.includes('cdn.jsdelivr.net')) return
  if (e.request.url.includes('unpkg.com')) return
  if (e.request.url.includes('fonts.googleapis.com')) return

  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached
      return fetch(e.request, { redirect: 'follow' }).then(res => {
        // Não cacheia: redirect, opaque, não-GET, erros
        if (res.ok && !res.redirected && res.type !== 'opaqueredirect' && e.request.method === 'GET') {
          const clone = res.clone()
          caches.open(CACHE).then(c => c.put(e.request, clone))
        }
        return res
      })
    }).catch(() => caches.match('/404.html'))
  )
})
