using System;
using System.Text;
using AccelDraw.Bridge.Native;

namespace AccelDraw.Bridge
{
    /// <summary>
    /// Friendly .NET wrapper over <c>accel_bridge_native.dll</c> (a P/Invoke bridge to
    /// <c>shilpi-client</c>). One instance is one live connection to a running
    /// <c>shilpid</c> — this is the "server client" path from the ShilpiDB README's
    /// AADT integration table: an embedded engine isn't practical for a managed
    /// .NET Framework 4.8 AutoCAD add-in, so AccelDraw always talks to a shilpid
    /// process, local or remote, over this bridge (or over shilpi-http as a fallback
    /// — see <c>docs/ARCHITECTURE.md</c>).
    /// </summary>
    public sealed class ShilpiDbClient : IDisposable
    {
        private IntPtr _handle;
        private bool _disposed;

        private ShilpiDbClient(IntPtr handle)
        {
            _handle = handle;
        }

        /// <summary>Connects to a running shilpid, e.g. <c>"127.0.0.1:7420"</c>.</summary>
        public static ShilpiDbClient Connect(string address)
        {
            var handle = NativeMethods.accel_bridge_connect(address);
            if (handle == IntPtr.Zero)
                throw new ShilpiDbException($"Could not connect to shilpid at '{address}': {ReadLastError()}");

            return new ShilpiDbClient(handle);
        }

        public void Put(ulong id, ShilpiBbox bbox, byte[] payload)
        {
            ThrowIfDisposed();
            payload = payload ?? Array.Empty<byte>();

            int rc = NativeMethods.accel_bridge_put(
                _handle, id, bbox.MinX, bbox.MinY, bbox.MaxX, bbox.MaxY, payload, (UIntPtr)payload.Length);

            if (rc != 0)
                throw new ShilpiDbException($"put({id}) failed: {ReadLastError()}");
        }

        public bool TryGet(ulong id, out ShilpiBbox bbox, out byte[] payload)
        {
            ThrowIfDisposed();
            var coords = new double[4];

            int rc = NativeMethods.accel_bridge_get(_handle, id, out var outPayload, out var outLen, coords);
            if (rc < 0)
                throw new ShilpiDbException($"get({id}) failed: {ReadLastError()}");

            if (rc == 0)
            {
                bbox = default;
                payload = null;
                return false;
            }

            bbox = new ShilpiBbox(coords[0], coords[1], coords[2], coords[3]);
            int len = checked((int)(ulong)outLen);
            payload = new byte[len];
            if (len > 0)
                System.Runtime.InteropServices.Marshal.Copy(outPayload, payload, 0, len);
            NativeMethods.accel_bridge_free_bytes(outPayload, outLen);
            return true;
        }

        public bool Delete(ulong id)
        {
            ThrowIfDisposed();
            int rc = NativeMethods.accel_bridge_delete(_handle, id);
            if (rc < 0)
                throw new ShilpiDbException($"delete({id}) failed: {ReadLastError()}");
            return rc == 1;
        }

        public ulong[] QueryBbox(ShilpiBbox bbox)
        {
            ThrowIfDisposed();
            int rc = NativeMethods.accel_bridge_query_bbox(
                _handle, bbox.MinX, bbox.MinY, bbox.MaxX, bbox.MaxY, out var outIds, out var outCount);

            if (rc != 0)
                throw new ShilpiDbException($"query_bbox failed: {ReadLastError()}");

            int count = checked((int)(ulong)outCount);
            var ids = new ulong[count];
            if (count > 0)
            {
                var buffer = new long[count];
                System.Runtime.InteropServices.Marshal.Copy(outIds, buffer, 0, count);
                for (int i = 0; i < count; i++)
                    ids[i] = unchecked((ulong)buffer[i]);
            }
            NativeMethods.accel_bridge_free_ids(outIds, outCount);
            return ids;
        }

        public void Save()
        {
            ThrowIfDisposed();
            int rc = NativeMethods.accel_bridge_save(_handle);
            if (rc != 0)
                throw new ShilpiDbException($"save failed: {ReadLastError()}");
        }

        private static string ReadLastError()
        {
            UIntPtr needed = NativeMethods.accel_bridge_last_error(null, UIntPtr.Zero);
            int len = checked((int)(ulong)needed);
            if (len == 0)
                return "(no error message)";

            var buf = new byte[len];
            NativeMethods.accel_bridge_last_error(buf, (UIntPtr)len);
            return Encoding.UTF8.GetString(buf);
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(ShilpiDbClient));
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            _disposed = true;
            if (_handle != IntPtr.Zero)
            {
                NativeMethods.accel_bridge_disconnect(_handle);
                _handle = IntPtr.Zero;
            }
        }
    }
}
