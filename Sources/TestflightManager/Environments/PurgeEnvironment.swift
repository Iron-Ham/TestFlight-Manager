import AppStoreConnect_Swift_SDK
import Foundation

struct PurgeEnvironment: @unchecked Sendable {
  typealias MetricsPeriod = APIEndpoint.V1.BetaGroups.WithID.Metrics.BetaTesterUsages.GetParameters
    .Period

  var loadCredentials: () throws -> Credentials?
  var fetchApps: (Credentials) async throws -> [App]
  var fetchBetaGroupsForApp: (Credentials, String) async throws -> [BetaGroup]
  var fetchBetaGroup: (Credentials, String) async throws -> BetaGroup
  var fetchBetaTesters: (Credentials, String) async throws -> [BetaTester]
  var fetchUsage: (Credentials, String, MetricsPeriod) async throws -> [String: Int]
  var removeTesters: (Credentials, String, [String]) async throws -> Void
  var print: (String) -> Void
  var prompt: (String) throws -> String?
  var confirm: (String) throws -> Bool

  static let live = PurgeEnvironment(
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
          fieldsBetaGroups: [.name, .publicLink, .publicLinkID],
          limit: 200
        )

      var groups: [BetaGroup] = []
      for try await page in provider.paged(request) {
        groups.append(contentsOf: page.data)
      }
      return groups
    },
    fetchBetaGroup: { credentials, groupID in
      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .betaGroups
        .id(groupID)
        .get(parameters: .init(fieldsBetaGroups: [.name, .app]))
      let response = try await provider.request(request)
      return response.data
    },
    fetchBetaTesters: { credentials, groupID in
      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .betaGroups
        .id(groupID)
        .betaTesters
        .get(
          fieldsBetaTesters: [.firstName, .lastName, .email, .state],
          limit: 200
        )

      var testers: [BetaTester] = []
      for try await page in provider.paged(request) {
        testers.append(contentsOf: page.data)
      }
      return testers
    },
    fetchUsage: { credentials, groupID, period in
      let provider = try makeProvider(from: credentials)
      let endpoint = APIEndpoint
        .v1
        .betaGroups
        .id(groupID)
        .metrics
        .betaTesterUsages
      let parameters = APIEndpoint
        .V1
        .BetaGroups
        .WithID
        .Metrics
        .BetaTesterUsages
        .GetParameters(
          period: period,
          groupBy: [.betaTesters],
          limit: 200
        )

      let request = Request<BetaTesterUsageMetricsResponse>(
        path: endpoint.path,
        method: "GET",
        query: parameters.asQuery,
        id: "betaGroups_betaTesterUsages_getMetrics_custom"
      )

      var sessionCounts: [String: Int] = [:]
      for try await page in provider.paged(request) {
        let pageCounts = page.sessionCountsByTester()
        for (testerID, totalSessions) in pageCounts {
          sessionCounts[testerID, default: 0] += totalSessions
        }
      }
      return sessionCounts
    },
    removeTesters: { credentials, groupID, testerIDs in
      guard !testerIDs.isEmpty else { return }

      let provider = try makeProvider(from: credentials)
      let request = APIEndpoint
        .v1
        .betaGroups
        .id(groupID)
        .relationships
        .betaTesters
        .delete(
          BetaGroupBetaTestersLinkagesRequest(
            data: testerIDs.map { .init(type: .betaTesters, id: $0) }
          )
        )

      try await provider.request(request)
    },
    print: { message in
      Swift.print(message)
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

extension PurgeEnvironment {
  fileprivate static func makeProvider(from credentials: Credentials) throws -> APIProvider {
    let configuration = try credentials.apiConfiguration()
    return APIProvider(configuration: configuration)
  }
}

actor PurgeEnvironmentProvider {
  static let shared = PurgeEnvironmentProvider()

  private var environment: PurgeEnvironment = .live

  func current() -> PurgeEnvironment {
    environment
  }

  func set(_ environment: PurgeEnvironment) {
    self.environment = environment
  }

  func reset() {
    environment = .live
  }
}

private struct BetaTesterUsageMetricsResponse: Decodable {
  let data: [Datum]
  let links: AppStoreConnect_Swift_SDK.PagedDocumentLinks
  let meta: AppStoreConnect_Swift_SDK.PagingInformation?

  struct Datum: Decodable {
    let dataPoints: [DataPoint]
    let dimensions: Dimensions?

    enum CodingKeys: String, CodingKey {
      case dataPoints
      case dimensions
    }

    init(dataPoints: [DataPoint], dimensions: Dimensions?) {
      self.dataPoints = dataPoints
      self.dimensions = dimensions
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)

      if let array = try? container.decode([DataPoint].self, forKey: .dataPoints) {
        self.dataPoints = array
      } else if let single = try? container.decode(DataPoint.self, forKey: .dataPoints) {
        self.dataPoints = [single]
      } else {
        self.dataPoints = []
      }

      self.dimensions = try container.decodeIfPresent(Dimensions.self, forKey: .dimensions)
    }
  }

  struct DataPoint: Decodable {
    let start: String?
    let end: String?
    let values: Values?

    struct Values: Decodable {
      let crashCount: Int?
      let sessionCount: Int?
      let feedbackCount: Int?
    }
  }

  struct Dimensions: Decodable {
    let betaTesters: BetaTesters?

    struct BetaTesters: Decodable {
      let data: String?

      private struct ResourceIdentifier: Decodable {
        let id: String?
      }

      init(data: String?) {
        self.data = data
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringValue = try? container.decode(String.self, forKey: .data) {
          self.init(data: stringValue)
          return
        }

        if let identifier = try? container.decode(ResourceIdentifier.self, forKey: .data),
          let id = identifier.id
        {
          self.init(data: id)
          return
        }

        if var unkeyed = try? container.nestedUnkeyedContainer(forKey: .data) {
          if let identifier = try? unkeyed.decode(ResourceIdentifier.self), let id = identifier.id {
            self.init(data: id)
            return
          }
          if let stringValue = try? unkeyed.decode(String.self) {
            self.init(data: stringValue)
            return
          }
        }

        self.init(data: nil)
      }

      private enum CodingKeys: String, CodingKey {
        case data
      }
    }
  }

  func sessionCountsByTester() -> [String: Int] {
    var counts: [String: Int] = [:]
    for datum in data {
      guard let testerID = datum.dimensions?.betaTesters?.data else { continue }
      let totalSessions = datum.dataPoints.reduce(0) { partial, point in
        partial + (point.values?.sessionCount ?? 0)
      }
      counts[testerID, default: 0] += totalSessions
    }
    return counts
  }
}
