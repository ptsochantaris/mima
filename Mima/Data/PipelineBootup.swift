import CoreML
import Foundation
import StableDiffusion
import SwiftUI

@globalActor
enum BootupActor {
    final actor ActorType {}
    static let shared = ActorType()
}

enum ModelVersion: String, Identifiable, CaseIterable {
    case sd14, sd15, sd20, sd21
        
    var zipName: String {
#if canImport(Cocoa)
        "\(rawValue).1.zip"
#else
        "\(rawValue).iOS.1.zip"
#endif
    }
    
    var displayName: String {
        switch self {
        case .sd14: return "Stable Diffusion 1.4"
        case .sd15: return "Stable Diffusion 1.5"
        case .sd20: return "Stable Diffusion 2.0"
        case .sd21: return "Stable Diffusion 2.1"
        }
    }
    
    var id: String {
        rawValue
    }
}

final class PipelineBootup: NSObject, URLSessionDownloadDelegate {
    private let modelVersion: ModelVersion
    private let temporaryZip: String
    private let storageDirectory: URL
    private let appDocumentsUrl: URL
    private let checkFile: URL
    private lazy var tempUrl = URL(fileURLWithPath: temporaryZip)

    static var persistedModelVersion: ModelVersion {
        get {
            if let value = UserDefaults.standard.string(forKey: "SelectedModelVersion"), let version = ModelVersion(rawValue: value) {
                return version
            }
            return .sd15
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "SelectedModelVersion")
        }
    }

    override init() {
        modelVersion = PipelineBootup.persistedModelVersion

        temporaryZip = NSTemporaryDirectory().appending(modelVersion.zipName)

        let docUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        appDocumentsUrl = docUrl
        
        let storeUrl = docUrl.appending(path: modelVersion.rawValue, directoryHint: .isDirectory)
        storageDirectory = storeUrl

        checkFile = storeUrl.appending(path: "ready.1", directoryHint: .notDirectory)
        
        super.init()
    }
    
    func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        NSLog("Download task created: \(task.taskIdentifier)")
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
                NSLog("Error setting up the model: \(error.localizedDescription)")
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
            NSLog("Error setting up the model: \(error.localizedDescription)")
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
            NSLog("Need to fetch model...")
            if FileManager.default.fileExists(atPath: temporaryZip) {
                try FileManager.default.removeItem(at: tempUrl)
            }

            do {
                await PipelineState.shared.setPhase(to: .setup(warmupPhase: .downloading(progress: 0)))
                NSLog("Requesting new model transfer...")
                let downloadUrl = URL(string: "https://bruvault.net/\(modelVersion.zipName)")!
                let task = urlSession.downloadTask(with: downloadUrl)
                task.resume()
            }
        }
    }

    @BootupActor
    private func modelDownloaded() async throws {
        NSLog("Downloaded model...")
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .expanding))
        NSLog("Decompressing model...")
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        try FileManager.default.unzipItem(at: tempUrl, to: appDocumentsUrl)

        NSLog("Cleaning up...")
        try FileManager.default.removeItem(at: tempUrl)
        FileManager.default.createFile(atPath: checkFile.path, contents: nil)
        try await modelReady()
    }

    @BootupActor
    private func modelReady() async throws {
        await PipelineState.shared.setPhase(to: .setup(warmupPhase: .initialising))
        NSLog("Constructing pipeline...")
        let config = MLModelConfiguration()
        #if canImport(Cocoa)
            config.computeUnits = .cpuAndGPU
            let pipeline = try StableDiffusionPipeline(resourcesAt: storageDirectory, configuration: config, disableSafety: true)
        #else
            config.computeUnits = .cpuAndNeuralEngine
            let pipeline = try StableDiffusionPipeline(resourcesAt: storageDirectory, configuration: config, disableSafety: true, reduceMemory: true)
        #endif
        NSLog("Warmup...")
        try pipeline.loadResources()
        NSLog("Pipeline ready")
        await PipelineState.shared.setPhase(to: .ready(pipeline))
        await Model.shared.startRenderingIfNeeded()
    }
}
