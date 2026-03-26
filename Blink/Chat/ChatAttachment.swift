import Foundation
import UniformTypeIdentifiers

enum ChatAttachmentKind: String, Codable, Hashable {
    case image
    case file
}

struct ChatAttachment: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let path: String
    let name: String
    let mimeType: String
    let kind: ChatAttachmentKind
    let byteCount: Int64?

    var isImage: Bool {
        kind == .image
    }

    static func make(from url: URL) -> ChatAttachment {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .nameKey])
        let contentType = values?.contentType
        let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
        let kind: ChatAttachmentKind = contentType?.conforms(to: .image) == true ? .image : .file

        return ChatAttachment(
            id: UUID().uuidString,
            path: url.path,
            name: values?.name ?? url.lastPathComponent,
            mimeType: mimeType,
            kind: kind,
            byteCount: values?.fileSize.map(Int64.init)
        )
    }
}
