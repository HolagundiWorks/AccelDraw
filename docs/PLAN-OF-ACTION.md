# Plan of Action

Concrete, sequenced, actionable next steps — as opposed to
[ROADMAP.md](ROADMAP.md)'s longer arc. Each item names what "done" looks
like so it's checkable.

## 1. Get a real build (blocking everything else)

Nothing in this repo has compiled yet. In order:

1. Install a .NET SDK capable of `net48` (the Windows 11 targeting pack is
   already present; the SDK is not):
   ```powershell
   winget install Microsoft.DotNet.SDK.8
   ```
2. `dotnet build AccelDraw.sln` from the repo root. Fix whatever the
   compiler surfaces in `AccelDraw.Core/Geometry/Snapshot/Plugin/ShilpiDb` —
   expect a few, this was written without a compiler in the loop.
3. `dotnet test tests/AccelDraw.Geometry.Tests` and
   `dotnet test tests/AccelDraw.Snapshot.Tests` — both should pass with no
   AutoCAD or ShilpiDB running.
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

1. Install Rust: `winget install Rustlang.Rustup` (or rustup.rs), then
   `rustup default stable`.
2. `cd bridge && cargo build --release -p accel-bridge-native`. This pulls
   `shilpidb`/`shilpi-client` from GitHub at the pinned commit — fix the
   pinned `rev` in `bridge/accel-bridge-native/Cargo.toml` if that commit
   ever gets rewritten/force-pushed away.
3. Clone `shilpidb` locally (`gh repo clone HolagundiWorks/shilpidb`) if not
   already present, and run a `shilpid` instance:
   ```bash
   cargo run -p shilpid --manifest-path ../shilpidb/Cargo.toml -- --bind 127.0.0.1:7420 --data ./smoke.vdb
   ```
4. Copy `bridge/target/release/accel_bridge_native.dll` next to
   `AccelDraw.Bridge.Smoke.exe`'s output, then
   `dotnet run --project bridge/AccelDraw.Bridge.Smoke -- 127.0.0.1:7420` and
   confirm `SMOKE PASSED`.
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
