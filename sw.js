/* Service worker — Gestion Collaborateurs
   - La page elle-même : réseau d'abord (toujours la dernière version),
     copie en cache si le réseau est lent ou coupé.
   - Bibliothèques (React, Supabase, XLSX, polices…) : servies depuis le cache
     pour un lancement rapide, mises à jour en arrière-plan.
   - Les données (Supabase, EmailJS) ne sont jamais mises en cache. */
const VERSION = 'v47';
const PAGE_CACHE = 'collab-page-' + VERSION;
const LIB_CACHE = 'collab-libs-' + VERSION;
const CORE = ['./', './index.html'];
const LIB_HOSTS = ['unpkg.com', 'cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];
const NETWORK_TIMEOUT_MS = 4000;

self.addEventListener('install', e => {
  e.waitUntil(caches.open(PAGE_CACHE).then(c => c.addAll(CORE)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(k => k.startsWith('collab-') && k !== PAGE_CACHE && k !== LIB_CACHE).map(k => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

function pageNetworkFirst(req) {
  return caches.open(PAGE_CACHE).then(cache => {
    const network = fetch(req).then(res => {
      if (res && res.ok) cache.put(req, res.clone());
      return res;
    });
    const timeout = new Promise(resolve => setTimeout(resolve, NETWORK_TIMEOUT_MS));
    const fallback = () => cache.match(req, { ignoreSearch: true }).then(r => r || cache.match('./'));
    return Promise.race([network, timeout.then(fallback)])
      .then(res => res || network)
      .catch(() => fallback().then(r => r || network));
  });
}

function libStaleWhileRevalidate(req) {
  return caches.open(LIB_CACHE).then(cache => cache.match(req).then(cached => {
    const network = fetch(req).then(res => {
      if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
      return res;
    }).catch(() => cached);
    return cached || network;
  }));
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin === self.location.origin) {
    if (req.mode === 'navigate' || url.pathname.endsWith('/') || url.pathname.endsWith('.html')) {
      e.respondWith(pageNetworkFirst(req));
    }
    // Icônes et manifeste : jamais interceptés (Safari les lit directement pour l'écran d'accueil)
    return;
  }
  if (LIB_HOSTS.includes(url.hostname)) {
    e.respondWith(libStaleWhileRevalidate(req));
  }
});

// Clic sur une notification : ramène l'appli au premier plan (ou l'ouvre)
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if ('focus' in c) return c.focus(); }
    return self.clients.openWindow('./');
  }));
});
