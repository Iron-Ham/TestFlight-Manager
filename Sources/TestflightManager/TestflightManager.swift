import ArgumentParser

@main
struct TestFlightManager: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "CLI tool for managing TestFlight users via App Store Connect.",
    subcommands: [Login.self, Config.self, Purge.self],
    defaultSubcommand: Login.self
  )
}
