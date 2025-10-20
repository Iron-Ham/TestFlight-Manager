import Foundation

struct CredentialsStore {
  private let fileManager = FileManager.default
  let fileURL: URL

  init() {
    let baseDirectory = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("testflight-mgmt", isDirectory: true)
    self.fileURL = baseDirectory.appendingPathComponent("credentials.json", isDirectory: false)
  }

  func save(_ credentials: Credentials) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(credentials)

    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: [.atomic])
  }
}
