# AccelDraw Roadmap

Phased, each phase gated on the previous one actually working — not just
compiling. See [PLAN-OF-ACTION.md](PLAN-OF-ACTION.md) for the immediate,
concrete next steps; this file is the longer arc.

## Phase 01 — Vector Memory & Time Machine (current)

**Status: `AccelDraw.sln` builds clean, both unit test projects pass, and a
real NETLOAD session against AutoCAD 2022 confirmed the plugin loads and
`ACCELDRAW_SAVE`/`SNAPSHOTS`/`STATUS`/`OVERLAY` all work correctly end to
end (real handles, real geometry, a real `.adw` on disk). That pass also
found and fixed two real bugs — see the entry below.**

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
- [x] **NETLOAD acceptance test, partial** — `ACCELDRAW_SAVE` (with a real
      LINE/CIRCLE/TEXT selection, anchor point, and extent), `SNAPSHOTS`,
      `STATUS`, and `OVERLAY` (both ON and OFF) all confirmed working live.
      Found and fixed two real bugs surfaced only by real AutoCAD objects:
      `EntityCloner.ClonedEntityIds` (was `ClonedIds`) hard-cast every
      `WblockCloneObjects`-mapped id to `Entity`, which crashes when the
      clone also drags along a non-graphical dependent (here, the
      `RegAppTableRecord` `EntityTag` itself creates for XData) — now
      filters to actual entities first. `OverlayCommand.EnsureOff` called
      `Entity.Erase()` while the overlay layer was still locked
      (`eOnLockedLayer`) — now unlocks for the erase, relocks after.
      Still unverified: `COMPARE`, `RESTORE` (Full and Partial), `ANCHOR` —
      interrupted mid-session; same acceptance test, next NETLOAD pass.
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
- [x] **First real build** of the Rust crate — `cargo build --release -p
      accel-bridge-native` compiled clean against the pinned `shilpidb`/
      `shilpi-client` commit; `AccelDraw.Bridge.Smoke` round-tripped
      put/get/query_bbox/delete against a real `shilpid` (`SMOKE PASSED`)
- [ ] `ACCELDRAW_SHILPI_PULL` / an overlay-from-ShilpiDB command (the read
      side `ShilpiSnapshotSync.TryPull`/`QueryRegion` already support)
- [ ] Replace FNV-1a entity ids with content-addressed ids (mirroring AADT's
      blake3 Merkle object ids, ADR-0021) once collision risk matters
- [x] Automatic `accel_bridge_native.dll` copy on build (an MSBuild item in
      `AccelDraw.Bridge.Native.csproj` now flows it to every consumer) — this
      wasn't just cosmetic: the missing DLL was silently hanging
      `AccelDraw.Manager`'s UI thread (see bridge/README.md)
- [x] `bridge/scripts/install-shilpid-local.ps1` — persistent local `shilpid`
      (autosaving `.vdb`, `PATH`, `ACCELDRAW_SHILPID_ADDR`, start-at-login),
      verified via `shilpi` CLI and `AccelDraw.Bridge.Smoke`
- [x] `AccelDraw.Manager` — standalone WinForms GUI (snapshots, floor
      anchors, ShilpiDB status/push), no AutoCAD needed to run it
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

This phase starts with the inventory pass, not code — **done**: see
[docs/AADT-INVENTORY.md](AADT-INVENTORY.md) for the crate-by-crate bucket
assignment (6 Port, 2 Extract, 15 Drop). Next: scope the first Port item
(`aadt-standards`, a layer catalog) as its own task.

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
