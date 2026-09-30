#!/usr/bin/env node
/**
 * Walk the money path — market → offer → checkout — and screenshot each step,
 * so the screens with real data can be reviewed.
 *
 *   node journey.js [outDir] [--email a@b.c] [--password secret]
 *
 * Needs demo data: `mix run priv/repo/demo_market.exs` (or `mix ecto.setup`).
 * Requires the dev server:  mix phx.server
 */
const path = require("path");
const { open, logIn, settle, fill, clickAndWait } = require("./lib/browser");

const BASE = process.env.BASE_URL || "http://localhost:4000";

const flag = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
};

async function main() {
  const outDir = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : ".";
  const email = flag("email", "customer@example.com");
  const password = flag("password", "correct horse battery");

  const written = [];
  const capture = async (page, name) => {
    const file = path.join(outDir, `${name}.png`);
    await page.screenshot({ path: file });
    written.push(file);
  };

  const { browser, page } = await open({ url: `${BASE}/` });
  await capture(page, "journey-1-market");

  const chip = await page.$(".vn-chip:not(.vn-chip--on)");
  if (chip) {
    await chip.click();
    await settle(page);
    await capture(page, "journey-2-filtered");
  }

  const link = await page.$(".vn-offer-link");
  if (!link) {
    throw new Error("no offers on the market — run `mix run priv/repo/demo_market.exs`");
  }
  // Read the href and navigate explicitly, rather than racing the click.
  const href = await link.evaluate((el) => el.getAttribute("href"));
  const offerUrl = new URL(href, BASE).toString();
  await page.goto(offerUrl, { waitUntil: "networkidle0" });
  await settle(page);
  await capture(page, "journey-3-offer");

  // A different grade moves the selected card and the live total.
  await fill(page, "order[link]", "https://instagram.com/viewninjas");
  await fill(page, "order[quantity]", "100");
  const grades = await page.$$(".vn-grade-card");
  if (grades.length > 1) {
    await grades[1].click();
    await settle(page);
  }
  await capture(page, "journey-4-below-minimum");

  // Sign in, then continue through to checkout.
  await logIn(page, { url: `${BASE}/users/log-in`, email, password });
  await page.goto(offerUrl, { waitUntil: "networkidle0" });
  await settle(page);
  await fill(page, "order[link]", "https://instagram.com/viewninjas");
  // The cheap lane starts at 5,000, so this is a legal order.
  await fill(page, "order[quantity]", "5000");
  await settle(page);
  await capture(page, "journey-5-ready");

  const submit = await page.$("#checkout");
  if (submit) {
    await clickAndWait(page, submit);
  } else {
    console.error("no #checkout button found");
  }
  await capture(page, "journey-6-checkout");

  for (const [url, name] of [
    ["/orders", "journey-7-orders"],
    ["/wallet", "journey-8-wallet"],
    ["/account", "journey-9-account"],
  ]) {
    await page.goto(`${BASE}${url}`, { waitUntil: "networkidle0" });
    await settle(page);
    await capture(page, name);
  }

  console.log(written.join("\n"));
  await browser.close();
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
