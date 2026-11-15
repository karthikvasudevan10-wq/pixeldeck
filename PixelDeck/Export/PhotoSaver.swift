import Foundation
import Photos

/// Saves exported images (animated GIFs stay animated) and videos to the photo library.
/// Uses add-only access: iOS asks once, and the app can never read the user's photos.
enum PhotoSaver {
    enum Failure: LocalizedError {
        case denied
        case failed(Error?)
        var errorDescription: String? {
            switch self {
            case .denied:
                String(localized: "Pixel Deck isn't allowed to add to your photo library. You can allow it in Settings, or use Share instead.")
            case .failed(let error):
                error?.localizedDescription ?? String(localized: "Couldn't save to your photo library.")
            }
        }
    }

    static func save(_ urls: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        let media = urls.filter { ["png", "gif", "mp4"].contains($0.pathExtension.lowercased()) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in media {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: url.pathExtension.lowercased() == "mp4" ? .video : .photo, fileURL: url, options: nil)
                }
            }
        } catch {
            throw Failure.failed(error)
        }
    }
}
