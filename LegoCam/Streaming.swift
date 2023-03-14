//
//  Streaming.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import CoreGraphics
import Foundation

class MJPEGStreamer: NSObject, ObservableObject, URLSessionDataDelegate {
    enum StreamError: LocalizedError, Equatable {
        case invalidResponse
        case invalidData
        case streamError(Int)
        case other(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Received an invalid response from the server."
            case .invalidData: return "Received invalid data from the server."
            case .streamError(let code): return "An HTTP error occurred (code \(code))."
            case .other(let description): return description
            }
        }
    }

    @MainActor
    enum State: Equatable {
        case idle
        case connecting(URLSessionDataTask)
        case streaming(URLSessionDataTask)
        case error(StreamError)
    }

    @Published var state = State.idle
    @Published var image: CGImage?
    @Published var latestResponseHeaders: [AnyHashable: Any]?

    var error: StreamError? {
        if case let .error(error) = state {
            return error
        }
        return nil
    }

    private let session = URLSession(configuration: .default)

    private var munger: JPEGMunger?

    func stop() {
        if case let .streaming(task) = state {
            task.cancel()
        }

        state = .idle
        image = nil
        munger = nil
    }

    func start(address: String) {
        guard case .idle = state else {
            NSLog("ERROR: Already started stream")
            return
        }

        guard let url = URL(string: address) else {
            state = .idle
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 5)
        let task = session.dataTask(with: request)
        task.delegate = self
        task.resume()

        state = .connecting(task)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        guard let response = response as? HTTPURLResponse else {
            NSLog("ERROR: Invalid response type: \(response)")
            stop()
            return .cancel
        }

        let currentState = await MainActor.run(resultType: State.self, body: { state })

        switch (currentState, response.statusCode) {
        case (.connecting, 200 ..< 299):
            await MainActor.run { state = .streaming(dataTask) }

        case (_, 400 ..< 599):
            NSLog("Error receiving stream: \(response.statusCode)")
            await MainActor.run { state = .error(.streamError(response.statusCode)) }
            return .cancel

        default: break
        }

        if let contentType = response.value(forHTTPHeaderField: "Content-Type"), contentType == "image/jpeg",
           let contentLength = Int(response.value(forHTTPHeaderField: "Content-Length") ?? "") {
            DispatchQueue.main.async {
                self.latestResponseHeaders = response.allHeaderFields
            }
            munger = JPEGMunger(bytes: contentLength)
        }

        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            if let newImage = try munger?.munge(data: data) {
                DispatchQueue.main.async {
                    guard case .streaming = self.state else { return }
                    self.image = newImage
                }
            }
        } catch {
            NSLog("Error munging data: \(error.localizedDescription)")
            munger = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if case .idle = self.state { return }

            if let error = error {
                NSLog("ERROR: \(error.localizedDescription)")
                self.state = .error(error as? StreamError ?? .other(error.localizedDescription))
            } else {
                self.state = .idle
            }
        }
    }
}


private struct JPEGMunger {
    let bytes: Int
    var data = Data()

    mutating func munge(data newData: Data) throws -> CGImage? {
        guard newData.count + data.count <= bytes else {
            throw MJPEGStreamer.StreamError.invalidData
        }

        data.append(newData)

        if data.count == bytes {
            guard let provider = CGDataProvider(data: data as CFData) else {
                throw MJPEGStreamer.StreamError.invalidData
            }

            return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }

        return nil
    }
}
