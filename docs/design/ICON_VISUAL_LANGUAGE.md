# Fulus Icon Visual Language

## Direction

Fulus uses **2D realistic object artwork** for business objects and simple conventional glyphs for controls.

The object artwork should feel illustrated and tactile without becoming glossy 3D:
- clear real-world silhouette
- restrained perspective
- two or three material tones
- subtle directional shading
- small highlights only where they explain material
- soft, grounded shadow
- transparent background
- no emoji treatment
- no toy-like 3D rendering
- no gradients used merely for decoration

## Object vs control rule

**Objects are realistic. Controls are simple.**

Use illustrated objects for:
- store, cart, product/stock box
- wallet, payment card, receipt
- reports and documents
- customers/staff
- printer and supplier truck
- cloud/backup

Keep conventional glyphs for:
- add/remove
- back/forward
- close
- check
- edit/delete
- search/filter/sort
- chevrons
- visibility
- more
- refresh

## Implementation

FulusIcons remains the semantic vocabulary. FulusIconVisual is the single rendering boundary for object artwork. This keeps screens independent of individual asset paths.

The first production-quality sample set is stored under assets/icons_2d/. The set is intentionally small until the visual direction has been validated across the core home/sell/stock/money surfaces.

## Research benchmark

The closest public visual reference found during the research pass is Icons8's Skeuomorphism family. Icons8 describes the family as realistically rendered, pixel-perfect artwork and provides both PNG and vector formats.

Icons8 permits commercial use with attribution on its free tier and removes the attribution requirement on paid plans. Redistribution of the original icon files is prohibited.

For Fulus, the committed artwork in this branch is original Fulus artwork rather than copied Icons8 files. The library is being used as a visual benchmark, not as a source of copied assets.

Research:
- https://icons8.com/icons/set/shopping--style-skeuomorphism--static--icons8
- https://icons8.com/license
