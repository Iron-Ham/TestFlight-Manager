import XCTest

@testable import TestflightManager

final class ConfigTests: XCTestCase {
  private var temporaryFiles: [URL] = []

  override func tearDown() {
    for fileURL in temporaryFiles {
      try? FileManager.default.removeItem(at: fileURL)
    }
    temporaryFiles.removeAll()
    super.tearDown()
  }

  func testRunSavesProvidedValues() async throws {
    let provider = ConfigEnvironmentProvider.shared
    let keyURL = try makeTemporaryKeyFile()

    var responses: [String?] = ["NEW_ISSUER", "NEW_KEY", keyURL.path]
    var savedConfiguration: LoginConfiguration?
    var printedMessages: [String] = []
    let expectedURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")

    await provider.set(
      ConfigEnvironment(
        loadConfiguration: {
          nil
        },
        saveConfiguration: { configuration in
          savedConfiguration = configuration
          return expectedURL
        },
        prompt: { _, _ in
          responses.removeFirst()
        },
        print: { message in
          printedMessages.append(message)
        }
      )
    )
    defer { Task { await provider.reset() } }

    let command = Config()
    try await command.run()

    XCTAssertEqual(savedConfiguration?.issuerID, "NEW_ISSUER")
    XCTAssertEqual(savedConfiguration?.keyID, "NEW_KEY")
    XCTAssertEqual(savedConfiguration?.privateKeyPath, keyURL.path)
    XCTAssertTrue(printedMessages.last?.contains(expectedURL.path) ?? false)
  }

  func testRunKeepsExistingValuesWhenInputEmpty() async throws {
    let provider = ConfigEnvironmentProvider.shared

    var responses: [String?] = [nil, "  ", nil]
    var savedConfiguration: LoginConfiguration?
    let existing = LoginConfiguration(
      issuerID: "EXISTING_ISSUER",
      keyID: "EXISTING_KEY",
      privateKeyPath: "/tmp/existing.p8"
    )

    await provider.set(
      ConfigEnvironment(
        loadConfiguration: {
          existing
        },
        saveConfiguration: { configuration in
          savedConfiguration = configuration
          return URL(fileURLWithPath: "/tmp/unused.json")
        },
        prompt: { _, _ in
          responses.removeFirst()
        },
        print: { _ in }
      )
    )
    defer { Task { await provider.reset() } }

    let command = Config()
    try await command.run()

    XCTAssertEqual(savedConfiguration, existing)
  }

  func testRunRePromptsUntilPrivateKeyValid() async throws {
    let provider = ConfigEnvironmentProvider.shared
    let validKeyURL = try makeTemporaryKeyFile()

    var responses: [String?] = [nil, nil, "/tmp/invalid.p8", validKeyURL.path]
    var savedConfiguration: LoginConfiguration?
    var printedMessages: [String] = []

    await provider.set(
      ConfigEnvironment(
        loadConfiguration: {
          LoginConfiguration()
        },
        saveConfiguration: { configuration in
          savedConfiguration = configuration
          return URL(fileURLWithPath: "/tmp/saved.json")
        },
        prompt: { _, _ in
          responses.removeFirst()
        },
        print: { message in
          printedMessages.append(message)
        }
      )
    )
    defer { Task { await provider.reset() } }

    let command = Config()
    try await command.run()

    XCTAssertEqual(savedConfiguration?.privateKeyPath, validKeyURL.path)
    XCTAssertTrue(printedMessages.contains(where: { $0.contains("No file found") }))
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
