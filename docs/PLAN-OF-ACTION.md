# Plan of Action

Concrete, sequenced, actionable next steps — as opposed to
[ROADMAP.md](ROADMAP.md)'s longer arc. Each item names what "done" looks
like so it's checkable.

## 1. Get a real build (blocking everything else)

**Done: steps 1-3.** The .NET 8 SDK is installed, `AccelDraw.sln` builds
with 0 errors/warnings, and both test projects pass in full. Three bugs the
compiler caught that a review pass missed: `SnapshotStore.Directory` (a
property) shadowing the `System.IO.Directory` namespace inside its own
constructor; the `Snapshot` class being resolved as its own containing
namespace when referenced from a sibling namespace (renamed to
`LoadedSnapshot`); and `Vector3d.ZeroVector`, which doesn't exist on
`Autodesk.AutoCAD.Geometry.Vector3d`. Still open:

4. `NETLOAD` `AccelDraw.Plugin.dll` into a real AutoCAD 2022 session and run
   the acceptance test from the original milestone plan. **Partially done**:
   drew LINE/CIRCLE/TEXT, ran `ACCELDRAW_SAVE` (name, anchor point, extent
   corners all prompted and captured correctly — real handles, real
   geometry, verified against the actual `.adw` on disk), `ACCELDRAW_SNAPSHOTS`,
   `ACCELDRAW_STATUS`, and `ACCELDRAW_OVERLAY` (ON and OFF). Two real bugs
   found and fixed this pass — see ROADMAP.md Phase 01. **Still to run**:
   `ACCELDRAW_COMPARE` (move an entity, confirm MOVED shows up), `ACCELDRAW_RESTORE`
   (Full and Partial), modify-the-drawing-then-reopen-and-reload-from-disk.
5. Additionally exercise what was added after that plan: `ACCELDRAW_ANCHOR
   Define` a floor anchor, `ACCELDRAW_SAVE` a snapshot against it, redefine
   the anchor to a new point, `ACCELDRAW_RESTORE` → Full → Anchor and confirm
   the restored geometry follows the new anchor position; separately,
   `ACCELDRAW_RESTORE` → Partial and confirm only the entities you select
   from the overlay come back, with their original layer/color/linetype
   intact (not stuck on the `AccelDraw$OVERLAY` layer). Not yet run.

## 2. Get the ShilpiDB bridge building

**Done: steps 1-4, verified end to end.** Notes for reproducing on another
machine:

1. Rust toolchain: `winget install --id Rustlang.Rustup --silent` starts an
   interactive `rustup-init.exe` that winget's silent flag doesn't actually
   suppress (it just hangs indefinitely). Download `rustup-init.exe`
   directly and run it with explicit non-interactive flags instead:
   ```powershell
   Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile rustup-init.exe
   .\rustup-init.exe -y --default-host x86_64-pc-windows-gnu --default-toolchain stable --profile default
   ```
   The GNU host (not MSVC) is required, not just preferred: the MSVC host's
   `rustc` runs fine but has no linker without Visual C++ Build Tools, which
   this machine doesn't have. The GNU host bundles its own linker (`ld.exe`
   under `rustlib/.../bin/self-contained/`), so `cargo build` links without
   installing Visual Studio at all. Confirm with `rustup default
   stable-x86_64-pc-windows-gnu` and `rustc --version` in a fresh shell.
2. `cd bridge && cargo build --release -p accel-bridge-native` — pulled
   `shilpidb`/`shilpi-client` from GitHub at the pinned commit and compiled
   clean, no fixes needed. Fix the pinned `rev` in
   `bridge/accel-bridge-native/Cargo.toml` if that commit ever gets
   rewritten/force-pushed away.
3. Clone `shilpidb` locally (`gh repo clone HolagundiWorks/shilpidb`) if not
   already present, build and run a `shilpid` instance:
   ```bash
   cargo build --release -p shilpid -p shilpi --manifest-path ../shilpidb/Cargo.toml
   ../shilpidb/target/release/shilpid.exe --bind 127.0.0.1:7420 --data ./smoke.vdb
   ```
4. `dotnet build bridge/AccelDraw.Bridge.Smoke/AccelDraw.Bridge.Smoke.csproj`,
   copy `bridge/target/release/accel_bridge_native.dll` next to the built
   `AccelDraw.Bridge.Smoke.exe`, then run
   `AccelDraw.Bridge.Smoke.exe 127.0.0.1:7420` — confirmed `SMOKE PASSED`
   (put/get/query_bbox/delete all round-tripped the exact bbox and payload).
5. Copy the same DLL next to `AccelDraw.Plugin.dll`'s output, set
   `ACCELDRAW_SHILPID_ADDR=127.0.0.1:7420`, and from inside AutoCAD run
   `ACCELDRAW_SHILPI_STATUS` (expect "ENABLED, connected"), then
   `ACCELDRAW_SAVE` a snapshot and `ACCELDRAW_SHILPI_PUSH` it — confirm with
   ShilpiDB's own CLI (`shilpi -e "stats"` against the same `--data` file, or
   its GUI) that records actually landed.

## 3. AADT inventory pass (before any porting — see ROADMAP.md phase 3)

**Done** — see [docs/AADT-INVENTORY.md](AADT-INVENTORY.md): all 23 crates
under `AADT/crates/` sorted into Port (6, as design reference — most of
AADT is built over its own standalone document model, so this means
reimplementing the *idea* against AutoCAD entities, not moving Rust code),
Extract (2 — `aadt-geometry`, `aadt-dxf`), or Drop (15 — the standalone
shell, its own document model/persistence/rendering, and everything built
directly on top of those). WinUI-shell-specific pieces (`aadt-ffi`,
`native/aad-winui`, the `bridge/` SSO pieces) landed in Drop as expected.

**Still needs the repo owner's sign-off before any of the Port items turn
into actual code.** Once that happens, the recommended first pick is
`aadt-standards` (a real AIA/US NCS layer catalog) — smallest, most
self-contained, and it directly unblocks layer-based classification
("line on the wall layer = wall part") rather than leaving that as a
free-text guess.

## 3b. Standalone GUI + persistent local ShilpiDB

**Done.** `src/AccelDraw.Manager` — a WinForms desktop app needing no
AutoCAD — browses `.adw` snapshots (with detail/delete/push-to-ShilpiDB),
manages project floor anchors, and tests/pushes to ShilpiDB, all through a
real UI instead of AutoCAD's command line. `bridge/scripts/install-shilpid-local.ps1`
installs a persistent local `shilpid` (autosaving `.vdb`, on `PATH`,
`ACCELDRAW_SHILPID_ADDR` set, starts at login) — verified via the `shilpi`
CLI and `AccelDraw.Bridge.Smoke` against it.

Verifying the Manager's own UI interactively (as opposed to the library
code it calls, which is separately verified) turned out to need real mouse
clicks on a legacy WinForms `TabControl` that doesn't expose a proper UIA
`TabItem` tree — screen-coordinate automation across a multi-monitor setup
proved too fragile to fully finish confirming the "Test Connection" button
click-through, though the app itself was confirmed to load, render all
three tabs/controls correctly, and no longer hang after the native-DLL fix.
Worth a real manual click-through next time someone's at the machine.

## 4. AI provider seam (see ARCHITECTURE.md §4)

Not started. First concrete step once phases 1-2 above are green: add
`IAiProvider` to `AccelDraw.Core`, a no-op/stub implementation, and the
`ACCELDRAW_AI_PROVIDER` config switch — before wiring any real model calls,
so the seam exists and is testable independent of which provider is live.

## 5. Housekeeping

- The on-disk folder for this repo is still named `archidb` — the rename to
  something like `AccelDraw` couldn't be done from inside this session (the
  session's sandbox holds a lock on its own working directory), so do it
  manually once this session ends:
  ```powershell
  Rename-Item "D:\Work Development\Repos\archidb" "D:\Work Development\Repos\AccelDraw"
  ```
  Then update any local shortcuts/`launch.json`/IDE workspace files that
  reference the old path.
- Confirm the pinned ShilpiDB commit (`bridge/accel-bridge-native/Cargo.toml`)
  is still what's intended once ShilpiDB itself moves forward — this repo
  won't pick up ShilpiDB changes automatically, by design.
