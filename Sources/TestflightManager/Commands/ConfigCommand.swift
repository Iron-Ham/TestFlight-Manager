import ArgumentParser
import Foundation

struct Config: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Interactively configure default values for the login command."
  )

  func run() async throws {
    let environment = await ConfigEnvironmentProvider.shared.current()
    var configuration = try environment.loadConfiguration() ?? LoginConfiguration()

    environment.print(
      "Configure default values used by the login command. Press return to keep the current value."
    )

    configuration.issuerID = try promptForValue(
      prompt: "Issuer ID",
      current: configuration.issuerID,
      environment: environment
    )

    configuration.keyID = try promptForValue(
      prompt: "Key ID",
      current: configuration.keyID,
      environment: environment
    )

    configuration.privateKeyPath = try promptForPrivateKeyPath(
      current: configuration.privateKeyPath,
      environment: environment
    )

    let fileURL = try environment.saveConfiguration(configuration)
    environment.print("Saved configuration to \(fileURL.path).")
  }

  private func promptForValue(
    prompt: String,
    current: String?,
    environment: ConfigEnvironment
  ) throws -> String? {
    let input = try environment.prompt(prompt, current)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard let value = input, !value.isEmpty else {
      return current
    }
    return value
  }

  private func promptForPrivateKeyPath(
    current: String?,
    environment: ConfigEnvironment
  ) throws -> String? {
    var existing = current
    while true {
      let input = try environment.prompt("Private key path", existing)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )

      guard let value = input, !value.isEmpty else {
        return existing
      }

      let expanded = (value as NSString).expandingTildeInPath
      if FileManager.default.fileExists(atPath: expanded) {
        existing = expanded
        return existing
      }

      environment.print("No file found at \(value). Please provide a valid path.")
    }
  }
}
