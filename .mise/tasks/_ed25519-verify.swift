// Checks a Sparkle EdDSA signature with the public key alone; Sparkle's `sign_update --verify`
// reads the private key from the keychain instead. Used by check-release.
// Usage: swift .mise/tasks/_ed25519-verify.swift <SUPublicEDKey> <edSignature> <file>
// Exit status: 0 valid, 1 invalid, 2 unusable input.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let keyData = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[2]),
      let file = FileManager.default.contents(atPath: arguments[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else {
    FileHandle.standardError.write(Data("ed25519-verify: usage: <base64 public key> <base64 signature> <file>\n".utf8))
    exit(2)
}
exit(key.isValidSignature(signature, for: file) ? 0 : 1)
