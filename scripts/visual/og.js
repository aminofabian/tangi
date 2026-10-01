#!/usr/bin/env node
/**
 * Render the OpenGraph / Twitter share card to a PNG.
 *
 *   node og.js                            # → ../../priv/static/images/og-image.png
 *   node og.js /tmp/card.png              # somewhere else
 *
 * The card is `og.html`, screenshotted at exactly 1200×630 — the size Facebook,
 * X/Twitter, LinkedIn and WhatsApp crop to. Re-run it after any brand or copy
 * change and commit the result; nothing in the build depends on this script.
 */
const path = require("path");
const puppeteer = require("puppeteer-core");
const { chromePath } = require("./lib/browser");

const WIDTH = 1200;
const HEIGHT = 630;

async function main() {
  const out =
    process.argv[2] || path.resolve(__dirname, "../../priv/static/images/og-image.png");
  const url = "file://" + path.resolve(__dirname, "og.html");

  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    // file:// fonts are otherwise blocked as cross-origin.
    args: [
      "--no-sandbox",
      "--force-color-profile=srgb",
      "--hide-scrollbars",
      "--allow-file-access-from-files",
    ],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: 1 });
    await page.goto(url, { waitUntil: "networkidle0", timeout: 30000 });
    await page.evaluate(() => document.fonts && document.fonts.ready);
    await page.screenshot({
      path: out,
      type: "png",
      clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT },
    });
    console.log(`wrote ${out}`);
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
