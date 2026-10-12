import Foundation
import CryptoKit
import Security

enum ChatGPTConnectionError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

struct ChatGPTRegistration: Codable {
    let subject: String
    let email: String?
    let clientID: String
}

struct ChatGPTAccount: Codable {
    let subject: String
    let email: String?
    let clientID: String
    let accessToken: String
    let refreshToken: String?
    let idToken: String
    let scopes: [String]
    let expiresAt: Date
    var allowsPlanUsage: Bool { scopes.contains("chatgpt.tokens.use.direct") }
}

// Tokens remain in this app's device-local Keychain, never SwiftData or iCloud.
enum ChatGPTKeychain {
    static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Tierin.ChatGPT",
         kSecAttrAccount as String: name,
         kSecAttrSynchronizable as String: false]
    }
    static func read(_ name: String) throws -> Data? {
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ChatGPTConnectionError.message("Couldn’t read the saved ChatGPT connection.")
        }
        return data
    }
    static func write(_ data: Data, name: String) throws {
        let query = query(name)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw ChatGPTConnectionError.message("Couldn’t save the ChatGPT connection.")
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw ChatGPTConnectionError.message("Couldn’t save the ChatGPT connection.")
        }
    }
    static func remove(_ name: String) throws {
        let status = SecItemDelete(query(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChatGPTConnectionError.message("Couldn’t remove the saved ChatGPT connection.")
        }
    }
}

enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ChatGPTConnectionError.message("Couldn’t start a secure sign-in.")
        }
        return Data(bytes).base64URL
    }
    static func hostID() throws -> String {
        if let saved = try ChatGPTKeychain.read("host"), let value = String(data: saved, encoding: .utf8) { return value }
        let value = "urn:uuid:" + UUID().uuidString.lowercased()
        try ChatGPTKeychain.write(Data(value.utf8), name: "host")
        return value
    }
    static func authorizationURL(host: String, callback: URL, state: String, nonce: String, verifier: String, account: ChatGPTAccount?, registration: ChatGPTRegistration? = nil, planUsage: Bool) -> URL {
        var values = ["client_id": account?.clientID ?? registration?.clientID ?? "dynamic_agent_client",
                      "ext_agent_host_id": host, "response_type": "code",
                      "redirect_uri": callback.absoluteString, "resource": resource,
                      "scope": "openid profile email" + (planUsage ? " offline_access resource.invoke chatgpt.tokens.use.direct" : ""),
                      "state": state, "nonce": nonce, "code_challenge_method": "S256",
                      "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL]
        if let account { values["id_token_hint"] = account.idToken }
        else if let registration { values["login_hint"] = registration.email }
        else { values["agent_name_hint"] = "Tierin" }
        var components = URLComponents(string: issuer + "/api/accounts/authorize")!
        components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    static func callbackValues(_ url: URL, expectedURL: URL, state: String, clientID: String?) throws -> (code: String, client: String) {
        guard url.scheme == expectedURL.scheme, url.host == expectedURL.host,
              url.port == expectedURL.port, url.path == expectedURL.path,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            throw ChatGPTConnectionError.message("The sign-in callback was invalid.")
        }
        var values: [String: String] = [:]
        for item in items {
            guard values[item.name] == nil, let value = item.value else {
                throw ChatGPTConnectionError.message("The sign-in callback was invalid.")
            }
            values[item.name] = value
        }
        guard values["state"] == state else { throw ChatGPTConnectionError.message("The sign-in request did not match. Try again.") }
        if values["error"] != nil { throw ChatGPTConnectionError.message("ChatGPT sign-in wasn’t approved.") }
        guard let code = values["code"], !code.isEmpty,
              let client = values["client_id"] ?? clientID, client != "dynamic_agent_client", !client.isEmpty,
              clientID == nil || values["client_id"] == nil || clientID == values["client_id"] else {
            throw ChatGPTConnectionError.message("ChatGPT registration was incomplete. Try again.")
        }
        return (code, client)
    }
    static func form(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(values.sorted { $0.key < $1.key }.map {
            ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" +
            ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
    }
    static func request(_ url: URL, form values: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let values {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form(values)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 1_048_576 else {
            throw ChatGPTConnectionError.message("ChatGPT couldn’t complete the request. Try signing in again.")
        }
        return data
    }
    struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String
        let token_type: String
        let expires_in: Double
        let scope: String
    }
    static func exchange(code: String, client: String, verifier: String, callback: URL, nonce: String) async throws -> ChatGPTAccount {
        let data = try await request(URL(string: issuer + "/api/accounts/oauth/token")!, form: [
            "grant_type": "authorization_code", "client_id": client, "code": code,
            "code_verifier": verifier, "redirect_uri": callback.absoluteString, "resource": resource])
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        guard tokens.token_type.lowercased() == "bearer", !tokens.access_token.isEmpty, tokens.expires_in > 0 else {
            throw ChatGPTConnectionError.message("ChatGPT returned an invalid connection.")
        }
        let identity = try await validatedIdentity(tokens.id_token, client: client, nonce: nonce)
        return ChatGPTAccount(subject: identity.subject, email: identity.email, clientID: client,
                              accessToken: tokens.access_token, refreshToken: tokens.refresh_token,
                              idToken: tokens.id_token, scopes: tokens.scope.components(separatedBy: " "),
                              expiresAt: Date().addingTimeInterval(tokens.expires_in))
    }
    static func validatedIdentity(_ token: String, client: String, nonce: String) async throws -> (subject: String, email: String?) {
        let discovery = try await request(URL(string: issuer + "/.well-known/openid-configuration")!)
        guard let configuration = try JSONSerialization.jsonObject(with: discovery) as? [String: Any],
              configuration["issuer"] as? String == issuer,
              let jwksString = configuration["jwks_uri"] as? String, let jwksURL = URL(string: jwksString),
              jwksURL.scheme == "https", jwksURL.host == "auth.openai.com" else {
            throw ChatGPTConnectionError.message("Couldn’t verify the ChatGPT provider.")
        }
        let jwks = try await request(jwksURL)
        return try verifyIdentity(token, jwks: jwks, client: client, nonce: nonce)
    }
    static func verifyIdentity(_ token: String, jwks: Data, client: String, nonce: String) throws -> (subject: String, email: String?) {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3, let headerData = Data(base64URL: parts[0]),
              let payloadData = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String,
              let claims = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw ChatGPTConnectionError.message("Couldn’t verify the ChatGPT identity.")
        }
        guard let document = try JSONSerialization.jsonObject(with: jwks) as? [String: Any],
              let keys = document["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              key["alg"] == nil || key["alg"] as? String == "RS256",
              key["use"] == nil || key["use"] as? String == "sig",
              let modulus = key["n"] as? String, let exponent = key["e"] as? String,
              let n = Data(base64URL: modulus), let e = Data(base64URL: exponent), n.count >= 256, !e.isEmpty else {
            throw ChatGPTConnectionError.message("Couldn’t verify the ChatGPT signing key.")
        }
        let keyData = der(tag: 0x30, value: derInteger(n) + derInteger(e))
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                       kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                    Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil) else {
            throw ChatGPTConnectionError.message("The ChatGPT identity signature was invalid.")
        }
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard claims["iss"] as? String == issuer, audience.contains(client),
              audience.count <= 1 || claims["azp"] as? String == client,
              claims["nonce"] as? String == nonce,
              let expires = claims["exp"] as? Double, expires > Date().timeIntervalSince1970,
              let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw ChatGPTConnectionError.message("The ChatGPT identity did not match this sign-in.")
        }
        if let notBefore = claims["nbf"] as? Double, notBefore > Date().timeIntervalSince1970 + 60 {
            throw ChatGPTConnectionError.message("The ChatGPT identity is not valid yet.")
        }
        return (subject, claims["email"] as? String)
    }
    private static func derInteger(_ data: Data) -> Data {
        var value = Data(data.drop(while: { $0 == 0 }))
        if value.isEmpty { value = Data([0]) }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return der(tag: 2, value: value)
    }
    private static func der(tag: UInt8, value: Data) -> Data {
        var length = value.count
        var encoded = Data()
        if length < 128 { encoded.append(UInt8(length)) }
        else {
            while length > 0 { encoded.insert(UInt8(length & 255), at: 0); length >>= 8 }
            encoded.insert(0x80 | UInt8(encoded.count), at: 0)
        }
        return Data([tag]) + encoded + value
    }
    static func revoke(_ account: ChatGPTAccount) async throws {
        guard let refresh = account.refreshToken else { return }
        let discovery = try await request(URL(string: issuer + "/.well-known/openid-configuration")!)
        guard let configuration = try JSONSerialization.jsonObject(with: discovery) as? [String: Any],
              let endpoint = configuration["revocation_endpoint"] as? String, let url = URL(string: endpoint),
              url.scheme == "https", url.host == "auth.openai.com" else {
            throw ChatGPTConnectionError.message("Couldn’t confirm remote sign-out.")
        }
        _ = try await request(url, form: ["token": refresh, "token_type_hint": "refresh_token", "client_id": account.clientID])
    }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}

