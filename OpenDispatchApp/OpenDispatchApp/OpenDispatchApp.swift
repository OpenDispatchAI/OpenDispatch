import SwiftData
import SwiftUI

@main
struct OpenDispatchApp: App {
    let modelContainer: ModelContainer
    @StateObject private var appState: AppState

    init() {
        let schema = Schema([
            DispatchEventRecord.self,
            InstalledSkillRecord.self,
            RepositorySourceRecord.self,
            LocalLogRecord.self,
            UserExampleRecord.self,
            SuppressedExampleRecord.self,
        ])
        let configuration = ModelConfiguration("OpenDispatch")
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to build model container: \(error.localizedDescription)")
        }
        modelContainer = container
        _appState = StateObject(wrappedValue: AppState(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.bootstrap()
                }
        }
        .modelContainer(modelContainer)
    }
}
