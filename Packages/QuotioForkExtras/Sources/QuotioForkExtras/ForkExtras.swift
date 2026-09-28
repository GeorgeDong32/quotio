// Fork-owned extensions to upstream Quotio: fallback proxy bridge,
// request logging, remote proxy mode, and Gemini quota tracking.
// Everything fork-specific lives in this package so upstream merges
// never collide with fork code.

import Foundation

public enum QuotioForkExtras {
    /// Marker for the fork package version carrying the port.
    public static let portBase = "upstream-efe2f82"
}
