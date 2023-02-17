//
//  LegoCamApp.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import SwiftUI

@main
struct LegoCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(streamer: MJPEGStreamer())
        }
    }
}
