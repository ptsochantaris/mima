import Foundation

extension ListItem {
    enum State: Codable {
        case queued, rendering(step: Float, total: Float), done, cancelled, error, creating, cloning(needsFlash: Bool), blocked

        var shouldStayInRenderQueue: Bool {
            switch self {
            case .error:
                return false
            case .cancelled:
                return false
            case .cloning:
                return false
            case .creating:
                return false
            case .queued:
                return true
            case .rendering:
                return true
            case .done:
                return false
            case .blocked:
                return false
            }
        }

        var isWaiting: Bool {
            if case .queued = self {
                return true
            }
            return false
        }

        var isCreator: Bool {
            if case .creating = self {
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
        
        var isBlocked: Bool {
            if case .blocked = self {
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
            case creating
            case clonedCreator // to retire later
            case cloning
            case blocked
        }

        enum GalleryEntryDecoderError: Error {
            case decodingState
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
            if (try? values.decode(Bool.self, forKey: .creating)) != nil {
                self = .creating
                return
            }
            if (try? values.decode(Bool.self, forKey: .cloning)) != nil {
                self = .cloning(needsFlash: false)
                return
            }
            if (try? values.decode(Bool.self, forKey: .blocked)) != nil {
                self = .blocked
                return
            }
            if (try? values.decode(Bool.self, forKey: .clonedCreator)) != nil {
                self = .cloning(needsFlash: false)
                return
            }
            throw GalleryEntryDecoderError.decodingState
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .queued, .rendering:
                try container.encode(true, forKey: .queued)
            case .cancelled:
                try container.encode(true, forKey: .cancelled)
            case .error:
                try container.encode(true, forKey: .error)
            case .done:
                try container.encode(true, forKey: .ready)
            case .creating:
                try container.encode(true, forKey: .creating)
            case .cloning:
                try container.encode(true, forKey: .cloning)
            case .blocked:
                try container.encode(true, forKey: .blocked)
            }
        }
    }
}
