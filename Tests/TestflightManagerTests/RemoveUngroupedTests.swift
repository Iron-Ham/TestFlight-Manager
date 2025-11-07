import AppStoreConnect_Swift_SDK
import XCTest

@testable import TestFlightManager

final class RemoveUngroupedTests: XCTestCase {
  private var temporaryFiles: [URL] = []

  override func tearDown() {
    for fileURL in temporaryFiles {
      try? FileManager.default.removeItem(at: fileURL)
    }
    temporaryFiles.removeAll()
    super.tearDown()
  }

  func testRunRemovesUngroupedTesters() async throws {
    let credentials = try makeCredentials()

    var removedTesterIDs: [String] = []
    var printedMessages: [String] = []

    let appTesters = [
      makeTester(id: "grouped1", email: "grouped1@example.com"),
      makeTester(id: "grouped2", email: "grouped2@example.com"),
      makeTester(id: "ungrouped1", email: "ungrouped1@example.com"),
      makeTester(id: "ungrouped2", email: "ungrouped2@example.com"),
    ]

    let groupTesters = [
      makeTester(id: "grouped1", email: "grouped1@example.com"),
      makeTester(id: "grouped2", email: "grouped2@example.com"),
    ]

    let provider = RemoveUngroupedEnvironmentProvider.shared
    await provider.set(
      RemoveUngroupedEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in
          XCTFail("fetchApps should not be called when app ID is provided")
          return []
        },
        fetchBetaGroupsForApp: { _, _ in
          [BetaGroup(type: .betaGroups, id: "group1")]
        },
        fetchAppTesters: { _, _ in appTesters },
        fetchBetaGroupTesters: { _, _ in groupTesters },
        removeAppTesters: { _, _, ids in removedTesterIDs = ids },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try RemoveUngrouped.parse([
      "--app-id", "app123",
    ])

    try await command.run()

    XCTAssertEqual(Set(removedTesterIDs), Set(["ungrouped1", "ungrouped2"]))
    XCTAssertTrue(printedMessages.contains { $0.contains("2 ungrouped tester") })
    XCTAssertTrue(printedMessages.contains { $0.contains("Removed 2") })
  }

  func testDryRunDoesNotRemoveTesters() async throws {
    let credentials = try makeCredentials()

    var removeCallCount = 0
    var printedMessages: [String] = []

    let appTesters = [makeTester(id: "ungrouped", email: "test@example.com")]

    let provider = RemoveUngroupedEnvironmentProvider.shared
    await provider.set(
      RemoveUngroupedEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in
          XCTFail("fetchApps should not be called when app ID is provided")
          return []
        },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchAppTesters: { _, _ in appTesters },
        fetchBetaGroupTesters: { _, _ in [] },
        removeAppTesters: { _, _, _ in removeCallCount += 1 },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try RemoveUngrouped.parse([
      "--app-id", "app123",
      "--dry-run",
    ])

    try await command.run()

    XCTAssertEqual(removeCallCount, 0)
    XCTAssertTrue(printedMessages.contains("Dry run summary:"))
    XCTAssertTrue(printedMessages.contains(" - Total app testers: 1"))
    XCTAssertTrue(printedMessages.contains(" - Ungrouped testers: 1"))
    XCTAssertTrue(printedMessages.contains("Dry run: no testers were removed."))
  }

  func testDryRunWritesUngroupedTestersToFileWhenRequested() async throws {
    let credentials = try makeCredentials()

    var printedMessages: [String] = []
    let appTesters = [
      makeTester(id: "ungrouped", email: "ungrouped@example.com")
    ]

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("csv")
    temporaryFiles.append(outputURL)

    let provider = RemoveUngroupedEnvironmentProvider.shared
    await provider.set(
      RemoveUngroupedEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchAppTesters: { _, _ in appTesters },
        fetchBetaGroupTesters: { _, _ in [] },
        removeAppTesters: { _, _, _ in XCTFail("removeAppTesters should not be called") },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try RemoveUngrouped.parse([
      "--app-id", "app123",
      "--dry-run",
      "--output-path", outputURL.path,
      "--output-format", "csv",
    ])

    try await command.run()

    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    let contents = try String(contentsOf: outputURL)
    XCTAssertTrue(contents.contains("tester_id"))
    XCTAssertTrue(contents.contains("ungrouped"))
    XCTAssertFalse(printedMessages.contains(where: { $0.contains("ungrouped@example.com") }))
    XCTAssertTrue(
      printedMessages.contains {
        $0.contains(outputURL.lastPathComponent)
      }
    )
  }

  func testRunThrowsWhenCredentialsMissing() async {
    let provider = RemoveUngroupedEnvironmentProvider.shared
    await provider.set(
      RemoveUngroupedEnvironment(
        loadCredentials: { nil },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchAppTesters: { _, _ in
          XCTFail("fetchAppTesters should not be called when credentials are missing")
          return []
        },
        fetchBetaGroupTesters: { _, _ in [] },
        removeAppTesters: { _, _, _ in },
        print: { _ in },
        prompt: { _ in nil },
        confirm: { _ in false }
      )
    )
    defer { Task { await provider.reset() } }

    do {
      let command = try RemoveUngrouped.parse([
        "--app-id", "app123",
      ])
      try await command.run()
      XCTFail("Expected command to throw when credentials are missing")
    } catch let error as CLIError {
      if case .credentialsNotFound(let message) = error {
        XCTAssertTrue(message.contains("login"))
      } else {
        XCTFail("Unexpected CLIError: \(error)")
      }
    } catch {
      XCTFail("Unexpected error thrown: \(error)")
    }
  }

  func testRunHandlesNoUngroupedTesters() async throws {
    let credentials = try makeCredentials()

    var printedMessages: [String] = []

    let appTesters = [
      makeTester(id: "grouped", email: "grouped@example.com")
    ]

    let groupTesters = [
      makeTester(id: "grouped", email: "grouped@example.com")
    ]

    let provider = RemoveUngroupedEnvironmentProvider.shared
    await provider.set(
      RemoveUngroupedEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in
          [BetaGroup(type: .betaGroups, id: "group1")]
        },
        fetchAppTesters: { _, _ in appTesters },
        fetchBetaGroupTesters: { _, _ in groupTesters },
        removeAppTesters: { _, _, _ in XCTFail("removeAppTesters should not be called") },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try RemoveUngrouped.parse([
      "--app-id", "app123",
    ])

    try await command.run()

    XCTAssertTrue(printedMessages.contains { $0.contains("No ungrouped testers found") })
  }

  func testRunHandlesNoAppTesters() async throws {
    let credentials = try makeCredentials()

    var printedMessages: [String] = []

    let provider = RemoveUngroupedEnvironmentProvider.shared
    await provider.set(
      RemoveUngroupedEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchAppTesters: { _, _ in [] },
        fetchBetaGroupTesters: { _, _ in [] },
        removeAppTesters: { _, _, _ in XCTFail("removeAppTesters should not be called") },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try RemoveUngrouped.parse([
      "--app-id", "app123",
    ])

    try await command.run()

    XCTAssertTrue(printedMessages.contains { $0.contains("No testers found for app") })
  }

  private func makeCredentials() throws -> Credentials {
    let keyURL = try makeTemporaryKeyFile()
    return try Credentials(issuerID: "ISSUER", keyID: "KEY", privateKeyPath: keyURL.path)
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

  private func makeTester(id: String, email: String) -> BetaTester {
    BetaTester(
      type: .betaTesters,
      id: id,
      attributes: .init(email: email)
    )
  }
}
