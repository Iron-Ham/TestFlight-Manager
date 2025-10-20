import Foundation

struct LoginEnvironment: @unchecked Sendable {
  var makeCredentials: (String, String, String) throws -> Credentials
  var verifyCredentials: (Credentials) async throws -> Void
  var saveCredentials: (Credentials) throws -> URL
  var printer: (String) -> Void
  var loadConfiguration: () throws -> LoginConfiguration?

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
      Logger.stdout.notice(message)
    },
    loadConfiguration: {
      let store = ConfigurationStore()
      return try store.load()
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
