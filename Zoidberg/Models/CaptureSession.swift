import Foundation

struct CaptureSession: Codable {
    private(set) var items: [CaptureItem] = []
    let createdAt: Date

    var isEmpty: Bool { items.isEmpty }

    init() {
        self.createdAt = Date()
    }

    mutating func addItem(_ item: CaptureItem) {
        items.append(item)
    }

    mutating func clear() {
        items.removeAll()
    }

    var allMediaFiles: [(filename: String, sourcePath: String)] {
        items.compactMap { $0.mediaFiles }.flatMap { $0 }
    }

    func toMarkdown(title: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h:mm a"
        let dateString = formatter.string(from: createdAt)

        let heading = title ?? "Capture — \(dateString)"
        var lines: [String] = []
        lines.append("# \(heading)")
        lines.append("")
        lines.append("Notes captured on \(dateString)")
        lines.append("")
        lines.append("---")
        lines.append("")

        for item in items {
            lines.append(item.toMarkdown())
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func fallbackFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(formatter.string(from: createdAt))-capture.md"
    }
}
