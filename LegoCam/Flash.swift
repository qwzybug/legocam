//
//  Flash.swift
//  LegoCam
//
//  Created by devin chalmers on 3/8/23.
//

import SwiftUI

class Bulb: ObservableObject {
    @Published public var state = false

    public func flash(illuminationTime: Duration = .seconds(0.01)) {
        state = true
        Task {
            try await Task.sleep(for: illuminationTime)
            state = false
        }
    }
}

struct FlashOverlay: View {
    @ObservedObject var bulb = Bulb()

    var flashColor = Color.white
    var flashOpacity = 0.9
    var fadeSpeed = 0.5

    var body: some View {
        Rectangle()
            .foregroundColor(flashColor)
            .opacity(bulb.state ? flashOpacity : 0.0)
            .animation(.easeOut(duration: fadeSpeed), value: bulb.state)
            .transaction { transaction in
                transaction.disablesAnimations = bulb.state
            }
    }
}
