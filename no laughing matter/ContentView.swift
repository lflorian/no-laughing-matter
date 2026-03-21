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

#Preview {
    ContentView()
}
