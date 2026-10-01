// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/viewninjas"
import topbar from "../vendor/topbar"

// ---------------------------------------------------------------- PWA install
//
// Chrome offers installation through a *single, early* `beforeinstallprompt`
// event. It routinely fires before the LiveView socket has connected and mounted
// the install hooks — and it never fires again in that session — so a returning
// visitor (service worker already active) misses it and is never offered the
// install at all. It is caught here, at bundle load, kept on `window`, and
// announced, so a hook that mounts later can still use it.
window.__vnInstallPrompt = null

const isStandalone = () =>
  window.matchMedia("(display-mode: standalone)").matches ||
  window.navigator.standalone === true

// iOS Safari — including a desktop Safari in touch mode. It never fires
// `beforeinstallprompt`, so those visitors are shown the manual steps instead.
const isIos = () => {
  const ua = window.navigator.userAgent
  return /iphone|ipad|ipod/i.test(ua) || (ua.includes("Macintosh") && "ontouchend" in document)
}

// The one place that owns the browser's install prompt. The hooks are thin: they
// only decide *when* to show a button and call `vnPwa.install()` on a click.
window.vnPwa = {
  available: () => window.__vnInstallPrompt !== null,
  installed: isStandalone,
  ios: isIos,

  // One click hands over to the browser's own install sheet. The stashed event is
  // cleared afterwards because it can only be prompted once.
  async install() {
    const prompt = window.__vnInstallPrompt
    if (!prompt) return "unavailable"

    prompt.prompt()
    const choice = await prompt.userChoice
    window.__vnInstallPrompt = null
    window.dispatchEvent(new Event("phx:pwa-installed"))
    return choice ? choice.outcome : "unknown"
  },
}

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault()
  window.__vnInstallPrompt = event
  window.dispatchEvent(new Event("phx:pwa-installable"))
})

window.addEventListener("appinstalled", () => {
  window.__vnInstallPrompt = null
  window.dispatchEvent(new Event("phx:pwa-installed"))
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Push/pop feel on live navigation (scope.md §12). LiveView 1.2 ships no
// View Transitions hook of its own, so the shell animates the incoming view
// in the direction of travel — a back/forward slide for a pop, forward for a
// push. The keyframes live in app.css.
let vnNavDirection = "forward"
window.addEventListener("phx:navigate", ({detail}) => {
  vnNavDirection = detail && detail.pop ? "back" : "forward"
})
window.addEventListener("phx:page-loading-stop", () => {
  const main = document.querySelector(".vn-main")
  if (!main) return
  main.classList.remove("vn-enter-forward", "vn-enter-back")
  void main.offsetWidth // restart the animation
  main.classList.add(vnNavDirection === "back" ? "vn-enter-back" : "vn-enter-forward")
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// PWA (scope.md §12): register the service worker so the shop is installable
// and survives a dead spot. It caches assets and the offline splash only, never
// HTML — a cached page would carry one signed-in user's CSRF token.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/service-worker.js")
      .catch((error) => console.warn("service worker registration failed", error))
  })
}

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

