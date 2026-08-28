//
//  HaloApp.swift
//  Halo
//
//  Created by Karthik Vishnuvajjala on 27/08/26.
//

import SwiftUI

@main
struct HaloApp: App {
    /// True when this process is hosting unit tests. The tests exercise logic
    /// directly, so the app skips its real UI — starting the camera pipeline
    /// under the test runner is pointless and was crashing the host process.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Color.black
            } else {
                ContentView()
            }
        }
    }
}
