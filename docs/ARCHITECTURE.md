# AccelDraw Architecture

## 1. Position in the ecosystem

```
                         AUTOCAD
                            |
                    AccelDraw.Plugin
              (Time Machine: SAVE/OVERLAY/COMPARE/RESTORE)
                            |
              +-------------+--------------+
              |                            |
        local .adw package          ShilpiDB (shared store)
     (native DWG + vectors.json)   via bridge/ or shilpi-http
                                            |
                              +-------------+-------------+
                              |                           |
                         shilpid server            ShilpiDB Desktop (GUI)
                              |
                        AADT (native CAD app, being superseded — see §6)
```

AutoCAD remains the drafting surface. AccelDraw is the bridge between it and
a durable, comparable, restorable vector record of what was drawn — first
locally (`.adw`), optionally also in ShilpiDB, the storage engine this
ecosystem already built and shares with AADT. Nothing here does
architectural interpretation (no "this is a wall") — see the original
milestone plan's non-goals; that is a later phase, deliberately.

## 2. Layering (unchanged from the milestone plan)

| Layer | Project | Depends on |
| --- | --- | --- |
| AutoCAD add-in | `AccelDraw.Plugin` | Core, Geometry, Snapshot, ShilpiDb |
| Structured contracts for automation/AI | `AccelDraw.Core` | Geometry, Snapshot |
| Normalized geometry + comparison | `AccelDraw.Geometry` | — (no AutoCAD, no ShilpiDB) |
| Local `.adw` package | `AccelDraw.Snapshot` | Geometry |
| ShilpiDB entity <-> record mapping | `AccelDraw.ShilpiDb` | Geometry, `bridge/AccelDraw.Bridge` |
| Native bridge (managed) | `bridge/AccelDraw.Bridge`, `.Native` | `accel-bridge-native` (Rust cdylib) |
| Native bridge (Rust) | `bridge/accel-bridge-native` | `shilpidb`, `shilpi-client` (pinned by commit) |

`AccelDraw.Geometry` and `AccelDraw.Snapshot` stay AutoCAD-free and
ShilpiDB-free on purpose — they're the reusable core a future non-AutoCAD
host (or AADT itself, or a batch tool) could depend on without dragging in
either integration.

## 3. ShilpiDB integration

### 3.1 Why a native bridge, not HTTP

ShilpiDB ships two reachability paths for a non-Rust host: `shilpi-http`
(plain JSON/REST — zero build tooling, one HTTP hop per call) and a native
client crate (`shilpi-client`, blocking TCP, typed). AADT embeds the latter
directly since it's a Rust codebase. AccelDraw is .NET Framework 4.8 with no
native interop of its own, so this repo adds a thin Rust `cdylib`
(`bridge/accel-bridge-native`) that wraps `shilpi-client` behind a plain C
ABI, plus a P/Invoke layer (`bridge/AccelDraw.Bridge.Native` /
`AccelDraw.Bridge`) — avoiding the HTTP hop and matching AADT's approach of
depending on ShilpiDB's Rust crates directly, pinned to one commit
(`bridge/accel-bridge-native/Cargo.toml`), the same convention `aadt-vdb`
uses. `shilpi-http` remains available as a zero-build fallback if the native
DLL can't be shipped in some deployment (see §7 open questions).

### 3.2 Data flow

`AccelDraw.Plugin` extracts a `VectorDocument` (spec's normalized entity
model) exactly as it did before ShilpiDB existed in this repo's scope. What's
new is `AccelDraw.ShilpiDb`, which:

1. Computes a WCS bounding box per entity (`EntityBbox`) — what ShilpiDB's
   spatial index actually indexes on.
2. Serializes the whole `VectorEntity` (geometry + properties + identity) as
   the record's opaque JSON payload — ShilpiDB is schema-agnostic by design,
   so the entity schema lives entirely on the AccelDraw side.
3. Derives a `u64` record id from `SnapshotEntityId` via FNV-1a
   (`EntityIds`) — a known simplification; see §7.

`ACCELDRAW_SHILPI_PUSH` is the only wired command today: it pushes an
already-saved local snapshot's entities into a running `shilpid`. Pulling a
ShilpiDB region *into* AutoCAD (the inverse — the "reference mode" from the
original spec's XREF-style vision) is not implemented yet; `ShilpiSnapshotSync`
already has the read-side primitives (`TryPull`, `QueryRegion`) `AccelDraw.Plugin`
needs to grow that command from.

### 3.3 Where ShilpiDB sits relative to the local `.adw` format

Today: `.adw` is the source of truth; ShilpiDB is an opt-in mirror
(`ACCELDRAW_SHILPID_ADDR` unset = fully local, no behavior change). This is
deliberate — the original milestone's rule that Phase 01 works completely
offline still holds. Making ShilpiDB the *primary* store (so overlay/compare/
restore read from it directly, and AutoCAD and AADT genuinely share live
state rather than a manually-pushed mirror) is roadmap work, not done here.

## 4. Anchors, extents, and partial restore

Three related additions to the original Time Machine model, all implemented:

**Anchor point.** What the milestone plan called a snapshot's "base point"
is now explicitly the snapshot's *local origin* — `ACCELDRAW_SAVE` prompts
for it as "Anchor point". It's still just a WCS point stored in the
manifest; nothing changed about what it *is*, only what it's for (see
"restore at" below).

**Extent (the tile boundary).** `ACCELDRAW_SAVE` now also prompts for a
rectangle (two corners, rubber-banded like a window select) that defines
how far this snapshot's "territory" extends — deliberately independent of
the union of its entities' own bounding boxes. A snapshot can legitimately
declare a boundary bigger (or smaller) than what's currently drawn inside
it, e.g. a fixed grid cell for a floor plan that isn't fully drawn yet.
Stored as `SnapshotManifest.Extent` (`extent.min`/`extent.max`) and, when
`ACCELDRAW_SHILPI_PUSH` runs, pushed to ShilpiDB as one extra "tile" record
per snapshot (`{snapshotId}/tile`, see `ShilpiSnapshotSync.Push`) — so a
spatial query against ShilpiDB can answer "which snapshot covers this
point?" even where no entity happens to sit.

**Floor anchors.** `ACCELDRAW_ANCHOR` defines/lists named, project-wide WCS
reference points (`floor-anchors.json`, one level above the per-drawing
`snapshots/` folder, so every drawing saving into that folder shares the
same anchors) — e.g. "Ground Floor", "First Floor". `ACCELDRAW_SAVE`
optionally records which anchor a snapshot was taken relative to, plus that
anchor's origin *at save time* (`SnapshotManifest.FloorAnchor`).
`ACCELDRAW_RESTORE`, in Full mode, can then restore "at Anchor": it looks
up the anchor's *current* origin, diffs it against the origin recorded at
save time, and applies that delta as a translation — so if a floor's anchor
gets redefined later (the floor plan moves), previously-saved snapshots
follow it instead of staying pinned to stale coordinates. This is the
"anchor grids at larger distance" design from the original request,
implemented as a flat per-project list rather than a literal grid — nothing
stops a caller from naming anchors on a grid pattern if that's useful, the
store doesn't impose one.

**Partial restore.** `ACCELDRAW_RESTORE` prompts for Full or Partial.
Partial: it overlays the snapshot (reusing `ACCELDRAW_OVERLAY`'s locked
`AccelDraw$OVERLAY` layer — `OverlayCommand.EnsureOn`/`EnsureOff`), lets the
user select which overlaid entities to keep via ordinary AutoCAD selection
(filtered to that layer), and restores only those — reusing AutoCAD's own
picking model instead of a custom UI. The mechanism that makes this work
without depending on AutoCAD's undocumented handle-preservation behavior
across clones: `EntityCloner.CloneToNewDatabase` tags every entity it clones
into a snapshot's side DWG with its *original* handle via XData
(`EntityTag`), and XData reliably survives every subsequent clone AutoCAD
does — so when the user selects an overlaid (twice-cloned) entity, reading
its XData back still gives the exact handle `EntityReader` recorded as
`VectorEntity.SourceHandle` at save time, which is how the partial-restore
path recovers that entity's original layer/color/linetype/lineweight
(`RestoreCommand.ApplyOriginalProperties`) instead of leaving it on the
overlay layer.

## 5. The AI plug-in seam

Per the original spec's non-negotiable rule (its §24, carried forward
verbatim): **an AI agent never generates or executes arbitrary AutoCAD
automation code.** It only issues structured commands against
`AccelDraw.Core`'s interfaces (`SELECT_ENTITIES`, `RESTORE_SNAPSHOT`,
`COMPARE_SNAPSHOTS`, and — once wired — `PUSH_TO_SHILPIDB` /
`QUERY_SHILPIDB`). The CAD engine interprets those commands; the AI never
touches the AutoCAD API surface directly.

None of the AI layer itself is implemented yet — this is the seam it will
plug into, specified now so later work doesn't have to retrofit it:

```
            AI AGENT
               |
        Command Parser
               |
     AccelDraw.Core interfaces
   (IVectorExtractor, ISnapshotService, IGeometryComparer, + ShilpiDb ops)
               |
     AccelDraw.Plugin  <-- always the only thing touching AutoCAD's API
```

**Provider must be pluggable, not hard-coded**, between:

- **Cloud API** — any Anthropic/OpenAI-compatible HTTPS endpoint. Config:
  `ACCELDRAW_AI_PROVIDER=cloud`, `ACCELDRAW_AI_API_KEY`,
  `ACCELDRAW_AI_ENDPOINT` (default the provider's own API base URL).
- **Local model** — an Ollama-compatible endpoint (`http://localhost:11434`
  by default), so a firm can run entirely offline/on-prem if their CAD data
  is sensitive. Config: `ACCELDRAW_AI_PROVIDER=local`,
  `ACCELDRAW_AI_ENDPOINT` (default `http://localhost:11434`).

Planned shape (not yet implemented — a target for the interface, to keep
the eventual implementation swappable):

```csharp
public interface IAiProvider
{
    Task<string> CompleteAsync(string systemPrompt, string userPrompt, CancellationToken ct);
}

public sealed class CloudAiProvider : IAiProvider { /* HTTPS call to the configured cloud endpoint */ }
public sealed class LocalAiProvider : IAiProvider { /* HTTP call to a local Ollama-compatible endpoint */ }
```

A factory reads `ACCELDRAW_AI_PROVIDER` and returns whichever implementation
is configured; `AccelDraw.Plugin` and any future command-parsing layer code
against `IAiProvider` only, never against a specific vendor SDK. See
docs/ROADMAP.md phase 4 for when this actually gets built.

## 6. AADT: consolidation decision

**Decision (this session, per the repo owner):** AccelDraw supersedes AADT.
AADT stops being developed as a separate native CAD app; AccelDraw is the
flagship going forward.

What this does **not** mean: a mechanical port of AADT's ~20 Rust crates
(DXF import, geometry, rendering, LISP, takeoff, standards, its own
`aadt-vdb`/`aadt-vecdb`) into this repo in one pass. AADT and AccelDraw have
different hosting architectures — AADT is a standalone native app (Rust core
+ C++/WinUI shell); AccelDraw is hosted inside AutoCAD. "Superseding" means:
AccelDraw is where new CAD-intelligence work happens, and AADT's capabilities
get evaluated one at a time for whether they:

1. **Port into AccelDraw directly** (e.g. its layer-standard-driven semantic
   tagging, if AutoCAD's own layer model can carry the same information) —
   or
2. **Become a shared crate** both AccelDraw's bridge and any future non-AutoCAD
   surface can depend on (e.g. `aadt-dxf`'s DXF import, `aadt-takeoff`) — or
3. **Get dropped** if they only make sense for a standalone-app UI AccelDraw
   doesn't have (e.g. `aadt-render`'s Direct2D canvas, the WinUI shell, the
   LISP console).

See docs/ROADMAP.md phase 3 for the capability-by-capability list this
produces, and docs/PLAN-OF-ACTION.md for the first concrete step (an
inventory pass over AADT's crates before any porting starts).

## 7. Open questions / known simplifications

- **FNV-1a entity ids** (§3.2) risk collision at scale; AADT's blake3-based
  content-addressed ids (its ADR-0021) are the ecosystem's real answer.
  Migrate `EntityIds` once collision risk actually matters (see roadmap).
- **No pull-side command yet** — `ACCELDRAW_SHILPI_PUSH` exists,
  `ACCELDRAW_SHILPI_PULL` / an overlay-from-ShilpiDB command doesn't.
- **Nothing in this repo has been compiled.** No .NET SDK/MSBuild and no
  Rust toolchain were available on the machine this was written on. Treat
  every file as reviewed-but-unverified until a real build passes.
