import Foundation

/// Handles leveled logging with optional ANSI styling.
struct Logger: Sendable {
  enum Level: String {
    case debug
    case info
    case notice
    case warning
    case error
  }

  private let theme: ConsoleTheme
  private let isVerbose: Bool
  private let isQuiet: Bool
  private let fileHandle: FileHandle

  init(
    theme: ConsoleTheme = ConsoleTheme.resolve(stream: .stderr),
    isVerbose: Bool = false,
    isQuiet: Bool = false,
    fileHandle: FileHandle = .standardError
  ) {
    self.theme = theme
    self.isVerbose = isVerbose
    self.isQuiet = isQuiet
    self.fileHandle = fileHandle
  }

  func log(_ message: String, level: Level = .info) {
    guard shouldLog(level: level) else { return }

    let styles = styles(for: level)

    let labelText: String?
    if isVerbose {
      let rawLabel = "[\(level.rawValue.uppercased())]"
      labelText = theme.applying(styles.label, to: rawLabel) + " "
    } else {
      labelText = nil
    }

    let styledMessage = apply(styles.message, to: message)
    let output = "\(labelText ?? "")\(styledMessage)\n"

    if let data = output.data(using: .utf8) {
      fileHandle.write(data)
    }
  }

  func debug(_ message: @autoclosure () -> String) {
    guard isVerbose else { return }
    log(message(), level: .debug)
  }

  func debug(_ build: () -> String) {
    guard isVerbose else { return }
    log(build(), level: .debug)
  }

  func info(_ message: @autoclosure () -> String) {
    log(message(), level: .info)
  }

  func notice(_ message: @autoclosure () -> String) {
    log(message(), level: .notice)
  }

  func warning(_ message: @autoclosure () -> String) {
    log(message(), level: .warning)
  }

  func error(_ message: @autoclosure () -> String) {
    log(message(), level: .error)
  }

  func applying(_ style: ConsoleTheme.Style, to text: String) -> String {
    theme.applying(style, to: text)
  }

  var consoleTheme: ConsoleTheme { theme }
  var isVerboseEnabled: Bool { isVerbose }
  var isQuietEnabled: Bool { isQuiet }

  private func shouldLog(level: Level) -> Bool {
    switch level {
    case .debug:
      return isVerbose
    case .info:
      return !isQuiet || isVerbose
    default:
      return true
    }
  }

  private func styles(for level: Level) -> (label: ConsoleTheme.Style, message: ConsoleTheme.Style) {
    switch level {
    case .debug:
      return (theme.muted, theme.muted)
    case .info:
      return (theme.infoLabel, theme.infoMessage)
    case .notice:
      return (theme.emphasis, theme.infoMessage)
    case .warning:
      return (theme.warningLabel, theme.warningMessage)
    case .error:
      return (theme.errorLabel, theme.errorMessage)
    }
  }

  private func apply(_ style: ConsoleTheme.Style, to message: String) -> String {
    let prefix = style.prefix(isEnabled: theme.isEnabled)
    guard !prefix.isEmpty else { return message }
    let reset = "\u{001B}[0m"
    let reenabled = message.replacingOccurrences(of: reset, with: reset + prefix)
    return "\(prefix)\(reenabled)\(reset)"
  }
}

extension Logger {
  static let stdout = Logger(
    theme: ConsoleTheme.resolve(stream: .stdout),
    fileHandle: .standardOutput
  )

  static let stderr = Logger(
    theme: ConsoleTheme.resolve(stream: .stderr),
    fileHandle: .standardError
  )
}
