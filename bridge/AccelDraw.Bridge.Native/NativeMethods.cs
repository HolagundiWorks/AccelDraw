using System;
using System.Runtime.InteropServices;

namespace AccelDraw.Bridge.Native
{
    /// <summary>
    /// Raw P/Invoke declarations for <c>accel_bridge_native.dll</c> (built from
    /// <c>bridge/accel-bridge-native</c>, a Rust cdylib over <c>shilpi-client</c>).
    /// This is the ABI layer only — no marshaling convenience, no error
    /// translation. <see cref="AccelDraw.Bridge.ShilpiDbClient"/> is the
    /// friendly wrapper callers should use instead.
    /// </summary>
    public static class NativeMethods
    {
        private const string Lib = "accel_bridge_native";

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern IntPtr accel_bridge_connect([MarshalAs(UnmanagedType.LPStr)] string addr);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void accel_bridge_disconnect(IntPtr handle);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int accel_bridge_put(
            IntPtr handle,
            ulong id,
            double minX, double minY, double maxX, double maxY,
            byte[] payload, UIntPtr payloadLen);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int accel_bridge_get(
            IntPtr handle,
            ulong id,
            out IntPtr outPayload,
            out UIntPtr outLen,
            [Out] double[] outBbox);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void accel_bridge_free_bytes(IntPtr ptr, UIntPtr len);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int accel_bridge_delete(IntPtr handle, ulong id);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int accel_bridge_query_bbox(
            IntPtr handle,
            double minX, double minY, double maxX, double maxY,
            out IntPtr outIds,
            out UIntPtr outCount);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern void accel_bridge_free_ids(IntPtr ptr, UIntPtr len);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern int accel_bridge_save(IntPtr handle);

        [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
        public static extern UIntPtr accel_bridge_last_error(byte[] buf, UIntPtr bufLen);
    }
}
