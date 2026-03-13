import Foundation

enum CaptureItem: Codable, Equatable {
    case text(String)
    case image(filename: String, originalPath: String)
    case video(filename: String, originalPath: String)
    case link(URL)

    func toMarkdown() -> String {
        switch self {
        case .text(let content):
            return content
        case .image(let filename, _):
            return "![\(filename)](attachments/\(filename))"
        case .video(let filename, _):
            return "[\(filename)](attachments/\(filename))"
        case .link(let url):
            return "[\(url.absoluteString)](\(url.absoluteString))"
        }
    }

    var mediaFiles: [(filename: String, sourcePath: String)]? {
        switch self {
        case .image(let filename, let path), .video(let filename, let path):
            return [(filename, path)]
        case .text, .link:
            return nil
        }
    }
}
