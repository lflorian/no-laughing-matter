//
//  AnalysisTestView.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import SwiftUI

/// Test view for LLM classification (moved from original ContentView)
struct AnalysisTestView: View {
    @State private var input = ""
    @State private var result: LLMClassification?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Enter humor event description", text: $input)
                .textFieldStyle(.roundedBorder)

            Button("Analyze", action: analyze)

            if let result {
                Text("Intention: \(result.primaryIntention)")
                Text("Confidence: \(result.confidenceRating)")
                    .font(.headline)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("Phase 3: LLM Classifier")
    }

    private func analyze() {
        Task {
            errorMessage = nil
            do {
                result = try await IntelligenceManager.shared.analyzeEvent(input)
            } catch {
                result = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AnalysisTestView()
}
