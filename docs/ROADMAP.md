# AccelDraw Roadmap

Phased, each phase gated on the previous one actually working — not just
compiling. See [PLAN-OF-ACTION.md](PLAN-OF-ACTION.md) for the immediate,
concrete next steps; this file is the longer arc.

## Phase 01 — Vector Memory & Time Machine (current)

**Status: `AccelDraw.sln` builds clean and both unit test projects pass in
full (.NET 8 SDK, targeting net48 against the AutoCAD 2022 reference
assemblies). Not yet run inside real AutoCAD.**

- [x] Normalized entity model + comparer (`AccelDraw.Geometry`)
- [x] `.adw` local package format (`AccelDraw.Snapshot`)
- [x] `ACCELDRAW_SAVE` / `SNAPSHOTS` / `OVERLAY` / `COMPARE` / `RESTORE`
- [x] Anchor point + manually-defined extent (tile boundary) on every
      snapshot; `ACCELDRAW_ANCHOR` for named, project-wide floor anchors;
      `ACCELDRAW_RESTORE` can restore Full or Partial (select from the
      overlay), and Full restore can land at the original point, a picked
      point, or wherever a floor anchor currently sits — see
      [ARCHITECTURE.md §4](ARCHITECTURE.md#4-anchors-extents-and-partial-restore)
- [x] `ACCELDRAW_STATUS` — snapshot count/disk usage, floor anchor count, ShilpiDB reachability
- [x] Unit tests for the comparer, the `.adw` round trip, and floor anchor storage
- [x] **First real build** — `dotnet build AccelDraw.sln`, 0 errors/warnings;
      fixed a `SnapshotStore.Directory` property shadowing `System.IO.Directory`,
      a `Snapshot` type shadowed by its own namespace (renamed to
      `LoadedSnapshot`), and a nonexistent `Vector3d.ZeroVector`
- [ ] NETLOAD acceptance test against real AutoCAD (the 19-step test in the
      original milestone plan)
- [ ] Entity support beyond the 7 milestone types (SPLINE, HATCH, DIMENSION,
      LEADER, MLEADER, SOLID, 3DFACE, ATTRIBUTEREFERENCE, 3DPOLYLINE,
      ELLIPSE, POLYLINE)
- [ ] `ACCELDRAW_PREVIEW`, `ACCELDRAW_REPLACE`, `ACCELDRAW_DELETE`
- [ ] SQLite-backed metadata store (replacing the folder-scan `SnapshotStore`)
      once snapshot counts make scanning slow

## Phase 01.5 — ShilpiDB bridge (scaffolded this session)

- [x] `accel-bridge-native` (Rust cdylib, C ABI over `shilpi-client`)
- [x] `AccelDraw.Bridge.Native` / `AccelDraw.Bridge` (P/Invoke + friendly wrapper)
- [x] `AccelDraw.ShilpiDb` (entity <-> record mapping: bbox + JSON payload,
      plus one tile-boundary record per snapshot from its manually-defined extent)
- [x] `ACCELDRAW_SHILPI_STATUS`, `ACCELDRAW_SHILPI_PUSH`
- [ ] **First real build** of the Rust crate (`cargo build -p accel-bridge-native`)
      and the smoke test against a real `shilpid` — install `rustup` first
- [ ] `ACCELDRAW_SHILPI_PULL` / an overlay-from-ShilpiDB command (the read
      side `ShilpiSnapshotSync.TryPull`/`QueryRegion` already support)
- [ ] Replace FNV-1a entity ids with content-addressed ids (mirroring AADT's
      blake3 Merkle object ids, ADR-0021) once collision risk matters
- [ ] A build/packaging step that copies `accel_bridge_native.dll` next to
      `AccelDraw.Plugin.dll` automatically (currently manual, see bridge/README.md)
- [ ] Decide whether ShilpiDB becomes the *primary* store (compare/overlay/
      restore read from it directly) instead of an opt-in mirror of `.adw`

## Phase 02 — Geometry relationships (spec's original "Vector Trading Engine")

Distance, parallel/perpendicular, intersection, containment, alignment,
repetition, symmetry, offset, connectivity, enclosure — geometry *patterns*,
still not semantics. Natural next step once ShilpiDB holds enough drawings
to make cross-entity queries worth running server-side rather than in the
AutoCAD process.

## Phase 03 — AADT capability migration

Per the consolidation decision in [ARCHITECTURE.md §6](ARCHITECTURE.md#6-aadt-consolidation-decision):
AccelDraw supersedes AADT. Before porting anything, inventory what AADT
actually has and sort each crate into one of three buckets:

| Bucket | Meaning | Candidates (to verify, not assumed) |
| --- | --- | --- |
| Port into AccelDraw | Makes sense inside an AutoCAD-hosted add-in | layer-standard semantic tagging, standards/metadata (`aadt-standards`), takeoff logic (`aadt-takeoff`) |
| Extract to a shared crate | Useful to AccelDraw *and* any future non-AutoCAD surface | DXF import (`aadt-dxf`), the object/graph model (`aadt-object`, `aadt-graph`) if AccelDraw ends up needing its own outside AutoCAD's |
| Drop | Only made sense for a standalone-app UI | `aadt-render` (Direct2D canvas), the WinUI shell (`native/aad-winui`), `aadt-lisp` console, installer |

This phase starts with the inventory pass (PLAN-OF-ACTION.md), not code.

## Phase 04 — AI integration layer

Per [ARCHITECTURE.md §5](ARCHITECTURE.md#5-the-ai-plug-in-seam):

1. `IAiProvider` interface in `AccelDraw.Core`.
2. `CloudAiProvider` (Anthropic/OpenAI-compatible HTTPS) and `LocalAiProvider`
   (Ollama-compatible HTTP) implementations, selected by
   `ACCELDRAW_AI_PROVIDER`.
3. A structured command layer the AI actually talks to —
   `SELECT_ENTITIES`, `RESTORE_SNAPSHOT`, `COMPARE_SNAPSHOTS`,
   `PUSH_TO_SHILPIDB`, `QUERY_SHILPIDB` — never raw AutoCAD automation code
   generated by the model.
4. Optional per-entity embedding storage in ShilpiDB (its own roadmap item 4,
   "AI integration layer... a similarity index alongside SpatialGrid") once
   there's a real embedding provider wired up to produce them.

## Phase 05 — Semantic classification & knowledge graph

Geometry pattern -> object class (wall, door, window, column, ...) -> the
architectural knowledge graph (project -> building -> floor -> room ->
wall/door/window/furniture -> services), and finally natural-language
queries against it ("what changed?", "find all windows", "show walls longer
than 5m"). This is where the original spec's phases 03-05 land, once phases
01-04 above are real and working.
