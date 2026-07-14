import Foundation

/// Shared authenticated transport for OAuth task providers. Tokens enter and
/// leave only through the credential store; request logs and SQLite never see
/// them. Refresh responses replace the old refresh token when the provider
/// rotates it.
final class OAuthTaskProviderSession {
    private let configuration: OAuthProviderConfiguration
    private let credentials: OAuthCredentialStoring
    private let transport: any OAuthHTTPTransport
    private let now: () -> Date

    init(
        configuration: OAuthProviderConfiguration,
        credentials: OAuthCredentialStoring = KeychainOAuthCredentialStore(),
        transport: any OAuthHTTPTransport = URLSessionOAuthHTTPTransport(),
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.transport = transport
        self.now = now
    }

    var authorizationState: TaskProviderAuthorizationState {
        guard OAuthProviderConfiguration.load(provider: configuration.provider) != nil
                || configuration.clientID.isEmpty == false else {
            return .notConfigured
        }
        return (try? credentials.loadCredential(for: configuration.provider)) == nil
            ? .notDetermined
            : .authorized
    }

    func send(_ makeRequest: (String) throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        var credential = try await currentCredential()
        var request = try makeRequest(credential.accessToken)
        var (data, response) = try await transport.data(for: request)
        // A revoked or clock-skewed access token can fail before its advertised
        // expiry. Rotate it once, then replay the original request exactly once.
        if response.statusCode == 401, credential.refreshToken != nil {
            credential = try await refreshCredential(credential)
            request = try makeRequest(credential.accessToken)
            (data, response) = try await transport.data(for: request)
        }
        return try checkedResponse(data: data, response: response)
    }

    private func checkedResponse(
        data: Data,
        response: HTTPURLResponse
    ) throws -> (Data, HTTPURLResponse) {
        switch response.statusCode {
        case 200..<300:
            return (data, response)
        case 401:
            throw TaskProviderError.authorizationRequired
        case 403:
            throw TaskProviderError.accessDenied
        case 404:
            throw TaskProviderError.taskNotFound
        case 409, 412:
            throw TaskProviderError.conflict
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .map { " Retry after \($0) seconds." } ?? ""
            throw TaskProviderError.providerFailure(
                "The task provider is rate limiting requests.\(retryAfter)"
            )
        default:
            throw TaskProviderError.providerFailure("The task provider returned HTTP \(response.statusCode).")
        }
    }

    private func currentCredential() async throws -> OAuthCredential {
        guard let credential = try credentials.loadCredential(for: configuration.provider) else {
            throw TaskProviderError.authorizationRequired
        }
        guard credential.needsRefresh else { return credential }
        return try await refreshCredential(credential)
    }

    private func refreshCredential(
        _ credential: OAuthCredential
    ) async throws -> OAuthCredential {
        guard let refreshToken = credential.refreshToken else {
            try? credentials.deleteCredential(for: configuration.provider)
            throw TaskProviderError.authorizationRequired
        }
        let response = try await OAuthTokenExchange.perform(
            OAuthTokenExchange.refreshTokenRequest(
                configuration: configuration,
                refreshToken: refreshToken
            ),
            transport: transport
        )
        let refreshed = OAuthCredential(
            provider: credential.provider,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: response.expiresIn.map { now().addingTimeInterval($0) },
            accountKey: credential.accountKey,
            displayName: credential.displayName,
            scopes: response.scope?.split(separator: " ").map(String.init) ?? credential.scopes
        )
        try credentials.saveCredential(refreshed)
        return refreshed
    }
}
