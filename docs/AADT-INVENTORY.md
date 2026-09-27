# AADT Crate Inventory

The reading/triage pass called for in [PLAN-OF-ACTION.md §3](PLAN-OF-ACTION.md)
before any porting starts, per the consolidation decision in
[ARCHITECTURE.md §6](ARCHITECTURE.md#6-aadt-consolidation-decision). One line
per crate: what it does, what it depends on, and which bucket from
[ROADMAP.md phase 3](ROADMAP.md) it falls into — **Port** (the idea, not
necessarily the literal Rust, since AccelDraw is a C# AutoCAD add-in and most
of AADT's crates are built over its own standalone document model),
**Extract** (a shared Rust crate neither host's UI depends on), or **Drop**
(only made sense for AADT's standalone app).

This is a reading pass, not a commitment — each "Port" below still needs its
own scoping and sign-off before code moves. Of AADT's 23 crates: 6 Port
(as design, not code), 2 Extract, 15 Drop.

## Port (informs AccelDraw's design — not a literal code port)

| Crate | What it does | Why it matters to AccelDraw |
| --- | --- | --- |
| `aadt-detect` | Deterministic wall pairing, wall graph, room extraction, openings/structural/furniture detection from geometry. | This *is* the Phase 05 "geometry pattern → object class" step (ROADMAP.md) — the algorithms are the reference for what AccelDraw's own semantic layer needs to do, reimplemented against AutoCAD entities instead of `aadt-model`. |
| `aadt-standards` | AIA/US NCS layer catalog, WCAG contrast audit, named layer-set presets. | Directly answers "how do we know a line on a given layer means wall/door/window" — the layer-driven classification question already raised for AccelDraw. A layer *catalog* (not just a free-text layer name) is what makes that classification reliable instead of guesswork. |
| `aadt-embed` | Local, offline geometric ML embedder/classifier: geometry → AIA layer + category, no cloud call. | The concrete shape of ROADMAP phase 4's "optional per-entity embedding storage" — offline-first, which matches the local-AI half of the `IAiProvider` seam in ARCHITECTURE.md §5. |
| `aadt-object` | Typed engineering objects over document entities, with engineering properties and an append-only audit log. | The Object DB pattern AccelDraw's own knowledge-graph phase (ROADMAP phase 5) will need — entity → typed object, with provenance. |
| `aadt-graph` | Persisted typed engineering relationships between objects; promotes detection output into objects + graph. | The reference design for ROADMAP phase 5's architectural knowledge graph (project → building → floor → room → wall/door/window). |
| `aadt-assist` | AI service layer: gated suggestions that *propose but never commit*. | This is the exact principle AccelDraw already committed to (spec §24 / ARCHITECTURE.md §5: AI never touches AutoCAD directly, only structured commands) — `aadt-assist`'s architecture is the closest existing reference for how to actually build that gate. |
| `aadt-takeoff` | Quantity takeoff / BOQ generation over the Object DB. | Matches ShilpiDB's own README calling out AORMS's "plan-measurement and quantity-takeoff surface" as the natural consumer of this geometry substrate — real, already-identified business value, not speculative. |
| `aadt-api` | Loopback-only, token-gated local HTTP/JSON API over a live session; one write path is the command line. | A concrete precedent for how a future AI/automation client reaches AccelDraw without ever calling the AutoCAD API directly — informs the command-parser layer in ARCHITECTURE.md §5. |

(Eight listed, since `aadt-api` and `aadt-assist` are as much "port the
pattern" as `aadt-detect` etc. — grouped here rather than under Extract
because neither is meaningfully separable from AADT's session model as-is.)

## Extract (a shared, UI-independent Rust crate)

| Crate | What it does | Why extract rather than port or drop |
| --- | --- | --- |
| `aadt-geometry` | 2D geometry kernel: points, vectors, segments, polylines, tolerance, bbox, intersection math. No dependencies. | Zero-dependency and UI-independent already — a natural shared crate for any future Rust-side geometry work (e.g. a Phase 02 "geometry relationships" engine sitting next to ShilpiDB), without needing AADT's document model at all. |
| `aadt-dxf` | DXF/DWG import-export into a document model. | Not needed by AccelDraw itself (it reads live AutoCAD entities via the API, not files) — but matches ShilpiDB's own roadmap item 2, "SVG and DXF interchange." Worth extracting for *that* project rather than porting into AccelDraw. |

## Drop (only made sense for AADT's standalone app)

| Crate | What it does | Why it doesn't carry over |
| --- | --- | --- |
| `aadt-model` | AADT's own document model: entity store, layers, attributes. | AutoCAD *is* AccelDraw's document model — this would be a duplicate, not an addition. |
| `aadt-vdb` | AADT's CAD-specific `.vdb` layout over ShilpiDB, built on `aadt-model`. | Superseded by `AccelDraw.ShilpiDb`, which does the same job (entity ↔ ShilpiDB record) against AutoCAD entities directly. |
| `aadt-store` | Native `.aadt` SQLite document persistence. | AccelDraw's persistence is the DWG (via AutoCAD) plus `.adw` (via `AccelDraw.Snapshot`) — a third file format isn't needed. |
| `aadt-render` | GPU-accelerated 2D canvas (wgpu) for a standalone app. | AutoCAD already renders the drawing. |
| `aadt-app` | The egui desktop shell tying the above together. | No standalone shell in AccelDraw's architecture. |
| `aadt-cli` | Headless CLI entry point for that shell's command scripts/batch runs. | Tied to `aadt-app`; AccelDraw's automation surface is AutoCAD commands + (later) the AI command layer, not a separate CLI binary. |
| `aadt-ffi` | C ABI over `aadt-app::Session` for the WinUI native shell. | No WinUI shell in AccelDraw. |
| `aadt-command` | Command interpreter: registry, aliases, history, tab-completion. | AutoCAD already has one; AccelDraw's commands are `[CommandMethod]` attributes on top of it. |
| `aadt-lisp` | Embedded Scheme/AutoLISP-compatible interpreter. | AutoCAD already has real AutoLISP; no need to re-embed a compatible one. |
| `aadt-library` | On-disk block/hatch/font/image libraries. | AutoCAD's block table and hatch patterns already cover this natively. |
| `aadt-docs` | Title blocks, notes library, PLOTSETUP, sheet production. | AutoCAD's layouts/plot system already covers this. |
| `aadt-pdf` | PDF markup & comparison (Bluebeam-class). | A separate product concern from CAD-hosted drafting; out of scope for this consolidation, not disqualified as its own future tool. |
| `aadt-vecdb` | A second, custom vector database over drawing-element embeddings. | Would duplicate ShilpiDB's own roadmap item 4 ("a similarity index alongside SpatialGrid") — better to extend ShilpiDB than maintain a second vector store. The *confidence-gated metadata-mapping* idea inside it is worth remembering when that ShilpiDB work happens, even though the crate itself doesn't carry over. |

## Next step

Per PLAN-OF-ACTION.md: pick the single highest-value item from the Port
list and scope it as its own follow-up task. `aadt-standards` (a real layer
catalog) is the smallest, most self-contained candidate and directly
unblocks the layer-based classification question already raised for
AccelDraw — a reasonable place to start once there's a live AutoCAD test
loop to validate classification decisions against.
