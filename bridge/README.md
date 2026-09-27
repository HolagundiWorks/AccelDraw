# AccelDraw · ShilpiDB bridge

A native bridge from the AutoCAD add-in (managed, .NET Framework 4.8, no
Rust toolchain of its own) to `shilpid` (Rust), so AccelDraw's Time Machine
snapshots can live in the same ShilpiDB store AADT uses — not just in local
`.adw` packages. See [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for
how this fits the rest of the system.

| Layer | Path | What it is |
| --- | --- | --- |
| Native ABI | [`accel-bridge-native`](accel-bridge-native) | Rust `cdylib`. Thin C ABI (`extern "C"`) over `shilpi-client::Client` — connect, put, get, delete, query_bbox, save. Pinned to one `shilpidb` commit, same convention as AADT's `aadt-vdb`. |
| Raw bindings | [`AccelDraw.Bridge.Native`](AccelDraw.Bridge.Native) | C#. `[DllImport]` declarations for `accel_bridge_native.dll`, no marshaling convenience. |
| Friendly wrapper | [`AccelDraw.Bridge`](AccelDraw.Bridge) | C#. `ShilpiDbClient` — the type AccelDraw.Plugin and any future AccelDraw surface should actually call. |
| Smoke test | [`AccelDraw.Bridge.Smoke`](AccelDraw.Bridge.Smoke) | C# console app. Round-trips one record against a real `shilpid`, independent of AutoCAD. |

Why a native bridge instead of `shilpi-http` (plain `HttpClient`, no build
step): avoids the HTTP hop and matches AADT's approach of embedding
ShilpiDB's Rust client directly. The cost is a Rust build step and a native
DLL to ship alongside the AutoCAD add-in — `shilpi-http` remains a valid
fallback (see ARCHITECTURE.md's "Reachability" section) for a host that
can't or doesn't want to carry that DLL.

## Build

Requires a Rust toolchain (`rustup`) in addition to the .NET side's
requirements (see the repo root README).

```bash
cd bridge
cargo build --release -p accel-bridge-native
```

Copy the resulting `target/release/accel_bridge_native.dll` next to
`AccelDraw.Plugin.dll` (and next to `AccelDraw.Bridge.Smoke.exe` for the
smoke test) — same "sidecar" pattern AADT and ShilpiDB's own GUI use for
their native/Tauri binaries. A build step to automate that copy is future
work (see [`docs/ROADMAP.md`](../docs/ROADMAP.md)).

## Smoke test

```bash
# terminal 1
cargo run -p shilpid --manifest-path ../../shilpidb/Cargo.toml -- --bind 127.0.0.1:7420 --data ./smoke.vdb

# terminal 2 (after building accel_bridge_native.dll per above)
dotnet run --project AccelDraw.Bridge.Smoke -- 127.0.0.1:7420
```

Expect `SMOKE PASSED`. This only proves the bridge and a live `shilpid` can
round-trip a record — it does not exercise AutoCAD or the entity <-> record
mapping in `AccelDraw.ShilpiDb` (that needs the full NETLOAD acceptance test
in the root plan).
