import SwiftUI

@main
struct MyApp: App {
    @StateObject var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showLogin = true

    var body: some View {
        if authVM.isLoggedIn {
            HomeView()
                .environmentObject(authVM)
        } else {
            if showLogin {
                LoginView(showLogin: $showLogin)
                    .environmentObject(authVM)
            } else {
                RegisterView(showLogin: $showLogin)
                    .environmentObject(authVM)
            }
        }
    }
}
