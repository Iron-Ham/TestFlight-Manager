import Foundation

struct ConfigurationStore {
  private let fileManager = FileManager.default
  let fileURL: URL

  init() {
    let baseDirectory = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("testflight-mgmt", isDirectory: true)
    self.fileURL = baseDirectory.appendingPathComponent("config.json", isDirectory: false)
  }

  func load() throws -> LoginConfiguration? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    return try decoder.decode(LoginConfiguration.self, from: data)
  }

  @discardableResult
  func save(_ configuration: LoginConfiguration) throws -> URL {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(configuration)

    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: [.atomic])
    return fileURL
  }
}
