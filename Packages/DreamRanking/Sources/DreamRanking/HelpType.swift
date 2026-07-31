import Foundation

/// Canonical help-type taxonomy — the matching currency between what a dream
/// needs and what a supporter offers. Mirrors the SQL enum `help_type`.
public enum HelpType: String, Codable, CaseIterable, Sendable, Hashable {
    case code
    case design
    case funding
    case mentorship
    case marketing
    case legal
    case space
    case other

    /// Swift twin of SQL `to_help_type` (0021_help_types.sql) — keep in sync.
    /// Legacy "Network" maps to mentorship (intros are mentorship-adjacent).
    public static func normalize(_ raw: String) -> HelpType {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "code", "coding", "engineering", "development", "developer":
            return .code
        case "design":
            return .design
        case "funding", "investment", "investor":
            return .funding
        case "mentorship", "mentor", "mentoring", "network", "networking":
            return .mentorship
        case "marketing":
            return .marketing
        case "legal":
            return .legal
        case "space", "venue":
            return .space
        default:
            return .other
        }
    }

    /// Human-readable form used in reason strings.
    public var displayName: String {
        switch self {
        case .code: return "coding"
        case .design: return "design"
        case .funding: return "funding"
        case .mentorship: return "mentorship"
        case .marketing: return "marketing"
        case .legal: return "legal help"
        case .space: return "a space"
        case .other: return "a hand"
        }
    }
}
