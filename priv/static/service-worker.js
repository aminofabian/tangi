/*
 * Tangi service worker (scope.md §12).
 *
 * The app is server-rendered per request and the LiveView socket carries the
 * live state, so this worker caches *assets*, never HTML: a cached page would
 * carry a CSRF token and a payload meant for one signed-in user. Navigations
 * are network-first and fall back to `/offline.html` when the phone has no
 * signal — that page is the "offline splash" the scope asks for.
 *
 * Bump VERSION to retire every cache below it.
 */

const VERSION = "tangi-v1";
const CORE = `${VERSION}-core`;
const RUNTIME = `${VERSION}-runtime`;

const OFFLINE_URL = "/offline.html";

/* Stable, un-fingerprinted URLs — the shell's own furniture, safe to precache
 * verbatim. Digested build assets are picked up at runtime instead, so this
 * list never needs to know a build hash. */
const CORE_ASSETS = [
  OFFLINE_URL,
  "/manifest.json",
  "/images/logo.png",
  "/images/logo-mark.png",
  "/images/icon-192.png",
  "/images/icon-512.png",
  "/fonts/fredoka-latin.woff2",
  "/fonts/nunito-latin.woff2",
];

/* A production build asset carries a content hash in its name, e.g.
 * `app-9f2c…4a.css`; such a file can never change under that name. */
const FINGERPRINTED = /-[0-9a-f]{16,}\.(?:js|css)$/;

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CORE);
      // Individually, so one 404 does not sink the whole install.
      await Promise.all(
        CORE_ASSETS.map((url) =>
          cache.add(new Request(url, { cache: "reload" })).catch(() => {})
        )
      );
      await self.skipWaiting();
    })()
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key !== CORE && key !== RUNTIME)
          .map((key) => caches.delete(key))
      );
      await self.clients.claim();
    })()
  );
});

// The page asks for this when it wants a new worker to take over immediately.
self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  // Leave everything but same-origin GETs alone: the LiveView socket
  // (/live) and the payment callbacks must reach the network untouched.
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/live")) return;

  if (request.mode === "navigate") {
    event.respondWith(navigate(request));
    return;
  }

  if (isAsset(url.pathname)) {
    event.respondWith(asset(request, url.pathname));
  }
});

/* Network-first. HTML is never cached, so a signed-in page can never be
 * replayed to someone else; the offline splash is the only fallback. */
async function navigate(request) {
  try {
    return await fetch(request);
  } catch {
    const cached = await caches.match(OFFLINE_URL);
    return cached || new Response("Offline", { status: 503, headers: { "Content-Type": "text/plain" } });
  }
}

/* Fingerprinted build output is served from cache at once; everything else
 * (fonts, images, and dev assets that carry no hash) is fetched first so a
 * rebuild is never masked, with the cache as the offline fallback. */
async function asset(request, pathname) {
  const cache = await caches.open(RUNTIME);
  const cached = await cache.match(request);

  if (cached && FINGERPRINTED.test(pathname)) return cached;

  try {
    const response = await fetch(request);
    if (response.ok && response.type === "basic") cache.put(request, response.clone());
    return response;
  } catch {
    return cached || Response.error();
  }
}

function isAsset(pathname) {
  return (
    pathname.startsWith("/assets/") ||
    pathname.startsWith("/fonts/") ||
    pathname.startsWith("/images/")
  );
}
