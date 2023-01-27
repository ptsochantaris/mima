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

@RenderActor
final class PipelineBootup: NSObject, URLSessionDownloadDelegate {
#if canImport(Cocoa)
    private static let temporaryZip = NSTemporaryDirectory().appending("sd15.zip")
#else
    private static let temporaryZip = NSTemporaryDirectory().appending("sd15iOS.zip")
#endif
    private static let appDocumentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private static let storageDirectory = appDocumentsUrl.appending(path: "sd15", directoryHint: .isDirectory)

    private let tempUrl = URL(fileURLWithPath: temporaryZip)
    private let checkFile = storageDirectory.appending(path: "ready", directoryHint: .notDirectory)

    private lazy var backgroundSession = URLSession(configuration: .background(withIdentifier: "build.bru.mima.urlSession"), delegate: self, delegateQueue: nil)

    nonisolated func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        NSLog("Download task created: \(task.taskIdentifier)")
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        Task { @PipelineActor in
            PipelineState.shared.phase = .setup(warmupPhase: .downloading(progress: progress))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? FileManager.default.moveItem(at: location, to: tempUrl)
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
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task { @PipelineActor in
                PipelineState.shared.phase = .setup(warmupPhase: .downloadingError(error: error))
            }
            return
        }
    }

    func startup() async throws {
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
                
                if await backgroundSession.tasks.2.first != nil {
                    NSLog("Continuing existing transfer...")
                } else {
                    NSLog("Requesting new model transfer...")
                    let downloadUrl = URL(string: "https://pub-51bef0e5d3e547d399bb6ca8d76a7d70.r2.dev/sd15.zip")!
                    let task = backgroundSession.downloadTask(with: downloadUrl)
                    task.resume()
                }
            }
        }
    }
    
    private func modelDownloaded() throws {
        NSLog("Downloaded model...")
        
        Task { @PipelineActor in
            PipelineState.shared.phase = .setup(warmupPhase: .expanding)
        }
        
        NSLog("Decompressing model...")
        let storageDirectory = PipelineBootup.appDocumentsUrl
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        try FileManager.default.unzipItem(at: tempUrl, to: PipelineBootup.appDocumentsUrl)
        
        NSLog("Cleaning up...")
        try FileManager.default.removeItem(at: tempUrl)
        FileManager.default.createFile(atPath: checkFile.path, contents: nil)
        try modelReady()
    }
    
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
        Task { @MainActor in
            Model.shared.startRenderingIfNeeded()
        }
    }
}
