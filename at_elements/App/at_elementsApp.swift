//
//  at_elementsApp.swift
//  at_elements
//
//  Created by Evgeny on 9/12/26.
//

import SwiftUI

@main
struct at_elementsApp: App {
    init() {
        BootLog.say("App.init")
        Manifest.shared.startBootReload()
    }

    var body: some Scene {
        let _ = BootLog.say("App.body")
        WindowGroup {
            let _ = BootLog.say("WindowGroup.content")
            ManifestBootView()
        }
    }
}

private struct ManifestBootView: View {
    @State private var ready = false

    var body: some View {
        let _ = BootLog.say("ManifestBootView.body ready=\(ready)")
        if ready {
            ContentView()
                .onAppear { BootLog.say("ContentView.onAppear") }
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading packs…")
                }
                .foregroundStyle(.white)
            }
            .onAppear { BootLog.say("ManifestBootView.onAppear") }
            .task {
                BootLog.say("ManifestBootView.task start")
                DemoSeeder.copyIfNeeded()
                _ = await Manifest.shared.awaitBootReload()
                BootLog.say("ManifestBootView.task done")
                ready = true
            }
        }
    }
}
