import Foundation

/// Stores the session token in the Keychain and caches it in memory.
actor TokenVault {
    static let shared = TokenVault(keychain: KeychainStore(service: "com.mathys.dares"))

    private let keychain: KeychainStore
    private var cached: String?

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func currentToken() -> String? {
        if let cached { return cached }
        let value = keychain.read()
        cached = value
        return value
    }

    func store(_ token: String) throws {
        try keychain.save(token)
        cached = token
    }

    func clear() {
        try? keychain.delete()
        cached = nil
    }
}
