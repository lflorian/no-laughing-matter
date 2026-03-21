//
//  SettingsView.swift
//  no laughing matter
//

import SwiftUI

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var hasExistingKey = false
    @State private var statusMessage: String?
    @State private var isSuccess = false
    @State private var isValidating = false

    var body: some View {
        Form {
            Section("Claude API Key") {
                HStack {
                    SecureField("sk-ant-api03-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    if hasExistingKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 12) {
                    Button("Save") {
                        Task { await saveAndValidateKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty || isValidating)

                    if hasExistingKey {
                        Button("Delete", role: .destructive) {
                            deleteKey()
                        }
                        .buttonStyle(.bordered)
                    }

                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(isSuccess ? .green : .red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 200)
        .onAppear {
            hasExistingKey = APIKeyManager.load() != nil
        }
    }

    private func saveAndValidateKey() async {
        isValidating = true
        defer { isValidating = false }
        
        // First, save the key
        do {
            try APIKeyManager.save(apiKey)
            hasExistingKey = true
        } catch {
            statusMessage = "Failed to save: \(error.localizedDescription)"
            isSuccess = false
            return
        }
        
        // Then validate it
        do {
            let client = ClaudeAPIClient()
            let _ = try await client.classify(
                systemPrompt: "Respond with the classify_humor tool. This is a validation test.",
                userPrompt: "Test: A speaker makes a joke and the audience laughs."
            )
            statusMessage = "API key saved and validated successfully."
            isSuccess = true
            apiKey = ""
        } catch {
            statusMessage = "Validation failed: \(error.localizedDescription)"
            isSuccess = false
            // Delete the invalid key
            try? APIKeyManager.delete()
            hasExistingKey = false
        }
    }

    private func deleteKey() {
        do {
            try APIKeyManager.delete()
            hasExistingKey = false
            apiKey = ""
            statusMessage = "API key deleted."
            isSuccess = true
        } catch {
            statusMessage = error.localizedDescription
            isSuccess = false
        }
    }
}
