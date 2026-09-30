# Tangi — the brand system

The shell is themed with the **Tangi** identity: a playful, rounded, social-media
voice that still reads as a serious shop. Everything below is implemented in
[`priv/static/assets/css/app.css`](priv/static/assets/css/app.css); the templates
never carry a colour literal.

## Palette

| Token | Hex | Role |
| --- | --- | --- |
| `--tangi-navy` | `#010649` | Outlines, headings, body text, dark surfaces |
| `--tangi-blue` | `#03a2fc` | Primary brand colour — buttons, active icons, fills |
| `--tangi-cyan` | `#03cbfd` | Highlight / secondary blue |
| `--tangi-purple` | `#732bfb` | Accent |
| `--tangi-pink` | `#fa1383` | Strong accent — important CTAs, errors |
| `--tangi-yellow` | `#fdb304` | Attention, badges |
| `--tangi-white` | `#fdf8fc` | Type and surfaces on dark |

Supporting tints sampled from the same artwork:

| Token | Hex | Role |
| --- | --- | --- |
| `--tangi-electric` | `#027dfb` | Link *text* on light backgrounds |
| `--tangi-page` | `#f8fbff` | App background |
| `--tangi-muted` | `#4b5275` | Secondary text |

The `--vn-*` tokens the shell actually styles with are aliases of the above, so a
recolour is one edit to that block.

### Contrast

The bright brand blues are for **fills and icons**, not for small type on white:
`#03a2fc` on white is only 2.8:1. So:

- body copy is navy on a near-white page,
- link text uses `--vn-accent-text` (electric blue) and is set at weight 600,
- errors use `--vn-danger`, the palette pink darkened until it reaches 4.5:1.

**Type on a coloured fill is always the brand off-white** (`--vn-on-accent`), never
navy — a dark label on a bright fill reads as muddy and is not a look this brand
uses. The two exceptions are the light fills: cyan and yellow keep navy, because
off-white type on them would be invisible.

Known trade-off: off-white on `#03a2fc` measures 2.6:1, under the 4.5:1 that
small text wants. It is the intended brand look; if you ever want it to pass,
swap `--vn-accent` for `#0169de` (4.9:1) — one line. Off-white on the purple is
5.8:1 and on the pink 3.7:1.

`default.css` ships the stock daisyUI theme inside `@layer theme`. The unlayered
`:root` block in `app.css` overrides its `--color-*` variables, so the generated
`CoreComponents` (buttons, inputs, alerts, tables) come out on-brand too.

## Typography

| Use | Face | Weight |
| --- | --- | --- |
| Headings, brand name, buttons, chips, badges, grades | Fredoka | 600–700 |
| Body, labels, small UI, tables | Nunito | 400–800 |

Both are **self-hosted** in `priv/static/fonts/` (latin subset, variable weight,
`font-display: swap`) and preloaded from the root layout. Total ~69 KB. scope.md
§12 forbids blocking first paint on a web font, so the system stack stays in the
`font-family` fallback chain and text paints immediately.

### Scale

One scale, eight steps, and nothing in the shell invents a size:

| Token | px | Used for |
| --- | --- | --- |
| `--vn-text-2xs` | 11 | tab labels |
| `--vn-text-xs` | 12 | badges, uppercase stat labels, table headers |
| `--vn-text-sm` | 13 | field labels, table cells, captions |
| `--vn-text-ui` | 15 | the UI default — buttons, chips, list rows, alerts |
| `--vn-text-body` | 16 | prose and **all inputs** (the iOS zoom floor) |
| `--vn-text-lg` | 18 | card titles, prices |
| `--vn-text-xl` | 22 | page titles, the live total |
| `--vn-text-2xl` | 28 | the payment sheet amount |

Figures that get compared — `.vn-price`, `.vn-total__value`, ledger rows, table
cells — carry `font-variant-numeric: tabular-nums`, so prices do not shuffle
sideways as the digits change.

## Craft rules

These are the things that make the shell feel deliberate rather than assembled:

- **One control height.** `--vn-control-h` (44 px) sizes every button and every
  field, in the hand-written shell *and* in daisyUI's, so nothing is off by 4 px.
  It is also the §12 tap target.
- **Radius is a system.** Pills for anything you press, `--vn-radius-field` for
  fields, `--vn-radius` for surfaces, `--vn-radius-lg` for the hero.
- **Shadows are navy-tinted**, never grey. Three steps: `--vn-shadow-1` on cards,
  `--vn-shadow-2` on the hero and hover, `--vn-shadow-3` for sheets.
- **Focus is the brand blue** with a translucent halo — the same treatment on
  links, buttons, chips and fields, and always `:focus-visible` except on text
  inputs, which show focus on click too.
- **"Selected" is one look everywhere**: soft blue fill, brand-blue border. It
  means the same thing on a chip, a grade card and an active tab.
- **Disabled controls go neutral**, not a faded brand fill, so they cannot be
  mistaken for a lighter primary action.
- **Motion is opt-in and short**: `--vn-fast` (120 ms) for state, `--vn-ease` for
  the curve, and everything collapses under `prefers-reduced-motion`.
- Hover states live inside `@media (hover: hover)`, because a phone should never
  depend on one.

## Artwork

The artwork in `priv/static/images/` is the supplied Tangi logo, used as-is. The
The source file is 1536×1024 RGBA on a transparent canvas; the web copies are
trimmed to the artwork and palette-quantised (flat-colour art compresses ~25×).

| File | What it is |
| --- | --- |
| `priv/static/images/logo.png` | The full lockup — the mascot over the "tangi" bubble wordmark, trimmed to the artwork and palette-quantised, 569×459, transparent |
| `priv/static/images/logo-mark.png` | The mascot alone, cut clear of the wordmark at y=644 (the tail bottoms out at ~650, the letter tops start at ~645), 512×512, transparent |
| `priv/static/images/icon-*.png` | The mark on the brand off-white, for the manifest's `any` icons |
| `priv/static/images/maskable-*.png` | The mark at 70% on brand blue, inside the maskable safe zone |
| `priv/static/images/apple-touch-icon.png` | 180×180, opaque (iOS composites transparency onto black) |
| `priv/static/favicon.ico` | 16/32/48 px raster of the mark |

The full lockup is what the shell header and the home hero draw, via
`ViewNinjasWeb.Layouts.brand/1`. The square mark is only for icon slots.

## Applying it somewhere new

1. Reach for `--vn-*` tokens, never a hex literal.
2. Display type goes through the `h1…h5` rule or `font-family: var(--vn-font-display)`,
   and sizes come from the `--vn-text-*` scale.
3. Anything you press is `--vn-control-h` tall and pill-shaped.
4. Carry the logo with `<Layouts.brand />` rather than re-embedding the image.

## Checking it

The shell is reviewed by rendering it, not by reading the markup. See
[`scripts/visual/`](scripts/visual/README.md): `shot.js` screenshots and measures
one screen, `journey.js` walks market → offer → checkout 
(`mix run priv/repo/demo_market.exs` first), and `stylebook.js` renders every
component at once — including the M-Pesa sheet, which needs configured payments
to reach for real.
