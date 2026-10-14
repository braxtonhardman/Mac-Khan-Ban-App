import Foundation
import Security
import SwiftUI
import Observation

struct GitHubRepository: Decodable, Identifiable, Hashable, Sendable {
    let id: Int64
    let fullName: String
    let isPrivate: Bool

    static func webURL(fullName: String) -> URL? {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: "https://github.com/" + fullName)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case isPrivate = "private"
    }
}

enum GitHubConnectionError: LocalizedError {
    case message(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .unauthorized: return "GitHub rejected this token. Replace it with a valid, unexpired token."
        }
    }
}

// A fine-grained, metadata-only token stays on this device and never enters SwiftData or iCloud.
enum GitHubKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Tierin.GitHub",
         kSecAttrAccount as String: "token",
         kSecAttrSynchronizable as String: false]
    }

    static func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw GitHubConnectionError.message("Couldn’t read the GitHub connection.")
        }
        return token
    }

    static func write(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw GitHubConnectionError.message("Couldn’t save the GitHub connection.")
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw GitHubConnectionError.message("Couldn’t save the GitHub connection.")
        }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubConnectionError.message("Couldn’t remove the GitHub connection.")
        }
    }
}

private final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward a personal token to a redirected endpoint.
        completionHandler(nil)
    }
}

enum GitHubClient {
    private static let session = URLSession(configuration: .ephemeral, delegate: GitHubRedirectPolicy(), delegateQueue: nil)

    struct User: Decodable { let login: String }
    static func username(token: String, session: URLSession? = nil) async throws -> String {
        let (data, _) = try await request(path: "user", token: token, session: session)
        return try JSONDecoder().decode(User.self, from: data).login
    }

    static func repositories(token: String, session: URLSession? = nil) async throws -> [GitHubRepository] {
        var result: [Int64: GitHubRepository] = [:]
        for page in 1...10 {
            try Task.checkCancellation()
            let (data, response) = try await request(path: "user/repos?per_page=100&page=\(page)&sort=full_name", token: token, session: session)
            let batch = try JSONDecoder().decode([GitHubRepository].self, from: data)
            for repository in batch { result[repository.id] = repository }
            let more = response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true
            if !more { return result.values.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending } }
        }
        throw GitHubConnectionError.message("This token exposes more than 1,000 repositories. Select fewer repositories in its GitHub settings, then refresh.")
    }

    private static func request(path: String, token: String, session: URLSession?) async throws -> (Data, HTTPURLResponse) {
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw GitHubConnectionError.unauthorized
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/" + path)!)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tierin", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await (session ?? self.session).data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw GitHubConnectionError.message("GitHub didn’t respond. Try again.")
        }
        if response.statusCode == 401 { throw GitHubConnectionError.unauthorized }
        if response.statusCode == 429 || (response.statusCode == 403 && (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" || response.value(forHTTPHeaderField: "Retry-After") != nil)) {
            throw GitHubConnectionError.message("GitHub’s request limit has been reached. Wait before refreshing again.")
        }
        if response.statusCode == 403 {
            throw GitHubConnectionError.message("GitHub denied access. Check the token’s selected repositories, metadata permission, and organization approval.")
        }
        guard response.statusCode == 200, data.count < 2_000_000 else {
            throw GitHubConnectionError.message("Couldn’t load GitHub data. Try again later.")
        }
        return (data, response)
    }
}

@MainActor @Observable
final class GitHubConnection {
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var repositoryCount: Int?
    private(set) var username: String?
    private(set) var needsReconnect = false
    var error: String?

    func load() {
        do { isConnected = try GitHubKeychain.read() != nil }
        catch { self.error = error.localizedDescription }
    }

    func connect(token: String) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = try await GitHubClient.username(token: token)
            let repositories = try await GitHubClient.repositories(token: token)
            try Task.checkCancellation()
            try GitHubKeychain.write(token)
            self.username = username
            needsReconnect = false
            repositoryCount = repositories.count
            isConnected = true
        } catch {
            self.error = (error as? GitHubConnectionError)?.localizedDescription ?? "Couldn’t connect GitHub. Try again."
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            guard let token = try GitHubKeychain.read() else { isConnected = false; return }
            let username = try await GitHubClient.username(token: token)
            let repositories = try await GitHubClient.repositories(token: token)
            try Task.checkCancellation()
            self.username = username
            repositoryCount = repositories.count
            needsReconnect = false
            isConnected = true
        } catch is CancellationError { }
        catch {
            if case GitHubConnectionError.unauthorized = error { needsReconnect = true }
            self.error = (error as? GitHubConnectionError)?.localizedDescription ?? "Couldn’t refresh GitHub. Check your connection and try again."
        }
    }

    func disconnect() {
        do {
            try GitHubKeychain.remove()
            isConnected = false
            repositoryCount = nil
            username = nil
            needsReconnect = false
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// Standalone network tests compile the production client without the app UI.
#if !INTEGRATION_TESTING
struct GitHubProfileView: View {
    @Bindable var connection: GitHubConnection
    @State private var token = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                IntegrationSettingsCard(title: "Account connection") {
                    IntegrationAccountHeader(service: "GitHub",
                        identity: connection.username.map { "@" + $0 } ?? (connection.isConnected ? "Saved on this device" : "Link repositories to your Tierin projects"),
                        connected: connection.isConnected, needsReconnect: connection.needsReconnect)
                    if connection.isConnected {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Repository access").font(AppTypography.contextTitle)
                            if let count = connection.repositoryCount {
                                Text("\(count) repositories available to link")
                                    .font(AppTypography.supporting).foregroundStyle(.secondary)
                            }
                            Text("Choose a repository when creating or editing a project.")
                                .font(AppTypography.supporting).foregroundStyle(.secondary)
                        }
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack { connectionActions }
                            VStack(alignment: .leading, spacing: 12) { connectionActions }
                        }
                    }
                }
                .disabled(connection.isBusy)
                if !connection.isConnected || connection.needsReconnect {
                    IntegrationSettingsCard(title: connection.needsReconnect ? "Reconnect account" : "Connect account") {
                        Text("Fine-grained access token").font(AppTypography.contextTitle)
                        SecureField("Paste your GitHub token", text: $token)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        Text("Select the repositories you want Tierin to see. Only read access to repository metadata is needed.")
                            .font(AppTypography.supporting).foregroundStyle(.secondary)
                        Button("Connect GitHub") {
                            Task {
                                await connection.connect(token: token)
                                if connection.error == nil { token = "" }
                            }
                        }
                        .appGlassButton(accent: true)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                            .font(AppTypography.supporting)
                    }
                    .disabled(connection.isBusy)
                }
                IntegrationSettingsCard(title: "Permissions & storage") {
                    Label("Repository metadata only", systemImage: "lock.shield")
                        .font(AppTypography.contextTitle)
                    Text("Tierin does not need code, issue, or write access. Your access token stays securely on this device.")
                        .font(AppTypography.supporting).foregroundStyle(.secondary)
                }
                if connection.isBusy { ProgressView("Checking GitHub…").font(AppTypography.supporting) }
                if let error = connection.error {
                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                }
            }.padding(24)
        }
        .task {
            connection.load()
            if connection.isConnected { await connection.refresh() }
        }
        .onDisappear { token = "" }
    }
    @ViewBuilder private var connectionActions: some View {
        Button("Refresh connection") { Task { await connection.refresh() } }
            .appGlassButton()
        Button("Disconnect", role: .destructive) { connection.disconnect() }
            .appGlassButton()
    }

}

#endif
