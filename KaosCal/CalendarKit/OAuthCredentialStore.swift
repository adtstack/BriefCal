import Foundation
import Security
import CryptoKit
import AppKit
import Network

/// OAuth credentials deliberately live outside SQLite. Local database exports
/// are therefore useful for recovery without becoming bearer-token backups.
struct OAuthCredential: Codable, Equatable {
    let provider: TaskProviderKind
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let accountKey: String
    let displayName: String
    let scopes: [String]

    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }
}

protocol OAuthCredentialStoring: AnyObject {
    func loadCredential(
        for provider: TaskProviderKind
    ) throws -> OAuthCredential?
    func saveCredential(_ credential: OAuthCredential) throws
    func deleteCredential(for provider: TaskProviderKind) throws
}

enum OAuthCredentialStoreError: LocalizedError, Equatable {
    case encodingFailed
    case keychain(OSStatus)
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The provider credential could not be encoded."
        case .keychain:
            "KaosCal could not access the secure credential store."
        case .invalidCredential:
            "The saved provider credential is invalid. Connect the provider again."
        }
    }
}

final class KeychainOAuthCredentialStore: OAuthCredentialStoring {
    private let service: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        service: String = Bundle.main.bundleIdentifier
            .map { "\($0).task-provider-oauth" }
            ?? "com.kaoscal.task-provider-oauth"
    ) {
        self.service = service
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func loadCredential(
        for provider: TaskProviderKind
    ) throws -> OAuthCredential? {
        var query = baseQuery(provider: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OAuthCredentialStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw OAuthCredentialStoreError.invalidCredential
        }
        do {
            return try decoder.decode(OAuthCredential.self, from: data)
        } catch {
            throw OAuthCredentialStoreError.invalidCredential
        }
    }

    func saveCredential(_ credential: OAuthCredential) throws {
        let data: Data
        do {
            data = try encoder.encode(credential)
        } catch {
            throw OAuthCredentialStoreError.encodingFailed
        }
        let query = baseQuery(provider: credential.provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OAuthCredentialStoreError.keychain(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw OAuthCredentialStoreError.keychain(updateStatus)
        }
    }

    func deleteCredential(for provider: TaskProviderKind) throws {
        let status = SecItemDelete(baseQuery(provider: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OAuthCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(provider: TaskProviderKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}

/// OAuth client configuration shipped with the app. Google may require the
/// Desktop client credential during token exchange; its value is injected at
/// build time and is never stored with user tokens or provider metadata.
struct OAuthProviderConfiguration: Equatable {
    let provider: TaskProviderKind
    let clientID: String
    let clientSecret: String?
    let redirectURI: URL

    init(
        provider: TaskProviderKind,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL
    ) {
        self.provider = provider
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }

    func replacingRedirectURI(_ redirectURI: URL) -> OAuthProviderConfiguration {
        OAuthProviderConfiguration(
            provider: provider,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )
    }

    static func load(
        provider: TaskProviderKind,
        bundle: Bundle = .main
    ) -> OAuthProviderConfiguration? {
        let prefix: String
        switch provider {
        case .googleTasks:
            prefix = "KaosCalGoogleTasks"
        case .todoist:
            prefix = "KaosCalTodoist"
        case .microsoftToDo:
            prefix = "KaosCalMicrosoftToDo"
        case .appleReminders:
            return nil
        }
        guard let clientID = validString(
            bundle.object(forInfoDictionaryKey: "\(prefix)ClientID")
        ), let redirectString = validString(
            bundle.object(forInfoDictionaryKey: "\(prefix)RedirectURI")
        ), let redirectURI = URL(string: redirectString) else {
            return nil
        }
        let clientSecret = provider == .googleTasks
            ? validString(bundle.object(
                forInfoDictionaryKey: "KaosCalGoogleTasksClientSecret"
            ))
            : nil
        guard provider != .googleTasks || clientSecret != nil else {
            return nil
        }
        return OAuthProviderConfiguration(
            provider: provider,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )
    }

    private static func validString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

struct OAuthPKCEChallenge: Equatable {
    let verifier: String
    let challenge: String

    static func make() throws -> OAuthPKCEChallenge {
        // RFC 7636 allows 43–128 unreserved characters. Base64URL-encoding
        // 64 random bytes yields an 86-character verifier without padding.
        var bytes = [UInt8](repeating: 0, count: 64)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw OAuthCredentialStoreError.keychain(status)
        }
        return make(verifier: base64URL(Data(bytes)))
    }

    static func make(verifier: String) -> OAuthPKCEChallenge {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return OAuthPKCEChallenge(
            verifier: verifier,
            challenge: base64URL(Data(digest))
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthAuthorizationRequestError: LocalizedError, Equatable {
    case invalidRedirect(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case let .invalidRedirect(message):
            message
        case .invalidURL:
            "The provider authorization URL could not be created."
        }
    }
}

struct OAuthAuthorizationRequest: Equatable {
    let url: URL
    let state: String
    let pkce: OAuthPKCEChallenge

    static func make(
        configuration: OAuthProviderConfiguration,
        state: String = UUID().uuidString,
        pkce: OAuthPKCEChallenge? = nil
    ) throws -> OAuthAuthorizationRequest {
        let pkce = try pkce ?? OAuthPKCEChallenge.make()
        try validateRedirect(configuration)
        let endpoint: URL
        let scopes: [String]
        var items = [URLQueryItem](
            arrayLiteral:
                URLQueryItem(name: "client_id", value: configuration.clientID),
                URLQueryItem(
                    name: "redirect_uri",
                    value: configuration.redirectURI.absoluteString
                ),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
        )
        switch configuration.provider {
        case .googleTasks:
            endpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            scopes = [
                "openid",
                "email",
                "profile",
                "https://www.googleapis.com/auth/tasks"
            ]
            items.append(URLQueryItem(name: "access_type", value: "offline"))
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        case .todoist:
            endpoint = URL(string: "https://app.todoist.com/oauth/authorize")!
            // Todoist's public-client metadata flow uses a comma-separated
            // scope value. data:read_write also permits the OIDC userinfo
            // request used only to derive a stable account key.
            scopes = ["data:read_write"]
        case .microsoftToDo:
            endpoint = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
            // `profile` supplies display metadata; Graph `/me.id` is the
            // authoritative account identity for the access token below.
            scopes = [
                "openid", "profile", "offline_access", "User.Read",
                "Tasks.ReadWrite"
            ]
        case .appleReminders:
            throw OAuthAuthorizationRequestError.invalidURL
        }
        if !scopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let url = components?.url else {
            throw OAuthAuthorizationRequestError.invalidURL
        }
        return OAuthAuthorizationRequest(url: url, state: state, pkce: pkce)
    }

    private static func validateRedirect(
        _ configuration: OAuthProviderConfiguration
    ) throws {
        guard let scheme = configuration.redirectURI.scheme?.lowercased(),
              let host = configuration.redirectURI.host?.lowercased() else {
            throw OAuthAuthorizationRequestError.invalidRedirect(
                "The OAuth redirect URI must include a scheme and host."
            )
        }
        switch configuration.provider {
        case .googleTasks:
            guard scheme == "http", host == "127.0.0.1" || host == "localhost" else {
                throw OAuthAuthorizationRequestError.invalidRedirect(
                    "Google Tasks requires an HTTP loopback redirect such as http://127.0.0.1:<port>/oauth/callback."
                )
            }
        case .todoist:
            guard scheme == "https" || host == "localhost" || host == "127.0.0.1" else {
                throw OAuthAuthorizationRequestError.invalidRedirect(
                    "Todoist requires an HTTPS redirect, except for a localhost testing redirect."
                )
            }
        case .microsoftToDo:
            guard scheme == "https" || host == "localhost" || host == "127.0.0.1" else {
                throw OAuthAuthorizationRequestError.invalidRedirect(
                    "Microsoft To Do requires an HTTPS redirect, except for a localhost testing redirect."
                )
            }
        case .appleReminders:
            break
        }
    }
}

protocol OAuthHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionOAuthHTTPTransport: OAuthHTTPTransport {
    private static let session = URLSession(
        configuration: .ephemeral,
        delegate: OAuthSameOriginRedirectDelegate(),
        delegateQueue: nil
    )

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TaskProviderError.providerFailure(
                "The OAuth provider returned an invalid HTTP response."
            )
        }
        return (data, response)
    }
}

enum OAuthHTTPRedirectPolicy {
    static func permitsRedirect(from source: URL, to destination: URL) -> Bool {
        guard let sourceScheme = source.scheme?.lowercased(),
              let destinationScheme = destination.scheme?.lowercased(),
              let sourceHost = source.host?.lowercased(),
              let destinationHost = destination.host?.lowercased() else {
            return false
        }
        return sourceScheme == destinationScheme
            && sourceHost == destinationHost
            && effectivePort(source) == effectivePort(destination)
            && destination.user == nil
            && destination.password == nil
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

private final class OAuthSameOriginRedirectDelegate: NSObject,
    URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let source = response.url,
              let destination = request.url,
              OAuthHTTPRedirectPolicy.permitsRedirect(
                from: source,
                to: destination
              ) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum OAuthTokenExchangeError: LocalizedError, Equatable {
    case authorizationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .authorizationFailed(message):
            "Provider authorization failed: \(message)"
        case .invalidResponse:
            "The provider returned an invalid token response."
        }
    }
}

enum OAuthGrantedScopeError: LocalizedError, Equatable {
    case missingRequiredScopes([String])

    var errorDescription: String? {
        switch self {
        case let .missingRequiredScopes(scopes):
            "Provider authorization did not grant the required access: \(scopes.joined(separator: ", ")). Reconnect and approve all requested permissions."
        }
    }
}

enum OAuthGrantedScopeValidator {
    static func validate(
        provider: TaskProviderKind,
        grantedScope: String?
    ) throws {
        guard provider == .googleTasks else { return }
        let granted = Set(
            (grantedScope ?? "")
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
        )
        let required = [
            "openid",
            "https://www.googleapis.com/auth/tasks"
        ]
        let missing = required.filter { !granted.contains($0) }
        guard missing.isEmpty else {
            throw OAuthGrantedScopeError.missingRequiredScopes(missing)
        }
    }
}

enum OAuthAuthorizationCallbackError: LocalizedError, Equatable {
    case cancelled
    case denied(String)
    case stateMismatch
    case missingCode
    case duplicateParameter(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Provider authorization was cancelled."
        case let .denied(message): "Provider authorization was denied: \(message)"
        case .stateMismatch: "The OAuth callback did not match the authorization request."
        case .missingCode: "The OAuth callback did not include an authorization code."
        case let .duplicateParameter(name):
            "The OAuth callback included the parameter more than once: \(name)."
        }
    }
}

enum OAuthAuthorizationCallback {
    static func authorizationCode(
        from callbackURL: URL,
        expectedState: String
    ) throws -> String {
        var values = [String: String]()
        var names = Set<String>()
        for item in URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? [] {
            guard names.insert(item.name).inserted else {
                throw OAuthAuthorizationCallbackError.duplicateParameter(
                    item.name
                )
            }
            if let value = item.value {
                values[item.name] = value
            }
        }
        guard values["state"] == expectedState else {
            throw OAuthAuthorizationCallbackError.stateMismatch
        }
        if let error = values["error"] {
            if error == "access_denied" {
                throw OAuthAuthorizationCallbackError.denied(
                    values["error_description"] ?? error
                )
            }
            throw OAuthAuthorizationCallbackError.denied(
                values["error_description"] ?? error
            )
        }
        guard let code = values["code"], !code.isEmpty else {
            throw OAuthAuthorizationCallbackError.missingCode
        }
        return code
    }
}

struct OAuthTokenResponse: Decodable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?
    /// Used transiently to derive Microsoft tenant and display metadata.
    /// It is never written to SQLite or Keychain.
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case idToken = "id_token"
    }
}

struct OAuthAccountIdentity: Equatable {
    let accountKey: String
    let displayName: String
}

/// Resolves a non-email account key immediately after OAuth exchange. The
/// resolver does not persist provider profiles or ID tokens; only the stable
/// key and display label returned here are retained with the local binding.
enum OAuthAccountIdentityResolver {
    static func resolve(
        provider: TaskProviderKind,
        tokenResponse: OAuthTokenResponse,
        transport: any OAuthHTTPTransport
    ) async throws -> OAuthAccountIdentity {
        switch provider {
        case .googleTasks:
            let profile = try await profile(
                GoogleProfile.self,
                at: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!,
                accessToken: tokenResponse.accessToken,
                transport: transport
            )
            return OAuthAccountIdentity(
                accountKey: profile.subject,
                displayName: nonEmpty(profile.name) ?? nonEmpty(profile.email) ?? "Google account"
            )
        case .todoist:
            let profile = try await profile(
                TodoistProfile.self,
                at: URL(string: "https://api.todoist.com/api/v1/user")!,
                accessToken: tokenResponse.accessToken,
                transport: transport
            )
            return OAuthAccountIdentity(
                accountKey: profile.id.value,
                displayName: nonEmpty(profile.fullName) ?? nonEmpty(profile.email) ?? "Todoist account"
            )
        case .microsoftToDo:
            let claims = try MicrosoftIDTokenClaims(token: tokenResponse.idToken)
            let profile = try await profile(
                MicrosoftProfile.self,
                at: URL(string: "https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName")!,
                accessToken: tokenResponse.accessToken,
                transport: transport
            )
            guard let graphAccountID = nonEmpty(profile.id) else {
                throw TaskProviderError.providerFailure(
                    "Microsoft did not return the Graph account identity required to connect To Do."
                )
            }
            let accountKey = [
                claims.tenantID.uuidString.lowercased(),
                graphAccountID
            ].joined(separator: ":")
            return OAuthAccountIdentity(
                accountKey: accountKey,
                displayName: nonEmpty(profile.displayName)
                    ?? nonEmpty(claims.name)
                    ?? nonEmpty(profile.userPrincipalName)
                    ?? "Microsoft account"
            )
        case .appleReminders:
            throw TaskProviderError.notConfigured
        }
    }

    private static func profile<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        accessToken: String,
        transport: any OAuthHTTPTransport
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw TaskProviderError.providerFailure(
                    "The provider returned an invalid account profile."
                )
            }
        case 401:
            throw TaskProviderError.authorizationRequired
        case 403:
            throw TaskProviderError.accessDenied
        default:
            throw TaskProviderError.providerFailure(
                "The provider could not verify the connected account."
            )
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct GoogleProfile: Decodable {
        let subject: String
        let name: String?
        let email: String?
        enum CodingKeys: String, CodingKey { case subject = "sub", name, email }
    }

    private struct TodoistProfile: Decodable {
        let id: StringOrNumber
        let fullName: String?
        let email: String?
        enum CodingKeys: String, CodingKey { case id, email; case fullName = "full_name" }
    }

    private struct MicrosoftProfile: Decodable {
        let id: String
        let displayName: String?
        let userPrincipalName: String?
    }

    private struct StringOrNumber: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self.value = value
            } else if let value = try? container.decode(Int.self) {
                self.value = String(value)
            } else {
                throw DecodingError.typeMismatch(
                    String.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected a string or numeric identifier."
                    )
                )
            }
        }
    }

    private struct MicrosoftIDTokenClaims {
        let tenantID: UUID
        let name: String?

        init(token: String?) throws {
            guard let token,
                  let payload = token.split(separator: ".").dropFirst().first,
                  let data = Self.base64URLData(String(payload)),
                  let claims = try? JSONDecoder().decode(Claims.self, from: data),
                  let rawTenantID = OAuthAccountIdentityResolver.nonEmpty(claims.tenantID),
                  let tenantID = UUID(uuidString: rawTenantID) else {
                throw TaskProviderError.providerFailure(
                    "Microsoft did not return a valid tenant identity required to connect To Do."
                )
            }
            self.tenantID = tenantID
            name = OAuthAccountIdentityResolver.nonEmpty(claims.name)
        }

        private struct Claims: Decodable {
            let tenantID: String?
            let name: String?
            enum CodingKeys: String, CodingKey { case tenantID = "tid", name }
        }

        private static func base64URLData(_ value: String) -> Data? {
            var base64 = value
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            return Data(base64Encoded: base64)
        }
    }
}

enum OAuthProviderConnection {
    /// Exchanges the one-time authorization code, derives the provider account
    /// key, and saves only the refreshable credential to Keychain.
    static func connect(
        configuration: OAuthProviderConfiguration,
        code: String,
        pkce: OAuthPKCEChallenge,
        credentials: OAuthCredentialStoring = KeychainOAuthCredentialStore(),
        transport: any OAuthHTTPTransport = URLSessionOAuthHTTPTransport(),
        now: @escaping () -> Date = Date.init
    ) async throws -> OAuthCredential {
        let response = try await OAuthTokenExchange.perform(
            OAuthTokenExchange.authorizationCodeRequest(
                configuration: configuration,
                code: code,
                pkce: pkce
            ),
            transport: transport
        )
        try OAuthGrantedScopeValidator.validate(
            provider: configuration.provider,
            grantedScope: response.scope
        )
        let identity = try await OAuthAccountIdentityResolver.resolve(
            provider: configuration.provider,
            tokenResponse: response,
            transport: transport
        )
        let credential = OAuthCredential(
            provider: configuration.provider,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { now().addingTimeInterval($0) },
            accountKey: identity.accountKey,
            displayName: identity.displayName,
            scopes: response.scope?.split(separator: " ").map(String.init) ?? []
        )
        try credentials.saveCredential(credential)
        return credential
    }
}

enum OAuthLoopbackAuthorizationError: LocalizedError, Equatable {
    case unsupportedRedirect
    case listenerUnavailable
    case browserDidNotOpen
    case malformedCallback
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedRedirect:
            "This provider needs an HTTP localhost redirect for in-app connection."
        case .listenerUnavailable:
            "KaosCal could not start the local OAuth callback listener."
        case .browserDidNotOpen:
            "KaosCal could not open the system browser for sign-in."
        case .malformedCallback:
            "The provider returned an invalid local callback."
        case .timedOut:
            "Provider authorization timed out. Reconnect and finish sign-in in the browser."
        }
    }
}

struct OAuthLoopbackAuthorizationReceipt: Equatable {
    let code: String
    let pkce: OAuthPKCEChallenge
    let effectiveRedirectURI: URL
}

/// Starts an OAuth authorization-code flow in the system browser and captures
/// exactly one callback on an HTTP loopback address. The cryptographically
/// random state is still validated before the code is exchanged, so a request
/// to the listener alone cannot connect an account.
enum OAuthLoopbackBrowserAuthorization {
    static let defaultTimeout: TimeInterval = 5 * 60

    static func authorize(
        configuration: OAuthProviderConfiguration,
        timeout: TimeInterval = defaultTimeout,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) async throws -> OAuthLoopbackAuthorizationReceipt {
        guard configuration.redirectURI.scheme?.lowercased() == "http",
              let host = configuration.redirectURI.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1" else {
            throw OAuthLoopbackAuthorizationError.unsupportedRedirect
        }
        let configuredPort: NWEndpoint.Port?
        if let portValue = configuration.redirectURI.port {
            guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: portValue) ?? 0),
                  port.rawValue != 0 else {
                throw OAuthLoopbackAuthorizationError.unsupportedRedirect
            }
            configuredPort = port
        } else {
            configuredPort = nil
        }
        let result = try await receiveCallback(
            configuration: configuration,
            port: configuredPort ?? .any,
            timeout: timeout,
            openURL: openURL
        )
        return OAuthLoopbackAuthorizationReceipt(
            code: try OAuthAuthorizationCallback.authorizationCode(
                from: result.callbackURL,
                expectedState: result.request.state
            ),
            pkce: result.request.pkce,
            effectiveRedirectURI: result.configuration.redirectURI
        )
    }

    private static func receiveCallback(
        configuration: OAuthProviderConfiguration,
        port: NWEndpoint.Port,
        timeout: TimeInterval,
        openURL: @escaping (URL) -> Bool
    ) async throws -> OAuthLoopbackCallbackResult {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            listener = try NWListener(using: parameters, on: port)
        } catch {
            throw OAuthLoopbackAuthorizationError.listenerUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            let relay = OAuthLoopbackCallbackRelay(
                listener: listener,
                continuation: continuation
            )
            relay.scheduleTimeout(after: timeout)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let boundPort = listener.port,
                          let effectiveRedirectURI = effectiveRedirectURI(
                            configuration.redirectURI,
                            port: boundPort.rawValue
                          ) else {
                        relay.finish(
                            .failure(OAuthLoopbackAuthorizationError.listenerUnavailable)
                        )
                        return
                    }
                    let effectiveConfiguration = configuration
                        .replacingRedirectURI(effectiveRedirectURI)
                    do {
                        let request = try OAuthAuthorizationRequest.make(
                            configuration: effectiveConfiguration
                        )
                        let context = OAuthLoopbackRequestContext(
                            request: request,
                            configuration: effectiveConfiguration
                        )
                        relay.setContext(context)
                        guard openURL(request.url) else {
                            relay.finish(
                                .failure(
                                    OAuthLoopbackAuthorizationError.browserDidNotOpen
                                )
                            )
                            return
                        }
                    } catch {
                        relay.finish(.failure(error))
                    }
                case .failed:
                    relay.finish(
                        .failure(OAuthLoopbackAuthorizationError.listenerUnavailable)
                    )
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                receiveHTTPRequest(on: connection) { data in
                    guard let context = relay.context else {
                        connection.cancel()
                        return
                    }
                    let callback = data.flatMap { callbackURL(
                        from: $0,
                        redirectURI: context.configuration.redirectURI
                    ) }
                    let result: Result<OAuthLoopbackCallbackResult, Error>
                    if let callback {
                        do {
                            _ = try OAuthAuthorizationCallback.authorizationCode(
                                from: callback,
                                expectedState: context.request.state
                            )
                            result = .success(
                                OAuthLoopbackCallbackResult(
                                    callbackURL: callback,
                                    request: context.request,
                                    configuration: context.configuration
                                )
                            )
                        } catch {
                            result = .failure(error)
                        }
                    } else {
                        result = .failure(
                            OAuthLoopbackAuthorizationError.malformedCallback
                        )
                    }
                    let succeeded: Bool
                    switch result {
                    case .success:
                        succeeded = true
                    case .failure:
                        succeeded = false
                    }
                    let response = callbackHTTPResponse(succeeded: succeeded)
                    connection.send(
                        content: response.data(using: .utf8),
                        completion: .contentProcessed { _ in connection.cancel() }
                    )
                    switch result {
                    case .success:
                        relay.finish(result)
                    case let .failure(error):
                        // A random local request, malformed request, or stale
                        // state must not consume the one real browser callback.
                        // A provider denial with the correct state is terminal.
                        if case .denied = error as? OAuthAuthorizationCallbackError {
                            relay.finish(result)
                        }
                    }
                }
            }
            listener.start(queue: .main)
        }
    }

    static func effectiveRedirectURI(_ baseURI: URL, port: UInt16) -> URL? {
        guard port != 0,
              var components = URLComponents(
                url: baseURI,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        components.port = Int(port)
        return components.url
    }

    static func callbackHTTPResponse(succeeded: Bool) -> String {
        if succeeded {
            return "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\nSign-in response received. Return to KaosCal while it finishes connecting."
        }
        return "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\nSign-in was not completed. Return to KaosCal to see the error and try again."
    }

    static func callbackURL(from data: Data, redirectURI: URL) -> URL? {
        guard let request = String(data: data, encoding: .utf8),
              request.contains("\r\n\r\n") || request.contains("\n\n"),
              let firstLine = request.split(separator: "\n", maxSplits: 1).first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              var components = URLComponents(
                url: redirectURI,
                resolvingAgainstBaseURL: false
              ),
              let target = URLComponents(string: String(parts[1])),
              target.scheme == nil,
              target.host == nil,
              target.user == nil,
              target.password == nil else {
            return nil
        }
        let expectedPath = components.path.isEmpty ? "/" : components.path
        let receivedPath = target.path.isEmpty ? "/" : target.path
        guard receivedPath == expectedPath else { return nil }
        components.percentEncodedQuery = target.percentEncodedQuery
        return components.url
    }

    private static func receiveHTTPRequest(
        on connection: NWConnection,
        accumulated: Data = Data(),
        completion: @escaping (Data?) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4 * 1_024
        ) { data, _, isComplete, error in
            var request = accumulated
            if let data {
                request.append(data)
            }
            guard request.count <= 16 * 1_024 else {
                completion(nil)
                return
            }
            let hasCompleteHeaders = request.range(
                of: Data("\r\n\r\n".utf8)
            ) != nil || request.range(of: Data("\n\n".utf8)) != nil
            if hasCompleteHeaders || isComplete || error != nil {
                completion(hasCompleteHeaders ? request : nil)
                return
            }
            receiveHTTPRequest(
                on: connection,
                accumulated: request,
                completion: completion
            )
        }
    }
}

private struct OAuthLoopbackRequestContext {
    let request: OAuthAuthorizationRequest
    let configuration: OAuthProviderConfiguration
}

private struct OAuthLoopbackCallbackResult {
    let callbackURL: URL
    let request: OAuthAuthorizationRequest
    let configuration: OAuthProviderConfiguration
}

private final class OAuthLoopbackCallbackRelay: @unchecked Sendable {
    private let listener: NWListener
    private let continuation: CheckedContinuation<OAuthLoopbackCallbackResult, Error>
    private let lock = NSLock()
    private var isFinished = false
    private var requestContext: OAuthLoopbackRequestContext?
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        listener: NWListener,
        continuation: CheckedContinuation<OAuthLoopbackCallbackResult, Error>
    ) {
        self.listener = listener
        self.continuation = continuation
    }

    var context: OAuthLoopbackRequestContext? {
        lock.lock()
        defer { lock.unlock() }
        return requestContext
    }

    func setContext(_ context: OAuthLoopbackRequestContext) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        requestContext = context
    }

    func scheduleTimeout(after interval: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(OAuthLoopbackAuthorizationError.timedOut))
        }
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        timeoutWorkItem = workItem
        lock.unlock()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, interval),
            execute: workItem
        )
    }

    func finish(_ result: Result<OAuthLoopbackCallbackResult, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let timeoutWorkItem = timeoutWorkItem
        lock.unlock()
        timeoutWorkItem?.cancel()
        listener.cancel()
        continuation.resume(with: result)
    }
}

enum OAuthTokenExchange {
    static func authorizationCodeRequest(
        configuration: OAuthProviderConfiguration,
        code: String,
        pkce: OAuthPKCEChallenge
    ) -> URLRequest {
        var values = [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": pkce.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI.absoluteString
        ]
        appendGoogleClientSecret(
            configuration: configuration,
            to: &values
        )
        return formRequest(
            endpoint: tokenEndpoint(for: configuration.provider),
            values: values
        )
    }

    static func refreshTokenRequest(
        configuration: OAuthProviderConfiguration,
        refreshToken: String
    ) -> URLRequest {
        var values = [
            "client_id": configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        appendGoogleClientSecret(
            configuration: configuration,
            to: &values
        )
        return formRequest(
            endpoint: tokenEndpoint(for: configuration.provider),
            values: values
        )
    }

    private static func appendGoogleClientSecret(
        configuration: OAuthProviderConfiguration,
        to values: inout [String: String]
    ) {
        guard configuration.provider == .googleTasks,
              let clientSecret = configuration.clientSecret,
              !clientSecret.isEmpty else {
            return
        }
        values["client_secret"] = clientSecret
    }

    static func perform(
        _ request: URLRequest,
        transport: any OAuthHTTPTransport = URLSessionOAuthHTTPTransport()
    ) async throws -> OAuthTokenResponse {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw OAuthTokenExchangeError.authorizationFailed(
                errorMessage(in: data) ?? "HTTP \(response.statusCode)"
            )
        }
        do {
            return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw OAuthTokenExchangeError.invalidResponse
        }
    }

    private static func tokenEndpoint(for provider: TaskProviderKind) -> URL {
        switch provider {
        case .googleTasks:
            URL(string: "https://oauth2.googleapis.com/token")!
        case .todoist:
            URL(string: "https://api.todoist.com/oauth/access_token")!
        case .microsoftToDo:
            URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
        case .appleReminders:
            URL(string: "https://localhost/unsupported-oauth-token")!
        }
    }

    private static func formRequest(
        endpoint: URL,
        values: [String: String]
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = values
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(formEncode(key))=\(formEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(
                CharacterSet(charactersIn: "-._~")
            )
        ) ?? value
    }

    private static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String: Any] else {
            return nil
        }
        return values["error_description"] as? String
            ?? values["error"] as? String
    }
}
