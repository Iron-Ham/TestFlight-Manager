struct LoginConfiguration: Codable, Equatable {
  var issuerID: String?
  var keyID: String?
  var privateKeyPath: String?

  init(issuerID: String? = nil, keyID: String? = nil, privateKeyPath: String? = nil) {
    self.issuerID = issuerID
    self.keyID = keyID
    self.privateKeyPath = privateKeyPath
  }
}
