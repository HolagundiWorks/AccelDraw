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
   the acceptance test from the original milestone plan (draw the 7
   supported entity types, `ACCELDRAW_SAVE`, modify the drawing,
   `ACCELDRAW_OVERLAY`, `ACCELDRAW_COMPARE`, `ACCELDRAW_RESTORE`, reopen and
   reload from disk).
5. Additionally exercise what was added after that plan: `ACCELDRAW_ANCHOR
   Define` a floor anchor, `ACCELDRAW_SAVE` a snapshot against it, redefine
   the anchor to a new point, `ACCELDRAW_RESTORE` → Full → Anchor and confirm
   the restored geometry follows the new anchor position; separately,
   `ACCELDRAW_RESTORE` → Partial and confirm only the entities you select
   from the overlay come back, with their original layer/color/linetype
   intact (not stuck on the `AccelDraw$OVERLAY` layer); run `ACCELDRAW_STATUS`
   and confirm the counts match what you actually saved.

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

1. For each crate under `AADT/crates/`, write one line: what it does, what
   it depends on, and which ROADMAP.md phase-3 bucket (port / extract /
   drop) it falls into. This is a reading/triage task, not a coding task —
   don't start porting code until this list exists and the repo owner has
   signed off on it.
2. Flag anything that's load-bearing for AADT's WinUI shell specifically
   (native/aad-winui, the bridge/ SSO pieces) as "drop" candidates by
   default, since AccelDraw has no equivalent shell.
3. Once the list exists, pick the single highest-value "port" or "extract"
   item and scope it as its own follow-up task — don't try to do the whole
   list in one pass.

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
