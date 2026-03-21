//
//  VisualizerView.swift
//  no laughing matter
//
//  Created by Claude on 24.02.26.
//

import SwiftUI
import SwiftData

// MARK: - Tab Enum

enum VisualizerTab: CaseIterable {
    case whoLaughs, whoTriggers, crossParty, humorTypes, intentions, trends, gender, age, govOpp

    var title: String {
        switch self {
        case .whoLaughs: "Who Laughs"
        case .whoTriggers: "Who Triggers"
        case .crossParty: "Cross-Party"
        case .humorTypes: "Humor Types"
        case .intentions: "Intentions"
        case .trends: "Trends"
        case .gender: "Gender"
        case .age: "Age"
        case .govOpp: "Gov. vs. Opp."
        }
    }
}

// MARK: - Main View

struct VisualizerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = VisualizationViewModel()
    @State private var selectedTab: VisualizerTab = .whoLaughs

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phase 4: Visualizer")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitleText)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading events…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.events.isEmpty {
                emptyStateView
            } else {
                Picker("", selection: $selectedTab) {
                    ForEach(VisualizerTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    Group {
                        switch selectedTab {
                        case .whoLaughs: WhoLaughsTab(vm: viewModel)
                        case .whoTriggers: WhoTriggersTab(vm: viewModel)
                        case .crossParty: CrossPartyTab(vm: viewModel)
                        case .humorTypes: HumorTypesTab(vm: viewModel)
                        case .intentions: IntentionsTab(vm: viewModel)
                        case .trends: TrendsTab(vm: viewModel)
                        case .gender: GenderTab(vm: viewModel)
                        case .age: AgeTab(vm: viewModel)
                        case .govOpp: GovOppTab(vm: viewModel)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 720, minHeight: 600)
        .navigationTitle("Visualizer")
        .onAppear { viewModel.load(context: modelContext) }
        .toolbar {
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    viewModel.load(context: modelContext)
                }
            }
        }
    }

    private var subtitleText: String {
        if viewModel.events.isEmpty {
            return "No data loaded yet"
        }
        return "\(viewModel.events.count) humor events"
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No data to visualize")
                .font(.title3)
                .fontWeight(.medium)
            Text("Run Phases 1–3 to fetch protocols, extract humor events, and classify them.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Reload") { viewModel.load(context: modelContext) }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    VisualizerView()
}
