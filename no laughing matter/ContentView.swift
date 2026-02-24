//
//  ContentView.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    ProtocolFetchView()
                } label: {
                    Label("1. Protocol Fetcher", systemImage: "arrow.down.doc")
                }

                NavigationLink {
                    HumorParsingView()
                } label: {
                    Label("2. Event Parser", systemImage: "text.magnifyingglass")
                }

                NavigationLink {
                    ClassificationView()
                } label: {
                    Label("3. LLM Classifier", systemImage: "brain")
                }

                NavigationLink {
                    VisualizerView()
                } label: {
                    Label("4. Visualizer", systemImage: "chart.bar.xaxis")
                }
            }
            .navigationTitle("Pipeline")
        } detail: {
            Text("Select a phase from the sidebar")
                .foregroundStyle(.secondary)
        }
    }
}

/// Test view for LLM classification (moved from original ContentView)
struct AnalysisTestView: View {
    @State private var input = ""
    @State private var result: LLMClassification?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Enter humor event description", text: $input)
                .textFieldStyle(.roundedBorder)

            Button("Analyze") {
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

            if let result {
                Text("Reasoning: \(result.reasoning)")
                Text("Intention: \(result.humorIntention)")
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
}

#Preview {
    ContentView()
}
