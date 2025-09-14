//
//  DataFolderStore.swift
//  no laughing matter
//
//  Created by Florian Lammert on 14.09.25.
//

import SwiftUI
import AppKit

final class DataFolderStore: ObservableObject {
    @AppStorage("dataBookmark") private var dataBookmark: Data?
    @Published var folderURL: URL?

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true
        p.allowsMultipleSelection = false; p.prompt = "Choose"
        if p.runModal() == .OK, let url = p.url {
            _ = url.startAccessingSecurityScopedResource()
            if let bm = try? url.bookmarkData(options: [.withSecurityScope],
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil) {
                dataBookmark = bm; folderURL = url
            }
        }
    }

    func restoreFolderIfPossible() {
        guard let bm = dataBookmark else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bm, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            folderURL = url
        }
    }
}
