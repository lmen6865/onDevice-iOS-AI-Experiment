//
//  ContentView.swift
//  VoiceToText
//
//  Created by Menikdiwela, Lahiru 588 on 2026-05-11.
//

import Speech
import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State var currentRecording: Recording = Recording.blank()
    @State private var isRecording = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    ForEach(recordings) { recording in
                        NavigationLink {
                            TranscriptView(recording: $currentRecording, isRecording: $isRecording)
                                .onAppear { currentRecording = recording }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(recording.title))
                                    .font(.headline)
                                Text(recording.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !recording.text.characters.isEmpty {
                                    Text(
                                        String(recording.text.characters.prefix(50))
                                            + (recording.text.characters.count > 50 ? "..." : "")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteRecordings)
                }
                .navigationTitle("Memos")
                .toolbar {
                    EditButton()
                }

                if !isRecording {
                    VStack {
                        Spacer()

                        Button {
                            addRecording()
                        } label: {
                            Label("New", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.extraLarge)
                        .tint(Color(red: 0.36, green: 0.69, blue: 0.55))
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private func addRecording() {
        let newRecording = Recording.blank()
        modelContext.insert(newRecording)
        currentRecording = newRecording
    }

    private func deleteRecordings(offsets: IndexSet) {
        for index in offsets {
            deleteRecording(recordings[index])
        }
    }

    private func deleteRecording(_ recording: Recording) {
        modelContext.delete(recording)
    }
}
