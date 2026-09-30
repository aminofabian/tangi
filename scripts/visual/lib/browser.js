/**
 * Shared browser plumbing for the visual scripts.
 *
 * We drive a real Chrome rather than pulling a second browser down with
 * puppeteer, so this only needs `puppeteer-core`. Point CHROME_PATH at a
 * binary, or let it find one.
 */
const fs = require("fs");
const path = require("path");
const puppeteer = require("puppeteer-core");

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.name === "Google Chrome for Testing" || entry.name === "chrome-headless-shell")
      out.push(full);
  }
  return out;
}

function candidates() {
  const cache = path.join(process.env.HOME || "", ".cache/puppeteer");
  return [
    process.env.CHROME_PATH,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    ...(fs.existsSync(cache) ? walk(cache) : []),
  ];
}

function chromePath() {
  const found = candidates()
    .filter(Boolean)
    .find((p) => {
      try {
        return fs.statSync(p).isFile();
      } catch {
        return false;
      }
    });

  if (!found) {
    throw new Error(
      "No Chrome found. Set CHROME_PATH, for example:\n" +
        "  CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' node shot.js …"
    );
  }

  return found;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Let the page finish settling: LiveView's first mount re-renders from server
 * assigns, so touching the DOM before the socket is up loses the edit.
 */
async function settle(page) {
  await sleep(900);
  try {
    await page.evaluate(() => {
      const flash = document.getElementById("flash-group");
      if (flash) flash.remove();
    });
    await page.evaluate(() => document.fonts && document.fonts.ready);
  } catch {
    // A navigation can tear the context down mid-evaluate; that is fine.
  }
  await sleep(300);
}

/**
 * Type into a field and confirm it stuck, retrying if LiveView re-rendered the
 * form underneath us and wiped it.
 */
async function fill(page, name, value) {
  const sel = `input[name='${name}']`;

  for (let attempt = 0; attempt < 3; attempt++) {
    const el = await page.$(sel);
    if (!el) {
      await sleep(400);
      continue;
    }

    await el.click({ clickCount: 3 });
    await el.type(value);
    await sleep(500);

    const current = await page.$eval(sel, (e) => e.value).catch(() => null);
    if (current === value) return true;
  }

  console.error(`could not fill ${name}`);
  return false;
}

/** Click something that may navigate, without racing the navigation. */
async function clickAndWait(page, el) {
  await Promise.all([
    page.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 15000 }).catch(() => {}),
    el.click().catch(() => {}),
  ]);
  await settle(page);
}

/** Open a phone-shaped page at `url`. */
async function open({ url, width = 390, height = 844, scale = 2 }) {
  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    args: ["--no-sandbox", "--force-color-profile=srgb"],
  });
  const page = await browser.newPage();
  await page.setViewport({ width, height, deviceScaleFactor: scale });
  await page.goto(url, { waitUntil: "networkidle0", timeout: 30000 });
  await settle(page);
  return { browser, page };
}

/**
 * Log in through the real password form, so authenticated screens can be shot.
 *
 * The page also carries a magic-link form with its own `user[email]` field, so
 * every selector is scoped to `#login_form_password`.
 */
async function logIn(page, { url, email, password }) {
  await page.goto(url, { waitUntil: "networkidle0" });
  await page.type("#login_form_password input[name='user[email]']", email);
  await page.type("#login_form_password input[name='user[password]']", password);
  // These buttons carry no `type`, so `button[type=submit]` would match nothing.
  await clickAndWait(page, await page.$("#login_form_password button[name='user[remember_me]']"));
}

module.exports = { open, settle, fill, sleep, logIn, clickAndWait, chromePath };
