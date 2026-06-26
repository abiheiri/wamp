import Foundation

/// Logs only in DEBUG builds. The message is an `@autoclosure`, so in Release the
/// string is never constructed — both the call and its interpolation cost are
/// eliminated by the optimizer. Release builds (and GitHub CI, when built with
/// `-configuration Release`) compile without the `DEBUG` flag, making this a no-op.
///
/// Usage: `debugLog("stream format ready — \(format)")`
///
/// `nonisolated` so it can be called from the parser's async URLSession delegate
/// and the nonisolated AudioFileStream C callbacks, not just the main actor.
@inline(__always)
nonisolated func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
