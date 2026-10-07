import SwiftUI

@main
struct DiskCleanerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Disk Cleaner") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1020, minHeight: 640)
        }
        .commands {
            CommandMenu("Disco") {
                Button("Analizar") { model.startScan() }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
                Button("Carpeta superior") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
            }
        }
    }
}
