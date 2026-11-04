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
            data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.appendUTF8("\(value)\r\n")
        }

        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n")
        data.appendUTF8("Content-Type: \(file.mimeType)\r\n\r\n")
        data.append(file.data)
        data.appendUTF8("\r\n")

        data.appendUTF8("--\(boundary)--\r\n")
        self.body = data
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
