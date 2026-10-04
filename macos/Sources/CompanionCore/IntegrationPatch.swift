import Foundation

public enum IntegrationPatch {
    public static let begin = "# BEGIN DSH ALWAYS ON MANAGED"
    public static let end = "# END DSH ALWAYS ON MANAGED"
    public static func removing(from original: String) throws -> String {
        guard let start = original.range(of: begin) else {
            if original.contains(end) { throw PatchError.conflict }
            return original
        }
        guard let finish = original.range(of: end, range: start.upperBound..<original.endIndex),
              !original[start.upperBound...].contains(begin),
              !original[finish.upperBound...].contains(end) else { throw PatchError.conflict }
        var upper = finish.upperBound
        if upper < original.endIndex, original[upper] == "\n" { upper = original.index(after: upper) }
        var result = original; result.removeSubrange(start.lowerBound..<upper); return result
    }
    public static func installing(into original: String, pluginEntry: String) throws -> String {
        let clean = try removing(from: original)
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pluginEntry.contains("\n") else { throw PatchError.conflict }
        // Preserve all user text; support empty array documents explicitly.
        var prefix: String
        if trimmed.isEmpty || trimmed == "[]" { prefix = "" }
        else {
            let lines = clean.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") }), first.hasPrefix("- "),
                  !lines.contains("---"), !lines.contains("...") else { throw PatchError.unsupported }
            prefix = clean.hasSuffix("\n") ? clean : clean + "\n"
        }
        let quoted = String(data: try JSONEncoder().encode(pluginEntry), encoding: .utf8)!
        return prefix + "\(begin)\n- insert:\n    - id: dsh-always-on\n      name: \(quoted)\n\(end)\n"
    }
    public enum PatchError: Error { case conflict, unsupported }
}
