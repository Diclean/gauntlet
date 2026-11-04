import Foundation

/// Stores the session token in the Keychain and caches it in memory.
///
/// The Apple user id of the player lives next to it: the app asks Apple whether the
/// account still exists, so a revoked Apple ID cannot keep a session alive.
actor TokenVault {
    static let shared = TokenVault(keychain: KeychainStore(service: "com.mathys.dares"))

    private let keychain: any KeychainStoring
    private let appleKeychain: any KeychainStoring
    private var cached: String?
    private var cachedAppleUserID: String?

    /// The vault of the app: the token and the Apple user id have their own account.
    init(keychain: KeychainStore) {
        self.keychain = keychain
        self.appleKeychain = KeychainStore(service: keychain.service, account: "apple-user-id")
    }

    /// The vault of the tests: both stores are injected.
    init(keychain: any KeychainStoring, appleKeychain: any KeychainStoring) {
        self.keychain = keychain
        self.appleKeychain = appleKeychain
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

    /// The Apple user id of the signed in player — `nil` when the app never signed in.
    func appleUserID() -> String? {
        if let cachedAppleUserID { return cachedAppleUserID }
        let value = appleKeychain.read()
        cachedAppleUserID = value
        return value
    }

    func storeAppleUserID(_ userID: String) throws {
        try appleKeychain.save(userID)
        cachedAppleUserID = userID
    }

    /// Forgets the session: the token and the Apple user id are both deleted.
    func clear() {
        try? keychain.delete()
        try? appleKeychain.delete()
        cached = nil
        cachedAppleUserID = nil
    }
}
