//
//  MediaService.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/11/10.
//

import Foundation
import AVFoundation
import FirebaseStorage
import FirebaseAuth
import UIKit

/// メディア変換・アップロードを担当（actor で安全性確保）
///
/// ## 責務
/// - 動画のトランスコード（MP4/H.264/AAC）
/// - Storage へのアップロード（画像/動画）
/// - MediaDTO の生成
///
/// ## 使用例
/// ```swift
/// let service = MediaService()
/// let dtos = try await service.uploadMedia(
///     attachments: [.image(uiImage), .video(videoURL)],
///     roomId: "room123"
/// )
/// ```
actor MediaService {
    
    // MARK: - Public API
    
    /// 複数の添付ファイルを Storage にアップロードし MediaDTO を返す
    ///
    /// - Parameters:
    ///   - attachments: 添付メディア（画像 or 動画）
    ///   - roomId: 投稿先の Room ID
    /// - Returns: アップロード完了した MediaDTO の配列
    /// - Throws: Storage/Transcode のエラー
    /// - Note: postId と userId は内部で生成（Storage Rules の `{postId}/{authorId}` に準拠）
    nonisolated func uploadMedia(
        attachments: [SelectedAttachment.Kind],
        roomId: String
    ) async throws -> [MediaDTO] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.unauthenticated
        }
        
        // 一時的な postId を生成（Firestore に書き込む前に Storage パスを確定）
        let postId = UUID().uuidString
        
        var results: [MediaDTO] = []
        
        for (index, kind) in attachments.enumerated() {
            switch kind {
            case .image(let uiImage):
                guard let data = uiImage.jpegData(compressionQuality: 0.8) else {
                    throw AppError.invalidData
                }
                let width = Int(uiImage.size.width)
                let height = Int(uiImage.size.height)
                
                let dto = try await uploadImage(
                    index: index,
                    data: data,
                    width: width,
                    height: height,
                    roomId: roomId,
                    postId: postId,
                    userId: uid
                )
                results.append(dto)
                
            case .video(let url):
                let dto = try await uploadVideo(
                    index: index,
                    fileURL: url,
                    roomId: roomId,
                    postId: postId,
                    userId: uid
                )
                results.append(dto)
            }
        }
        
        return results
    }
    
    // MARK: - Transcoding
    
    /// 動画をMP4（H.264/AAC）に変換
    func transcodeToMP4(_ inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        
        if let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) {
            let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            if #available(iOS 18.0, *) {
                do {
                    try await session.export(to: outURL, as: .mp4)
                    return outURL
                } catch {
                    // Fallback to Reader/Writer
                }
            } else {
                session.outputURL = outURL
                session.outputFileType = .mp4
                session.shouldOptimizeForNetworkUse = true
                do {
                    try await awaitLegacyExport(session)
                    return outURL
                } catch {
                    // Fallback to Reader/Writer
                }
            }
        }
        
        return try await transcodeWithReaderWriter(asset)
    }
    
    // MARK: - Upload
    
    /// 画像をアップロードし MediaDTO を返す
    func uploadImage(
        index: Int,
        data: Data,
        width: Int,
        height: Int,
        roomId: String,
        postId: String,
        userId: String
    ) async throws -> MediaDTO {
        // Storage rule preflight
        guard let currentUid = Auth.auth().currentUser?.uid else {
            throw AppError.unauthenticated
        }
        guard currentUid == userId else {
            throw AppError.unauthorized
        }
        if data.count >= 10 * 1024 * 1024 {
            throw AppError.fileTooLarge("画像サイズが10MBを超えています")
        }
        
        let storage = Storage.storage()
        let fileName = "img_\(index)_\(UUID().uuidString).jpg"
        let ref = storage.reference().child("rooms/\(roomId)/posts/\(postId)/\(userId)/\(fileName)")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL().absoluteString
        
        return await MediaDTO(
            id: url,
            type: "image",
            mediaUrl: url,
            width: width,
            height: height,
            duration: nil,
            storagePath: ref.fullPath
        )
    }
    
    /// 動画をアップロードし MediaDTO を返す
    func uploadVideo(
        index: Int,
        fileURL: URL,
        roomId: String,
        postId: String,
        userId: String
    ) async throws -> MediaDTO {
        // Storage rule preflight
        guard let currentUid = Auth.auth().currentUser?.uid else {
            throw AppError.unauthenticated
        }
        guard currentUid == userId else {
            throw AppError.unauthorized
        }
        
        let mp4URL = try await transcodeToMP4(fileURL)
        
        let attrs = try FileManager.default.attributesOfItem(atPath: mp4URL.path)
        let byteCount = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if byteCount >= 200 * 1024 * 1024 {
            throw AppError.fileTooLarge("動画サイズが200MBを超えています")
        }
        
        let storage = Storage.storage()
        let fileName = "mov_\(index)_\(UUID().uuidString).mp4"
        let ref = storage.reference().child("rooms/\(roomId)/posts/\(postId)/\(userId)/\(fileName)")
        let meta = StorageMetadata()
        meta.contentType = "video/mp4"
        
        _ = try await ref.putFileAsync(from: mp4URL, metadata: meta)
        let download = try await ref.downloadURL().absoluteString
        
        let asset = AVURLAsset(url: mp4URL)
        let duration = try await asset.load(.duration).seconds
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await track?.load(.naturalSize) ?? .zero
        
        return await MediaDTO(
            id: download,
            type: "video",
            mediaUrl: download,
            width: Int(size.width),
            height: Int(size.height),
            duration: duration,
            storagePath: ref.fullPath
        )
    }
    
    // MARK: - Private Helpers
    
    /// iOS 17以前の AVAssetExportSession を async/await でラップ
    private nonisolated func awaitLegacyExport(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let error = session.error ?? AppError.transcodeError("Export failed or was cancelled")
                    continuation.resume(throwing: error)
                default:
                    continuation.resume(throwing: AppError.transcodeError("Unexpected status: \(session.status.rawValue)"))
                }
            }
        }
    }
    
    /// AVAssetReader/Writer を使った手動トランスコード
    private nonisolated func transcodeWithReaderWriter(_ asset: AVURLAsset) async throws -> URL {
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        
        // Video track
        let videoTracks = try await asset.load(.tracks).filter { $0.mediaType == .video }
        var videoInput: AVAssetWriterInput?
        var videoOutput: AVAssetReaderTrackOutput?
        
        if let vTrack = videoTracks.first {
            let naturalSize = try await vTrack.load(.naturalSize)
            let transform = try await vTrack.load(.preferredTransform)
            let estBitrate = max(1_000_000, Int(try await vTrack.load(.estimatedDataRate)))
            
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
            guard writer.canAdd(vInput) else {
                throw AppError.transcodeError("Cannot add video input")
            }
            writer.add(vInput)
            videoInput = vInput
            
            let vOutputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: vOutputSettings)
            guard reader.canAdd(vOut) else {
                throw AppError.transcodeError("Cannot add video output")
            }
            reader.add(vOut)
            videoOutput = vOut
        }
        
        // Audio track
        let audioTracks = try await asset.load(.tracks).filter { $0.mediaType == .audio }
        var audioInput: AVAssetWriterInput?
        var audioOutput: AVAssetReaderTrackOutput?
        
        if let aTrack = audioTracks.first {
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            aInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(aInput) else {
                throw AppError.transcodeError("Cannot add audio input")
            }
            writer.add(aInput)
            audioInput = aInput
            
            let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ])
            guard reader.canAdd(aOut) else {
                throw AppError.transcodeError("Cannot add audio output")
            }
            reader.add(aOut)
            audioOutput = aOut
        }
        
        // Start I/O
        writer.shouldOptimizeForNetworkUse = true
        guard writer.startWriting() else {
            throw writer.error ?? AppError.transcodeError("Cannot start writer")
        }
        guard reader.startReading() else {
            throw reader.error ?? AppError.transcodeError("Cannot start reader")
        }
        writer.startSession(atSourceTime: .zero)
        
        let group = DispatchGroup()
        
        // Video 処理
        if let vInput = videoInput, let vOutput = videoOutput {
            group.enter()
            vInput.requestMediaDataWhenReady(on: DispatchQueue(label: "transcode.video")) {
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
        
        // Audio 処理
        if let aInput = audioInput, let aOutput = audioOutput {
            group.enter()
            aInput.requestMediaDataWhenReady(on: DispatchQueue(label: "transcode.audio")) {
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
        
        // 両トラック完了を待機
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.notify(queue: .global()) {
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume()
                    } else {
                        let error = writer.error ?? AppError.transcodeError("Writer failed")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        // Reader のエラーチェック
        if reader.status == .failed {
            throw reader.error ?? AppError.transcodeError("Reader failed")
        }
        
        return outURL
    }
}
