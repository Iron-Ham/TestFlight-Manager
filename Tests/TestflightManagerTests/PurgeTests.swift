import AppStoreConnect_Swift_SDK
import XCTest

@testable import TestFlightManager

final class PurgeTests: XCTestCase {
  private var temporaryFiles: [URL] = []

  override func tearDown() {
    for fileURL in temporaryFiles {
      try? FileManager.default.removeItem(at: fileURL)
    }
    temporaryFiles.removeAll()
    super.tearDown()
  }

  func testRunRemovesInactiveTesters() async throws {
    let credentials = try makeCredentials()

    var removedTesterIDs: [String] = []
    var printedMessages: [String] = []

    let testers = [
      makeTester(id: "active", email: "active@example.com"),
      makeTester(id: "inactive", email: "inactive@example.com"),
    ]

    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in
          XCTFail("fetchApps should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroupsForApp: { _, _ in
          XCTFail("fetchBetaGroupsForApp should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroup: { _, _ in
          BetaGroup(
            type: .betaGroups,
            id: "group",
            relationships: .init(
              app: .init(data: .init(type: .apps, id: "app"))
            )
          )
        },
        fetchBetaTesters: { _, _ in testers },
        fetchUsage: { _, _, _ in ["active": 5] },
        removeTestersFromGroup: { _, _, _ in XCTFail("removeTestersFromGroup should not be called") },
        removeTestersFromTestFlight: { _, ids in removedTesterIDs = ids },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Purge.parse([
      "--app-id", "app",
      "--beta-group-id", "group",
      "--period", "30d",
    ])

    try await command.run()

    XCTAssertEqual(removedTesterIDs, ["inactive"])
    XCTAssertTrue(printedMessages.contains { $0.contains("inactive tester") })
    XCTAssertTrue(printedMessages.contains { $0.contains("Removed 1 tester") })
  }

  func testDryRunDoesNotRemoveTesters() async throws {
    let credentials = try makeCredentials()

    var removeCallCount = 0
    var printedMessages: [String] = []

    let testers = [makeTester(id: "inactive", email: "test@example.com")]

    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in
          XCTFail("fetchApps should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroupsForApp: { _, _ in
          XCTFail("fetchBetaGroupsForApp should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroup: { _, _ in
          BetaGroup(
            type: .betaGroups,
            id: "group",
            relationships: .init(
              app: .init(data: .init(type: .apps, id: "app"))
            )
          )
        },
        fetchBetaTesters: { _, _ in testers },
        fetchUsage: { _, _, _ in [:] },
        removeTestersFromGroup: { _, _, _ in removeCallCount += 1 },
        removeTestersFromTestFlight: { _, _ in removeCallCount += 1 },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Purge.parse([
      "--app-id", "app",
      "--beta-group-id", "group",
      "--dry-run",
    ])

    try await command.run()

    XCTAssertEqual(removeCallCount, 0)
    XCTAssertTrue(printedMessages.contains("Dry run summary:"))
    XCTAssertTrue(printedMessages.contains(" - Total testers: 1"))
    XCTAssertTrue(printedMessages.contains(" - Inactive testers: 1"))
    XCTAssertTrue(printedMessages.contains("Dry run: no testers were removed."))
  }

  func testDryRunWritesInactiveTestersToFileWhenRequested() async throws {
    let credentials = try makeCredentials()

    var printedMessages: [String] = []
    let testers = [
      makeTester(id: "inactive", email: "inactive@example.com")
    ]

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("csv")
    temporaryFiles.append(outputURL)

    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchBetaGroup: { _, _ in
          BetaGroup(
            type: .betaGroups,
            id: "group",
            relationships: .init(
              app: .init(data: .init(type: .apps, id: "app"))
            )
          )
        },
        fetchBetaTesters: { _, _ in testers },
        fetchUsage: { _, _, _ in [:] },
        removeTestersFromGroup: { _, _, _ in XCTFail("removeTestersFromGroup should not be called") },
        removeTestersFromTestFlight: { _, _ in XCTFail("removeTestersFromTestFlight should not be called") },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Purge.parse([
      "--app-id", "app",
      "--beta-group-id", "group",
      "--dry-run",
      "--output-path", outputURL.path,
      "--output-format", "csv"
    ])

    try await command.run()

    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    let contents = try String(contentsOf: outputURL, encoding: .utf8)
    XCTAssertTrue(contents.contains("tester_id"))
    XCTAssertTrue(contents.contains("inactive"))
    XCTAssertFalse(printedMessages.contains(where: { $0.contains("inactive@example.com") }))
    XCTAssertTrue(
      printedMessages.contains {
        $0.contains(outputURL.lastPathComponent)
      }
    )
  }

  func testRunThrowsWhenCredentialsMissing() async {
    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { nil },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchBetaGroup: { _, _ in
          XCTFail("fetchBetaGroup should not be called when credentials are missing")
          return BetaGroup(type: .betaGroups, id: "group")
        },
        fetchBetaTesters: { _, _ in [] },
        fetchUsage: { _, _, _ in [:] },
        removeTestersFromGroup: { _, _, _ in },
        removeTestersFromTestFlight: { _, _ in },
        print: { _ in },
        prompt: { _ in nil },
        confirm: { _ in false }
      )
    )
    defer { Task { await provider.reset() } }

    do {
      let command = try Purge.parse([
        "--app-id", "app",
        "--beta-group-id", "group",
      ])
      try await command.run()
      XCTFail("Expected purge to throw when credentials are missing")
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

  func testRunThrowsWhenBetaGroupAppMismatch() async throws {
    let credentials = try makeCredentials()

    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in [] },
        fetchBetaGroupsForApp: { _, _ in [] },
        fetchBetaGroup: { _, _ in
          BetaGroup(
            type: .betaGroups,
            id: "group",
            relationships: .init(
              app: .init(data: .init(type: .apps, id: "different-app"))
            )
          )
        },
        fetchBetaTesters: { _, _ in [] },
        fetchUsage: { _, _, _ in [:] },
        removeTestersFromGroup: { _, _, _ in },
        removeTestersFromTestFlight: { _, _ in },
        print: { _ in },
        prompt: { _ in nil },
        confirm: { _ in false }
      )
    )
    defer { Task { await provider.reset() } }

    do {
      let command = try Purge.parse([
        "--app-id", "app",
        "--beta-group-id", "group",
      ])
      try await command.run()
      XCTFail("Expected purge to throw when beta group app mismatches")
    } catch let error as CLIError {
      if case .invalidInput(let message) = error {
        XCTAssertTrue(message.contains("does not belong"))
      } else {
        XCTFail("Unexpected CLIError: \(error)")
      }
    } catch {
      XCTFail("Unexpected error thrown: \(error)")
    }
  }

  func testRunRemovesTestersFromGroupOnlyWhenSpecified() async throws {
    let credentials = try makeCredentials()

    var removedFromGroupIDs: [String] = []
    var printedMessages: [String] = []

    let testers = [
      makeTester(id: "active", email: "active@example.com"),
      makeTester(id: "inactive", email: "inactive@example.com"),
    ]

    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in
          XCTFail("fetchApps should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroupsForApp: { _, _ in
          XCTFail("fetchBetaGroupsForApp should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroup: { _, _ in
          BetaGroup(
            type: .betaGroups,
            id: "group",
            relationships: .init(
              app: .init(data: .init(type: .apps, id: "app"))
            )
          )
        },
        fetchBetaTesters: { _, _ in testers },
        fetchUsage: { _, _, _ in ["active": 5] },
        removeTestersFromGroup: { _, _, ids in removedFromGroupIDs = ids },
        removeTestersFromTestFlight: { _, _ in XCTFail("removeTestersFromTestFlight should not be called") },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Purge.parse([
      "--app-id", "app",
      "--beta-group-id", "group",
      "--period", "30d",
      "--removal-scope", "group-only",
    ])

    try await command.run()

    XCTAssertEqual(removedFromGroupIDs, ["inactive"])
    XCTAssertTrue(printedMessages.contains { $0.contains("inactive tester") })
    XCTAssertTrue(printedMessages.contains { $0.contains("Removed 1 tester(s) from beta group") })
  }

  func testRunRemovesTestersFromTestFlightByDefault() async throws {
    let credentials = try makeCredentials()

    var removedFromTestFlightIDs: [String] = []
    var printedMessages: [String] = []

    let testers = [
      makeTester(id: "active", email: "active@example.com"),
      makeTester(id: "inactive", email: "inactive@example.com"),
    ]

    let provider = PurgeEnvironmentProvider.shared
    await provider.set(
      PurgeEnvironment(
        loadCredentials: { credentials },
        fetchApps: { _ in
          XCTFail("fetchApps should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroupsForApp: { _, _ in
          XCTFail("fetchBetaGroupsForApp should not be called when identifiers are provided")
          return []
        },
        fetchBetaGroup: { _, _ in
          BetaGroup(
            type: .betaGroups,
            id: "group",
            relationships: .init(
              app: .init(data: .init(type: .apps, id: "app"))
            )
          )
        },
        fetchBetaTesters: { _, _ in testers },
        fetchUsage: { _, _, _ in ["active": 5] },
        removeTestersFromGroup: { _, _, _ in XCTFail("removeTestersFromGroup should not be called") },
        removeTestersFromTestFlight: { _, ids in removedFromTestFlightIDs = ids },
        print: { printedMessages.append($0) },
        prompt: { _ in nil },
        confirm: { _ in true }
      )
    )
    defer { Task { await provider.reset() } }

    let command = try Purge.parse([
      "--app-id", "app",
      "--beta-group-id", "group",
      "--period", "30d",
    ])

    try await command.run()

    XCTAssertEqual(removedFromTestFlightIDs, ["inactive"])
    XCTAssertTrue(printedMessages.contains { $0.contains("inactive tester") })
    XCTAssertTrue(printedMessages.contains { $0.contains("Removed 1 tester(s) from TestFlight") })
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
    _ = FileManager.default.createFile(atPath: url.path, contents: data)
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
