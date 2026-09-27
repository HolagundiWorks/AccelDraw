using System;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>
    /// Where to find a running shilpid, if AccelDraw should sync snapshots into ShilpiDB at all.
    /// Opt-in and off by default: reading/writing local .adw packages must keep working with no
    /// ShilpiDB process running (spec's original "Phase 01 should work completely locally" rule).
    /// </summary>
    public static class ShilpiConfig
    {
        private const string AddressEnvVar = "ACCELDRAW_SHILPID_ADDR";

        /// <summary>e.g. "127.0.0.1:7420", or null when ShilpiDB sync is disabled.</summary>
        public static string ServerAddress => Environment.GetEnvironmentVariable(AddressEnvVar);

        public static bool IsEnabled => !string.IsNullOrWhiteSpace(ServerAddress);
    }
}
