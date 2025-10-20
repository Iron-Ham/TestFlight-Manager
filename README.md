# Testflight Manager

Command-line utility for managing TestFlight testers via the App Store Connect API. It helps teams log in once, store credentials securely, configure sensible defaults, and purge inactive testers quickly.

## Prerequisites

- macOS 13 or later
- Swift 5.9 toolchain (Xcode 15 or the latest Swift toolchain)
- App Store Connect API key (Issuer ID, Key ID, and `.p8` private key file)

## Installation

Clone the repository and build the executable using Swift Package Manager:

```bash
# Clone the repo
git clone https://github.com/Iron-Ham/TestFlight-Manager.git
cd TestFlight-Manager

# Build once to validate dependencies
swift build
```

To install the executable globally, use SwiftPM’s install command:

```bash
swift build -c release
cp .build/release/TestflightManager /usr/local/bin/testflightmanager
```

You can choose another location on your PATH if `/usr/local/bin` requires elevated privileges.

## Configuration and Login

Before running management commands, configure defaults and store credentials:

1. **Configure defaults** (optional but recommended):
   ```bash
   testflightmanager config
   ```
   This command interactively prompts for default app ID, beta group ID, inactivity period, and dry-run preference. You can skip any value to keep existing settings.

2. **Login** (required):
   ```bash
   testflightmanager login
   ```
   Provide the App Store Connect API Issuer ID, Key ID, and the path to your `.p8` private key. The tool verifies access, then stores credentials securely in the keychain.

## Usage

### Purge Inactive Testers

Remove testers who have not launched the app during a selected period:

```bash
testflightmanager purge --app-id <app-id> --beta-group-id <group-id> --period 30d
```

Flags:
- `--app-id` / `--beta-group-id`: Identifiers to target an app and beta group. If omitted, the command can prompt interactively when `--interactive` or configuration defaults are available.
- `--period`: Inactivity window (`7d`, `30d`, `90d`, `365d`). Defaults to `30d` if not provided.
- `--dry-run`: Show inactive testers without removing them.
- `--interactive` (`-i`): Prompt for app, group, period, and dry-run choice when flags are missing.

Example interactive flow:

```bash
testflightmanager purge -i
```

The command:
- Lists eligible apps showing both the display name and bundle identifier.
- Lists beta groups for the chosen app.
- Shows dry-run summary: total testers and count meeting the inactivity criteria.
- In removal mode, asks for confirmation before deleting and prints the number of testers removed.

### Display Current Configuration

```bash
testflightmanager config --show
```

Opens the stored configuration values in JSON format.

## Development

Format the project:

```bash
./swift-format.sh
```

Run tests:

```bash
swift test
```

## Troubleshooting

- **`credentialsNotFound`**: Run `testflightmanager login` first.
- **API permission errors**: Confirm the API key has "Developer" or "App Manager" access to the relevant apps.
- **Interactive selection missing apps/groups**: Ensure the authenticated key is granted visibility to those resources.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
