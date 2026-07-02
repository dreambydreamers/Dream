import Foundation

/// Configuration for the Supabase project.
///
/// The publishable (anon) key is safe to ship in the client — Row Level Security
enum SupabaseConfig {
    static let url = URL(string: "https://ohmtchfldrqobwrtyhmz.supabase.co")!
    static let publishableKey = "sb_publishable_Is1KL26mN2mUUUkXZeOACA_V5iyoiUB"
}
