import Foundation

extension GalleryEntry {
    enum State: Codable {
        case queued, warmup, rendering(step: Float, total: Float), done, cancelled, error

        var isWaiting: Bool {
            if case .queued = self {
                return true
            }
            return isWarmup
        }

        var isWarmup: Bool {
            if case .warmup = self {
                return true
            }
            return false
        }

        var isRendering: Bool {
            if case .rendering = self {
                return true
            }
            return false
        }

        var isDone: Bool {
            if case .done = self {
                return true
            }
            return false
        }

        var isCancelled: Bool {
            if case .cancelled = self {
                return true
            }
            return false
        }

        enum CodingKeys: CodingKey {
            case queued
            case rendering
            case ready
            case cancelled
            case error
        }

        enum GalleryEntryDecoderError: Error {
            case decoding
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if (try? values.decode(Bool.self, forKey: .queued)) != nil {
                self = .queued
                return
            }
            if (try? values.decode(Bool.self, forKey: .cancelled)) != nil {
                self = .cancelled
                return
            }
            if (try? values.decode(Bool.self, forKey: .error)) != nil {
                self = .error
                return
            }
            if (try? values.decode(Bool.self, forKey: .ready)) != nil {
                self = .done
                return
            }
            throw GalleryEntryDecoderError.decoding
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .queued, .rendering, .warmup:
                try container.encode(true, forKey: .queued)
            case .cancelled:
                try container.encode(true, forKey: .cancelled)
            case .error:
                try container.encode(true, forKey: .error)
            case .done:
                try container.encode(true, forKey: .ready)
            }
        }
    }
}
