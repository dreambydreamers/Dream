import Combine
import Foundation
import Supabase
#if canImport(UIKit)
import UIKit
#endif

/// Buffered engagement-event logger. Call sites (added when the feed UI is
/// wired) record view/watch/skip/save/… events; the logger batches them and
/// flushes through the `log_engagement_batch` RPC, which maintains the
/// seen-set and exposure counters server-side.
///
/// These events shape ONLY the logging viewer's own affinity profile — the
/// backend never aggregates them into a per-dream quality signal.
@MainActor
final class EngagementLogger: ObservableObject {
    static let shared = EngagementLogger()

    private let client = SupabaseService.shared.client
    private var buffer: [EngagementEventPayload] = []
    private var flushTask: Task<Void, Never>?

    private static let bufferDefaultsKey = "engagement_event_buffer"
    private static let flushThreshold = 10
    private static let flushIntervalSeconds: UInt64 = 15
    private static let maxBatchSize = 100 // matches the RPC's cap

    private init() {
        restoreBuffer()
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await EngagementLogger.shared.flush() }
        }
        #endif
    }

    func log(
        _ type: EngagementEventType,
        dreamId: UUID,
        watchMs: Int? = nil,
        videoDurationMs: Int? = nil
    ) {
        buffer.append(EngagementEventPayload(
            type: type, dreamId: dreamId, watchMs: watchMs, videoDurationMs: videoDurationMs
        ))
        persistBuffer()
        if buffer.count >= Self.flushThreshold {
            Task { await flush() }
        } else {
            scheduleFlush()
        }
    }

    /// Sends everything buffered. Failed batches stay buffered for retry.
    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        guard !buffer.isEmpty else { return }

        while !buffer.isEmpty {
            let batch = Array(buffer.prefix(Self.maxBatchSize))
            do {
                try await client
                    .rpc("log_engagement_batch", params: ["p_events": batch])
                    .execute()
                buffer.removeFirst(min(batch.count, buffer.count))
                persistBuffer()
            } catch {
                print("[EngagementLogger] flush failed (\(buffer.count) buffered): \(error)")
                scheduleFlush()
                return
            }
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.flushIntervalSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    // MARK: - Crash/kill safety

    private func persistBuffer() {
        let data = try? JSONEncoder().encode(buffer)
        UserDefaults.standard.set(data, forKey: Self.bufferDefaultsKey)
    }

    private func restoreBuffer() {
        guard let data = UserDefaults.standard.data(forKey: Self.bufferDefaultsKey),
              let restored = try? JSONDecoder().decode([EngagementEventPayload].self, from: data)
        else { return }
        buffer = restored
        if !buffer.isEmpty { scheduleFlush() }
    }
}
