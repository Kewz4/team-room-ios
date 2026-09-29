import Foundation

enum LinkRoute: Equatable { case artifact(String), web(URL), unsupported }

enum LinkRouting {
    static func resolve(_ url: URL, relativeTo: String? = nil, server: String = "") -> LinkRoute {
        let scheme = url.scheme?.lowercased()
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.path == "/api/artifact", let path = parts?.queryItems?.first(where: { $0.name == "path" })?.value {
            let host = url.host ?? ""
            if host.isEmpty || host == URL(string: server)?.host || ["127.0.0.1", "localhost"].contains(host) || host.hasSuffix(".trycloudflare.com") {
                return .artifact(clean(path))
            }
        }
        if ["https", "http", "mailto"].contains(scheme ?? "") { return .web(url) }
        var path = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        if scheme == "file" { path = url.path.removingPercentEncoding ?? url.path }
        let windows = path.range(of: #"^/?[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
        guard scheme == nil || scheme == "file" || windows else { return .unsupported }
        path = clean(path)
        if windows || path.hasPrefix("/") { return .artifact(path) }
        while path.hasPrefix("./") { path.removeFirst(2) }
        if path.hasPrefix("workspace/") { return .artifact(path) }
        if let relativeTo {
            let base = clean(relativeTo).replacingOccurrences(of: "\\", with: "/")
            let parent = base.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")
            return .artifact(parent + "/" + path)
        }
        return .artifact(path)
    }

    private static func clean(_ value: String) -> String {
        var path = value.replacingOccurrences(of: "\\", with: "/")
        if path.range(of: #"^/[A-Za-z]:/"#, options: .regularExpression) != nil { path.removeFirst() }
        if let fragment = path.firstIndex(of: "#") { path = String(path[..<fragment]) }
        return path.replacingOccurrences(of: #":\d+(?:-\d+)?$"#, with: "", options: .regularExpression)
    }

    static func prepareMarkdown(_ text: String) -> String {
        // Native Markdown links must contain encoded URLs, including Windows paths with spaces.
        guard let regex = try? NSRegularExpression(pattern: #"\]\((<?(?:[A-Za-z]:[\\/]|/|\./|workspace/)[^\n]*?)\)"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            var path = String(result[range])
            if path.hasPrefix("<"), path.hasSuffix(">") { path = String(path.dropFirst().dropLast()) }
            path = path.replacingOccurrences(of: "\\", with: "/")
            let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: ":?&#=%"))
            if let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) { result.replaceSubrange(range, with: encoded) }
        }
        return result
    }
}

struct ArtifactRequest: Identifiable { let path: String; var id: String { path } }
