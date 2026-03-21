//
//  no_laughing_matterApp.swift
//  no laughing matter
//
//  Created by Florian Lammert on 13.01.26.
//

import SwiftUI
import SwiftData

@main
struct no_laughing_matterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [HumorEvent.self, ProtocolMetadata.self])

        Settings {
            SettingsView()
        }
    }
}
