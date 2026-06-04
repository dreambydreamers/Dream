import Foundation

/// Configuration for the Supabase project.
///
/// The publishable (anon) key is safe to ship in the client — Row Level Security
enum SupabaseConfig {
    static let url = URL(string: "https://qlrqcymqtxrrpekdzgxx.supabase.co")!
    static let publishableKey = "sb_publishable_aYnGiuDLqjAd4haLi5M3lg_sysU5QnR"
}
