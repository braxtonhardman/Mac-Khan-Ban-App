import Foundation

final class StubProtocol: URLProtocol {
    static var respond: (URLRequest) throws -> (Int, [String: String], Data) = { _ in fatalError("Unexpected request") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
@main struct GitHubTests {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var pages: [Int] = []
        StubProtocol.respond = { request in
            expect(request.url?.host == "api.github.com", "GitHub host")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "Authorization header")
            expect(request.httpMethod == "GET", "Read-only integration")
            let page = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!)!
            pages.append(page)
            let json = page == 1 ? "[{\"id\":2,\"full_name\":\"owner/Zebra\",\"private\":true}]" : "[{\"id\":2,\"full_name\":\"owner/Zebra\",\"private\":true},{\"id\":1,\"full_name\":\"owner/Alpha\",\"private\":false}]"
            return (200, page == 1 ? ["Link": "<https://api.github.com/user/repos?page=2>; rel=\"next\""] : [:], Data(json.utf8))
        }
        let repositories = try await GitHubClient.repositories(token: "test-token", session: session)
        expect(pages == [1, 2], "Follow pagination even with a short first page")
        expect(repositories.map(\.id) == [1, 2], "Deduplicate stable IDs and sort names")
        for (status, headers, expected) in [(401, [:], "rejected"), (403, [:], "denied"), (403, ["X-RateLimit-Remaining": "0"], "limit"), (429, [:], "limit"), (500, [:], "later")] {
            StubProtocol.respond = { _ in (status, headers, Data()) }
            do { _ = try await GitHubClient.repositories(token: "test-token", session: session); fatalError("Expected error") }
            catch { expect(error.localizedDescription.contains(expected), "Actionable status error") }
        }
        StubProtocol.respond = { _ in (200, [:], Data("{\"login\":\"octocat\"}".utf8)) }
        let user = try await GitHubClient.username(token: "test-token", session: session)
        expect(user == "octocat", "Verified account name")
        StubProtocol.respond = { _ in (200, [:], Data("[]".utf8)) }
        let empty = try await GitHubClient.repositories(token: "test-token", session: session)
        expect(empty.isEmpty, "Empty account is valid")
        for name in ["evil.test@github.com/repo", "../repo", "owner/repo?token=x", "owner/repo/extra", "owner/"] {
            expect(GitHubRepository.webURL(fullName: name) == nil, "Reject invalid stored repository names")
        }
        expect(GitHubRepository.webURL(fullName: "owner/my-repo")?.absoluteString == "https://github.com/owner/my-repo", "Safe repository URL")
        print("GitHub pagination, errors, identity, and repository URL tests passed.")
    }
}
