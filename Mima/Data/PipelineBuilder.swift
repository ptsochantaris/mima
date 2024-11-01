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
        case .sd3m, .sd14, .sd15, .sd20, .sd21, .sdXL: "5"
        }
    }

    #if canImport(AppKit)
        var zipName: String {
            "\(rawValue).\(latestRevision).zip"
        }
    #else
        var zipName: String {
            "\(rawValue).iOS.\(latestRevision).zip"
        }
    #endif

    var root: URL {
        appDocumentsUrl.appending(path: rawValue, directoryHint: .isDirectory)
    }

    var tempZipLocation: URL {
        URL(fileURLWithPath: NSTemporaryDirectory().appending(zipName))
    }

    var readyFileLocation: URL {
        root.appending(path: "ready.\(latestRevision)", directoryHint: .notDirectory)
    }

    case sd14, sd15, sd20, sd21, sdXL, sd3m

    var imageSize: CGFloat {
        switch self {
        case .sd14, .sd15, .sd20, .sd21:
            512
        case .sd3m, .sdXL:
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
        case .sd3m: "Stable Diffusion 3.0"
        }
    }

    static var allCases: [ModelVersion] {
        [.sd14, .sd15, .sd20, .sd21, .sdXL, .sd3m]
    }

    var id: String {
        rawValue
    }
}

@MainActor
final class PipelineBuilder: NSObject, URLSessionDownloadDelegate {
    private let modelLocation: URL
    private let zipLocation: URL
    private let zipName: String
    private let displayName: String
    private let readyFileLocation: URL
    private let useVersion: ModelVersion

    static var current: PipelineBuilder?

    init(selecting version: ModelVersion? = nil) {
        if let version {
            UserDefaults.standard.set(version.rawValue, forKey: "SelectedModelVersion")
            useVersion = version
            log("Switching over to \(useVersion.displayName)")
        } else {
            useVersion = Self.userSelectedVersion
            log("Already selected \(useVersion.displayName)")
        }

        displayName = useVersion.displayName
        modelLocation = useVersion.root
        zipName = useVersion.zipName
        zipLocation = useVersion.tempZipLocation
        readyFileLocation = useVersion.readyFileLocation
        super.init()

        Task {
            await startup()
        }
    }

    deinit {
        log("Completed setup for \(displayName)")
    }

    static var userSelectedVersion: ModelVersion {
        if let value = UserDefaults.standard.string(forKey: "SelectedModelVersion"), let version = ModelVersion(rawValue: value), ModelVersion.allCases.contains(version) {
            return version
        }
        return .sd15
    }

    nonisolated func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        log("Download task created: \(task.taskIdentifier)")
    }

    nonisolated func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        Task {
            await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloading(progress: progress)))
        }
    }

    nonisolated func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? FileManager.default.moveItem(at: location, to: zipLocation)
    }

    private func handleNetworkError(_ error: Error, in task: URLSessionTask) async {
        log("Network error on \(task.originalRequest?.url?.absoluteString ?? "<no url>"): \(error.localizedDescription)")
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloadingError(error: error)))
        await builderDone()
    }

    nonisolated func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task {
                await handleNetworkError(error, in: task)
            }
            return
        }

        if let response = task.response as? HTTPURLResponse, response.statusCode >= 400 {
            let error = NSError(domain: "build.bru.mima.network", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned code \(response.statusCode)"])
            Task {
                await handleNetworkError(error, in: task)
            }
            return
        }

        Task {
            do {
                try await modelDownloaded()
            } catch {
                log("Error setting up the model: \(error.localizedDescription)")
                await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloadingError(error: error)))
            }
            await builderDone()
        }
    }

    @BootupActor
    private func startup() async {
        log("Building pipeline assets for \(displayName)")

        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .booting))

        let downloadTasks = await urlSession.tasks.2
        while downloadTasks.count > 1, let last = downloadTasks.last {
            last.cancel()
        }

        do {
            if FileManager.default.fileExists(atPath: readyFileLocation.path) {
                log("Model ready...")
                downloadTasks.first?.cancel()
                try await modelReady()
                builderDone()
                return
            }

            log("Need to fetch model...")
            let fm = FileManager.default

            if fm.fileExists(atPath: zipLocation.path) {
                try fm.removeItem(at: zipLocation)
            }

            if fm.fileExists(atPath: modelLocation.path) {
                log("Clearing stale model data directory at \(modelLocation.path)")
                try fm.removeItem(at: modelLocation)
            }

            if let last = downloadTasks.last {
                if let modelZip = last.response?.url?.lastPathComponent, zipName == modelZip {
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
                let downloadUrl = URL(string: "https://bruvault.net/\(zipName)")!
                urlSession.downloadTask(with: downloadUrl).resume()
            }
        } catch {
            log("Error setting up the model: \(error.localizedDescription)")
            await PipelineState.shared.setPhase(to: .setup(warmupPhase: .initialisingError(error: error)))
            builderDone()
        }
    }

    @BootupActor
    private lazy var urlSession = URLSession(configuration: URLSessionConfiguration.background(withIdentifier: "build.bru.mima.background-download-session"), delegate: self, delegateQueue: nil)
    // Note: this needs extra handling for iOS, not yet implemented

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        log("Background URL session events complete")
    }

    enum BootError: LocalizedError {
        case couldNotCompleteUnpack(URL)

        var errorDescription: String? {
            switch self {
            case let .couldNotCompleteUnpack(version):
                "Could not complete model setup, probably due to a permission issue - please remove \(version.path) and try again."
            }
        }
    }

    @BootupActor
    private func modelDownloaded() async throws {
        log("Downloaded model to \(zipLocation.path)...")
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .expanding))

        log("Decompressing model...")
        let fm = FileManager.default
        if fm.fileExists(atPath: modelLocation.path) {
            log("Clearing previous model data directory at \(modelLocation.path)")
            try fm.removeItem(at: modelLocation)
        }

        log("Expanding model...")
        try Zip.unzipFile(zipLocation, destination: appDocumentsUrl, overwrite: true, password: nil)

        log("Cleaning up...")
        try fm.removeItem(at: zipLocation)

        log("Marking download as ready...")

        guard fm.createFile(atPath: readyFileLocation.path, contents: Data()) else {
            throw BootError.couldNotCompleteUnpack(modelLocation)
        }

        log("Proceeding with startup...")
        try await modelReady()
    }

    @BootupActor
    private func createPipeline(config: MLModelConfiguration, reduceMemory: Bool) async throws -> StableDiffusionPipelineProtocol {
        switch useVersion {
        case .sd14, .sd15, .sd20, .sd21:
            let disableSafety = await !Model.shared.useSafetyChecker
            return try StableDiffusionPipeline(resourcesAt: modelLocation, controlNet: [], configuration: config, disableSafety: disableSafety, reduceMemory: reduceMemory)
        case .sdXL:
            return try StableDiffusionXLPipeline(resourcesAt: modelLocation, configuration: config, reduceMemory: reduceMemory)
        case .sd3m:
            return try StableDiffusion3Pipeline(resourcesAt: modelLocation, configuration: config, reduceMemory: reduceMemory)
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
        #else
            config.computeUnits = .cpuAndNeuralEngine
            let pipeline = try await createPipeline(config: config, reduceMemory: true)
        #endif
        log("Warmup...")
        try pipeline.loadResources()
        log("Pipeline ready")
        await PipelineState.shared.setPhase(to: .ready(pipeline))
        await Model.shared.startRenderingIfNeeded()
    }

    @BootupActor
    private func builderDone() {
        log("Cleaning up pipeline builder...")
        urlSession.invalidateAndCancel()
        Task { @MainActor in
            Self.current = nil
        }
    }
}
