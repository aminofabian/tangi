#!/usr/bin/env node
/** Throwaway: shoot the shop page. */
const { open, settle, sleep } = require("./lib/browser");

(async () => {
  const width = Number(process.argv[2] || 430);
  const out = process.argv[3] || "tmp-shop.png";

  const { browser, page } = await open({
    url: "http://localhost:4000/shop",
    width,
    height: 900,
    scale: 2,
  });
  await settle(page);
  await sleep(800);
  await page.evaluate(() => {
    for (const sel of [".vn-tabbar", "#pwa-install", "#flash-group"]) {
      const el = document.querySelector(sel);
      if (el) el.remove();
    }
  });

  const main = await page.$("main");
  await main.screenshot({ path: out });
  console.log("wrote", out);

  await browser.close();
})().catch((err) => {
  console.error("FAILED:", err.message);
  process.exit(1);
});
