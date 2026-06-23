import Foundation
import Security
import SQLite3
import CommonCrypto

/// Reads and decrypts Chrome's `_hcmex_key` (and `device_id`) session cookies on macOS.
///
/// macOS Chrome cookie scheme (`v10`):
///   key = PBKDF2-HMAC-SHA1(KeychainPassword, salt="saltysalt", rounds=1003, len=16)
///   value = "v10" + AES-128-CBC(key, iv=16×0x20, PKCS7)
/// Recent Chrome versions prepend a 32-byte SHA-256(host) to the plaintext; we strip it
/// heuristically (the Bizneo session token always starts with "SFMyNTY").
public enum ChromeCookies {

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Build a `Cookie:` header value for the given host, e.g. `_hcmex_key=...; device_id=...`.
    public static func cookieHeader(profile: String, host: String,
                                    names: [String] = ["_hcmex_key", "device_id"]) throws -> String {
        guard let password = safeStoragePassword() else {
            throw BizneoError.cookieUnavailable("Keychain access to ‘Chrome Safe Storage’ was denied")
        }
        let key = pbkdf2SHA1(password: password, salt: Data("saltysalt".utf8), rounds: 1003, keyLen: 16)
        let encrypted = try readEncryptedCookies(profile: profile, host: host, names: names)
        guard !encrypted.isEmpty else {
            throw BizneoError.cookieUnavailable("No cookies for \(host) in Chrome profile ‘\(profile)’")
        }
        var parts: [String] = []
        for name in names {
            guard let enc = encrypted[name], let value = decryptValue(enc, key: key) else { continue }
            parts.append("\(name)=\(value)")
        }
        guard parts.contains(where: { $0.hasPrefix("_hcmex_key=") }) else {
            throw BizneoError.cookieUnavailable("Could not decrypt the _hcmex_key session cookie")
        }
        return parts.joined(separator: "; ")
    }

    // MARK: - Keychain

    static func safeStoragePassword() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    // MARK: - SQLite

    static func chromeCookiesPath(profile: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/\(profile)/Cookies")
    }

    static func readEncryptedCookies(profile: String, host: String, names: [String]) throws -> [String: Data] {
        let src = chromeCookiesPath(profile: profile)
        // Copy to temp so we can read while Chrome holds a lock on the original.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("biz_cookies_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: src, to: tmp)
        } catch {
            throw BizneoError.cookieUnavailable("Chrome cookie DB not found at \(src.path)")
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw BizneoError.cookieUnavailable("Could not open Chrome cookie DB")
        }
        defer { sqlite3_close(db) }

        let placeholders = names.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT name, encrypted_value FROM cookies WHERE host_key = ? AND name IN (\(placeholders));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw BizneoError.cookieUnavailable("Could not query Chrome cookie DB")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, host, -1, sqliteTransient)
        for (i, name) in names.enumerated() {
            sqlite3_bind_text(stmt, Int32(2 + i), name, -1, sqliteTransient)
        }

        var result: [String: Data] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: cName)
            if let blob = sqlite3_column_blob(stmt, 1) {
                let len = Int(sqlite3_column_bytes(stmt, 1))
                result[name] = Data(bytes: blob, count: len)
            }
        }
        return result
    }

    // MARK: - Crypto

    static func pbkdf2SHA1(password: Data, salt: Data, rounds: Int, keyLen: Int) -> Data {
        var derived = Data(count: keyLen)
        let passwordBytes = [UInt8](password)
        let saltBytes = [UInt8](salt)
        _ = derived.withUnsafeMutableBytes { dp in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), UInt32(rounds),
                dp.bindMemory(to: UInt8.self).baseAddress, keyLen)
        }
        return derived
    }

    static func aesCBCDecrypt(key: Data, iv: Data, data: Data) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var moved = 0
        let keyB = [UInt8](key), ivB = [UInt8](iv), dataB = [UInt8](data)
        let status = out.withUnsafeMutableBytes { op -> Int32 in
            CCCrypt(
                CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                keyB, keyB.count,
                ivB,
                dataB, dataB.count,
                op.baseAddress, outCapacity, &moved)
        }
        guard status == Int32(kCCSuccess) else { return nil }
        out.removeSubrange(moved..<out.count)
        return out
    }

    /// Decrypt a `v10` cookie value, handling the optional 32-byte SHA-256(host) prefix.
    static func decryptValue(_ enc: Data, key: Data) -> String? {
        let v10 = Data("v10".utf8)
        guard enc.count > 3, enc.prefix(3) == v10 else {
            // Not encrypted (older Chrome) — return as-is if printable.
            return String(data: enc, encoding: .utf8)
        }
        let ciphertext = Data(enc.dropFirst(3))
        let iv = Data(repeating: 0x20, count: 16)
        guard let plain = aesCBCDecrypt(key: key, iv: iv, data: ciphertext) else { return nil }

        // Candidate 1: strip 32-byte hash prefix (newer Chrome). Candidate 2: as-is (older).
        var candidates: [Data] = []
        if plain.count > 32 { candidates.append(Data(plain.dropFirst(32))) }
        candidates.append(plain)

        // Prefer a candidate that decodes to a Bizneo/Phoenix token.
        for c in candidates {
            if let s = String(data: c, encoding: .utf8), s.hasPrefix("SFMyNTY") { return s }
        }
        for c in candidates {
            if let s = String(data: c, encoding: .utf8), s.allSatisfy({ $0.isASCII && !$0.isNewline }) {
                return s
            }
        }
        return nil
    }
}
