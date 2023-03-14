//
//  LegoCamApp.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import SwiftUI

@main
struct LegoCamApp: App {
    let streamer = MJPEGStreamer()
    let model: LegoViewModel
    let bulb: Bulb

    init() {
        bulb = Bulb()
        model = LegoViewModel(streamer: streamer, bulb: bulb)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, streamer: streamer, bulb: bulb)
        }
    }
}
