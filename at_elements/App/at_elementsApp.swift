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
        StickmanFonts.boot()
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
    @State private var pendingURL: URL?
    @State private var toast = ""

    var body: some View {
        let _ = BootLog.say("ManifestBootView.body ready=\(ready)")
        ZStack {
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
            }
        }
        .onOpenURL { url in
            if ready {
                importIncoming(url)
            } else {
                pendingURL = url
            }
        }
        .task {
            BootLog.say("ManifestBootView.task start")
            DemoSeeder.copyIfNeeded()
            CustomsSeeder.copyIfNeeded()
            _ = await Manifest.shared.awaitBootReload()
            _ = await Manifest.shared.requestReloadCustomPack()
            BootLog.say("ManifestBootView.task done")
            ready = true
            if let url = pendingURL {
                pendingURL = nil
                importIncoming(url)
            }
        }
        .overlay {
            if !toast.isEmpty {
                Text(toast)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private func importIncoming(_ url: URL) {
        Task { @MainActor in
            do {
                switch url.pathExtension.lowercased() {
                case CustomItems.ext:
                    try await IncomingItem.importURL(url)
                    showToast("Item copied")
                case SceneSaver.ext:
                    try IncomingScene.importURL(url)
                    showToast("Scene copied")
                default:
                    showToast("error")
                }
            } catch {
                showToast("error")
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text {
                toast = ""
            }
        }
    }
}
