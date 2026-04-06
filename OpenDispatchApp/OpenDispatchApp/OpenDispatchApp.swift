import SwiftData
import SwiftUI

@main
struct OpenDispatchApp: App {
    let modelContainer: ModelContainer
    @State private var settings: SettingsStore
    @State private var compiler: SkillCompilationManager
    @State private var repositories: RepositoryManager
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

        let s = SettingsStore()
        let c = SkillCompilationManager(modelContainer: container, settings: s)
        let r = RepositoryManager(modelContainer: container, compiler: c)

        _settings = State(initialValue: s)
        _compiler = State(initialValue: c)
        _repositories = State(initialValue: r)
        _appState = StateObject(wrappedValue: AppState(
            modelContainer: container,
            compiler: c,
            settings: s,
            repositories: r
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(settings)
                .environment(compiler)
                .environment(repositories)
                .task {
                    await appState.bootstrap()
                }
        }
        .modelContainer(modelContainer)
    }
}
