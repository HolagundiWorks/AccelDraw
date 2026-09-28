# AccelDraw

An AutoCAD add-in that builds a persistent **vector memory / Time Machine**
layer for CAD drawings: it reads selected entities as normalized geometry,
snapshots them, and can overlay, compare, and restore past states —
with no architectural interpretation (no "this is a wall") at this stage.
Snapshots are stored both natively (a `.dwg` side-database, for exact
AutoCAD fidelity) and as normalized vectors, and can optionally sync into
**[ShilpiDB](https://github.com/HolagundiWorks/shilpidb)**, the shared
spatial vector-store engine also used by AADT — so an AutoCAD drawing and a
native ShilpiDB-backed drawing can live in one store.

Status: **Phase 01 milestone, verified live.** The .NET solution builds
clean and both unit test projects pass. A real NETLOAD session inside
AutoCAD 2022 confirmed the plugin loads and `ACCELDRAW_SAVE` produces a
correct `.adw` (real AutoCAD handles, exact geometry, anchor/extent/floor
anchor all captured) — that pass also caught and fixed two real bugs
(`ClonedEntityIds` hard-casting a non-`Entity` dependent object;
`Entity.Erase()` on a locked overlay layer). The ShilpiDB native bridge
builds and its smoke test round-trips real put/get/query/delete calls
against a live, **persistently installed** local `shilpid` — see
[`bridge/scripts/install-shilpid-local.ps1`](bridge/scripts/install-shilpid-local.ps1).
A standalone `AccelDraw.Manager` GUI (no AutoCAD required) browses
snapshots/anchors and talks to ShilpiDB directly — see Components below.

## Why this exists

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full picture. In
short: AutoCAD stays the drafting surface; AccelDraw captures what's drawn
into a durable, comparable, restorable vector record; ShilpiDB is the
storage substrate this and other CAD hosts (AADT) can share; a future AI
layer talks to structured commands over this substrate, never to raw
AutoCAD automation code.

## Components

| Project | What it is |
| --- | --- |
| [`src/AccelDraw.Geometry`](src/AccelDraw.Geometry) | Pure C#, no AutoCAD dependency. Normalized entity/geometry model and the deterministic UNCHANGED/MOVED/MODIFIED/ADDED/REMOVED comparer. |
| [`src/AccelDraw.Snapshot`](src/AccelDraw.Snapshot) | The `.adw` package format (manifest + vectors + native DWG, zipped) and the local snapshot store. |
| [`src/AccelDraw.Core`](src/AccelDraw.Core) | The `IVectorExtractor` / `ISnapshotService` / `IGeometryComparer` contracts a future AI/automation layer should call instead of touching AutoCAD directly. |
| [`src/AccelDraw.Plugin`](src/AccelDraw.Plugin) | The AutoCAD .NET add-in: `ACCELDRAW_SAVE`, `ACCELDRAW_SNAPSHOTS`, `ACCELDRAW_OVERLAY`, `ACCELDRAW_COMPARE`, `ACCELDRAW_RESTORE` (Full/Partial, with anchor-aware repositioning), `ACCELDRAW_ANCHOR`, `ACCELDRAW_STATUS`, `ACCELDRAW_SHILPI_STATUS`, `ACCELDRAW_SHILPI_PUSH`. |
| [`src/AccelDraw.ShilpiDb`](src/AccelDraw.ShilpiDb) | Maps AccelDraw's entity model onto ShilpiDB records (bbox + JSON payload) over the native bridge. |
| [`src/AccelDraw.Manager`](src/AccelDraw.Manager) | Standalone WinForms desktop app — no AutoCAD needed to run it. Browse/delete `.adw` snapshots, manage project floor anchors, and test/push to ShilpiDB, all outside AutoCAD's command line. |
| [`bridge`](bridge) | The native bridge to ShilpiDB: a Rust `cdylib` (`accel-bridge-native`) plus C# P/Invoke layers (`AccelDraw.Bridge.Native`, `AccelDraw.Bridge`), a standalone smoke test, and [`scripts/install-shilpid-local.ps1`](bridge/scripts/install-shilpid-local.ps1) for a persistent local `shilpid`. See [`bridge/README.md`](bridge/README.md). |
| [`lisp/`](lisp) | The legacy HCW/AccelDraw AutoLISP toolkit (area tables, metric room labels, text tools, layer standards, a manual layer-mapping dialog) — auto-loaded by `AccelDraw.Plugin` and exposed as an **AccelDraw Tools** ribbon tab. See below. |
| `tests/` | Unit tests for the comparer and the `.adw` round trip — no AutoCAD needed to run these. |

## Build

Requires .NET Framework 4.8 (targeting pack; Windows 11 ships it) and a
.NET SDK or MSBuild capable of building it, plus AutoCAD installed locally
for its reference assemblies (path configured in
[`Directory.Build.props`](Directory.Build.props)):

```bash
dotnet build AccelDraw.sln
dotnet test AccelDraw.Geometry.Tests
dotnet test AccelDraw.Snapshot.Tests
```

To also build the ShilpiDB bridge, you additionally need a Rust toolchain —
see [`bridge/README.md`](bridge/README.md).

Then in AutoCAD: `NETLOAD` → `src/AccelDraw.Plugin/bin/.../AccelDraw.Plugin.dll`.

## Legacy LISP toolkit

[`lisp/`](lisp) holds AutoLISP tools carried over from day-to-day drafting
work (area tables/labels, metric room tagging, text overlap/increment
tools, window labels, and two AutoCAD layer-standard setups: `VHLAYERS`
and the newer `HCWLAYERS`). `AccelDraw.Plugin` copies `lisp/` next to its
own DLL, auto-loads the deduplicated toolkit on NETLOAD the same way an
`acaddoc.lsp` would (see [`lisp/AccelDraw_LoadTools.lsp`](lisp/AccelDraw_LoadTools.lsp)
for exactly which files load and why some originals are archived instead —
several of the individually-supplied files were superseded by the
consolidated `hcwtools.lsp`), and exposes the commands as a ribbon tab
titled **AccelDraw Tools** (`src/AccelDraw.Plugin/UI/LegacyToolsRibbon.cs`).
AutoCAD's managed API dropped the old classic-toolbar type, so a ribbon tab
is the direct modern equivalent — it only appears in a ribbon-based
workspace (e.g. *Drafting & Annotation*), not in a classic/no-ribbon one.

New in this pass: **`LAYERMAP`** — a dialog for drawings that arrive with
someone else's ad-hoc layer names. Multi-select any number of existing
layers, pick one standard layer as the target, click "Map ->" (repeat for
other groups), then "Apply Mappings" moves every entity across and
optionally purges the emptied source layers. See
[`lisp/LayerMapper.lsp`](lisp/LayerMapper.lsp).

Type `ACCELDRAW_TOOLS_HELP` in AutoCAD for the full command list.

## Ecosystem

| Repo | Role |
| --- | --- |
| **AccelDraw** (this repo) | AutoCAD-hosted vector memory / Time Machine. The flagship CAD surface going forward — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the AADT consolidation decision. |
| [ShilpiDB](https://github.com/HolagundiWorks/shilpidb) | The shared storage engine (`.vdb` codec, spatial index, `shilpid` server, CLI, desktop GUI). |
| [AADT](https://github.com/HolagundiWorks/AADT) | Prior native CAD app built around ShilpiDB; being superseded by AccelDraw — see the roadmap for what migrates. |
| [AORMS](https://github.com/HolagundiWorks/aorms) | The broader architecture-practice management platform; a future consumer of this project's geometry substrate. |

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design, ShilpiDB integration, the AI plug-in seam.
- [docs/ROADMAP.md](docs/ROADMAP.md) — phased plan from here to a knowledge-graph-backed AI agent.
- [docs/PLAN-OF-ACTION.md](docs/PLAN-OF-ACTION.md) — the concrete next-session checklist.
- [docs/AADT-INVENTORY.md](docs/AADT-INVENTORY.md) — crate-by-crate Port/Extract/Drop triage of AADT ahead of the consolidation.
