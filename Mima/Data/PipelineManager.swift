import CoreML
import Foundation
import StableDiffusion
import SwiftUI
import ZIPFoundation

@globalActor
enum BootupActor {
    final actor ActorType {}
    static let shared = ActorType()
}

enum ModelVersion: String, Identifiable, CaseIterable {
    var currentRevision: String { "4" }

    case sd14, sd15, sd20, sd21, sdXL

    var zipName: String {
        #if canImport(AppKit)
            "\(rawValue).\(currentRevision).zip"
        #else
            "\(rawValue).iOS.\(currentRevision).zip"
        #endif
    }

    var imageSize: CGFloat {
        switch self {
        case .sd14, .sd15, .sd20, .sd21:
            512
        case .sdXL:
            1024
        }
    }

    var displayName: String {
        switch self {
        case .sd14: "Stable Diffusion 1.4"
        case .sd15: "Stable Diffusion 1.5"
        case .sd20: "Stable Diffusion 2.0"
        case .sd21: "Stable Diffusion 2.1"
        case .sdXL: "Stable Diffusion XL"
        }
    }

    static var allCases: [ModelVersion] {
        if #available(macOS 14, iOS 17, *) {
            [.sd14, .sd15, .sd20, .sd21, .sdXL]
        } else {
            [.sd14, .sd15, .sd20, .sd21]
        }
    }

    var id: String {
        rawValue
    }
}

final class PipelineManager: NSObject, URLSessionDownloadDelegate {
    private let modelVersion: ModelVersion
    private let temporaryZip: String
    private let storageDirectory: URL
    private let appDocumentsUrl: URL
    private let checkFile: URL
    private lazy var tempUrl = URL(fileURLWithPath: temporaryZip)

    static var persistedModelVersion: ModelVersion {
        get {
            if let value = UserDefaults.standard.string(forKey: "SelectedModelVersion"), let version = ModelVersion(rawValue: value), ModelVersion.allCases.contains(version) {
                return version
            }
            return .sd15
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "SelectedModelVersion")
        }
    }

    override init() {
        modelVersion = PipelineManager.persistedModelVersion

        temporaryZip = NSTemporaryDirectory().appending(modelVersion.zipName)

        let docUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        appDocumentsUrl = docUrl

        let storeUrl = docUrl.appending(path: modelVersion.rawValue, directoryHint: .isDirectory)
        storageDirectory = storeUrl

        checkFile = storeUrl.appending(path: "ready.\(modelVersion.currentRevision)", directoryHint: .notDirectory)

        super.init()
    }

    func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        log("Download task created: \(task.taskIdentifier)")
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        Task {
            await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloading(progress: progress)))
        }
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? FileManager.default.moveItem(at: location, to: tempUrl)
    }

    private func handleNetworkError(_ error: Error, in task: URLSessionTask) {
        log("Network error: \(error.localizedDescription)")
        Task {
            await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloadingError(error: error)))
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            handleNetworkError(error, in: task)
            return
        }

        if let response = task.response as? HTTPURLResponse, response.statusCode >= 400 {
            let error = NSError(domain: "build.bru.mima.network", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned code \(response.statusCode)"])
            handleNetworkError(error, in: task)
            return
        }

        Task {
            do {
                try await modelDownloaded()
            } catch {
                log("Error setting up the model: \(error.localizedDescription)")
                await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloadingError(error: error)))
            }
        }
    }

    @BootupActor
    func startup() async {
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .booting))

        let downloadTasks = await urlSession.tasks.2
        while downloadTasks.count > 1, let last = downloadTasks.last {
            last.cancel()
        }

        do {
            if FileManager.default.fileExists(atPath: checkFile.path) {
                log("Model ready...")
                downloadTasks.first?.cancel()
                try await modelReady()

            } else {
                log("Need to fetch model...")
                if FileManager.default.fileExists(atPath: temporaryZip) {
                    try FileManager.default.removeItem(at: tempUrl)
                }

                if let last = downloadTasks.last {
                    if let modelZip = last.response?.url?.lastPathComponent, Self.persistedModelVersion.zipName == modelZip {
                        log("Existing download for currently selected model detected, continuing")
                        return
                    } else {
                        log("Existing download task not recognized, will cancel")
                        last.cancel()
                    }
                }

                do {
                    await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloading(progress: 0)))
                    log("Requesting new model transfer...")
                    let downloadUrl = URL(string: "https://bruvault.net/\(modelVersion.zipName)")!
                    urlSession.downloadTask(with: downloadUrl).resume()
                }
            }
        } catch {
            log("Error setting up the model: \(error.localizedDescription)")
            await PipelineState.shared.setPhase(to: .setup(warmupPhase: .initialisingError(error: error)))
        }
    }

    @BootupActor
    private lazy var urlSession = URLSession(configuration: URLSessionConfiguration.background(withIdentifier: "build.bru.mima.background-download-session"), delegate: self, delegateQueue: nil)
    // Note: this needs extra handling for iOS, not yet implemented

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        log("Background URL session events complete")
    }

    @BootupActor
    private func modelDownloaded() async throws {
        log("Downloaded model...")
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .expanding))
        log("Decompressing model...")
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        try FileManager.default.unzipItem(at: tempUrl, to: appDocumentsUrl)

        log("Cleaning up...")
        try FileManager.default.removeItem(at: tempUrl)
        FileManager.default.createFile(atPath: checkFile.path, contents: nil)
        try await modelReady()
    }

    @BootupActor
    private func createPipeline(config: MLModelConfiguration, reduceMemory: Bool) async throws -> StableDiffusionPipelineProtocol {
        if #available(macOS 14.0, *), PipelineManager.persistedModelVersion == .sdXL {
            return try StableDiffusionXLPipeline(resourcesAt: storageDirectory, configuration: config, reduceMemory: reduceMemory)
        } else {
            let disableSafety = await !Model.shared.useSafetyChecker
            return try StableDiffusionPipeline(resourcesAt: storageDirectory, controlNet: [], configuration: config, disableSafety: disableSafety, reduceMemory: reduceMemory)
        }
    }

    

    @BootupActor
    private func modelReady() async throws {
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .initialising))
        log("Constructing pipeline...")
        let config = MLModelConfiguration()
        #if canImport(AppKit)
            config.computeUnits = .cpuAndGPU
            let pipeline = try await createPipeline(config: config, reduceMemory: false)
            log("Warmup...")
            try pipeline.loadResources()
        #else
            config.computeUnits = .cpuAndNeuralEngine
            let pipeline = try await createPipeline(config: config, reduceMemory: true)
        #endif
        log("Pipeline ready")
        await PipelineState.shared.setPhase(to: .ready(pipeline))
        await Model.shared.startRenderingIfNeeded()
    }
}
