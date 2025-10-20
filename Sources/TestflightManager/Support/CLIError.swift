import Foundation

enum CLIError: Error, CustomStringConvertible {
  case invalidInput(String)
  case privateKeyNotFound(String)
  case verificationFailed(String)

  var description: String {
    switch self {
    case .invalidInput(let message):
      return message
    case .privateKeyNotFound(let message):
      return message
    case .verificationFailed(let message):
      return "Verification failed: \(message)"
    }
  }
}

extension CLIError: LocalizedError {
  var errorDescription: String? { description }
}
