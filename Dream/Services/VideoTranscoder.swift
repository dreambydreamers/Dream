import AVFoundation
import Foundation

/// Re-encodes a captured/picked video to a sane mobile bitrate before upload.
///
/// Source clips from the camera are full-HD at ~15 Mbps (≈2 MB/s), which is far
/// more than a phone-sized vertical feed can show. Capping the bitrate to ~6 Mbps
/// (retaining 1080p resolution) cuts the stored file — and every byte of playback
/// egress — by ~60% with no visible quality loss.
///
/// Uses `AVAssetReader`/`AVAssetWriter` rather than `AVAssetExportSession` because
/// the export presets don't let you set a target bitrate.
enum VideoTranscoder {
    enum TranscodeError: Error { case noVideoTrack, exportFailed }

    /// Re-encodes `source` to H.264 `.mp4` at `targetBitrate`, scaled to fit
    /// `maxLongEdge` (preserving aspect & orientation). Returns a temp-file URL.
    ///
    /// If the source is already at/under ~1.2× the target bitrate and within the
    /// resolution cap, returns `source` unchanged (no point re-encoding).
    static func transcode(
        _ source: URL,
        targetBitrate: Int = 6_000_000,
        maxLongEdge: CGFloat = 1920
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TranscodeError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let fps = nominalFrameRate > 0 ? Int(nominalFrameRate.rounded()) : 30

        // Skip guard: if the file is already small enough, don't touch it.
        if try await sourceIsAlreadySmall(asset, naturalSize: naturalSize,
                                          targetBitrate: targetBitrate, maxLongEdge: maxLongEdge) {
            return source
        }

        let outputSize = fittedSize(naturalSize, maxLongEdge: maxLongEdge)

        // --- Reader ---
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw TranscodeError.exportFailed }
        reader.add(videoOutput)

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            let out = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            if reader.canAdd(out) { reader.add(out); audioOutput = out }
        }

        // --- Writer ---
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(outputSize.width),
                AVVideoHeightKey: Int(outputSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: targetBitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: max(fps * 2, 30),
                    AVVideoAllowFrameReorderingKey: true
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        // Preserve portrait/landscape orientation from the source track.
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { throw TranscodeError.exportFailed }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 128_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) { writer.add(input); audioInput = input }
        }

        // --- Run ---
        guard reader.startReading() else { throw reader.error ?? TranscodeError.exportFailed }
        guard writer.startWriting() else { throw writer.error ?? TranscodeError.exportFailed }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "video.transcode")

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await pump(input: videoInput, from: videoOutput, on: queue)
            }
            if let audioInput, let audioOutput {
                group.addTask {
                    await pump(input: audioInput, from: audioOutput, on: queue)
                }
            }
        }

        await writer.finishWriting()

        if reader.status == .failed || writer.status == .failed {
            try? FileManager.default.removeItem(at: outURL)
            throw writer.error ?? reader.error ?? TranscodeError.exportFailed
        }

        return outURL
    }

    // MARK: - Helpers

    /// Drains one reader output into one writer input, honoring back-pressure.
    private static func pump(
        input: AVAssetWriterInput,
        from output: AVAssetReaderTrackOutput,
        on queue: DispatchQueue
    ) async {
        await withCheckedContinuation { continuation in
            nonisolated(unsafe) let input = input
            nonisolated(unsafe) let output = output
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sample = output.copyNextSampleBuffer() {
                        if !input.append(sample) {
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    } else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    /// Scales `size` to fit within `maxLongEdge` on its longest side, preserving
    /// aspect ratio, never upscaling, and rounding to even dimensions (H.264 needs it).
    private static func fittedSize(_ size: CGSize, maxLongEdge: CGFloat) -> CGSize {
        let w = abs(size.width), h = abs(size.height)
        guard w > 0, h > 0 else { return CGSize(width: 1080, height: 1920) }
        let longEdge = max(w, h)
        let scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1
        func even(_ v: CGFloat) -> CGFloat { let r = (v * scale).rounded(); return r.truncatingRemainder(dividingBy: 2) == 0 ? r : r - 1 }
        return CGSize(width: max(even(w), 2), height: max(even(h), 2))
    }

    /// True when the source is already within the resolution cap and at/under
    /// ~1.2× the target bitrate — re-encoding would only lose quality.
    private static func sourceIsAlreadySmall(
        _ asset: AVURLAsset,
        naturalSize: CGSize,
        targetBitrate: Int,
        maxLongEdge: CGFloat
    ) async throws -> Bool {
        let longEdge = max(abs(naturalSize.width), abs(naturalSize.height))
        guard longEdge <= maxLongEdge else { return false }

        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 0 else { return false }

        guard let values = try? asset.url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return false }

        let bitrate = Double(bytes) * 8 / seconds
        return bitrate <= Double(targetBitrate) * 1.2
    }
}
