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
    private var isFlushing = false

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
    ///
    /// Guarded against re-entrancy: `log()`, the 15 s timer and the
    /// didEnterBackground observer can all call this, and the `await` on the RPC
    /// is a suspension point where a second caller would read the same buffer
    /// prefix and send it again — double-counting impressions.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

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

    /// Drops the buffer on sign-out. The caller flushes first; anything left
    /// here failed to send and must not be replayed as the next signed-in user,
    /// since `log_engagement_batch` attributes events to `auth.uid()` at flush
    /// time rather than at capture time.
    func reset() {
        flushTask?.cancel()
        flushTask = nil
        buffer = []
        UserDefaults.standard.removeObject(forKey: Self.bufferDefaultsKey)
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
