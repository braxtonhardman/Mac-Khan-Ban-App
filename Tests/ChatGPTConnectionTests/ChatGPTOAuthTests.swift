import Foundation
import Security
import CryptoKit

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
func rejects(_ operation: () throws -> Void) {
    do { try operation(); preconditionFailure("Expected rejection") } catch {}
}
func b64(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

@main struct OAuthTests {
    @MainActor static func main() async throws {
        let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!
        let authorize = ChatGPTOAuth.authorizationURL(host: "urn:uuid:test", callback: redirect,
            state: "state", nonce: "nonce", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", account: nil, planUsage: true)
        let items = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!
        expect(items.first { $0.name == "code_challenge" }?.value == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 PKCE vector")
        expect(items.first { $0.name == "client_id" }?.value == "dynamic_agent_client", "New registration")
        expect(items.first { $0.name == "scope" }?.value == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", "Plan usage scopes")
        let identityOnly = ChatGPTOAuth.authorizationURL(host: "urn:uuid:test", callback: redirect,
            state: "state", nonce: "nonce", verifier: "verifier", account: nil, planUsage: false)
        let identityScopes = URLComponents(url: identityOnly, resolvingAgainstBaseURL: false)!.queryItems!
            .first { $0.name == "scope" }?.value
        expect(identityScopes == "openid profile email", "Identity-only sign-in requests no plan usage permissions")
        let good = URL(string: redirect.absoluteString + "?code=code&state=state&client_id=oaiapp_test")!
        let values = try ChatGPTOAuth.callbackValues(good, expectedURL: redirect, state: "state", clientID: nil)
        expect(values.client == "oaiapp_test", "Issued client retained")
        for suffix in ["?code=c&state=wrong&client_id=oaiapp_test", "?code=c&state=state", "?code=c&state=state&state=state&client_id=oaiapp_test", "?error=access_denied&state=state", "?code=c&state=state&client_id=dynamic_agent_client"] {
            rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: redirect.absoluteString + suffix)!, expectedURL: redirect, state: "state", clientID: nil) }
        }
        rejects { _ = try ChatGPTOAuth.callbackValues(good, expectedURL: redirect, state: "state", clientID: "oaiapp_other") }
        rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: "http://localhost:1455/auth/callback?code=c&state=state&client_id=oaiapp_test")!, expectedURL: redirect, state: "state", clientID: nil) }
        rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: "http://127.0.0.1:1456/auth/callback?code=c&state=state&client_id=oaiapp_test")!, expectedURL: redirect, state: "state", clientID: nil) }
        rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: good.absoluteString + "#fragment")!, expectedURL: redirect, state: "state", clientID: nil) }
        rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: good.absoluteString.replacingOccurrences(of: "127.0.0.1", with: "user@127.0.0.1"))!, expectedURL: redirect, state: "state", clientID: nil) }
        var saved = ChatGPTSavedConnections()
        func account(_ client: String) -> ChatGPTAccount {
            ChatGPTAccount(subject: "user-" + client, email: "same@example.com", clientID: client,
                accessToken: "test", refreshToken: nil, idToken: "test", scopes: [], expiresAt: Date())
        }
        saved.connect(account("first"))
        saved.account = nil
        saved.connect(account("second"))
        saved.connect(account("second"))
        let restored = try JSONDecoder().decode(ChatGPTSavedConnections.self, from: JSONEncoder().encode(saved))
        expect(restored.registrations.count == 2, "Separate registrations retained without duplicate clients")
        expect(restored.account?.clientID == "second", "Atomic record restores active account")
        let returning = ChatGPTOAuth.authorizationURL(host: "urn:uuid:test", callback: redirect,
            state: "s", nonce: "n", verifier: "v", account: nil, registration: restored.registrations[0], planUsage: false)
        let returningItems = URLComponents(url: returning, resolvingAgainstBaseURL: false)!.queryItems!
        expect(returningItems.first { $0.name == "client_id" }?.value == "first", "Sign-out retains registration for reauthorization")
        expect(!returningItems.contains { $0.name == "id_token_hint" || $0.name == "agent_name_hint" }, "No old token or new registration hint after sign-out")
        expect(String(data: ChatGPTOAuth.form(["code": "a+b&= c"]), encoding: .utf8) == "code=a%2Bb%26%3D%20c", "Form escaping")

        // Generate a local RSA fixture. No network, browser or real account is used.
        let key = SecKeyCreateRandomKey([kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048] as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(key)!
        let der = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var cursor = 0
        func readLength() -> Int {
            let first = Int(der[cursor]); cursor += 1
            if first < 128 { return first }
            var size = 0
            for _ in 0..<(first & 127) { size = size * 256 + Int(der[cursor]); cursor += 1 }
            return size
        }
        expect(der[cursor] == 0x30, "RSA sequence"); cursor += 1; _ = readLength()
        func readInteger() -> Data {
            expect(der[cursor] == 2, "RSA integer"); cursor += 1
            let length = readLength(); let value = der.subdata(in: cursor..<(cursor + length)); cursor += length
            return Data(value.drop(while: { $0 == 0 }))
        }
        let n = readInteger(), e = readInteger()
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid": "fixture", "kty": "RSA", "alg": "RS256", "n": b64(n), "e": b64(e)]]])
        let header = b64(try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "fixture"]))
        func token(_ overrides: [String: Any] = [:]) throws -> String {
            var claims: [String: Any] = ["iss": ChatGPTOAuth.issuer, "sub": "user", "email": "user@example.com", "aud": "oaiapp_test", "nonce": "nonce", "exp": Date().timeIntervalSince1970 + 600]
            claims.merge(overrides) { _, new in new }
            let payload = b64(try JSONSerialization.data(withJSONObject: claims))
            let signing = header + "." + payload
            let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(signing.utf8) as CFData, nil)! as Data
            return signing + "." + b64(signature)
        }
        let signed = try token()
        let identity = try ChatGPTOAuth.verifyIdentity(signed, jwks: jwks, client: "oaiapp_test", nonce: "nonce")
        expect(identity.subject == "user", "Signed identity")
        let invalidClaims: [[String: Any]] = [["azp": "other"], ["iss": "https://attacker.invalid"], ["aud": "other"], ["nonce": "other"], ["exp": 1.0], ["sub": ""], ["aud": ["oaiapp_test", "other"]], ["nbf": Date().timeIntervalSince1970 + 600]]
        for overrides in invalidClaims {
            rejects { _ = try ChatGPTOAuth.verifyIdentity(token(overrides), jwks: jwks, client: "oaiapp_test", nonce: "nonce") }
        }
        let parts = signed.components(separatedBy: ".")
        let tampered = parts[0] + "." + b64(Data("{\"sub\":\"attacker\"}".utf8)) + "." + parts[2]
        rejects { _ = try ChatGPTOAuth.verifyIdentity(tampered, jwks: jwks, client: "oaiapp_test", nonce: "nonce") }

        let listener = ChatGPTCallbackListener()
        let callback = try await listener.start(state: "listener-state")
        async let received = listener.wait()
        let wrong = URL(string: callback.absoluteString + "?code=c&state=wrong&client_id=oaiapp_test")!
        let (_, rejected) = try await URLSession.shared.data(from: wrong)
        expect((rejected as? HTTPURLResponse)?.statusCode == 400, "Wrong state rejected without consuming listener")
        let valid = URL(string: callback.absoluteString + "?code=c&state=listener-state&client_id=oaiapp_test")!
        let (pageData, accepted) = try await URLSession.shared.data(from: valid)
        expect((accepted as? HTTPURLResponse)?.statusCode == 200, "Valid loopback callback")
        let page = String(decoding: pageData, as: UTF8.self)
        expect(page.contains("Open Tierin") && page.contains("tierin://auth/return"), "Callback has an app return action")
        expect(page.contains("/auth/complete") && !page.contains("listener-state"), "History is cleaned without reflecting callback parameters")
        expect((accepted as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8", "HTML response")
        expect((accepted as? HTTPURLResponse)?.value(forHTTPHeaderField: "Referrer-Policy") == "no-referrer", "Callback never sends its URL as a referrer")
        expect((accepted as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("default-src 'none'") == true, "No external callback-page resources")
        expect(ChatGPTReturnPage(appearance: .dark, accentRed: 100, accentGreen: 120, accentBlue: 140).html(kind: .received).contains("color-scheme: dark; --accent: rgb(100 120 140)"), "Profile theme and accent reach return page")
        expect(ChatGPTReturnPage().html(kind: .declined).contains("Connection not completed"), "Declined consent is not shown as success")
        let returned = try await received
        expect(returned == valid, "Callback returned intact")
        listener.cancel()
        let early = ChatGPTCallbackListener()
        let earlyURL = try await early.start(state: "early")
        let earlyCallback = URL(string: earlyURL.absoluteString + "?code=c&state=early&client_id=oaiapp_test")!
        _ = try await URLSession.shared.data(from: earlyCallback)
        let earlyResult = try await early.wait()
        expect(earlyResult == earlyCallback, "Fast callback is buffered until wait begins")
        early.cancel()
        let cancelled = ChatGPTCallbackListener()
        _ = try await cancelled.start(state: "cancelled")
        cancelled.cancel()
        do { _ = try await cancelled.wait(); preconditionFailure("Cancelled wait must fail immediately") } catch {}
        print("OAuth signature, PKCE, callback listener and cancellation tests passed.")
    }
}
