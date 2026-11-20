// DL CUADRA PRO · service worker (permite instalar la app y abrirla rápido)
const CACHE = "cuadra-pro-v3.7";
const SHELL = ["./", "index.html", "legal.html", "config.js", "manifest.json", "logo.svg", "dl-company.png",
  "icon-192.png", "icon-512.png", "icon-maskable-192.png", "icon-maskable-512.png", "apple-touch-icon.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
// Solo archivos de la propia app. Supabase y demás servicios siempre van directo a internet.
self.addEventListener("fetch", e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== "GET" || url.origin !== location.origin) return;
  const isPage = req.mode === "navigate" || /\.(html|js|json)$/.test(url.pathname) || url.pathname.endsWith("/");
  if (isPage) {
    // primero internet (siempre la versión más nueva); sin conexión, la copia guardada
    e.respondWith(fetch(req).then(r => { if (r.ok) { const c = r.clone(); caches.open(CACHE).then(k => k.put(req, c)); } return r; })
      .catch(() => caches.match(req, { ignoreSearch: true }).then(r => r || caches.match("index.html"))));
  } else {
    e.respondWith(caches.match(req).then(r => r || fetch(req).then(n => { if (n.ok) { const c = n.clone(); caches.open(CACHE).then(k => k.put(req, c)); } return n; })));
  }
});

// Notificaciones push (cierres de caja) — llegan aunque la app esté cerrada
self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: "DL CUADRA PRO", body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "DL CUADRA PRO", {
    body: d.body || "", icon: "icon-192.png", badge: "icon-192.png", tag: d.tag || "cuadra",
    renotify: true, vibrate: [120, 60, 120], data: { url: d.url || "./" }
  }));
});
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "./", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(ws => {
    for (const w of ws) { if (w.url.startsWith(self.registration.scope) && "focus" in w) { w.postMessage({ tipo: "abrir", url }); return w.focus(); } }
    return self.clients.openWindow(url);
  }));
});
