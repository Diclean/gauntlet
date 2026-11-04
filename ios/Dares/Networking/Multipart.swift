import Foundation

/// A single file part of a `multipart/form-data` body.
struct FilePart: Sendable {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

/// Builds a `multipart/form-data` body. No third-party dependency is used.
struct MultipartBody: Sendable {
    let boundary: String
    let body: Data

    init(boundary: String = "DaresBoundary-\(UUID().uuidString)", fields: [String: String], file: FilePart) {
        self.boundary = boundary
        var data = Data()

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            data.appendUTF8("--\(boundary)\r\n")
            data.appendUTF8("Content-Disposition: form-data; name=\"\(MultipartBody.sanitized(name))\"\r\n\r\n")
            data.appendUTF8("\(MultipartBody.sanitized(value))\r\n")
        }

        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"\(MultipartBody.sanitized(file.fieldName))\"; "
                + "filename=\"\(MultipartBody.sanitized(file.fileName))\"\r\n"
        )
        data.appendUTF8("Content-Type: \(MultipartBody.sanitized(file.mimeType))\r\n\r\n")
        data.append(file.data)
        data.appendUTF8("\r\n")

        data.appendUTF8("--\(boundary)--\r\n")
        self.body = data
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Removes the line breaks and the quotes of a header value.
    ///
    /// A caption or a file name comes from the device of the player: a line break in it
    /// would break out of its header and inject another part into the body (multipart
    /// injection). The value stays on one line instead.
    static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
