import Foundation
import Darwin

/// Yields a `()` value every time the file at `url` is written/extended/renamed.
/// Lives as long as the consumer keeps iterating; cancelling the consuming
/// `Task` tears down the underlying DispatchSource and closes the file
/// descriptor automatically.
func fileChangeStream(_ url: URL) -> AsyncStream<Void> {
    AsyncStream { continuation in
        guard url.isFileURL else { continuation.finish(); return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { continuation.finish(); return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { continuation.yield() }
        source.setCancelHandler { close(fd) }
        continuation.onTermination = { _ in source.cancel() }
        source.resume()
    }
}

/// Wraps `fileChangeStream` with a trailing debounce. Useful when Claude
/// writes a large file in many small chunks — we don't want to reload on
/// every chunk, just after the writes settle.
func debouncedFileChangeStream(_ url: URL, debounceMs: UInt64 = 200) -> AsyncStream<Void> {
    AsyncStream { continuation in
        let task = Task {
            var pending: Task<Void, Never>?
            for await _ in fileChangeStream(url) {
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
                    if !Task.isCancelled { continuation.yield() }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
