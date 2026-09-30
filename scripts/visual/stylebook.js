#!/usr/bin/env node
/**
 * Render every shell component with sample markup and screenshot it, so the
 * stylesheet can be reviewed without seeding any data.
 *
 *   node stylebook.js [url] [out.png] [--full]
 *
 * Requires the dev server:  mix phx.server
 */
const { open } = require("./lib/browser");

const SAMPLE = `
<section class="vn-card">
  <h2>Card title in Fredoka</h2>
  <p class="vn-muted">Body copy is Nunito at 16px with a 1.6 leading, so paragraphs stay readable on a cheap phone.</p>
  <dl class="vn-detail">
    <dt>Email</dt><dd>ops@example.com</dd>
    <dt>Phone</dt><dd>0712 345 678<span class="vn-badge vn-badge--ok">Verified</span></dd>
    <dt>Role</dt><dd>customer<span class="vn-badge">Read only</span></dd>
  </dl>
</section>

<section class="vn-card">
  <h2>Buttons</h2>
  <div style="display:flex;flex-wrap:wrap;gap:.5rem">
    <button class="vn-button">Primary action</button>
    <button class="vn-button vn-button--muted">Secondary</button>
    <button class="vn-button vn-button--accent">Buy now</button>
    <button class="vn-button" disabled>Disabled</button>
  </div>
  <div style="display:flex;flex-wrap:wrap;gap:.5rem;margin-top:.75rem">
    <button class="btn btn-primary">daisyUI primary</button>
    <button class="btn btn-primary btn-soft">daisyUI soft</button>
  </div>
</section>

<section class="vn-card">
  <h2>Pick a platform</h2>
  <div class="vn-chips">
    <button class="vn-chip vn-chip--on">All</button>
    <button class="vn-chip">Instagram</button>
    <button class="vn-chip">TikTok</button>
    <button class="vn-chip">YouTube</button>
  </div>
</section>

<section class="vn-card">
  <h2>Offers</h2>
  <ul class="vn-offers">
    <li><a class="vn-offer-link" href="#"><span class="vn-offer-link__title">Instagram followers</span><span class="vn-offer-link__from">from KSh 276</span></a></li>
    <li><a class="vn-offer-link" href="#"><span class="vn-offer-link__title">TikTok likes, cheap tier, refill on</span><span class="vn-offer-link__from">from KSh 1,240</span></a></li>
  </ul>
</section>

<section class="vn-card">
  <h2>Pick a grade</h2>
  <div class="vn-grades-pick">
    <button class="vn-grade-card vn-grade-card--on">
      <span class="vn-grade">Cheap</span>
      <span class="vn-price">276</span>
      <span class="vn-muted">slow</span>
    </button>
    <button class="vn-grade-card">
      <span class="vn-grade">Moderate</span>
      <span class="vn-price">412</span>
      <span class="vn-muted">fair</span>
    </button>
  </div>
  <div class="vn-total">
    <span class="vn-muted">1,000 followers</span>
    <span class="vn-total__value">KSh 276</span>
  </div>
</section>

<section class="vn-card">
  <h2>Wallet</h2>
  <div class="vn-stats">
    <div class="vn-stat"><span class="vn-stat__label">Balance</span><span class="vn-stat__value">KSh 1,482</span></div>
    <div class="vn-stat"><span class="vn-stat__label">Delivered</span><span class="vn-stat__value">18,400</span></div>
  </div>
  <ul class="vn-ledger">
    <li class="vn-ledger__row"><span class="vn-muted">Top up</span><span class="vn-ledger__amount">+ KSh 1,000</span></li>
    <li class="vn-ledger__row"><span class="vn-muted">Order 4821</span><span class="vn-ledger__amount vn-ledger__amount--out">− KSh 276</span></li>
  </ul>
</section>

<section class="vn-card">
  <h2>The M-Pesa sheet</h2>
  <p class="vn-muted">Full-screen in the app; shown inline here so it can be reviewed.</p>
</section>

<section class="vn-sheet" style="position:static;max-width:none;border:1px solid var(--vn-border);border-radius:var(--vn-radius)">
  <p class="vn-muted">A prompt is on your phone</p>
  <p class="vn-sheet__amount">KSh 843</p>
  <p class="vn-sheet__note">Enter your M-Pesa PIN to send KSh 843 to ViewNinjas. The prompt expires in 60 seconds.</p>
  <p class="vn-sheet__waiting">
    <span class="vn-pulse" aria-hidden="true"></span>
    <span class="vn-muted">Waiting for M-Pesa…</span>
  </p>
  <p class="vn-muted">Do not close this screen. If the prompt does not arrive, you can send it again.</p>
</section>

<section class="vn-sheet" style="position:static;max-width:none;border:1px solid var(--vn-border);border-radius:var(--vn-radius);margin-top:1rem">
  <p class="vn-sheet__amount">KSh 843</p>
  <p class="vn-error">The prompt was cancelled on your phone.</p>
  <p class="vn-muted">Nothing was charged. You can try again.</p>
  <button class="vn-button">Send the prompt again</button>
  <a class="vn-button vn-button--muted" href="#">Back to orders</a>
</section>

<section class="vn-card">
  <h2>States</h2>
  <p class="vn-error">That code has expired. Send a new one.</p>
  <div class="vn-suggestions" style="margin-top:.75rem">Suggestions sit on a soft blue panel.</div>
  <div class="vn-scroll" style="margin-top:.75rem">
    <table class="vn-table">
      <thead><tr><th>Service</th><th>Rate</th><th>Refill</th></tr></thead>
      <tbody>
        <tr><td>Instagram followers</td><td>0.90</td><td>yes</td></tr>
        <tr><td>TikTok likes</td><td>0.41</td><td>no</td></tr>
      </tbody>
    </table>
  </div>
  <span class="vn-skeleton" style="display:block;height:1.5rem;margin-top:.75rem"></span>
  <span class="vn-skeleton" style="display:block;height:1rem;width:60%;margin-top:.5rem"></span>
</section>
`;

async function main() {
  const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
  const url = args[0] || "http://localhost:4000/";
  const out = args[1] || "stylebook.png";
  const atIndex = process.argv.indexOf("--at");
  const at = atIndex === -1 ? null : process.argv[atIndex + 1];
  const { browser, page } = await open({ url, height: 1200 });

  await page.evaluate((html) => {
    const main = document.querySelector(".vn-main");
    if (!main) return;
    // Keep the hero for scale comparison, then swap the rest for the sample.
    const hero = main.querySelector(".vn-hero");
    main.innerHTML = "";
    if (hero) main.appendChild(hero);
    main.insertAdjacentHTML("beforeend", html);
    const bar = document.querySelector(".vn-tabbar");
    if (bar) bar.style.position = "static";
  }, SAMPLE);

  await new Promise((r) => setTimeout(r, 200));

  if (at) {
    const el = await page.$(at);
    if (!el) throw new Error(`no element matches ${at}`);
    await el.screenshot({ path: out });
  } else {
    await page.screenshot({ path: out, fullPage: true });
  }

  console.log(`wrote ${out}`);
  await browser.close();
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
