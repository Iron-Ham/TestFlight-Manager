# TestFlight Manager

A command-line tool for managing TestFlight users via App Store Connect. This utility helps you automate the removal of inactive beta testers from your TestFlight beta groups.

## Features

- **Authenticate** with App Store Connect using API credentials
- **Configure** default settings for easy reuse
- **Purge** inactive testers based on session activity over various time periods
- **Interactive mode** for easy app and beta group selection
- **Dry run** support to preview changes before applying them

## Prerequisites

- macOS 13.0 or later
- Swift 6.2 or later
- App Store Connect API credentials (issuer ID, key ID, and private key file)

## Getting App Store Connect API Credentials

To use this tool, you'll need to create API credentials in App Store Connect:

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/)
2. Go to **Users and Access** > **Integrations** > **App Store Connect API**
3. Click the **+** button to create a new key
4. Give it a name and select **App Manager** role (or appropriate role for your needs)
5. Click **Generate**
6. Download the `.p8` private key file (you can only download it once!)
7. Note the **Issuer ID** and **Key ID** displayed on the page

Keep your private key file secure and never commit it to version control.

## Installation

### Building from Source

Clone the repository and build the executable:

```bash
git clone https://github.com/Iron-Ham/TestFlight-Manager.git
cd TestFlight-Manager
swift build -c release
```

The compiled binary will be located at `.build/release/TestFlightManager`.

### Optional: Install to System Path

To make the tool available system-wide:

```bash
sudo cp .build/release/TestFlightManager /usr/local/bin/testflight-manager
```

## Usage

TestFlight Manager provides three main commands: `login`, `config`, and `purge`.

### 1. Authentication (`login`)

Authenticate with App Store Connect using your API credentials:

```bash
testflight-manager login \
  --issuer-id YOUR_ISSUER_ID \
  --key-id YOUR_KEY_ID \
  --private-key-path /path/to/AuthKey_XXXXX.p8
```

**Options:**
- `--issuer-id <issuer-id>` - App Store Connect API issuer identifier
- `--key-id <key-id>` - App Store Connect API key identifier
- `--private-key-path <path>` - Path to the .p8 private key file
- `--skip-verification` - Skip the API verification call (not recommended)

The credentials will be saved securely for future use.

### 2. Configuration (`config`)

Interactively configure default values to avoid repeatedly entering credentials:

```bash
testflight-manager config
```

This command will prompt you for:
- Issuer ID
- Key ID
- Private key path (with validation that the file exists)

Once configured, you can run `login` without any arguments, and it will use your saved defaults.

### 3. Purge Inactive Testers (`purge`)

Remove inactive testers from a beta group based on their session activity:

```bash
testflight-manager purge \
  --app-id YOUR_APP_ID \
  --beta-group-id YOUR_BETA_GROUP_ID \
  --period 30d \
  --dry-run
```

**Options:**
- `--app-id <app-id>` - Identifier of the app that owns the beta group
- `--beta-group-id <beta-group-id>` - Identifier of the beta group to purge
- `--period <period>` - Inactivity window: `7d`, `30d`, `90d`, or `365d` (default: 30d)
- `--dry-run` - List inactive testers without removing them
- `-i, --interactive` - Interactive mode with prompts for app/group selection

**Interactive Mode:**

For easier use, enable interactive mode to select your app and beta group from a list:

```bash
testflight-manager purge --interactive
```

This will guide you through:
1. Selecting an app from your accessible apps
2. Choosing a beta group from that app
3. Selecting an inactivity period
4. Choosing whether to do a dry run
5. Confirming the removal (if not a dry run)

## Examples

### Complete Workflow

1. **First time setup:**
   ```bash
   # Configure your credentials
   testflight-manager config
   
   # Login (will use configured credentials)
   testflight-manager login
   ```

2. **Find and remove inactive testers (safe mode):**
   ```bash
   # Use interactive mode with dry run to see what would be removed
   testflight-manager purge --interactive --dry-run
   ```

3. **Remove inactive testers:**
   ```bash
   # Actually remove inactive testers
   testflight-manager purge --interactive
   ```

### Non-Interactive Usage

If you know your app ID and beta group ID:

```bash
# Dry run first to see who would be removed
testflight-manager purge \
  --app-id 1234567890 \
  --beta-group-id abcd-1234-efgh-5678 \
  --period 90d \
  --dry-run

# If satisfied, remove the --dry-run flag
testflight-manager purge \
  --app-id 1234567890 \
  --beta-group-id abcd-1234-efgh-5678 \
  --period 90d
```

### Login with Specific Credentials

Override configured defaults for a one-time login:

```bash
testflight-manager login \
  --issuer-id 12345678-abcd-1234-abcd-123456789012 \
  --key-id ABC1234567 \
  --private-key-path ~/Downloads/AuthKey_ABC1234567.p8
```

## How It Works

1. **Authentication**: The tool uses your App Store Connect API credentials to authenticate via the [AppStoreConnect-Swift-SDK](https://github.com/AvdLee/appstoreconnect-swift-sdk)

2. **Activity Detection**: It queries TestFlight for tester session counts within the specified time period (7, 30, 90, or 365 days)

3. **Identification**: Testers with zero sessions in the specified period are marked as inactive

4. **Removal**: In non-dry-run mode, inactive testers are removed from the beta group

## Project Structure

```
TestFlightManager/
├── Sources/
│   └── TestflightManager/
│       ├── Commands/          # CLI command implementations
│       │   ├── LoginCommand.swift
│       │   ├── ConfigCommand.swift
│       │   └── PurgeCommand.swift
│       ├── Environments/      # Environment protocols for testability
│       ├── Models/            # Data models (Credentials, Configuration)
│       ├── Services/          # Business logic (stores, verifiers)
│       └── Support/           # Utilities and errors
└── Tests/
    └── TestflightManagerTests/
```

## Dependencies

- [AppStoreConnect-Swift-SDK](https://github.com/AvdLee/appstoreconnect-swift-sdk) - For App Store Connect API integration
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) - For CLI argument parsing

## Security Notes

- Credentials are stored locally in your home directory
- Never commit your `.p8` private key file to version control
- The tool requires appropriate App Store Connect API permissions
- Always test with `--dry-run` first before removing testers

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

See the repository for license information.

## Support

For issues, questions, or contributions, please visit the [GitHub repository](https://github.com/Iron-Ham/TestFlight-Manager).
