//
//  Streaming.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import CoreGraphics
import Foundation

class MJPEGStreamer: NSObject, ObservableObject, URLSessionDelegate, URLSessionDataDelegate {
    enum State: Equatable {
        case idle
        case streaming(URLSession, URLSessionDataTask)
    }

    @Published var state = State.idle
    @Published var image: CGImage? = nil

    private var munger: JPEGMunger?

    func stop() {
        if case let .streaming(session, task) = state {
            task.cancel()
            session.finishTasksAndInvalidate()
        }

        image = nil
        state = .idle
    }

    func start(address: String) {
        if case let .streaming(session, task) = state {
            task.cancel()
            session.finishTasksAndInvalidate()
        }

        guard let url = URL(string: address) else {
            state = .idle
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 5)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.delegate = self
        task.resume()

        state = .streaming(session, task)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           contentType == "image/jpeg",
           let contentLength = Int(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "") {
            munger = JPEGMunger(bytes: contentLength)
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let newImage = try? munger?.munge(data: data) {
            DispatchQueue.main.async {
                self.image = newImage
            }
        }
    }
}


private struct JPEGMunger {
    enum MungeError: Error {
        case invalidData
    }

    let bytes: Int
    var data = Data()

    mutating func munge(data newData: Data) throws -> CGImage? {
        guard newData.count + data.count > bytes else {
            throw MungeError.invalidData
        }

        data.append(newData)

        if data.count == bytes {
            guard let provider = CGDataProvider(data: data as CFData) else {
                throw MungeError.invalidData
            }

            return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }

        return nil
    }
}
