import Foundation

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var encoded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: encoded)
    }
}

enum PasskeyWebAuthnSerializer {
    static func assertionResponse(
        credentialID: Data,
        authenticatorData: Data,
        clientDataJSON: Data,
        signature: Data,
        userID: Data?
    ) -> [String: JSONValue] {
        let credential = credentialID.base64URLEncodedString()
        return [
            "id": .string(credential),
            "rawId": .string(credential),
            "type": .string("public-key"),
            "response": .object([
                "authenticatorData": .string(authenticatorData.base64URLEncodedString()),
                "clientDataJSON": .string(clientDataJSON.base64URLEncodedString()),
                "signature": .string(signature.base64URLEncodedString()),
                "userHandle": userID.map {
                    .string($0.base64URLEncodedString())
                } ?? .null
            ])
        ]
    }
}
