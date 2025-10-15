//
//  PostComposerViewModel.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/08/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import AVFoundation
import CoreMedia
import CoreVideo
import Observation

// Sendable wrapper for AVAssetExportSession used in iOS 17 fallback
final class _SendableExportSession: @unchecked Sendable {
    let s: AVAssetExportSession
    init(_ s: AVAssetExportSession) { self.s = s }
}

// iOS 17 fallback: await an export without capturing MainActor-isolated state
fileprivate func awaitLegacyExport(_ session: AVAssetExportSession) async throws {
    let box = _SendableExportSession(session)
    if #available(iOS 18.0, *) {
        // If this helper is ever called on iOS 18+, prefer the new async API using the already-set outputURL.
        guard let url = session.outputURL else {
            throw NSError(domain: "AVAssetExportSession",
                          code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Missing outputURL for export."])
        }
        try await session.export(to: url, as: .mp4)
    } else {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                box.s.exportAsynchronously {
                    Task { @MainActor in
                        switch box.s.status {
                        case .completed:
                            cont.resume()
                        case .failed, .cancelled:
                            let err = NSError(domain: "AVAssetExportSession",
                                              code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Export failed or was cancelled."])
                            cont.resume(throwing: err)
                        default:
                            let err = NSError(domain: "AVAssetExportSession",
                                              code: -2,
                                              userInfo: [NSLocalizedDescriptionKey: "Export finished in unexpected state: \(box.s.status)"])
                            cont.resume(throwing: err)
                        }
                    }
                }
            }
        }
    }
}

// Transcode helper not tied to MainActor
// Always output MP4 (H.264/AAC). Try ExportSession first; if unsupported, force re-encode.
fileprivate func transcodeToMP4(_ inputURL: URL) async throws -> URL {
    let asset = AVURLAsset(url: inputURL)

    // 1) Fast path — export to MP4 if supported
    if let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) {
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: outURL, as: .mp4)
                return outURL
            } catch {
                // Fall through to Reader/Writer
                debugPrint("⭐️decodeerror: \(error)⭐️")
            }
        } else {
            session.outputURL = outURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            do {
                try await awaitLegacyExport(session)
                return outURL
            } catch {
                // Fall through to Reader/Writer
            }
        }
    }

    // 2) Fallback — Reader/Writer to H.264 + AAC in MP4
    let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")

    let reader = try AVAssetReader(asset: asset)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

    // Video track (if present)
    let videoTrack = asset.tracks(withMediaType: .video).first
    var videoInput: AVAssetWriterInput?
    if let vTrack = videoTrack {
        let naturalSize = try await vTrack.load(.naturalSize)
        let transform = try await vTrack.load(.preferredTransform)
        let estBitrate = max(1_000_000, Int(try await vTrack.load(.estimatedDataRate))) // >= 1Mbps
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(abs(naturalSize.width)),
            AVVideoHeightKey: Int(abs(naturalSize.height)),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: estBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = false
        vInput.transform = transform
        guard writer.canAdd(vInput) else { throw NSError(domain: "Transcode", code: -10, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"]) }
        writer.add(vInput)
        videoInput = vInput

        let vOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        let vOutput = AVAssetReaderTrackOutput(track: vTrack, outputSettings: vOutputSettings)
        guard reader.canAdd(vOutput) else { throw NSError(domain: "Transcode", code: -11, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"]) }
        reader.add(vOutput)
    }

    // Audio track (optional)
    let audioTrack = asset.tracks(withMediaType: .audio).first
    var audioInput: AVAssetWriterInput?
    if let aTrack = audioTrack {
        let aSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        aInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(aInput) else { throw NSError(domain: "Transcode", code: -12, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input"]) }
        writer.add(aInput)
        audioInput = aInput

        let aOutput = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM
        ])
        guard reader.canAdd(aOutput) else { throw NSError(domain: "Transcode", code: -13, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output"]) }
        reader.add(aOutput)
    }

    // Start I/O
    writer.shouldOptimizeForNetworkUse = true
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Transcode", code: -14, userInfo: [NSLocalizedDescriptionKey: "Cannot start writer"]) }
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "Transcode", code: -15, userInfo: [NSLocalizedDescriptionKey: "Cannot start reader"]) }
    writer.startSession(atSourceTime: .zero)

    let group = DispatchGroup()
    let vQueue = DispatchQueue(label: "transcode.video")
    let aQueue = DispatchQueue(label: "transcode.audio")

    if let vInput = videoInput, let vOutput = reader.outputs.first(where: { ($0 as? AVAssetReaderTrackOutput)?.track.mediaType == .video }) as? AVAssetReaderTrackOutput {
        group.enter()
        vInput.requestMediaDataWhenReady(on: vQueue) {
            while vInput.isReadyForMoreMediaData {
                if let sample = vOutput.copyNextSampleBuffer() {
                    _ = vInput.append(sample)
                } else {
                    vInput.markAsFinished()
                    group.leave()
                    break
                }
            }
        }
    }

    if let aInput = audioInput, let aOutput = reader.outputs.first(where: { ($0 as? AVAssetReaderTrackOutput)?.track.mediaType == .audio }) as? AVAssetReaderTrackOutput {
        group.enter()
        aInput.requestMediaDataWhenReady(on: aQueue) {
            while aInput.isReadyForMoreMediaData {
                if let sample = aOutput.copyNextSampleBuffer() {
                    _ = aInput.append(sample)
                } else {
                    aInput.markAsFinished()
                    group.leave()
                    break
                }
            }
        }
    }

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        group.notify(queue: .global()) {
            writer.finishWriting {
                if writer.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: writer.error ?? NSError(domain: "Transcode", code: -16, userInfo: [NSLocalizedDescriptionKey: "Writer failed"]))
                }
            }
        }
    }

    if reader.status == .failed {
        throw reader.error ?? NSError(domain: "Transcode", code: -17, userInfo: [NSLocalizedDescriptionKey: "Reader failed"]) }

    return outURL
}

// File-scoped upload helpers (no MainActor capture)
fileprivate func uploadImageDTO(index: Int, data: Data, width: Int, height: Int, roomId: String, postId: String, userId: String) async throws -> MediaDTO {
    // ---- Storage rule preflight (auth/path/size) ----
    guard let currentUid = Auth.auth().currentUser?.uid else {
        throw NSError(domain: "StorageAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in (auth.uid is nil)"])
    }
    guard currentUid == userId else {
        throw NSError(domain: "StorageAuth", code: 403, userInfo: [NSLocalizedDescriptionKey: "authorId segment must equal current auth.uid"])
    }
    if data.count >= 10 * 1024 * 1024 {
        throw NSError(domain: "StorageRule", code: 413, userInfo: [NSLocalizedDescriptionKey: "Image too large (>= 10MB) per Storage rules"])
    }
    let storage = Storage.storage()
    let fileName = "img_\(index)_\(UUID().uuidString).jpg"
    let ref = storage.reference().child("rooms/\(roomId)/posts/\(postId)/\(userId)/\(fileName)")
    let storagePath = ref.fullPath
    let meta = StorageMetadata()
    meta.contentType = "image/jpeg"
    print("[Upload][image] path:", ref.fullPath, " contentType:", meta.contentType ?? "(nil)", " size:", data.count)
    _ = try await ref.putDataAsync(data, metadata: meta)
    let url = try await ref.downloadURL().absoluteString
    return MediaDTO(id: url, type: "image", mediaUrl: url, width: width, height: height, duration: nil, storagePath: storagePath)
}

fileprivate func uploadVideoDTO(index: Int, fileURL: URL, roomId: String, postId: String, userId: String) async throws -> MediaDTO {
    // ---- Storage rule preflight (auth/path) ----
    guard let currentUid = Auth.auth().currentUser?.uid else {
        throw NSError(domain: "StorageAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in (auth.uid is nil)"])
    }
    guard currentUid == userId else {
        throw NSError(domain: "StorageAuth", code: 403, userInfo: [NSLocalizedDescriptionKey: "authorId segment must equal current auth.uid"])
    }
    let storage = Storage.storage()
    let mp4URL = try await transcodeToMP4(fileURL)
    // ---- Size preflight (mirror Storage rule: < 200MB) ----
    let attrs = try FileManager.default.attributesOfItem(atPath: mp4URL.path)
    let byteCount = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    print("[Upload][video] MP4 size(bytes):", byteCount)
    if byteCount >= 200 * 1024 * 1024 {
        throw NSError(domain: "StorageRule", code: 413, userInfo: [NSLocalizedDescriptionKey: "Video too large (>= 200MB) per Storage rules"])
    }
    let fileName = "mov_\(index)_\(UUID().uuidString).mp4"
    let ref = storage.reference().child("rooms/\(roomId)/posts/\(postId)/\(userId)/\(fileName)")
    let storagePath = ref.fullPath
    let meta = StorageMetadata()
    meta.contentType = "video/mp4"
    print("[Upload][video] path:", ref.fullPath, " contentType:", meta.contentType ?? "(nil)")
    _ = try await ref.putFileAsync(from: mp4URL, metadata: meta)
    let download = try await ref.downloadURL().absoluteString
    let asset = AVURLAsset(url: mp4URL)
    let duration = try await asset.load(.duration).seconds
    let track = try await asset.loadTracks(withMediaType: .video).first
    let size = try await track?.load(.naturalSize) ?? .zero
    return MediaDTO(id: download, type: "video", mediaUrl: download, width: Int(size.width), height: Int(size.height), duration: duration, storagePath: storagePath)
}

@MainActor
@Observable
class PostComposerViewModel {
    private let db = Firestore.firestore()

    var isUploading = false
    var progress: Double = 0 // 0.0 ~ 1.0

    /// 動画を mp4 にエクスポート（サイズ削減）して一時URLを返す
    func exportVideoToMP4(_ inputURL: URL) async throws -> URL {
        return try await transcodeToMP4(inputURL)
    }

    /// 添付の一括アップロード（並列）→ MediaDTO配列を返す
    func uploadAttachments(roomId: String, postId: String, userId: String, attachments: [SelectedAttachment]) async throws -> [MediaDTO] {
        // Prepare Sendable jobs (avoid capturing UIImage/SelectedAttachment in concurrent tasks)
        enum UploadItem: Sendable {
            case image(data: Data, width: Int, height: Int)
            case video(url: URL)
        }
        var jobs: [(index: Int, item: UploadItem)] = []
        for (idx, att) in attachments.enumerated() {
            switch att.kind {
            case .image(let uiImage):
                guard let data = uiImage.jpegData(compressionQuality: 0.85) else {
                    throw NSError(domain: "ImageConvert", code: -1)
                }
                jobs.append((idx, .image(data: data,
                                         width: Int(uiImage.size.width),
                                         height: Int(uiImage.size.height))))
            case .video(let url):
                jobs.append((idx, .video(url: url)))
            }
        }

        let total = attachments.count
        var completed = 0
        progress = 0

        return try await withThrowingTaskGroup(of: MediaDTO.self) { group in
            for (index, item) in jobs {
                group.addTask {
                    switch item {
                    case .image(let data, let width, let height):
                        return try await uploadImageDTO(index: index, data: data, width: width, height: height, roomId: roomId, postId: postId, userId: userId)
                    case .video(let fileURL):
                        return try await uploadVideoDTO(index: index, fileURL: fileURL, roomId: roomId, postId: postId, userId: userId)
                    }
                }
            }

            var results: [MediaDTO] = []
            for try await dto in group {
                results.append(dto)
                completed += 1
                await MainActor.run {
                    self.progress = Double(completed) / Double(total)
                }
            }
            return results
        }
    }

    /// 投稿本体：Storage → Firestore
    func submit(content: String,
                currentRoomId: String,
                userId: String,
                userName: String,
                userIcon: String,
                attachments: [SelectedAttachment]) async throws {
        isUploading = true
        progress = 0
        defer { isUploading = false }

        // 先にドキュメントID発行
        // 入力サニタイズ & バリデーション
        let contentSan = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomIdSan = currentRoomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contentSan.isEmpty else {
            throw NSError(domain: "Post", code: 400, userInfo: [NSLocalizedDescriptionKey: "本文を入力してください"]) }
        guard !roomIdSan.isEmpty else {
            throw NSError(domain: "Post", code: 400, userInfo: [NSLocalizedDescriptionKey: "ルーム情報が取得できませんでした"]) }

        // Firestore: /rooms/{roomId}/posts/{postId}
        let postsRef = db.collection("rooms").document(roomIdSan).collection("posts")
        let docRef = postsRef.document() // ← Firestore にIDを任せる
        let postId = docRef.documentID

        // 添付アップロード（必要なければ空配列）
        let mediaDTOs = try await uploadAttachments(roomId: roomIdSan, postId: postId, userId: userId, attachments: attachments)

        // Firestore保存
        var mediaPayload: [[String: Any]] = []
        mediaPayload.reserveCapacity(mediaDTOs.count)
        for m in mediaDTOs {
            var item: [String: Any] = [
                "id": m.id,
                "type": m.type,
                "mediaUrl": m.mediaUrl,
                "width": m.width,
                "height": m.height,
            ]
            if let d = m.duration { item["duration"] = d }
            if let sp = m.storagePath { item["storagePath"] = sp }
            mediaPayload.append(item)
        }

        let payload: [String: Any] = [
            "content": contentSan,
            "authorId": userId,
            "authorName": userName,
            "userIcon": userIcon,
            "createdAt": FieldValue.serverTimestamp(),
            "media": mediaPayload
        ]

        try await docRef.setData(payload)
    }
}
