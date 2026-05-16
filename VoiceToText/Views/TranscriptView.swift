//
//  TranscriptView.swift
//  VoiceToText
//
//  Created by Menikdiwela, Lahiru 588 on 2026-05-11.
//

import AVFoundation
import Foundation
import Speech
import SwiftUI
import SwiftData
import FluidAudio

struct TranscriptView: View {
    @Binding var recording: Recording
    @Binding var isRecording: Bool
    @State var isGenerating = false

    @State var recorder: Recorder?
    @State var speechTranscriber: SpokenWordTranscriber

    @State var showingEnhancedView = false
    @State var enhancementError: String?

    @Environment(\.modelContext) private var modelContext
    
    init(recording: Binding<Recording>, isRecording: Binding<Bool>) {
        self._recording = recording
        self._isRecording = isRecording
        let transcriber = SpokenWordTranscriber(recording: recording)
        speechTranscriber = transcriber
        
        recorder = nil
        showingEnhancedView = recording.summary.wrappedValue != nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    if !recording.isDone {
                        liveRecordingView
                    } else if recording.summary != nil && showingEnhancedView {
                        enhancedView
                    } else {
                       playbackView
                   }
                }

                Spacer().frame(height: 100)
            }
                .padding(20)

                VStack {
                    Spacer()

                    bottomButtonBar
                }
                .ignoresSafeArea(.keyboard)
        }
        .navigationTitle(recording.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isRecording)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(recording.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 200)

                        if recording.isDone {
                            Text(recording.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        .onChange(of: isRecording) { oldValue, newValue in
            guard newValue != oldValue else { return }

            if newValue == true {
                if recording.isDone {
                    recording.isDone = false
                    speechTranscriber.reset()
                }
                Task {
                    do {
                        try await recorder?.record()
                    } catch {
                        await MainActor.run {
                            isRecording = false
                            enhancementError = "Recording failed: "
                        }
                    }
                }
            } else {
                Task {
                    do {
                        try await recorder?.stopRecording()
                        await generateTitleIfNeeded()
                        await generateAIEnhancements()
                    } catch {
                        await MainActor.run {
                            enhancementError =
                                "Error stopping recording: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        .onAppear {
            if recorder == nil {
                recorder = Recorder(
                    transcriber: speechTranscriber,
                    recording: $recording,
                    modelContext: modelContext
                )
            }

            if !recording.isDone && recording.text.characters.isEmpty {
                speechTranscriber.reset()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isRecording = true
                }
            }
        }
        .alert("Enhancement Error", isPresented: .constant(enhancementError != nil)) {
            Button("OK") {
                enhancementError = nil
            }
        } message: {
            if let error = enhancementError {
                Text(error)
            }
        }
    }

        @ViewBuilder
        private var bottomButtonBar: some View {
            HStack(spacing: 16) {
                if !recording.isDone {
                    recordButtonLarge
                } else {
                    // View toggle buttons
                    HStack(spacing: 12) {
                        if recording.summary != nil {
                            viewToggleButtonCompact
                        }
                    }
                    Spacer()
                    enhanceButtonCompact
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }

        @ViewBuilder
        private var recordButtonLarge: some View {
            Button {
                isRecording.toggle()
            } label: {
                HStack(spacing: 12) {
                    Label(
                        isRecording ? "Stop Recording" : "Start Recording",
                        systemImage: isRecording ? "stop.circle.fill" : "record.circle.fill"
                    )
                    .font(.headline)
                    .fontWeight(.semibold)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
            .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
        }

        @ViewBuilder
        private var viewToggleButtonCompact: some View {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    showingEnhancedView.toggle()
                }
            } label: {
                Label(
                    showingEnhancedView ? "Transcript" : "Summary",
                    systemImage: showingEnhancedView ? "doc.plaintext" : "sparkles"
                )
                .font(.body)
                .fontWeight(.medium)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(showingEnhancedView ? .gray : .green)
        }
        

        @ViewBuilder
        private var enhanceButtonCompact: some View {
            Button {
                handleAIEnhanceButtonTap()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        recording.summary != nil ? "Re-summarize" : "Summarize with AI",
                        systemImage: recording.summary != nil ? "arrow.clockwise" : "sparkles"
                    )
                    .font(.body)
                    .fontWeight(.medium)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(.green)
            .disabled(recording.text.characters.isEmpty || isGenerating)
        }

    @ViewBuilder
    private var enhancedView: some View {
        VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(.green)

                    Text("AI Summary")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if let summary = recording.summary, !String(summary.characters).isEmpty {
                    ScrollView {
                        Text(summary)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 16)
                    .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .foregroundStyle(.green)

                        VStack(spacing: 8) {
                            Text("Generating enhanced summary...")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("This may take a moment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var recordButton: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 8) {
                Label(
                    isRecording ? "Stop" : "Record",
                    systemImage: isRecording ? "stop.fill" : "record.circle"
                )
            }
        }
        .tint(isRecording ? .red : Color(red: 0.36, green: 0.69, blue: 0.55))
    }

    @ViewBuilder
    private var viewToggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                showingEnhancedView.toggle()
            }
        } label: {
            Label(
                showingEnhancedView ? "Transcript" : "Summary",
                systemImage: showingEnhancedView
                    ? "doc.plaintext.fill" : "sparkles.rectangle.stack.fill"
            )
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var enhanceButton: some View {
        Button {
            handleAIEnhanceButtonTap()
        } label: {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    recording.summary != nil ? "Re-enhance" : "Enhance",
                    systemImage: recording.summary != nil ? "arrow.clockwise" : "sparkles"
                )
            }
        }
        .buttonStyle(.glass)
        .tint(.green)
        .disabled(recording.text.characters.isEmpty || isGenerating)
    }

    @ViewBuilder
    var liveRecordingView: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if speechTranscriber.finalizedTranscript.utf8.isEmpty
                    && speechTranscriber.volatileTranscript.utf8.isEmpty
                {
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: isRecording)
                            
                            Text("Listening...")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("Start speaking into the microphone")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 32)
                        .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(
                            speechTranscriber.finalizedTranscript
                                + speechTranscriber.volatileTranscript
                        )
                        .font(.body)
                        .lineSpacing(4)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder
    var playbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(recording.textBrokenUpByParagraphs())
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

extension TranscriptView {

    func handleAIEnhanceButtonTap() {
        Task {
            await generateAIEnhancements()
        }
    }

    @MainActor
    private func generateAIEnhancements() async {
        isGenerating = true
        enhancementError = nil

        do {
            try await recording.generateAIEnhancements()
            withAnimation(.smooth(duration: 0.3)) {
                showingEnhancedView = true
            }
        } catch let error as FoundationModelsError {
            enhancementError = error.localizedDescription
        } catch {
            enhancementError = "Failed to generate AI enhancements: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    @MainActor
    private func generateTitleIfNeeded() async {
        guard !recording.text.characters.isEmpty,
            recording.title == "New Recording" || recording.title.isEmpty
        else {
            return
        }

        do {
            let suggestedTitle = try await recording.suggestedTitle() ?? recording.title
            recording.title = suggestedTitle
        } catch {
            print("Error generating title: \(error)")
        }
    }
}
