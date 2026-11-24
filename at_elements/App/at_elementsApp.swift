//
//  at_elementsApp.swift
//  at_elements
//
//  Created by Evgeny on 9/12/26.
//

import Bugsnag
import SwiftUI

extension Notification.Name {
    static let presentToast = Notification.Name("presentToast")
}

enum ToastCenter {
    static func show(_ text: String) {
        NotificationCenter.default.post(name: .presentToast, object: text)
    }
}

@main
struct at_elementsApp: App {
    init() {
        Bugsnag.start(withApiKey: "dccd548d484444458d79bcaf1857e20f")
        Analytics.boot()
        AppSettings.boot()
        Records.boot()
        BootLog.say("App.init")
        StickmanFonts.boot()
        AssetsLibrarySheet.configureBonePaperImagePicker()
        #if DEBUG
        Self.seedUITestIfNeeded()
        #endif
    }

    #if DEBUG
    private static func seedUITestIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed") else { return }
        guard let src = Bundle.main.url(forResource: "demo_intro", withExtension: "ats", subdirectory: "demo")
            ?? Bundle.main.url(forResource: "demo_intro", withExtension: "ats")
        else { return }
        let dir = SceneSaver.savedDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = dir.appendingPathComponent("UITestSeed.ats")
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: src, to: dst)
        CopyPasteBuffer.shared.clear()
        // Keep the first-run tutorial out of the way of the test: it hides the
        // frame rail (EDIT FRAME et al.) until it is skipped or finished.
        UserDefaults.standard.set(true, forKey: "simple_tutorial")
        UserDefaults.standard.set(true, forKey: "intro_auto_launched")
    }
    #endif

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
            AssetTemplates.prepare()
            DemoSeeder.copyIfNeeded()
            CustomsSeeder.removeSeeded()
            _ = await Manifest.shared.awaitBootReload()
            _ = await Manifest.shared.requestReloadCustomPack()
            BootLog.say("ManifestBootView.task done")
            ready = true
            if let url = pendingURL {
                pendingURL = nil
                importIncoming(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentToast)) { note in
            guard let text = note.object as? String, !text.isEmpty else { return }
            showToast(text)
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
            showToast(await IncomingFile.importURL(url))
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
