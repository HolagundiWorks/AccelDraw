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

`AccelDraw.Bridge.Native.csproj` then **copies `accel_bridge_native.dll`
automatically** into its own output and every downstream consumer's output
(`AccelDraw.Bridge` → `AccelDraw.Plugin`, `AccelDraw.Manager`,
`AccelDraw.Bridge.Smoke`) on the next `dotnet build`, via an MSBuild
`None`/`CopyToOutputDirectory` item that picks up the release build (falling
back to debug). This isn't cosmetic: forgetting this copy once caused a
real, silent hang — a .NET Framework WinForms app's UI thread blocking on
the `DllNotFoundException` from a P/Invoke call doesn't reliably surface as
a visible dialog the way it does in a console app, so the window just sits
there reporting "Responding" forever with 0% CPU. Found live testing
`AccelDraw.Manager`; fixed once, structurally, so it can't recur silently.

## Run a persistent local `shilpid`

```powershell
bridge\scripts\install-shilpid-local.ps1
```

Builds `shilpid`/`shilpi` from a local `shilpidb` checkout, installs them to
`%LOCALAPPDATA%\ShilpiDB\bin` (added to your User `PATH`), points them at a
persistent `%LOCALAPPDATA%\ShilpiDB\data\accel.vdb` (autosaving every 30s),
sets `ACCELDRAW_SHILPID_ADDR` so `AccelDraw.Plugin`/`AccelDraw.Manager` pick
it up with no manual config, adds a Startup-folder shortcut so it starts at
login, and starts it immediately for the current session. Re-run any time to
rebuild/reinstall — safe, idempotent, never touches the data file. Verify
with `shilpi -e "stats" --host 127.0.0.1:7420` or `AccelDraw.Manager`'s
ShilpiDB tab.

## Smoke test

```bash
# if not already running via install-shilpid-local.ps1:
shilpid --bind 127.0.0.1:7420 --data ./smoke.vdb

# after building accel_bridge_native.dll per above:
dotnet run --project AccelDraw.Bridge.Smoke -- 127.0.0.1:7420
```

Expect `SMOKE PASSED`. This only proves the bridge and a live `shilpid` can
round-trip a record — it does not exercise AutoCAD or the entity <-> record
mapping in `AccelDraw.ShilpiDb` (that needs the full NETLOAD acceptance test
in the root plan — already run once, see docs/PLAN-OF-ACTION.md).
