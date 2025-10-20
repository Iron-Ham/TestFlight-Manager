import AppStoreConnect_Swift_SDK
import Foundation

struct Credentials: Codable {
  let issuerID: String
  let keyID: String
  let privateKeyPath: String

  init(issuerID: String, keyID: String, privateKeyPath: String) throws {
    let trimmedIssuerID = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedKeyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedIssuerID.isEmpty else {
      throw CLIError.invalidInput("The issuer ID cannot be empty.")
    }
    guard !trimmedKeyID.isEmpty else {
      throw CLIError.invalidInput("The key ID cannot be empty.")
    }

    let expandedPath = (privateKeyPath as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: expandedPath) else {
      throw CLIError.privateKeyNotFound("Private key not found at path: \(privateKeyPath)")
    }

    self.issuerID = trimmedIssuerID
    self.keyID = trimmedKeyID
    self.privateKeyPath = expandedPath
  }

  func apiConfiguration() throws -> APIConfiguration {
    let url = URL(fileURLWithPath: privateKeyPath)
    return try APIConfiguration(
      issuerID: issuerID,
      privateKeyID: keyID,
      privateKeyURL: url
    )
  }
}
