#!/usr/bin/env node
/**
 * Screenshot a running screen at a phone viewport.
 *
 *   node shot.js <url> <out.png> [--width 390] [--height 844] [--full]
 *                [--at .vn-card] [--measure] [--login email:password]
 *
 * --measure prints the computed layout of the interesting bits (overflow,
 * control heights, type sizes) instead of guessing from pixels.
 *
 * Requires the dev server:  mix phx.server
 */
const { open, logIn, settle } = require("./lib/browser");

const PROPS = [
  "width",
  "height",
  "padding",
  "fontSize",
  "fontWeight",
  "fontFamily",
  "borderRadius",
  "boxShadow",
  "backgroundColor",
  "color",
  "outline",
];

const SELECTORS = [
  ".vn-app",
  ".vn-main",
  ".vn-topbar",
  ".vn-header",
  ".vn-brand",
  ".vn-brand__logo",
  ".vn-admin-nav",
  ".vn-admin-nav__list",
  ".vn-admin-nav__item",
  ".vn-page-title",
  ".vn-hero",
  ".vn-card",
  ".vn-actions",
  "h1",
  "h2",
  ".vn-button",
  ".vn-chip",
  ".vn-offer-link",
  ".vn-price",
  ".vn-total__value",
  ".vn-tabbar",
];

async function measure(page) {
  return page.evaluate(
    (props, selectors) => {
      const viewport = document.documentElement.clientWidth;
      const offenders = [];
      document.querySelectorAll("*").forEach((el) => {
        const r = el.getBoundingClientRect();
        if (r.width > viewport + 1 || r.right > viewport + 1) {
          offenders.push({
            tag: el.tagName.toLowerCase(),
            cls: String(el.className || "").slice(0, 60),
            width: Math.round(r.width),
            right: Math.round(r.right),
          });
        }
      });

      const rows = [];
      selectors.forEach((sel) => {
        const el = document.querySelector(sel);
        if (!el) return;
        const c = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        const row = {
          sel,
          box: `${Math.round(r.width)}x${Math.round(r.height)}`,
          at: `${Math.round(r.x)},${Math.round(r.y)}`,
          display: c.display,
        };
        props.forEach((p) => (row[p] = c[p]));
        rows.push(row);
      });

      return {
        viewport,
        scrollWidth: document.documentElement.scrollWidth,
        overflows: offenders.slice(0, 20),
        computed: rows,
      };
    },
    PROPS,
    SELECTORS
  );
}

async function main() {
  const [url, out, ...rest] = process.argv.slice(2);
  if (!url || !out) {
    console.error(
      "usage: node shot.js <url> <out.png> [--width 390] [--height 844] [--full] [--at sel] [--measure] [--login email:password]"
    );
    process.exit(1);
  }

  const flag = (name, fallback) => {
    const i = rest.indexOf(`--${name}`);
    return i === -1 ? fallback : rest[i + 1];
  };

  const { browser, page } = await open({
    url,
    width: Number(flag("width", 390)),
    height: Number(flag("height", 844)),
  });

  const login = flag("login", null);
  if (login) {
    const [email, password] = login.split(":");
    // Default the login page to the same origin we were pointed at.
    await logIn(page, {
      url: flag("login-url", new URL("/users/log-in", url).toString()),
      email,
      password,
    });
    // Logging in lands on the redirect target, so go back to what was asked for.
    await page.goto(url, { waitUntil: "networkidle0" });
    await settle(page);
  }

  if (rest.includes("--measure")) console.log(JSON.stringify(await measure(page), null, 1));

  const selector = flag("at", null);
  if (selector) {
    const el = await page.$(selector);
    if (!el) throw new Error(`no element matches ${selector}`);
    await el.screenshot({ path: out });
  } else {
    await page.screenshot({ path: out, fullPage: rest.includes("--full") });
  }

  console.log(`wrote ${out}`);
  await browser.close();
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
