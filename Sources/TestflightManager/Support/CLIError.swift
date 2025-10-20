import Foundation

enum CLIError: Error, CustomStringConvertible {
  case invalidInput(String)
  case privateKeyNotFound(String)
  case verificationFailed(String)
  case credentialsNotFound(String)
  case apiFailure(String)

  var description: String {
    switch self {
    case .invalidInput(let message):
      return message
    case .privateKeyNotFound(let message):
      return message
    case .verificationFailed(let message):
      return "Verification failed: \(message)"
    case .credentialsNotFound(let message):
      return message
    case .apiFailure(let message):
      return "API request failed: \(message)"
    }
  }
}

extension CLIError: LocalizedError {
  var errorDescription: String? { description }
}
