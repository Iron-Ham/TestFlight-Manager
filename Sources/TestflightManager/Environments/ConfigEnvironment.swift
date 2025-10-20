import Foundation

struct ConfigEnvironment: @unchecked Sendable {
  var loadConfiguration: () throws -> LoginConfiguration?
  var saveConfiguration: (LoginConfiguration) throws -> URL
  var prompt: (String, String?) throws -> String?
  var print: (String) -> Void

  static let live = ConfigEnvironment(
    loadConfiguration: {
      let store = ConfigurationStore()
      return try store.load()
    },
    saveConfiguration: { configuration in
      let store = ConfigurationStore()
      return try store.save(configuration)
    },
    prompt: { message, current in
      var promptMessage = message
      if let current, !current.isEmpty {
        promptMessage += " [\(current)]"
      }
      promptMessage += ": "
      FileHandle.standardOutput.write(Data(promptMessage.utf8))
      return readLine()
    },
    print: { message in
      Swift.print(message)
    }
  )
}

actor ConfigEnvironmentProvider {
  static let shared = ConfigEnvironmentProvider()

  private var environment: ConfigEnvironment = .live

  func current() -> ConfigEnvironment {
    environment
  }

  func set(_ environment: ConfigEnvironment) {
    self.environment = environment
  }

  func reset() {
    environment = .live
  }
}
