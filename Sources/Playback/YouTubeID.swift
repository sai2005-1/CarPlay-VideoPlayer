import Foundation

/// Extracts YouTube video IDs from any common URL format or a bare ID.
enum YouTubeID {
    private static let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    static func isValidID(_ s: String) -> Bool {
        s.count == 11 && s.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }

    static func extract(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidID(trimmed) { return trimmed }

        var candidate = trimmed
        if !candidate.lowercased().hasPrefix("http") { candidate = "https://" + candidate }
        guard let comps = URLComponents(string: candidate), let host = comps.host?.lowercased() else { return nil }

        let isYouTube = host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com")
        guard isYouTube else { return nil }

        if host == "youtu.be" {
            let first = comps.path.split(separator: "/").first.map(String.init) ?? ""
            return isValidID(first) ? first : nil
        }

        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, isValidID(v) {
            return v
        }

        let parts = comps.path.split(separator: "/").map(String.init)
        let markers: Set<String> = ["embed", "shorts", "live", "v", "e"]
        for (i, p) in parts.enumerated() where markers.contains(p) && i + 1 < parts.count {
            let id = parts[i + 1]
            if isValidID(id) { return id }
        }
        return nil
    }

    /// Returns the start time (seconds) from `t=` / `start=` parameters, if any.
    static func startTime(from input: String) -> Double? {
        guard let comps = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        guard let raw = comps.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value else { return nil }
        if let s = Double(raw) { return s }
        // Formats like 1h2m3s
        var total = 0.0
        var number = ""
        for ch in raw {
            if ch.isNumber { number.append(ch); continue }
            let n = Double(number) ?? 0
            switch ch {
            case "h": total += n * 3600
            case "m": total += n * 60
            case "s": total += n
            default: break
            }
            number = ""
        }
        if !number.isEmpty { total += Double(number) ?? 0 }
        return total > 0 ? total : nil
    }
}
