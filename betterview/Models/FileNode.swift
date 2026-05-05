import Foundation

enum FileKind {
    case directory
    case markdown
    case image
    case html
    case code
    case unsupported

    var isOpenable: Bool {
        switch self {
        case .markdown, .image, .code, .html: return true
        case .directory, .unsupported: return false
        }
    }
}

enum FileTypes {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdx"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]
    static let htmlExtensions: Set<String> = ["html", "htm"]
    static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cpp", "cc", "cxx",
        "js", "mjs", "cjs", "jsx", "ts", "tsx",
        "py", "rb", "go", "rs", "kt", "kts", "java", "scala",
        "sh", "bash", "zsh", "fish",
        "json", "yaml", "yml", "toml", "xml", "plist", "ini", "conf",
        "css", "scss", "sass", "less",
        "sql", "graphql", "proto",
        "txt", "log", "gitignore", "dockerignore", "env",
        "lua", "vim", "el", "lisp", "clj", "ex", "exs",
    ]
    static let codeFilenames: Set<String> = ["Makefile", "makefile", "Dockerfile", "Procfile"]

    static func kind(for url: URL) -> FileKind {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return .directory }

        let ext = url.pathExtension.lowercased()
        if markdownExtensions.contains(ext) { return .markdown }
        if imageExtensions.contains(ext) { return .image }
        if htmlExtensions.contains(ext) { return .html }
        if codeExtensions.contains(ext) { return .code }
        if codeFilenames.contains(url.lastPathComponent) { return .code }
        return .unsupported
    }
}

struct FileNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let kind: FileKind

    var name: String { url.lastPathComponent }
    var isDirectory: Bool { kind == .directory }
    var isOpenable: Bool { kind.isOpenable }

    static func loadChildren(of url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: opts
        ) else { return [] }

        let nodes = urls
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { FileNode(url: $0, kind: FileTypes.kind(for: $0)) }

        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
