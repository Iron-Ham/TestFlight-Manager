import AppStoreConnect_Swift_SDK
import ArgumentParser
import Foundation

@main
struct TestflightManager: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "CLI tool for managing TestFlight users via App Store Connect.",
    subcommands: [Login.self],
    defaultSubcommand: Login.self
  )
}

struct Login: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "login",
    abstract: "Authenticate with App Store Connect using an API key."
  )

  @Option(
    name: [.customLong("issuer-id")],
    help: "App Store Connect API issuer identifier."
  )
  var issuerID: String

  @Option(
    name: [.customLong("key-id")],
    help: "App Store Connect API key identifier."
  )
  var keyID: String

  @Option(
    name: [.customLong("private-key-path")],
    help: "Path to the .p8 private key file."
  )
  var privateKeyPath: String

  @Flag(
    name: [.customLong("skip-verification")],
    help: "Skip the API call used to verify the credentials."
  )
  var skipVerification: Bool = false

  func run() async throws {
  let environment = await LoginEnvironmentProvider.shared.current()
    let credentials = try environment.makeCredentials(issuerID, keyID, privateKeyPath)

    if !skipVerification {
      try await environment.verifyCredentials(credentials)
    }

    let fileURL = try environment.saveCredentials(credentials)
    environment.printer("Login succeeded. Saved credentials to \(fileURL.path).")
  }
}

struct LoginEnvironment: @unchecked Sendable {
  var makeCredentials: (String, String, String) throws -> Credentials
  var verifyCredentials: (Credentials) async throws -> Void
  var saveCredentials: (Credentials) throws -> URL
  var printer: (String) -> Void

  static let live = LoginEnvironment(
    makeCredentials: { issuerID, keyID, privateKeyPath in
      try Credentials(issuerID: issuerID, keyID: keyID, privateKeyPath: privateKeyPath)
    },
    verifyCredentials: { credentials in
      let verifier = CredentialsVerifier()
      try await verifier.verify(credentials: credentials)
    },
    saveCredentials: { credentials in
      let store = CredentialsStore()
      try store.save(credentials)
      return store.fileURL
    },
    printer: { message in
      print(message)
    }
  )
}

actor LoginEnvironmentProvider {
  static let shared = LoginEnvironmentProvider()

  private var environment: LoginEnvironment = .live

  func current() -> LoginEnvironment {
    environment
  }

  func set(_ environment: LoginEnvironment) {
    self.environment = environment
  }

  func reset() {
    environment = .live
  }
}

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

struct CredentialsVerifier {
  func verify(credentials: Credentials) async throws {
    let configuration = try credentials.apiConfiguration()
    let provider = APIProvider(configuration: configuration)

    let request = APIEndpoint
      .v1
      .apps
      .get(parameters: .init(limit: 1))

    do {
      _ = try await provider.request(request).data
      print("Verification succeeded.")
    } catch APIProvider.Error.requestFailure(let statusCode, let errorResponse, _) {
      let details = errorResponse?.errors?.map { "\($0.code): \($0.detail ?? $0.title)" }.joined(
        separator: ", "
      )
      throw CLIError.verificationFailed(
        "Request failed with status code \(statusCode). Details: \(details ?? "unknown error")."
      )
    } catch {
      throw CLIError.verificationFailed(error.localizedDescription)
    }
  }
}

struct CredentialsStore {
  private let fileManager = FileManager.default
  let fileURL: URL

  init() {
    let baseDirectory = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("testflight-mgmt", isDirectory: true)
    self.fileURL = baseDirectory.appendingPathComponent("credentials.json", isDirectory: false)
  }

  func save(_ credentials: Credentials) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(credentials)

    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: [.atomic])
  }
}

enum CLIError: Error, CustomStringConvertible {
  case invalidInput(String)
  case privateKeyNotFound(String)
  case verificationFailed(String)

  var description: String {
    switch self {
    case .invalidInput(let message):
      return message
    case .privateKeyNotFound(let message):
      return message
    case .verificationFailed(let message):
      return "Verification failed: \(message)"
    }
  }
}

extension CLIError: LocalizedError {
  var errorDescription: String? { description }
}
