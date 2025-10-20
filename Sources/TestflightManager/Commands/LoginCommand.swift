import ArgumentParser
import Foundation

struct Login: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "login",
    abstract: "Authenticate with App Store Connect using an API key."
  )

  @Option(
    name: [.customLong("issuer-id")],
    help: "App Store Connect API issuer identifier."
  )
  var issuerID: String?

  @Option(
    name: [.customLong("key-id")],
    help: "App Store Connect API key identifier."
  )
  var keyID: String?

  @Option(
    name: [.customLong("private-key-path")],
    help: "Path to the .p8 private key file."
  )
  var privateKeyPath: String?

  @Flag(
    name: [.customLong("skip-verification")],
    help: "Skip the API call used to verify the credentials."
  )
  var skipVerification: Bool = false

  func run() async throws {
    let environment = await LoginEnvironmentProvider.shared.current()
    let configuration = try environment.loadConfiguration() ?? LoginConfiguration()

    let resolvedIssuerID = try resolve(
      cliValue: issuerID,
      configuredValue: configuration.issuerID,
      fieldName: "issuer ID",
      flag: "--issuer-id"
    )

    let resolvedKeyID = try resolve(
      cliValue: keyID,
      configuredValue: configuration.keyID,
      fieldName: "key ID",
      flag: "--key-id"
    )

    let resolvedPrivateKeyPath = try resolve(
      cliValue: privateKeyPath,
      configuredValue: configuration.privateKeyPath,
      fieldName: "private key path",
      flag: "--private-key-path"
    )

    let credentials = try environment.makeCredentials(
      resolvedIssuerID,
      resolvedKeyID,
      resolvedPrivateKeyPath
    )

    if !skipVerification {
      try await environment.verifyCredentials(credentials)
    }

    let fileURL = try environment.saveCredentials(credentials)
    environment.printer("Login succeeded. Saved credentials to \(fileURL.path).")
  }

  private func resolve(
    cliValue: String?,
    configuredValue: String?,
    fieldName: String,
    flag: String
  ) throws -> String {
    if let trimmedCLI = cliValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmedCLI.isEmpty
    {
      return trimmedCLI
    }

    if let trimmedConfigured = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmedConfigured.isEmpty
    {
      return trimmedConfigured
    }

    throw CLIError.invalidInput(
      "Missing \(fieldName). Provide \(flag) or run 'TestFlightManager config' to set a default."
    )
  }
}
