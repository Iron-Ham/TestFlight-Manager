import AppStoreConnect_Swift_SDK
import ArgumentParser
import Foundation

struct RemoveUngrouped: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove-ungrouped",
    abstract: "Remove beta testers that are not assigned to any beta group."
  )

  enum OutputFormat: String, ExpressibleByArgument {
    case text
    case csv
  }

  @Option(
    name: [.customLong("app-id")],
    help: "Identifier of the app."
  )
  var appID: String?

  @Flag(
    name: [.customLong("dry-run")],
    help: "List ungrouped testers without removing them."
  )
  var dryRun: Bool = false

  @Flag(
    name: [.customLong("interactive"), .short],
    help: "Prompt to select options when not provided."
  )
  var interactive: Bool = false

  @Option(
    name: [.customLong("output-path")],
    help: "Write ungrouped tester details to the specified file instead of listing all entries."
  )
  var outputPath: String?

  @Option(
    name: [.customLong("output-format")],
    help: "Output file format (text or csv)."
  )
  var outputFormat: OutputFormat = .text

  func run() async throws {
    let environment = await RemoveUngroupedEnvironmentProvider.shared.current()

    do {
      guard let credentials = try environment.loadCredentials() else {
        throw CLIError.credentialsNotFound(
          "No saved credentials. Run 'TestFlightManager login' before removing ungrouped testers."
        )
      }

      let context = try await resolveContext(using: environment, credentials: credentials)

      // Fetch all app-level testers
      let allTesters = try await environment.fetchAppTesters(credentials, context.appID)
      guard !allTesters.isEmpty else {
        environment.print("No testers found for app \(context.appID).")
        return
      }

      // Fetch all beta groups for the app
      let betaGroups = try await environment.fetchBetaGroupsForApp(credentials, context.appID)

      // Fetch testers in each beta group and collect their IDs
      var groupedTesterIDs = Set<String>()
      for group in betaGroups {
        let groupTesters = try await environment.fetchBetaGroupTesters(credentials, group.id)
        groupedTesterIDs.formUnion(groupTesters.map { $0.id })
      }

      // Find testers that are not in any group
      let ungroupedTesters = allTesters.filter { !groupedTesterIDs.contains($0.id) }

      guard !ungroupedTesters.isEmpty else {
        environment.print("No ungrouped testers found for app \(context.appID).")
        return
      }

      environment.print(
        "Found \(ungroupedTesters.count) ungrouped tester(s) not assigned to any beta group:"
      )

      let sortedUngrouped = ungroupedTesters.sorted { lhs, rhs in
        displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs))
          == .orderedAscending
      }

      if let path = context.outputPath {
        try writeUngroupedTesters(
          sortedUngrouped,
          format: outputFormat,
          path: path
        )
        environment.print(
          "Wrote \(ungroupedTesters.count) ungrouped tester(s) to \(path)."
        )
      } else {
        for tester in sortedUngrouped {
          environment.print(" - \(displayName(for: tester))")
        }
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
        environment.print(" - Total app testers: \(allTesters.count)")
        environment.print(" - Ungrouped testers: \(ungroupedTesters.count)")
        environment.print("Dry run: no testers were removed.")
        return
      }

      try await environment.removeAppTesters(
        credentials,
        context.appID,
        ungroupedTesters.map { $0.id }
      )

      environment.print(
        "Removed \(ungroupedTesters.count) ungrouped tester(s) from app \(context.appID)."
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

extension RemoveUngrouped {
  fileprivate struct RunContext {
    let appID: String
    let dryRun: Bool
    let requiresConfirmation: Bool
    let outputPath: String?
    let outputFormat: OutputFormat
  }

  fileprivate func resolveContext(using environment: RemoveUngroupedEnvironment, credentials: Credentials)
    async throws -> RunContext
  {
    let shouldPrompt = interactive || appID == nil
    if !shouldPrompt {
      guard let appID else {
        throw CLIError.invalidInput(
          "App ID is required when interactive mode is disabled."
        )
      }
      return RunContext(
        appID: appID,
        dryRun: dryRun,
        requiresConfirmation: false,
        outputPath: Self.normalizeOutputPath(outputPath),
        outputFormat: outputFormat
      )
    }

    let apps = try await environment.fetchApps(credentials)
    guard !apps.isEmpty else {
      throw CLIError.invalidInput("No apps accessible with the current credentials.")
    }

    let selectedAppID = try selectAppID(current: appID, apps: apps, environment: environment)

    let confirmDryRun: Bool
    if let response = try environment.prompt("Dry run? (Y/n): ") {
      let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      confirmDryRun = normalized.isEmpty || normalized == "y" || normalized == "yes"
    } else {
      confirmDryRun = true
    }

    return RunContext(
      appID: selectedAppID,
      dryRun: confirmDryRun,
      requiresConfirmation: !confirmDryRun,
      outputPath: Self.normalizeOutputPath(outputPath),
      outputFormat: outputFormat
    )
  }

  private func selectAppID(
    current: String?,
    apps: [App],
    environment: RemoveUngroupedEnvironment
  ) throws -> String {
    if let current {
      if apps.contains(where: { $0.id == current }) {
        return current
      }
      throw CLIError.invalidInput("App ID \(current) not found in accessible apps.")
    }

    if apps.count == 1 {
      return apps[0].id
    }

    environment.print("Select an app:")
    for (index, app) in apps.enumerated() {
      let name = app.attributes?.name ?? "Unknown"
      let bundleID = app.attributes?.bundleID ?? "N/A"
      environment.print("\(index + 1). \(name) (\(bundleID))")
    }

    guard let input = try environment.prompt("Enter app number: "),
      let selection = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
      selection > 0,
      selection <= apps.count
    else {
      throw CLIError.invalidInput("Invalid app selection.")
    }

    return apps[selection - 1].id
  }

  private static func normalizeOutputPath(_ path: String?) -> String? {
    guard let path else { return nil }
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : (trimmed as NSString).expandingTildeInPath
  }
}

extension RemoveUngrouped {
  private func writeUngroupedTesters(
    _ testers: [BetaTester],
    format: OutputFormat,
    path: String
  ) throws {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()

    if directory.path != "" && directory.path != "." {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }

    let contents: String
    switch format {
    case .text:
      var lines: [String] = [
        "Ungrouped testers (not assigned to any beta group)",
        ""
      ]
      lines.append(contentsOf: testers.map { displayName(for: $0) })
      contents = lines.joined(separator: "\n") + "\n"
    case .csv:
      var rows: [String] = [
        "tester_id,first_name,last_name,email,state"
      ]
      for tester in testers {
        let attrs = tester.attributes
        let first = attrs?.firstName ?? ""
        let last = attrs?.lastName ?? ""
        let email = attrs?.email ?? ""
        let state = attrs?.state?.rawValue ?? ""
        let columns = [
          escapeCSV(tester.id),
          escapeCSV(first),
          escapeCSV(last),
          escapeCSV(email),
          escapeCSV(state)
        ]
        rows.append(columns.joined(separator: ","))
      }
      contents = rows.joined(separator: "\n") + "\n"
    }

    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func escapeCSV(_ value: String) -> String {
    let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
    if needsQuotes {
      let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
      return "\"\(escaped)\""
    }
    return value
  }
}
