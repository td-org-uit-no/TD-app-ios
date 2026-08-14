//
//  TD_appApp.swift
//  TD-app
//
//  Created by Katie Emblow on 13/08/2026.
//

import SwiftUI

@main
struct TD_appApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .task { await session.restore() }
        }
    }
}
