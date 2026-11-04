import Foundation

extension FileManager {
    /// Writes the data with the complete file protection.
    ///
    /// The proofs of the club — a capture, a downloaded video — are personal: the file
    /// is unreadable while the device is locked. The attribute is set after the write,
    /// because a write with the `.atomic` option keeps the protection of the temporary
    /// file of the system.
    func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
