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
    var currentRevision: String { "3" }

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
    private static var modelDownloadResumeData: Data?

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

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        PipelineManager.modelDownloadResumeData = (error as? NSError)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        if let error {
            Task {
                await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloadingError(error: error)))
            }
            return
        }

        if let response = task.response as? HTTPURLResponse, response.statusCode >= 400 {
            Task {
                let error = NSError(domain: "build.bru.mima.network", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned code \(response.statusCode)"])
                await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloadingError(error: error)))
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
        }
    }

    @BootupActor
    func startup() async {
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .booting))
        do {
            try await boot()
        } catch {
            log("Error setting up the model: \(error.localizedDescription)")
            await PipelineState.shared.setPhase(to: .setup(warmupPhase: .initialisingError(error: error)))
        }
    }

    @BootupActor
    private lazy var urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)

    @BootupActor
    private func boot() async throws {
        if FileManager.default.fileExists(atPath: checkFile.path) {
            try await modelReady()
        } else {
            log("Need to fetch model...")
            if FileManager.default.fileExists(atPath: temporaryZip) {
                try FileManager.default.removeItem(at: tempUrl)
            }

            do {
                await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloading(progress: 0)))
                let task: URLSessionTask
                if let resumeData = PipelineManager.modelDownloadResumeData {
                    log("Attempting to resume model transfer...")
                    task = urlSession.downloadTask(withResumeData: resumeData)
                    PipelineManager.modelDownloadResumeData = nil
                } else {
                    log("Requesting new model transfer...")
                    let downloadUrl = URL(string: "https://bruvault.net/\(modelVersion.zipName)")!
                    task = urlSession.downloadTask(with: downloadUrl)
                }
                task.resume()
            }
        }
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