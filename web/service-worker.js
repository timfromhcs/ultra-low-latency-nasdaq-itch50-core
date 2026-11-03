// =============================================================================
// File: web/service-worker.js
// Description: Offline cache for the ChipLab PWA. Cache-first for the app
//              shell and WASM, network fallback for everything else.
// =============================================================================
const CACHE = "chiplab-v3";
const ASSETS = [
  "./", "./index.html", "./styles.css", "./app.js", "./core.js", "./worker.js", "./gpu.js",
  "./wasm/chiplab_core.wasm", "./manifest.webmanifest", "./icons/icon.svg",
  "./icons/icon-192.png", "./icons/icon-512.png", "./og.png", "./docs.html",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // App shell is network-first so a new deploy is picked up immediately.
  const shell = /\.(?:html|js|css|wasm|webmanifest)$/.test(url.pathname) || url.pathname.endsWith("/");
  if (shell) {
    event.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match(req).then((c) => c || caches.match("./index.html")))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then((cached) => cached || fetch(req).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match("./index.html")))
  );
});
