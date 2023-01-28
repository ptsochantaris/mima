//
//  PipelineBootup.swift
//  Mima
//
//  Created by Paul Tsochantaris on 27/01/2023.
//

import Foundation
import CoreML
import StableDiffusion
import SwiftUI

@globalActor
enum BootupActor {
    final actor ActorType {}
    static let shared = ActorType()
}

final class PipelineBootup: NSObject, URLSessionDownloadDelegate {
#if canImport(Cocoa)
    private static let archiveName = "sd15.zip"
#else
    private static let archiveName = "sd15iOS.zip"
#endif
    private static let temporaryZip = NSTemporaryDirectory().appending(archiveName)
    private static let appDocumentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private static let storageDirectory = appDocumentsUrl.appending(path: "sd15", directoryHint: .isDirectory)

    private let tempUrl = URL(fileURLWithPath: temporaryZip)
    private let checkFile = storageDirectory.appending(path: "ready", directoryHint: .notDirectory)

    private lazy var backgroundSession = URLSession(configuration: .background(withIdentifier: "build.bru.mima.urlSession"), delegate: self, delegateQueue: nil)

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        NSLog("Download task created: \(task.taskIdentifier)")
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        Task { @PipelineActor in
            PipelineState.shared.phase = .setup(warmupPhase: .downloading(progress: progress))
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? FileManager.default.moveItem(at: location, to: tempUrl)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task { @PipelineActor in
                PipelineState.shared.phase = .setup(warmupPhase: .downloadingError(error: error))
            }
            return
        }
        if let response = task.response as? HTTPURLResponse, response.statusCode >= 400 {
            Task { @PipelineActor in
                let error = NSError(domain: "build.bru.mima.network", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server returned code \(response.statusCode)"])
                PipelineState.shared.phase = .setup(warmupPhase: .downloadingError(error: error))
            }
            return
        }
        Task {
            do {
                try await modelDownloaded()
            } catch {
                Task { @PipelineActor in
                    PipelineState.shared.phase = .setup(warmupPhase: .downloadingError(error: error))
                }
                NSLog("Error setting up the model: \(error.localizedDescription)")
            }
        }
    }
    
    @BootupActor
    func startup() async {
        Task { @PipelineActor in
            PipelineState.shared.phase = .setup(warmupPhase: .booting)
        }
        do {
            try await boot()
        } catch {
            Task { @PipelineActor in
                PipelineState.shared.phase = .setup(warmupPhase: .initialisingError(error: error))
            }
            NSLog("Error setting up the model: \(error.localizedDescription)")
        }
    }

    @BootupActor
    private func boot() async throws {
        if FileManager.default.fileExists(atPath: checkFile.path) {
            try modelReady()
        } else {
            NSLog("Need to fetch model...")
            if FileManager.default.fileExists(atPath: PipelineBootup.temporaryZip) {
                try FileManager.default.removeItem(at: tempUrl)
            }
            
            do {
                Task { @PipelineActor in
                    PipelineState.shared.phase = .setup(warmupPhase: .downloading(progress: 0))
                }
                
                if let existingTask = await backgroundSession.tasks.2.first {
                    NSLog("Continuing existing transfer (\(existingTask.taskIdentifier))...")
                } else {
                    NSLog("Requesting new model transfer...")
                    let downloadUrl = URL(string: "https://bruvault.net/\(PipelineBootup.archiveName)")!
                    let task = backgroundSession.downloadTask(with: downloadUrl)
                    task.resume()
                }
            }
        }
    }
    
    @BootupActor
    private func modelDownloaded() throws {
        NSLog("Downloaded model...")
        
        Task { @PipelineActor in
            PipelineState.shared.phase = .setup(warmupPhase: .expanding)
        }
        
        NSLog("Decompressing model...")
        let storageDirectory = PipelineBootup.storageDirectory
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        try FileManager.default.unzipItem(at: tempUrl, to: PipelineBootup.appDocumentsUrl)
        
        NSLog("Cleaning up...")
        try FileManager.default.removeItem(at: tempUrl)
        FileManager.default.createFile(atPath: checkFile.path, contents: nil)
        try modelReady()
    }
    
    @BootupActor
    private func modelReady() throws {
        
        Task { @PipelineActor in
            PipelineState.shared.phase = .setup(warmupPhase: .initialising)
        }
        
        NSLog("Constructing pipeline...")
        let config = MLModelConfiguration()
#if canImport(Cocoa)
        config.computeUnits = .all
        let pipeline = try StableDiffusionPipeline(resourcesAt: PipelineBootup.storageDirectory, configuration: config, disableSafety: true)
#else
        config.computeUnits = .cpuAndNeuralEngine
        let pipeline = try StableDiffusionPipeline(resourcesAt: PipelineBootup.storageDirectory, configuration: config, disableSafety: true, reduceMemory: true)
#endif
        NSLog("Warmup...")
        try pipeline.prewarmResources()
        NSLog("Pipeline ready")
        Task { @PipelineActor in
            withAnimation {
                PipelineState.shared.phase = .ready(pipeline)
            }
        }
        Task {
            await Model.shared.startRenderingIfNeeded()
        }
    }
}
