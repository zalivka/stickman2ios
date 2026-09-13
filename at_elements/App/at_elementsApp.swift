//
//  at_elementsApp.swift
//  at_elements
//
//  Created by Evgeny on 9/12/26.
//

import SwiftUI

@main
struct at_elementsApp: App {
    var body: some Scene {
        WindowGroup {
            ManifestBootView()
        }
    }
}

private struct ManifestBootView: View {
    @State private var ready = false

    var body: some View {
        if ready {
            ContentView()
        } else {
            Color.black
                .task {
                    _ = await Manifest.shared.requestReload()
                    ready = true
                }
        }
    }
}
