import Foundation
import Security
import SwiftUI
import Observation

struct GitHubRepository: Decodable, Identifiable, Hashable, Sendable {
    let id: Int64
    let fullName: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case isPrivate = "private"
    }
}

enum GitHubConnectionError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let message): return message }
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

enum GitHubClient {
    static func repositories(token: String) async throws -> [GitHubRepository] {
        var result: [GitHubRepository] = []
        // Keep the picker bounded while still covering larger personal accounts.
        for page in 1...10 {
            let url = URL(string: "https://api.github.com/user/repos?per_page=100&page=\(page)&sort=updated")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GitHubConnectionError.message("GitHub didn’t respond. Try again.")
            }
            if response.statusCode == 401 {
                throw GitHubConnectionError.message("GitHub rejected this token. Check that it is valid and has not expired.")
            }
            guard response.statusCode == 200, data.count < 2_000_000 else {
                throw GitHubConnectionError.message("Couldn’t load repositories from GitHub. Try again later.")
            }
            let batch = try JSONDecoder().decode([GitHubRepository].self, from: data)
            result.append(contentsOf: batch)
            if batch.count < 100 { break }
        }
        return result
    }
}

@MainActor @Observable
final class GitHubConnection {
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var repositoryCount: Int?
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
            let repositories = try await GitHubClient.repositories(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
            try GitHubKeychain.write(token.trimmingCharacters(in: .whitespacesAndNewlines))
            repositoryCount = repositories.count
            isConnected = true
        } catch {
            self.error = (error as? GitHubConnectionError)?.localizedDescription ?? "Couldn’t connect GitHub. Try again."
        }
    }

    func disconnect() {
        do {
            try GitHubKeychain.remove()
            isConnected = false
            repositoryCount = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct GitHubProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var connection: GitHubConnection
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                AppSection("GitHub account") {
                    if connection.isConnected {
                        Label("Connected", systemImage: "checkmark.circle")
                            .font(AppTypography.body)
                        if let count = connection.repositoryCount {
                            Text("\(count) repositories available to link")
                                .font(AppTypography.supporting).foregroundStyle(.secondary)
                        }
                        Button("Disconnect", role: .destructive) { connection.disconnect() }
                            .appGlassButton()
                    } else {
                        Text("Connect GitHub to select repositories for your projects.")
                            .font(AppTypography.body)
                        SecureField("Fine-grained access token", text: $token)
                        Button("Connect GitHub") {
                            Task {
                                await connection.connect(token: token)
                                if connection.isConnected { token = "" }
                            }
                        }
                        .appGlassButton(accent: true)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    }
                    Text("Select the repositories you want Tierin to see. Repository metadata needs read access; no code, issue, or write permission is required. The token stays on this device.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                .disabled(connection.isBusy)
                if connection.isBusy { ProgressView("Checking GitHub…") }
                if let error = connection.error {
                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("GitHub")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .modifier(EditorSizing(width: 500, height: 520))
        .onAppear { connection.load() }
    }
}
