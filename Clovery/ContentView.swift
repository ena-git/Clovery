import SwiftUI

struct ContentView: View {
    var body: some View {
#if DEBUG
        if let fixture = IOSVerificationFixture.resolve() {
            IOSVerificationFixtureView(fixture: fixture)
        } else {
            ApplicationRootView()
        }
#else
        ApplicationRootView()
#endif
    }
}
