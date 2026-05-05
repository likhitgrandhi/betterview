import Foundation

nonisolated struct AgentSpec: Codable, Hashable, Sendable {
    var systemPrompt: String
    var description: String
    var attachedFiles: [String]
    var skills: [String]
    var model: String
    var outputContract: String

    init(
        systemPrompt: String = "",
        description: String = "",
        attachedFiles: [String] = [],
        skills: [String] = [],
        model: String = "sonnet",
        outputContract: String = ""
    ) {
        self.systemPrompt = systemPrompt
        self.description = description
        self.attachedFiles = attachedFiles
        self.skills = skills
        self.model = model
        self.outputContract = outputContract
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.systemPrompt = (try? c.decode(String.self, forKey: .systemPrompt)) ?? ""
        self.description = (try? c.decode(String.self, forKey: .description)) ?? ""
        self.attachedFiles = (try? c.decode([String].self, forKey: .attachedFiles)) ?? []
        self.skills = (try? c.decode([String].self, forKey: .skills)) ?? []
        self.model = (try? c.decode(String.self, forKey: .model)) ?? "sonnet"
        self.outputContract = (try? c.decode(String.self, forKey: .outputContract)) ?? ""
    }
}

nonisolated struct InputSpec: Codable, Hashable, Sendable {
    nonisolated enum FieldType: String, Codable, Hashable, Sendable { case text, textarea, file, url }
    var label: String
    var fieldType: FieldType
    var defaultValue: String?

    init(label: String, fieldType: FieldType = .textarea, defaultValue: String? = nil) {
        self.label = label
        self.fieldType = fieldType
        self.defaultValue = defaultValue
    }
}

nonisolated struct OutputSpec: Codable, Hashable, Sendable {
    nonisolated enum Format: String, Codable, Hashable, Sendable { case markdown, json, file }
    var label: String
    var format: Format

    init(label: String, format: Format = .markdown) {
        self.label = label
        self.format = format
    }
}

nonisolated struct NodeAvatar: Codable, Hashable, Sendable {
    /// Hex color like "D97757". The node renders a colored sphere with this hue.
    var colorHex: String
    /// SF Symbol fallback if the sphere look isn't right for this kind.
    var symbol: String?

    static let palette: [String] = [
        "D97757", "5BA3E0", "8E7AE0", "5DBE9C", "E3B14E", "C76B91", "6A8DD8", "9CB04A",
    ]

    static func auto(seed: Int) -> NodeAvatar {
        NodeAvatar(colorHex: palette[abs(seed) % palette.count], symbol: nil)
    }
}
