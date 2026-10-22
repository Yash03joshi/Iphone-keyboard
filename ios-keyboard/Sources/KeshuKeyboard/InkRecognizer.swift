import Foundation
import MLKitCommon
import MLKitDigitalInkRecognition

/// Thin wrapper around ML Kit Digital Ink for Hindi (Devanagari). Mirrors the Android
/// `InkRecognizer`. The model lives in the keyboard extension's own container, so the
/// extension downloads it itself (needs "Allow Full Access" for network).
/// All completions are delivered on the main queue.
final class InkRecognizer {
    static let shared = InkRecognizer()

    enum Failure: LocalizedError {
        case unsupportedLanguage
        case downloadFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .unsupportedLanguage: "ML Kit has no Hindi handwriting model"
            case .downloadFailed(let error): error?.localizedDescription ?? "Download failed"
            }
        }
    }

    private static let languageTag = "hi"
    // ML Kit uses at most the last 20 characters of pre-context.
    private static let maxPreContext = 20

    private let model: DigitalInkRecognitionModel?
    private var recognizer: DigitalInkRecognizer?
    private var downloadObservers: [NSObjectProtocol] = []

    private init() {
        model = DigitalInkRecognitionModelIdentifier(forLanguageTag: Self.languageTag)
            .map { DigitalInkRecognitionModel(modelIdentifier: $0) }
    }

    var isModelDownloaded: Bool {
        guard let model else { return false }
        return ModelManager.modelManager().isModelDownloaded(model)
    }

    func downloadModel(completion: @escaping (Error?) -> Void) {
        guard let model else {
            completion(Failure.unsupportedLanguage)
            return
        }
        removeDownloadObservers()
        let center = NotificationCenter.default
        let modelKey = ModelDownloadUserInfoKey.remoteModel.rawValue
        let errorKey = ModelDownloadUserInfoKey.error.rawValue
        downloadObservers = [
            center.addObserver(forName: .mlkitModelDownloadDidSucceed, object: nil, queue: .main) { [weak self] note in
                guard note.userInfo?[modelKey] is DigitalInkRecognitionModel else { return }
                self?.removeDownloadObservers()
                completion(nil)
            },
            center.addObserver(forName: .mlkitModelDownloadDidFail, object: nil, queue: .main) { [weak self] note in
                guard note.userInfo?[modelKey] is DigitalInkRecognitionModel else { return }
                self?.removeDownloadObservers()
                completion(Failure.downloadFailed(note.userInfo?[errorKey] as? Error))
            },
        ]
        let conditions = ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: true)
        _ = ModelManager.modelManager().download(model, conditions: conditions)
    }

    /// Returns candidate texts, best first.
    func recognize(
        _ ink: Ink,
        preContext: String,
        writingArea: CGSize,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard !ink.strokes.isEmpty else {
            completion(.success([]))
            return
        }
        guard let model else {
            completion(.failure(Failure.unsupportedLanguage))
            return
        }
        let client = recognizer ?? DigitalInkRecognizer.digitalInkRecognizer(
            options: DigitalInkRecognizerOptions(model: model)
        )
        recognizer = client
        let context = DigitalInkRecognitionContext(
            preContext: String(preContext.suffix(Self.maxPreContext)),
            writingArea: WritingArea(width: Float(writingArea.width), height: Float(writingArea.height))
        )
        client.recognize(ink: ink, context: context) { result, error in
            DispatchQueue.main.async {
                if let result {
                    completion(.success(result.candidates.map(\.text)))
                } else {
                    completion(.failure(error ?? Failure.unsupportedLanguage))
                }
            }
        }
    }

    /// Frees the loaded model; keyboard extensions have a tight memory limit.
    func releaseRecognizer() {
        recognizer = nil
    }

    private func removeDownloadObservers() {
        downloadObservers.forEach { NotificationCenter.default.removeObserver($0) }
        downloadObservers = []
    }
}
