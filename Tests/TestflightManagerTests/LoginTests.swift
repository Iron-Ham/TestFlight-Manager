import XCTest
@testable import TestflightManager

final class LoginTests: XCTestCase {
    private var temporaryFiles: [URL] = []

    override func tearDown() {
        temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryFiles.removeAll()
        super.tearDown()
    }

    func testRunVerifiesAndSavesCredentials() async throws {
        let keyURL = try makeTemporaryKeyFile()
        let expectedSaveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        var verifiedCredentials: [Credentials] = []
        var savedCredentials: Credentials?
        var printedMessages: [String] = []

        let provider = LoginEnvironmentProvider.shared
        await provider.set(LoginEnvironment(
            makeCredentials: { issuerID, keyID, privateKeyPath in
                XCTAssertEqual(issuerID, "ISSUER")
                XCTAssertEqual(keyID, "KEY")
                XCTAssertEqual(privateKeyPath, keyURL.path)
                return try Credentials(issuerID: issuerID, keyID: keyID, privateKeyPath: privateKeyPath)
            },
            verifyCredentials: { credentials in
                verifiedCredentials.append(credentials)
            },
            saveCredentials: { credentials in
                savedCredentials = credentials
                return expectedSaveURL
            },
            printer: { message in
                printedMessages.append(message)
            }
        ))

        let command = try Login.parse([
            "--issuer-id", "ISSUER",
            "--key-id", "KEY",
            "--private-key-path", keyURL.path
        ])
        do {
            try await command.run()
        } catch {
            await provider.reset()
            throw error
        }

        XCTAssertEqual(verifiedCredentials.count, 1)
        XCTAssertEqual(savedCredentials?.issuerID, "ISSUER")
        XCTAssertEqual(savedCredentials?.keyID, "KEY")
        XCTAssertEqual(savedCredentials?.privateKeyPath, keyURL.path)
        XCTAssertEqual(printedMessages.last, "Login succeeded. Saved credentials to \(expectedSaveURL.path).")

        await provider.reset()
    }

    func testRunSkipsVerificationWhenFlagProvided() async throws {
        let keyURL = try makeTemporaryKeyFile()
        let expectedSaveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        var verificationCallCount = 0

        let provider = LoginEnvironmentProvider.shared
        await provider.set(LoginEnvironment(
            makeCredentials: { issuerID, keyID, privateKeyPath in
                return try Credentials(issuerID: issuerID, keyID: keyID, privateKeyPath: privateKeyPath)
            },
            verifyCredentials: { _ in
                verificationCallCount += 1
            },
            saveCredentials: { _ in
                return expectedSaveURL
            },
            printer: { _ in }
        ))

        let command = try Login.parse([
            "--issuer-id", "ISSUER",
            "--key-id", "KEY",
            "--private-key-path", keyURL.path,
            "--skip-verification"
        ])
        do {
            try await command.run()
        } catch {
            await provider.reset()
            throw error
        }

        XCTAssertEqual(verificationCallCount, 0)
        await provider.reset()
    }

    func testRunPropagatesCredentialCreationError() async {
        let provider = LoginEnvironmentProvider.shared
        await provider.set(LoginEnvironment(
            makeCredentials: { _, _, _ in
                throw CLIError.invalidInput("bad input")
            },
            verifyCredentials: { _ in
                XCTFail("Verification should not be called when credential creation fails.")
            },
            saveCredentials: { _ in
                XCTFail("Save should not be called when credential creation fails.")
                return URL(fileURLWithPath: "/tmp/should-not-exist.json")
            },
            printer: { _ in
                XCTFail("Printer should not be called when credential creation fails.")
            }
        ))

        do {
            let command = try Login.parse([
                "--issuer-id", "ISSUER",
                "--key-id", "KEY",
                "--private-key-path", "/tmp/non-existent.p8"
            ])
            try await command.run()
            XCTFail("Expected credential creation to throw.")
        } catch let error as CLIError {
            if case .invalidInput(let message) = error {
                XCTAssertEqual(message, "bad input")
            } else {
                XCTFail("Unexpected CLIError thrown: \(error)")
            }
        } catch {
            XCTFail("Unexpected error thrown: \(error)")
        }
        await provider.reset()
    }

    private func makeTemporaryKeyFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("p8")
        let data = Data("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n".utf8)
        FileManager.default.createFile(atPath: url.path, contents: data)
        temporaryFiles.append(url)
        return url
    }
}
