//
//  Recording.swift
//  VoiceToText
//
//  Created by Menikdiwela, Lahiru 588 on 2026-05-11.
//

import AVFoundation
import Foundation
import FoundationModels
import FluidAudio
import SwiftData
import SwiftUI

@Model
class Recording {
    typealias StartTime = CMTime

    var title: String
    var text: AttributedString
    var isDone: Bool
    var createdAt: Date

    var summary: AttributedString?


    init(
        title: String, text: AttributedString, url: URL? = nil, isDone: Bool = false
    ) {
        self.title = title
        self.text = text
        self.isDone = isDone
        self.createdAt = Date()
        self.summary = nil
    }

    func generateAIEnhancements() async throws {
        guard SystemLanguageModel.default.isAvailable else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "Foundation Models not available", code: -1))
        }

        let transcriptText = String(text.characters)
        guard !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoundationModelsError.generationFailed(
                NSError(domain: "No content to enhance", code: -2))
        }

        let titleResult = try? await generateEnhancedTitle(from: transcriptText)
        let summaryResult = try? await generateRichSummary(from: transcriptText)

        self.title = titleResult ?? "New Note"
        self.summary = summaryResult ?? "Something went wrong generating a summary."
    }

    private func generateEnhancedTitle(from text: String) async throws -> String {
        let session = await SLM.createSession(
            instructions: """
                You are an expert at creating clear, descriptive titles for voice memos and transcripts.
                Your task is to create a concise, informative title that captures the main topic or purpose.

                Guidelines:
                - Keep titles between 3-8 words
                - Use title case (capitalize major words)
                - Focus on the main topic or key insight
                - Avoid generic words like memo or recording
                - Be specific and descriptive
                - Do not wrap the title in quotes
                """)

        let prompt =
            "Create a clear, descriptive title for this voice memo transcript (do not include quotes in your response):\n\n\(text)"

        let title = try await SLM.generateText(
            session: session,
            prompt: prompt,
            options: SLM.temperatureOptions(0.3)
        )
        return title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: "\"", with: "")
    }

    private func generateRichSummary(from text: String) async throws -> AttributedString {
        let session = await SLM.createSession(
            instructions: """
                You are an expert at creating concise, informative summaries of voice memos and transcripts.
                Your summaries should capture the key points, main topics, and important details.

                Guidelines:
                - Create 2-4 well-structured paragraphs
                - Include key points and important details
                - Mark important concepts or key terms that should be highlighted
                - Output in markdown format
                """)

        let prompt = "Create a comprehensive summary of this voice memo transcript:\n\n\(text)"
        let summaryText = try await SLM.generateText(
            session: session,
            prompt: prompt,
            options: SLM.temperatureOptions(0.4)
        )
        return try AttributedString(markdown: summaryText)
    }
    
    func suggestedTitle() async throws -> String? {
            return try await generateEnhancedTitle(from: String(text.characters))
        }
}

extension Recording {
    static func blank() -> Recording{
        return .init(title: "New Recording", text: AttributedString(""))
    }
    
    func textBrokenUpByParagraphs() -> AttributedString {
            var final = AttributedString("")
            var working = AttributedString("")
            let copy = text
            copy.runs.forEach { run in
                if copy[run.range].characters.contains(".") {
                    working.append(copy[run.range])
                    final.append(working)
                    final.append(AttributedString("\n\n"))
                    working = AttributedString("")
                } else {
                    if working.characters.isEmpty {
                        let newText = copy[run.range].characters
                        let attributes = run.attributes
                        let trimmed = newText.trimmingPrefix(" ")
                        let newAttributed = AttributedString(trimmed, attributes: attributes)
                        working.append(newAttributed)
                    } else {
                        working.append(copy[run.range])
                    }
                }
            }

            if final.characters.isEmpty {
                return working
            }

            return final
    }
}
