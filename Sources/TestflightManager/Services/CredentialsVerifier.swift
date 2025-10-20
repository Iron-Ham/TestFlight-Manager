import AppStoreConnect_Swift_SDK

struct CredentialsVerifier {
  func verify(credentials: Credentials) async throws {
    let configuration = try credentials.apiConfiguration()
    let provider = APIProvider(configuration: configuration)

    let request = APIEndpoint
      .v1
      .apps
      .get(parameters: .init(limit: 1))

    do {
      _ = try await provider.request(request).data
      Swift.print("Verification succeeded.")
    } catch APIProvider.Error.requestFailure(let statusCode, let errorResponse, _) {
      let details = errorResponse?.errors?.map { "\($0.code): \($0.detail ?? $0.title)" }.joined(
        separator: ", "
      )
      throw CLIError.verificationFailed(
        "Request failed with status code \(statusCode). Details: \(details ?? "unknown error")."
      )
    } catch {
      throw CLIError.verificationFailed(error.localizedDescription)
    }
  }
}
