import SwiftUI

struct ApplicationRootView: View {
    let api: AuthenticationAPIProtocol
    @StateObject private var sessionController: ApplicationSessionController
    @StateObject private var upgradeController: LegacyUpgradeController
    @StateObject private var fontStore: AppFontStore
    @State private var hasRestoredSession = false
    @State private var showsBindingAuthentication = false

    init(
        api: AuthenticationAPIProtocol? = nil,
        sessionController: ApplicationSessionController? = nil,
        fontStore: AppFontStore? = nil,
        detector: LegacyDataDetecting? = nil,
        userDefaults: UserDefaults = .standard,
        currentVersion: String? = nil
    ) {
        let resolvedAPI = api ?? Self.makeAPI()
        let resolvedSessionController = sessionController ??
            ApplicationSessionController(api: resolvedAPI)
        let resolvedDetector = detector ?? LegacyDataDetector(userDefaults: userDefaults)
        let resolvedVersion = currentVersion ??
            (Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.0.0")

        self.api = resolvedAPI
        _sessionController = StateObject(wrappedValue: resolvedSessionController)
        _fontStore = StateObject(wrappedValue: fontStore ?? AppFontStore())
        _upgradeController = StateObject(
            wrappedValue: LegacyUpgradeController(
                detector: resolvedDetector,
                currentVersion: resolvedVersion,
                userDefaults: userDefaults
            )
        )
    }

    var body: some View {
        routeView
            .task {
                guard !hasRestoredSession else { return }
                hasRestoredSession = true
                await sessionController.restoreSession()
            }
            .onChange(of: sessionController.state.session != nil) { hasSession in
                guard hasSession, showsBindingAuthentication else { return }
                upgradeController.dismissNotice()
                showsBindingAuthentication = false
            }
            .sheet(isPresented: $showsBindingAuthentication) {
                NavigationStack {
                    AuthenticationFlowView(
                        api: api,
                        sessionController: sessionController
                    )
                }
            }
            .environment(\.appFontSelection, fontStore.selection)
    }

    @ViewBuilder
    private var routeView: some View {
        switch upgradeController.currentRoute(
            hasSession: sessionController.state.session != nil
        ) {
        case .authentication:
            AuthenticationFlowView(
                api: api,
                sessionController: sessionController
            )
        case .diary:
            diaryView
        case .legacyDiaryWithUpgradeNotice:
            diaryView
                .overlay(alignment: .bottom) {
                    UpgradeNoticeView(
                        later: upgradeController.dismissNotice,
                        bindAccount: { showsBindingAuthentication = true }
                    )
                }
        }
    }

    private var diaryView: some View {
        WebView(fontStore: fontStore)
            .ignoresSafeArea()
    }

    private static func makeAPI() -> AuthenticationAPI {
        let buildConfiguration: BuildConfiguration
        #if DEBUG
            buildConfiguration = .debug
        #else
            buildConfiguration = .release
        #endif

        let configuration: APIConfiguration
        if let current = try? APIConfiguration.current(),
           (try? current.validate(for: buildConfiguration)) != nil
        {
            configuration = current
        } else {
            configuration = APIConfiguration(
                baseURL: URL(string: "https://invalid.clovery.local")!
            )
        }
        return AuthenticationAPI(client: APIClient(configuration: configuration))
    }
}
