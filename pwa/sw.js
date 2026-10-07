// Orbit (telephone) : fonctionne hors ligne.
// Fichier genere par tools/build_pwa.py a partir de sw.template.js (ne pas modifier sw.js a la main).
'use strict';
const CACHE = 'orbit-ed3c238fab77';
const FILES = ["./", "index.html", "manifest.webmanifest", "css/app.css", "js/app.js", "js/store.js", "js/zip.js", "js/orbit.js", "data/jokes.json", "data/culture.json", "data/unstick.json", "icons/icon.svg", "icons/icon-192.png", "icons/icon-512.png", "icons/maskable-512.png"];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('orbit-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Les fichiers de l'appli viennent du cache (hors ligne, instantane) ; une nouvelle
// version est installee en arriere-plan et prise au lancement suivant.
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // ouverture depuis « Partager » (?share...) ou un raccourci : c'est toujours la page de l'appli
  const key = req.mode === 'navigate' ? './' : req;
  event.respondWith(
    caches.open(CACHE).then((cache) => cache.match(key, { ignoreSearch: req.mode === 'navigate' }).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((res) => {
        if (res.ok && res.type === 'basic') cache.put(req, res.clone());
        return res;
      });
    }))
  );
});

// Clic sur une notification (fin de focus, rappel) : on revient dans l'appli
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) { if ('focus' in c) return c.focus(); }
      return self.clients.openWindow('./');
    })
  );
});
