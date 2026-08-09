# Fulus Mark

## Concept

The reference mark builds an M from nested chevron facets converging to a point — a crown/wing shape. Rather than reskin that same technique into an F, this uses a different construction: a bold spine (the tallest stroke, angled to a blade tip at top) plus two forward-leaning arm blades of increasing... decreasing height — read together, spine-to-arms, it's an ascending block rhythm, which was chosen deliberately: Fulus is a business-growth tool, so the F itself reads a little like a bar chart. Same color family as your reference (navy, red, warm tan, white — sampled directly from your M so the two feel related), different geometry, different logic for why the shapes are where they are.

The circular "coin" framing on two of the variants is the other deliberate choice — Fulus means money, so a coin-edged badge is a more literal tie to the name than a plain square would be.

## Files

**App icon (square, full-bleed navy)** — use these for actual app store icons. iOS and Android both apply their own corner/shape mask on install, so app icon source images should always be plain squares, never pre-cropped to a circle:
- `fulus-app-icon-1024.png` — App Store source size
- `fulus-app-icon-512.png` — Play Store
- `fulus-app-icon-192.png` — Android/PWA
- `fulus-app-icon-180.png` — iOS home screen
- `fulus-mark-square.svg` — vector source

**Circular badge (full detail)** — for web headers, README badges, social avatars, anywhere a circular mark reads better than a square:
- `fulus-badge-512.png`, `fulus-badge-256.png`
- `fulus-mark-badge.svg` — vector source

**Favicon (simplified)** — the 3-color split turns to mud at 16–32px the same way any detailed mark does, so this variant drops to a solid white F on the navy coin instead:
- `favicon.ico` — multi-resolution (16px + 32px), drop straight into a site root
- `favicon-32.png`, `favicon-16.png`
- `fulus-mark-favicon.svg` — vector source

**Transparent mark** — just the F, no background, for placing on anything other than navy:
- `fulus-mark-transparent-512.png`
- `fulus-mark-transparent.svg` — vector source

## Colors

| | Hex |
|---|---|
| Navy | `#093051` |
| Red | `#E33B30` |
| Tan | `#B59D83` |
| White | `#FFFFFF` |

All four SVGs are hand-built vector source (plain polygons, no embedded raster) — safe to open and re-edit directly in Figma/Illustrator/Inkscape if you want to nudge anything.
