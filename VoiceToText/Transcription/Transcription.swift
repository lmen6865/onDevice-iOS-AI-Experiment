//
//  Transcription.swift
//  VoiceToText
//
//  Created by Menikdiwela, Lahiru 588 on 2026-05-11.
//

import Foundation
import Speech
import SwiftUI

@Observable
@MainActor
final class SpokenWordTranscriber {
    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), any Error>?

    // The format of the audio.
    var analyzerFormat: AVAudioFormat?

    let converter = BufferConverter()

    let recording: Binding<Recording>

    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""

    static let locale =  Locale(identifier: "en-US")

    init(recording: Binding<Recording>) {
        self.recording = recording
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation
    }

    func setUpTranscriber() async throws {
        transcriber = SpeechTranscriber(
            locale: SpokenWordTranscriber.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            throw TranscriptionError.failedToSetupRecognitionStream
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        do {
            try await ensureModel(transcriber: transcriber, locale: SpokenWordTranscriber.locale)
        } catch let error as TranscriptionError {
            throw error
        }

        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [
            transcriber
        ])

        guard analyzerFormat != nil else {
            throw TranscriptionError.invalidAudioDataType
        }

        recognizerTask = Task {
            print("Starting recognition task...")
            do {
                var resultCount = 0
                for try await case let result in transcriber.results {
                    resultCount += 1
                    let text = result.text
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                        updateRecordingWithNewText(withFinal: text)
                    } else {
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.5)
                    }
                }
            } catch {
                print(
                    "Speech recognition failed: \(error.localizedDescription)"
                )
            }
        }

        do {
            try await analyzer?.start(inputSequence: inputSequence)
        } catch {
            print(
                "Failed to start SpeechAnalyzer: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func updateRecordingWithNewText(withFinal str: AttributedString) {
        recording.text.wrappedValue.append(str)
    }

    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let analyzerFormat else {
            throw TranscriptionError.invalidAudioDataType
        }

        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)

        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    public func finishTranscribing() async throws {
        inputBuilder.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
    }

    public func reset() {
        volatileTranscript = ""
        finalizedTranscript = ""
    }
}

extension SpokenWordTranscriber {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        try await downloadIfNeeded(for: transcriber)
        try await reserveLocale(locale: locale)
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module])
        {
            try await downloader.downloadAndInstall()
        } else {
            print("No download needed")
        }
    }

    func reserveLocale(locale: Locale) async throws {
        let allocated = await AssetInventory.reservedLocales
        if allocated.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            return
        }
        try await AssetInventory.reserve(locale: locale)
    }

    func release() async {
        let allocated = await AssetInventory.reservedLocales
        for locale in allocated {
            await AssetInventory.release(reservedLocale: locale)
        }
    }
}

public enum TranscriptionError: Error {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound

    var descriptionString: String {
        switch self {

        case .couldNotDownloadModel:
            return "Could not download the model."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format."
        case .localeNotSupported:
            return "This locale is not yet supported by SpeechAnalyzer."
        case .noInternetForModelDownload:
            return
                "The model could not be downloaded because the user is not connected to internet."
        case .audioFilePathNotFound:
            return "Couldn't write audio to file."
        }
    }
}
