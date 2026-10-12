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
    static func main() throws {
        let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!
        let authorize = ChatGPTOAuth.authorizationURL(host: "urn:uuid:test", callback: redirect,
            state: "state", nonce: "nonce", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", account: nil, planUsage: true)
        let items = URLComponents(url: authorize, resolvingAgainstBaseURL: false)!.queryItems!
        expect(items.first { $0.name == "code_challenge" }?.value == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 PKCE vector")
        expect(items.first { $0.name == "client_id" }?.value == "dynamic_agent_client", "New registration")
        let good = URL(string: redirect.absoluteString + "?code=code&state=state&client_id=oaiapp_test")!
        let values = try ChatGPTOAuth.callbackValues(good, expectedURL: redirect, state: "state", clientID: nil)
        expect(values.client == "oaiapp_test", "Issued client retained")
        for suffix in ["?code=c&state=wrong&client_id=oaiapp_test", "?code=c&state=state", "?code=c&state=state&state=state&client_id=oaiapp_test", "?error=access_denied&state=state", "?code=c&state=state&client_id=dynamic_agent_client"] {
            rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: redirect.absoluteString + suffix)!, expectedURL: redirect, state: "state", clientID: nil) }
        }
        rejects { _ = try ChatGPTOAuth.callbackValues(good, expectedURL: redirect, state: "state", clientID: "oaiapp_other") }
        rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: "http://localhost:1455/auth/callback?code=c&state=state&client_id=oaiapp_test")!, expectedURL: redirect, state: "state", clientID: nil) }
        rejects { _ = try ChatGPTOAuth.callbackValues(URL(string: "http://127.0.0.1:1456/auth/callback?code=c&state=state&client_id=oaiapp_test")!, expectedURL: redirect, state: "state", clientID: nil) }
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
        let invalidClaims: [[String: Any]] = [["iss": "https://attacker.invalid"], ["aud": "other"], ["nonce": "other"], ["exp": 1.0], ["sub": ""], ["aud": ["oaiapp_test", "other"]], ["nbf": Date().timeIntervalSince1970 + 600]]
        for overrides in invalidClaims {
            rejects { _ = try ChatGPTOAuth.verifyIdentity(token(overrides), jwks: jwks, client: "oaiapp_test", nonce: "nonce") }
        }
        let parts = signed.components(separatedBy: ".")
        let tampered = parts[0] + "." + b64(Data("{\"sub\":\"attacker\"}".utf8)) + "." + parts[2]
        rejects { _ = try ChatGPTOAuth.verifyIdentity(tampered, jwks: jwks, client: "oaiapp_test", nonce: "nonce") }
        print("OAuth callback, PKCE, form encoding and signed identity tests passed.")
    }
}
