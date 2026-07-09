import Foundation

/// Configuration for the Supabase project.
///
/// The publishable key is safe to ship in the client; Row Level Security and
/// RPC permissions enforce backend access.
enum SupabaseConfig {
    static let url = URL(string: "https://ohmtchfldrqobwrtyhmz.supabase.co")!
    static let publishableKey = "sb_publishable_Is1KL26mN2mUUUkXZeOACA_V5iyoiUB"
}
