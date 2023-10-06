import CoreML
import Foundation
import StableDiffusion
import SwiftUI
import Zip

@globalActor
enum BootupActor {
    final actor ActorType {}
    static let shared = ActorType()
}

let appDocumentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

enum ModelVersion: String, Identifiable, CaseIterable {
    private var latestRevision: String {
        switch self {
        case .sd14: "3"
        case .sd15: "3"
        case .sd20: "3"
        case .sd21: "3"
        case .sdXL: "4"
        }
    }

    var zipName: String {
        #if canImport(AppKit)
            "\(rawValue).\(latestRevision).zip"
        #else
            "\(rawValue).iOS.\(latestRevision).zip"
        #endif
    }

    var root: URL {
        appDocumentsUrl.appending(path: rawValue, directoryHint: .isDirectory)
    }

    var tempZipLocation: URL {
        URL(fileURLWithPath: NSTemporaryDirectory().appending(zipName))
    }

    var readyFileLocation: URL {
        root.appending(path: "ready.\(latestRevision)", directoryHint: .notDirectory)
    }

    case sd14, sd15, sd20, sd21, sdXL

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

    private(set) static var userSelectedVersion: ModelVersion {
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

    init(selecting version: ModelVersion? = nil) {
        if let version {
            modelVersion = version
            Self.userSelectedVersion = version
        } else {
            modelVersion = Self.userSelectedVersion
        }
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
        try? FileManager.default.moveItem(at: location, to: modelVersion.tempZipLocation)
    }

    private func handleNetworkError(_ error: Error, in _: URLSessionTask) {
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
            if FileManager.default.fileExists(atPath: modelVersion.readyFileLocation.path) {
                log("Model ready...")
                downloadTasks.first?.cancel()
                try await modelReady()

            } else {
                log("Need to fetch model...")
                let fm = FileManager.default

                if fm.fileExists(atPath: modelVersion.tempZipLocation.path) {
                    try fm.removeItem(at: modelVersion.tempZipLocation)
                }

                if fm.fileExists(atPath: modelVersion.root.path) {
                    log("Clearing stale model data directory at \(modelVersion.root)")
                    try fm.removeItem(at: modelVersion.root)
                }

                if let last = downloadTasks.last {
                    if let modelZip = last.response?.url?.lastPathComponent, modelVersion.zipName == modelZip {
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

    func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        log("Background URL session events complete")
    }

    enum BootError: LocalizedError {
        case couldNotCompleteUnpack(ModelVersion)

        var errorDescription: String? {
            switch self {
            case let .couldNotCompleteUnpack(version):
                "Could not complete model setup, probably due to a permission issue - please remove \(version.root) and try again."
            }
        }
    }

    @BootupActor
    private func modelDownloaded() async throws {
        log("Downloaded model...")
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .expanding))

        await Task.yield()
        log("Decompressing model...")
        let fm = FileManager.default
        if fm.fileExists(atPath: modelVersion.root.path) {
            log("Clearing previous model data directory at \(modelVersion.root)")
            try fm.removeItem(at: modelVersion.root)
        }

        await Task.yield()
        log("Expanding model...")
        try Zip.unzipFile(modelVersion.tempZipLocation, destination: appDocumentsUrl, overwrite: true, password: nil)

        await Task.yield()
        log("Cleaning up...")
        try fm.removeItem(at: modelVersion.tempZipLocation)

        await Task.yield()
        log("Marking download as ready...")
        guard fm.createFile(atPath: modelVersion.readyFileLocation.path, contents: Data()) else {
            throw BootError.couldNotCompleteUnpack(modelVersion)
        }

        await Task.yield()
        log("Proceeding with startup...")
        try await modelReady()
    }

    @BootupActor
    private func createPipeline(config: MLModelConfiguration, reduceMemory: Bool) async throws -> StableDiffusionPipelineProtocol {
        var attempts = 3
        while true {
            do {
                if #available(macOS 14.0, *), modelVersion == .sdXL {
                    return try StableDiffusionXLPipeline(resourcesAt: modelVersion.root, configuration: config, reduceMemory: reduceMemory)
                } else {
                    let disableSafety = await !Model.shared.useSafetyChecker
                    return try StableDiffusionPipeline(resourcesAt: modelVersion.root, controlNet: [], configuration: config, disableSafety: disableSafety, reduceMemory: reduceMemory)
                }
            } catch {
                log("Error while initializing, will retry: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                attempts -= 1
                if attempts == 0 {
                    throw error
                }
            }
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
