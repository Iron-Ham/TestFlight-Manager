import XCTest

@testable import TestflightManager

final class LoginTests: XCTestCase {
  private var temporaryFiles: [URL] = []

  override func tearDown() {
    for fileURL in temporaryFiles {
      try? FileManager.default.removeItem(at: fileURL)
    }
    temporaryFiles.removeAll()
    super.tearDown()
  }

  func testRunVerifiesAndSavesCredentials() async throws {
    let keyURL = try makeTemporaryKeyFile()
    let expectedSaveURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")

    var verifiedCredentials: [Credentials] = []
    var savedCredentials: Credentials?
    var printedMessages: [String] = []

    let provider = LoginEnvironmentProvider.shared
    await provider.set(
      LoginEnvironment(
        makeCredentials: { issuerID, keyID, privateKeyPath in
          XCTAssertEqual(issuerID, "ISSUER")
          XCTAssertEqual(keyID, "KEY")
          XCTAssertEqual(privateKeyPath, keyURL.path)
          return try Credentials(issuerID: issuerID, keyID: keyID, privateKeyPath: privateKeyPath)
        },
        verifyCredentials: { credentials in
          verifiedCredentials.append(credentials)
        },
        saveCredentials: { credentials in
          savedCredentials = credentials
          return expectedSaveURL
        },
        printer: { message in
          printedMessages.append(message)
        },
        loadConfiguration: {
          nil
        }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Login.parse([
      "--issuer-id", "ISSUER",
      "--key-id", "KEY",
      "--private-key-path", keyURL.path,
    ])
    try await command.run()

    XCTAssertEqual(verifiedCredentials.count, 1)
    XCTAssertEqual(savedCredentials?.issuerID, "ISSUER")
    XCTAssertEqual(savedCredentials?.keyID, "KEY")
    XCTAssertEqual(savedCredentials?.privateKeyPath, keyURL.path)
    XCTAssertEqual(
      printedMessages.last,
      "Login succeeded. Saved credentials to \(expectedSaveURL.path)."
    )

  }

  func testRunSkipsVerificationWhenFlagProvided() async throws {
    let keyURL = try makeTemporaryKeyFile()
    let expectedSaveURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")

    var verificationCallCount = 0

    let provider = LoginEnvironmentProvider.shared
    await provider.set(
      LoginEnvironment(
        makeCredentials: { issuerID, keyID, privateKeyPath in
          try Credentials(issuerID: issuerID, keyID: keyID, privateKeyPath: privateKeyPath)
        },
        verifyCredentials: { _ in
          verificationCallCount += 1
        },
        saveCredentials: { _ in
          expectedSaveURL
        },
        printer: { _ in },
        loadConfiguration: {
          nil
        }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Login.parse([
      "--issuer-id", "ISSUER",
      "--key-id", "KEY",
      "--private-key-path", keyURL.path,
      "--skip-verification",
    ])
    try await command.run()

    XCTAssertEqual(verificationCallCount, 0)
  }

  func testRunUsesConfigurationDefaultsWhenOptionsOmitted() async throws {
    let keyURL = try makeTemporaryKeyFile()
    let expectedSaveURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")

    var savedCredentials: Credentials?
    var recordedIssuerID: String?
    var recordedKeyID: String?
    var recordedPath: String?

    let provider = LoginEnvironmentProvider.shared
    await provider.set(
      LoginEnvironment(
        makeCredentials: { issuerID, keyID, privateKeyPath in
          recordedIssuerID = issuerID
          recordedKeyID = keyID
          recordedPath = privateKeyPath
          return try Credentials(issuerID: issuerID, keyID: keyID, privateKeyPath: privateKeyPath)
        },
        verifyCredentials: { _ in },
        saveCredentials: { credentials in
          savedCredentials = credentials
          return expectedSaveURL
        },
        printer: { _ in },
        loadConfiguration: {
          LoginConfiguration(
            issuerID: "CONFIG_ISSUER",
            keyID: "CONFIG_KEY",
            privateKeyPath: keyURL.path
          )
        }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Login.parse([])
    try await command.run()

    XCTAssertEqual(recordedIssuerID, "CONFIG_ISSUER")
    XCTAssertEqual(recordedKeyID, "CONFIG_KEY")
    XCTAssertEqual(recordedPath, keyURL.path)
    XCTAssertEqual(savedCredentials?.issuerID, "CONFIG_ISSUER")
    XCTAssertEqual(savedCredentials?.keyID, "CONFIG_KEY")
    XCTAssertEqual(savedCredentials?.privateKeyPath, keyURL.path)
  }

  func testRunFailsWhenRequiredValueMissing() async {
    let provider = LoginEnvironmentProvider.shared
    await provider.set(
      LoginEnvironment(
        makeCredentials: { _, _, _ in
          XCTFail("Credentials should not be created when required input is missing.")
          throw CLIError.invalidInput("unexpected")
        },
        verifyCredentials: { _ in
          XCTFail("Verification should not run when required input is missing.")
        },
        saveCredentials: { _ in
          XCTFail("Save should not run when required input is missing.")
          return URL(fileURLWithPath: "/tmp/unexpected.json")
        },
        printer: { _ in },
        loadConfiguration: {
          LoginConfiguration()
        }
      )
    )
    defer { Task { await provider.reset() } }

    do {
      let command = try Login.parse([])
      try await command.run()
      XCTFail("Expected login to throw when configuration is incomplete.")
    } catch let error as CLIError {
      if case .invalidInput(let message) = error {
        XCTAssertTrue(message.contains("issuer ID"))
      } else {
        XCTFail("Unexpected CLIError thrown: \(error)")
      }
    } catch {
      XCTFail("Unexpected error thrown: \(error)")
    }
  }

  func testRunPropagatesCredentialCreationError() async {
    let provider = LoginEnvironmentProvider.shared
    await provider.set(
      LoginEnvironment(
        makeCredentials: { _, _, _ in
          throw CLIError.invalidInput("bad input")
        },
        verifyCredentials: { _ in
          XCTFail("Verification should not be called when credential creation fails.")
        },
        saveCredentials: { _ in
          XCTFail("Save should not be called when credential creation fails.")
          return URL(fileURLWithPath: "/tmp/should-not-exist.json")
        },
        printer: { _ in
          XCTFail("Printer should not be called when credential creation fails.")
        },
        loadConfiguration: {
          nil
        }
      )
    )
    defer { Task { await provider.reset() } }

    do {
      let command = try Login.parse([
        "--issuer-id", "ISSUER",
        "--key-id", "KEY",
        "--private-key-path", "/tmp/non-existent.p8",
      ])
      try await command.run()
      XCTFail("Expected credential creation to throw.")
    } catch let error as CLIError {
      if case .invalidInput(let message) = error {
        XCTAssertEqual(message, "bad input")
      } else {
        XCTFail("Unexpected CLIError thrown: \(error)")
      }
    } catch {
      XCTFail("Unexpected error thrown: \(error)")
    }
  }

  private func makeTemporaryKeyFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("p8")
    let data = Data("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n".utf8)
    FileManager.default.createFile(atPath: url.path, contents: data)
    temporaryFiles.append(url)
    return url
  }
}
