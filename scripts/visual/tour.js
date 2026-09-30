#!/usr/bin/env node
/**
 * Shoot every back-office screen in one browser session.
 *
 *   node tour.js [base] [email:password] [out-prefix]
 *
 * Writes `<prefix>-desk-<page>.png` for each section at 1440×900, then a phone
 * pass, then one shot of a long page scrolled to its foot — which is the only
 * way to see that the sidebar stays pinned and that the workspace owns its own
 * scroll.
 *
 * It logs in once, deliberately: the dev app rate-limits the password form per
 * IP, so a handful of `shot.js --login` runs in a row start landing on the login
 * page instead of the screen you asked for. If `shot.js` gives you a login
 * screen, come here instead.
 */
const { open, logIn, settle, sleep } = require("./lib/browser");

const BASE = process.argv[2] || "http://localhost:4000";
const LOGIN = process.argv[3] || "ops@example.com:correct horse battery";
const OUT = process.argv[4] || "../../.shots/tour";

const PAGES = [
  "admin",
  "admin/orders",
  "admin/suppliers",
  "admin/catalog",
  "admin/pricing",
  "admin/costs",
  "admin/settlements",
  "admin/insight",
  "admin/settings"
];

(async () => {
  const { browser, page } = await open({ url: `${BASE}/users/log-in`, width: 1440, height: 900 });
  const [email, password] = LOGIN.split(":");
  await logIn(page, { url: `${BASE}/users/log-in`, email, password });

  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
  for (const path of PAGES) {
    await page.goto(`${BASE}/${path}`, { waitUntil: "networkidle0" });
    await settle(page);
    const ok = await page.$(".vn-admin-nav");
    const name = path.replace("admin/", "").replace("admin", "overview");
    const file = `${OUT}-desk-${name}.png`;
    await page.screenshot({ path: file, fullPage: true });
    console.log(`${ok ? "ok  " : "MISS"} ${path} -> ${file}`);
    await sleep(300);
  }

  // Same session, phone width: the fallback must still be a working page.
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1 });
  for (const path of ["admin", "admin/costs", "admin/suppliers"]) {
    await page.goto(`${BASE}/${path}`, { waitUntil: "networkidle0" });
    await settle(page);
    const name = path.replace("admin/", "").replace("admin", "overview");
    const file = `${OUT}-phone-${name}.png`;
    await page.screenshot({ path: file, fullPage: true });
    console.log(`ok   ${path} -> ${file}`);
  }

  // A long page, scrolled to the foot, at the real viewport size: the sticky
  // sidebar must still be there and the workspace must own the scroll.
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
  await page.goto(`${BASE}/admin/settings`, { waitUntil: "networkidle0" });
  await settle(page);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await sleep(500);
  const bar = await page.$eval(".vn-topbar", (el) => {
    const r = el.getBoundingClientRect();
    return `${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`;
  });
  console.log(`scrolled .vn-topbar at ${bar}`);
  await page.screenshot({ path: `${OUT}-scroll-foot.png` });
  console.log(`ok   scrolled -> ${OUT}-scroll-foot.png`);

  await browser.close();
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
