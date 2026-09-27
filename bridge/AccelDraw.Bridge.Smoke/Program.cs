using System;
using System.Text;
using AccelDraw.Bridge;

namespace AccelDraw.Bridge.Smoke
{
    /// <summary>
    /// Minimal end-to-end check of the native bridge, independent of AutoCAD:
    /// connect to a running shilpid, round-trip one record, report pass/fail.
    /// Mirrors AADT's Aadt.Bridge.Smoke role for its own bridge.
    ///
    ///   cargo build --release -p accel-bridge-native   (produces accel_bridge_native.dll)
    ///   cargo run -p shilpid -- --bind 127.0.0.1:7420 --data ./smoke.vdb
    ///   dotnet run --project bridge/AccelDraw.Bridge.Smoke -- 127.0.0.1:7420
    /// </summary>
    public static class Program
    {
        public static int Main(string[] args)
        {
            string address = args.Length > 0 ? args[0] : "127.0.0.1:7420";
            Console.WriteLine($"Connecting to shilpid at {address} ...");

            try
            {
                using (var client = ShilpiDbClient.Connect(address))
                {
                    const ulong id = 999_999;
                    byte[] payload = Encoding.UTF8.GetBytes("accel-bridge-smoke");
                    var bbox = ShilpiBbox.FromCorners(0, 0, 10, 10);

                    client.Put(id, bbox, payload);
                    Console.WriteLine("put: ok");

                    if (!client.TryGet(id, out var readBack, out var readPayload))
                    {
                        Console.WriteLine("get: FAILED (record not found)");
                        return 1;
                    }

                    string text = Encoding.UTF8.GetString(readPayload);
                    Console.WriteLine($"get: bbox=({readBack.MinX},{readBack.MinY})-({readBack.MaxX},{readBack.MaxY}) payload=\"{text}\"");

                    var hits = client.QueryBbox(ShilpiBbox.FromCorners(-1, -1, 1, 1));
                    Console.WriteLine($"query_bbox: {hits.Length} hit(s)");

                    client.Delete(id);
                    Console.WriteLine("delete: ok");
                }

                Console.WriteLine("SMOKE PASSED");
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"SMOKE FAILED: {ex.Message}");
                return 1;
            }
        }
    }
}
