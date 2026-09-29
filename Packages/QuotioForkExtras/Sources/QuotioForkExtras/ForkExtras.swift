// Fork-owned extensions to upstream Quotio: fallback proxy bridge,
// request logging, remote proxy mode, and Gemini quota tracking.
// Everything fork-specific lives in this package so upstream merges
// never collide with fork code.
//
// NOTE: keep this type's name different from the module name — a type
// named exactly like its module breaks BUILD_LIBRARY_FOR_DISTRIBUTION
// swiftinterface generation (Release archives).

import Foundation

public enum ForkExtras {
    /// Marker for the fork package version carrying the port.
    public static let portBase = "upstream-efe2f82"
}
