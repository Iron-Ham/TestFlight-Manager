import AppStoreConnect_Swift_SDK
import Foundation

struct RemoveUngroupedEnvironment: @unchecked Sendable {
  var loadCredentials: () throws -> Credentials?
  var fetchApps: (Credentials) async throws -> [App]
  var fetchBetaGroupsForApp: (Credentials, String) async throws -> [BetaGroup]
  var fetchAppTesters: (Credentials, String) async throws -> [BetaTester]
  var fetchBetaGroupTesters: (Credentials, String) async throws -> [BetaTester]
  var removeAppTesters: (Credentials, String, [String]) async throws -> Void
  var print: (String) -> Void
  var prompt: (String) throws -> String?
  var confirm: (String) throws -> Bool

  static let live = RemoveUngroupedEnvironment(
    loadCredentials: {
      let store = CredentialsStore()
      return try store.load()
    },
    fetchApps: { credentials in
      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .apps
        .get(
          parameters: .init(
            sort: [.name],
            fieldsApps: [.name, .bundleID],
            limit: 200
          )
        )

      var apps: [App] = []
      for try await page in provider.paged(request) {
        apps.append(contentsOf: page.data)
      }
      return apps
    },
    fetchBetaGroupsForApp: { credentials, appID in
      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .apps
        .id(appID)
        .betaGroups
        .get(
          fieldsBetaGroups: [.name],
          limit: 200
        )

      let progressLogger = Logger.stdout
      let progressTheme = progressLogger.consoleTheme
      progressLogger.notice(
        "Fetching beta groups for app "
          + progressLogger.applying(progressTheme.emphasis, to: appID)
          + "..."
      )

      var groups: [BetaGroup] = []
      for try await page in provider.paged(request) {
        groups.append(contentsOf: page.data)
      }

      let totalLabel = progressLogger.applying(progressTheme.emphasis, to: "\(groups.count)")
      progressLogger.notice("Found " + totalLabel + " beta group(s).")
      return groups
    },
    fetchAppTesters: { credentials, appID in
      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .betaTesters
        .get(
          parameters: .init(
            filterApps: [appID],
            fieldsBetaTesters: [.firstName, .lastName, .email, .state],
            limit: 200
          )
        )

      let progressLogger = Logger.stdout
      let progressTheme = progressLogger.consoleTheme
      progressLogger.notice(
        "Fetching all beta testers for app "
          + progressLogger.applying(progressTheme.emphasis, to: appID)
          + "..."
      )

      var testers: [BetaTester] = []
      var pageIndex = 0
      var lastReportedCount = 0
      for try await page in provider.paged(request) {
        pageIndex += 1
        testers.append(contentsOf: page.data)
        let total = testers.count
        if pageIndex == 1 || total - lastReportedCount >= 500 {
          let formattedCount = progressLogger.applying(progressTheme.emphasis, to: "\(total)")
          progressLogger.info("Fetched " + formattedCount + " beta tester(s)...")
          lastReportedCount = total
        }
      }
      let totalLabel = progressLogger.applying(progressTheme.emphasis, to: "\(testers.count)")
      progressLogger.notice("Completed fetching " + totalLabel + " beta tester(s).")
      return testers
    },
    fetchBetaGroupTesters: { credentials, groupID in
      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .betaGroups
        .id(groupID)
        .betaTesters
        .get(
          fieldsBetaTesters: [.email],
          limit: 200
        )

      var testers: [BetaTester] = []
      for try await page in provider.paged(request) {
        testers.append(contentsOf: page.data)
      }
      return testers
    },
    removeAppTesters: { credentials, appID, testerIDs in
      guard !testerIDs.isEmpty else { return }

      let provider = try makeProvider(from: credentials)
      let progressLogger = Logger.stdout
      let progressTheme = progressLogger.consoleTheme

      progressLogger.notice(
        "Removing "
          + progressLogger.applying(progressTheme.emphasis, to: "\(testerIDs.count)")
          + " tester(s) from app..."
      )

      // The API requires removing testers one at a time or in small batches
      // We'll batch them in groups of 100 for efficiency
      let batchSize = 100
      var removedCount = 0

      for batchStart in stride(from: 0, to: testerIDs.count, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, testerIDs.count)
        let batch = Array(testerIDs[batchStart..<batchEnd])

        let request = APIEndpoint
          .v1
          .apps
          .id(appID)
          .relationships
          .betaTesters
          .delete(
            AppBetaTestersLinkagesRequest(
              data: batch.map { .init(type: .betaTesters, id: $0) }
            )
          )

        try await provider.request(request)
        removedCount += batch.count

        if testerIDs.count > batchSize {
          progressLogger.info(
            "Removed "
              + progressLogger.applying(progressTheme.emphasis, to: "\(removedCount)")
              + " of "
              + progressLogger.applying(progressTheme.emphasis, to: "\(testerIDs.count)")
              + " tester(s)..."
          )
        }
      }

      progressLogger.notice(
        "Successfully removed "
          + progressLogger.applying(progressTheme.emphasis, to: "\(removedCount)")
          + " tester(s)."
      )
    },
    print: { message in
      Logger.stdout.info(message)
    },
    prompt: { message in
      FileHandle.standardOutput.write(Data(message.utf8))
      return readLine()
    },
    confirm: { message in
      FileHandle.standardOutput.write(Data(message.utf8))
      let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return response == "y" || response == "yes"
    }
  )
}

extension RemoveUngroupedEnvironment {
  fileprivate static func makeProvider(from credentials: Credentials) throws -> APIProvider {
    let configuration = try credentials.apiConfiguration()
    return APIProvider(configuration: configuration)
  }
}

actor RemoveUngroupedEnvironmentProvider {
  static let shared = RemoveUngroupedEnvironmentProvider()

  private var environment: RemoveUngroupedEnvironment = .live

  func current() -> RemoveUngroupedEnvironment {
    environment
  }

  func set(_ environment: RemoveUngroupedEnvironment) {
    self.environment = environment
  }

  func reset() {
    environment = .live
  }
}
