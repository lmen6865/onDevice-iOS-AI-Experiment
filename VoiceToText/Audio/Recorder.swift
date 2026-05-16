//
//  Recorder.swift
//  VoiceToText
//
//  Created by Menikdiwela, Lahiru 588 on 2026-05-11.
//

import AVFoundation
import Foundation
import SwiftUI
import SwiftData
import FluidAudio

class Recorder {
    private var outputContinuation: AsyncStream<AudioData>.Continuation?
    private let recordingEngine: AVAudioEngine

    private let transcriber: SpokenWordTranscriber
    private var audioFile: AVAudioFile?
    var playerNode: AVAudioPlayerNode?

    var recording: Binding<Recording>
    
    private let modelContext: ModelContext

    init(transcriber: SpokenWordTranscriber, recording: Binding<Recording>, modelContext: ModelContext) {
        self.recordingEngine = AVAudioEngine()
        self.transcriber = transcriber
        self.recording = recording
        self.modelContext = modelContext
    }

    func record() async throws {

        guard await isAuthorized() else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        do {
            try setUpAudioSession()
        } catch {
            throw error
        }

        do {
            try await transcriber.setUpTranscriber()
        } catch {
            throw error
        }

        do {
            let audioStreamSequence = try await audioStream()
            for await audioData in audioStreamSequence {
                // Process the buffer for transcription
                try await self.transcriber.streamAudioToTranscriber(audioData.buffer)
            }
        } catch {
            throw error
        }
    }

    func stopRecording() async throws {
        if recordingEngine.isRunning {
            recordingEngine.stop()
        }

        recordingEngine.inputNode.removeTap(onBus: 0)

        let recordingIsDoneBinding = recording.isDone
        await MainActor.run {
            recordingIsDoneBinding.wrappedValue = true
        }

        outputContinuation?.finish()
        outputContinuation = nil

        do {
            try await transcriber.finishTranscribing()
        } catch {
            throw error
        }
    }

    func pauseRecording() {
        recordingEngine.pause()
    }

    func resumeRecording() throws {
        try recordingEngine.start()
    }

    func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func audioStream() async throws -> AsyncStream<AudioData> {
        try setupRecordingEngine()

        recordingEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingEngine.inputNode.outputFormat(forBus: 0)
        ) { [weak self] (buffer, time) in
            guard let self else { return }
            // Wrap in AudioData to make it Sendable for Swift 6
            let audioData = AudioData(buffer: buffer, time: time)
            self.outputContinuation?.yield(audioData)
        }

        recordingEngine.prepare()
        try recordingEngine.start()
        print("Recording engine started successfully")

        return AsyncStream(AudioData.self, bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }
    }

    private func setupRecordingEngine() throws {
        if recordingEngine.isRunning {
            recordingEngine.stop()
        }

        recordingEngine.inputNode.removeTap(onBus: 0)
        recordingEngine.reset()
    }
}

extension Recorder {
    nonisolated func isAuthorized() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

public struct AudioData: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer
    var time: AVAudioTime
}
