import AppStoreConnect_Swift_SDK
import ArgumentParser
import Foundation

struct Purge: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "purge",
    abstract: "Remove inactive testers from a TestFlight beta group."
  )

  enum InactivityWindow: String, ExpressibleByArgument {
    case days7 = "7d"
    case days30 = "30d"
    case days90 = "90d"
    case days365 = "365d"

    var sdkValue: PurgeEnvironment.MetricsPeriod {
      switch self {
      case .days7:
        return .p7d
      case .days30:
        return .p30d
      case .days90:
        return .p90d
      case .days365:
        return .p365d
      }
    }

    var description: String {
      switch self {
      case .days7:
        return "7 days"
      case .days30:
        return "30 days"
      case .days90:
        return "90 days"
      case .days365:
        return "365 days"
      }
    }
  }

  @Option(
    name: [.customLong("app-id")],
    help: "Identifier of the app that owns the beta group."
  )
  var appID: String?

  @Option(
    name: [.customLong("beta-group-id")],
    help: "Identifier of the beta group to purge."
  )
  var betaGroupID: String?

  @Option(
    name: [.customLong("period")],
    help: "Inactivity window (7d, 30d, 90d, or 365d)."
  )
  var period: InactivityWindow?

  @Flag(
    name: [.customLong("dry-run")],
    help: "List inactive testers without removing them."
  )
  var dryRun: Bool = false
  @Flag(
    name: [.customLong("interactive"), .short],
    help: "Prompt to select options when not provided."
  )
  var interactive: Bool = false

  func run() async throws {
    let environment = await PurgeEnvironmentProvider.shared.current()

    do {
      guard let credentials = try environment.loadCredentials() else {
        throw CLIError.credentialsNotFound(
          "No saved credentials. Run 'TestFlightManager login' before purging testers."
        )
      }

      let context = try await resolveContext(using: environment, credentials: credentials)
      let betaGroup = try await environment.fetchBetaGroup(credentials, context.betaGroupID)
      let relationshipAppID = betaGroup.relationships?.app?.data?.id
      let groupMatchesApp: Bool

      if let relationshipAppID {
        groupMatchesApp = relationshipAppID == context.appID
      } else {
        let groupsForApp = try await environment.fetchBetaGroupsForApp(credentials, context.appID)
        groupMatchesApp = groupsForApp.contains(where: { $0.id == betaGroup.id })
      }

      guard groupMatchesApp else {
        throw CLIError.invalidInput(
          "Beta group \(context.betaGroupID) does not belong to app \(context.appID)."
        )
      }

      let testers = try await environment.fetchBetaTesters(credentials, context.betaGroupID)
      guard !testers.isEmpty else {
        environment.print("No testers found in beta group \(context.betaGroupID).")
        return
      }

      let sessionCounts = try await environment.fetchUsage(
        credentials,
        context.betaGroupID,
        context.period.sdkValue
      )

      let inactiveTesters = testers.filter { tester in
        let sessions = sessionCounts[tester.id] ?? 0
        return sessions == 0
      }

      guard !inactiveTesters.isEmpty else {
        environment.print(
          "No inactive testers found for beta group \(context.betaGroupID) in the last \(context.period.description)."
        )
        return
      }

      environment.print(
        "Found \(inactiveTesters.count) inactive tester(s) with no sessions in the last \(context.period.description):"
      )

      let sortedInactive = inactiveTesters.sorted { lhs, rhs in
        displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs))
          == .orderedAscending
      }

      for tester in sortedInactive {
        environment.print(" - \(displayName(for: tester))")
      }

      var shouldDryRun = context.dryRun
      if context.requiresConfirmation {
        let confirmed = try environment.confirm("Proceed with removal? (y/N): ")
        if !confirmed {
          shouldDryRun = true
        }
      }

      if shouldDryRun {
        environment.print("Dry run summary:")
        environment.print(" - Total testers: \(testers.count)")
        environment.print(" - Inactive testers: \(inactiveTesters.count)")
        environment.print("Dry run: no testers were removed.")
        return
      }

      try await environment.removeTesters(
        credentials,
        context.betaGroupID,
        inactiveTesters.map { $0.id }
      )

      environment.print(
        "Removed \(inactiveTesters.count) tester(s) from beta group \(context.betaGroupID)."
      )
    } catch let error as CLIError {
      throw error
    } catch let error as APIProvider.Error {
      throw CLIError.apiFailure(error.localizedDescription)
    } catch {
      throw error
    }
  }

  private func displayName(for tester: BetaTester) -> String {
    let attributes = tester.attributes
    let first = attributes?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let last = attributes?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let email = attributes?.email?.trimmingCharacters(in: .whitespacesAndNewlines)

    let components = [first, last].compactMap { $0 }.filter { !$0.isEmpty }
    let fullName = components.joined(separator: " ")

    if !fullName.isEmpty, let email, !email.isEmpty {
      return "\(fullName) <\(email)>"
    }

    if !fullName.isEmpty {
      return fullName
    }

    if let email, !email.isEmpty {
      return email
    }

    return tester.id
  }
}

extension Purge {
  fileprivate struct RunContext {
    let appID: String
    let betaGroupID: String
    let period: InactivityWindow
    let dryRun: Bool
    let requiresConfirmation: Bool
  }

  fileprivate func resolveContext(using environment: PurgeEnvironment, credentials: Credentials)
    async throws -> RunContext
  {
    let shouldPrompt = interactive || appID == nil || betaGroupID == nil
    if !shouldPrompt {
      guard let appID, let betaGroupID else {
        throw CLIError.invalidInput(
          "App ID and beta group ID are required when interactive mode is disabled."
        )
      }
      return RunContext(
        appID: appID,
        betaGroupID: betaGroupID,
        period: period ?? .days30,
        dryRun: dryRun,
        requiresConfirmation: false
      )
    }

    let apps = try await environment.fetchApps(credentials)
    guard !apps.isEmpty else {
      throw CLIError.invalidInput("No apps accessible with the current credentials.")
    }

    let selectedAppID = try selectAppID(current: appID, apps: apps, environment: environment)

    let groups = try await environment.fetchBetaGroupsForApp(credentials, selectedAppID)
    guard !groups.isEmpty else {
      throw CLIError.invalidInput("App \(selectedAppID) has no beta groups.")
    }

    let selectedGroupID = try selectGroupID(
      current: betaGroupID,
      groups: groups,
      environment: environment
    )
    let resolvedPeriod = try selectPeriod(current: period, environment: environment)
    let resolvedDryRun: Bool
    if dryRun {
      resolvedDryRun = true
    } else {
      resolvedDryRun = try askDryRun(preselected: dryRun, environment: environment)
    }

    return RunContext(
      appID: selectedAppID,
      betaGroupID: selectedGroupID,
      period: resolvedPeriod,
      dryRun: resolvedDryRun,
      requiresConfirmation: !resolvedDryRun
    )
  }

  fileprivate func selectAppID(current: String?, apps: [App], environment: PurgeEnvironment) throws
    -> String
  {
    if let current, apps.contains(where: { $0.id == current }) {
      return current
    }

    environment.print("Select an app:")
    let appLogger = Logger.stdout
    let appTheme = appLogger.consoleTheme
    let appDivider = appLogger.applying(appTheme.muted, to: " → ")
    let appBullet = appLogger.applying(appTheme.muted, to: " • ")

    for (index, app) in apps.enumerated() {
      let name = app.attributes?.name ?? "(no name)"
      let bundleID = app.attributes?.bundleID?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      let cleanedBundleID = bundleID.flatMap { $0.isEmpty ? nil : $0 }

      let indexLabel = appLogger.applying(appTheme.metadata, to: "[")
        + appLogger.applying(appTheme.emphasis, to: "\(index + 1)")
        + appLogger.applying(appTheme.metadata, to: "]")

      let nameStyled = appLogger.applying(appTheme.commitSubject, to: name)
      var details: [String] = []
      if let cleanedBundleID {
        details.append(appLogger.applying(appTheme.path, to: cleanedBundleID))
      }
      details.append(appLogger.applying(appTheme.metadata, to: "id: \(app.id)"))

      let suffix = details.isEmpty ? "" : appDivider + details.joined(separator: appBullet)
      environment.print(" \(indexLabel) \(nameStyled)\(suffix)")
    }

    while true {
      let input = try environment.prompt("Enter choice (1-\(apps.count)): ")?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if let input, let value = Int(input), (1...apps.count).contains(value) {
        return apps[value - 1].id
      }
    }
  }

  fileprivate func selectGroupID(
    current: String?,
    groups: [BetaGroup],
    environment: PurgeEnvironment
  ) throws -> String {
    if let current, groups.contains(where: { $0.id == current }) {
      return current
    }

    environment.print("Select a beta group:")
    let groupLogger = Logger.stdout
    let groupTheme = groupLogger.consoleTheme
    let groupDivider = groupLogger.applying(groupTheme.muted, to: " → ")
    let groupBullet = groupLogger.applying(groupTheme.muted, to: " • ")

    for (index, group) in groups.enumerated() {
      let name = group.attributes?.name ?? "(no name)"
      let publicLink = group.attributes?.publicLink
      let publicLinkID = group.attributes?.publicLinkID

      let indexLabel = groupLogger.applying(groupTheme.metadata, to: "[")
        + groupLogger.applying(groupTheme.emphasis, to: "\(index + 1)")
        + groupLogger.applying(groupTheme.metadata, to: "]")

      let nameStyled = groupLogger.applying(groupTheme.commitSubject, to: name)
      var details: [String] = [groupLogger.applying(groupTheme.metadata, to: "id: \(group.id)")]
      if let publicLink {
        details.append(groupLogger.applying(groupTheme.path, to: publicLink))
      }
      if let publicLinkID {
        details.append(groupLogger.applying(groupTheme.metadata, to: "link-id: \(publicLinkID)"))
      }

      let suffix = details.isEmpty ? "" : groupDivider + details.joined(separator: groupBullet)
      environment.print(" \(indexLabel) \(nameStyled)\(suffix)")
    }

    while true {
      let input = try environment.prompt("Enter choice (1-\(groups.count)): ")?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if let input, let value = Int(input), (1...groups.count).contains(value) {
        return groups[value - 1].id
      }
    }
  }

  fileprivate func selectPeriod(current: InactivityWindow?, environment: PurgeEnvironment) throws
    -> InactivityWindow
  {
    if let current {
      return current
    }

    environment.print("Select inactivity window:")
    let options: [InactivityWindow] = [.days7, .days30, .days90, .days365]
    for (index, option) in options.enumerated() {
      environment.print(" [\(index + 1)] \(option.description)")
    }

    while true {
      let input = try environment.prompt("Enter choice (1-\(options.count)): ")?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if let input, let value = Int(input), (1...options.count).contains(value) {
        return options[value - 1]
      }
    }
  }

  fileprivate func askDryRun(preselected: Bool, environment: PurgeEnvironment) throws -> Bool {
    if preselected {
      return true
    }
    let response = try environment.prompt("Dry run? (Y/n): ")?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).lowercased()
    if let response {
      return response.isEmpty || response == "y" || response == "yes"
    }
    return true
  }
}
