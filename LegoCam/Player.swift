//
//  Player.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import Foundation

class Player<T>: ObservableObject {
    @Published var currentFrame: T? = nil

    private var timer: Timer?

    func play(frames: [T], framerate: Int = 30) {
        guard frames.count > 0 else { return }

        var idx = -1
        timer = Timer.scheduledTimer(withTimeInterval: (1.0 / Double(framerate)), repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            idx = (idx + 1) % frames.count
            self.currentFrame = frames[idx]
        })
    }

    func stop() {
        currentFrame = nil
        timer?.invalidate()
        timer = nil
    }
}
