import SwiftUI

struct ContentView: View {
    init() {
        // SwiftUI can't fully style the tab bar yet, so drive it through the
        // UIKit appearance proxy. It uses the same background as the page so
        // the bar doesn't read as a differently-coloured band.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(TD.background)
        appearance.shadowColor = UIColor(TD.inputBorder)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            EventsView()
                .tabItem { Label("Arrangementer", systemImage: "calendar") }

            JobsView()
                .tabItem { Label("Stillinger", systemImage: "briefcase") }

            TDBytesView()
                .tabItem { Label("TD Bytes", systemImage: "cart") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .tint(TD.red)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
}
