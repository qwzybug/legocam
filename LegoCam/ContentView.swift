//
//  ContentView.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import CoreGraphics
import SwiftUI

struct Frame: Identifiable {
    let id = UUID()
    let image: CGImage
}

struct ContentView: View {
    @AppStorage("streamingAddress") var address: String = ""
    @State var frames: [Frame] = []

    @ObservedObject var streamer: MJPEGStreamer
    @ObservedObject var player = Player<Frame>()

    @State var selectedFrameIndex: Int? = nil
    var selectedFrame: Frame? {
        if let idx = selectedFrameIndex, idx < frames.count {
            return frames[idx]
        } else {
            return nil
        }
    }

    var body: some View {
        VStack {
            HStack {
                TextField("URL", text: $address)
                    .disabled(streamer.state != .idle)
                    .disableAutocorrection(true)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif

                switch streamer.state {
                case .idle, .error:
                    Button("Connect") {
                        streamer.start(address: address)
                    }

                case .connecting:
                    Button("Connecting...", action: {}).disabled(true)

                case .streaming:
                    Button("Stop") {
                        streamer.stop()
                    }
                }
            }

            ZStack {
                let image = selectedFrame?.image ?? player.currentFrame?.image ?? streamer.image
                if let image = image {
                    Image(image, scale: 1, label: Text("Image"))
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(lineWidth: 2)
                                .foregroundColor(image == streamer.image ? .accentColor : .secondary)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .foregroundColor(.secondary)
                        .aspectRatio(1.5, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                if selectedFrameIndex != nil {
                    selectedFrameIndex = nil
                } else if let image = streamer.image {
                    frames.append(Frame(image: image))
                }
            } label: {
                Image(systemName: "camera")
            }
            .frame(width: 48, height: 48)
            .buttonStyle(.borderless)
            .background(.red)
            .foregroundColor(.primary)
            .clipShape(Circle())
            .opacity(streamer.image != nil ? 1.0 : 0.5)
            .disabled(streamer.image == nil)

            HStack(spacing: 0) {
                ScrollView([.horizontal]) {
                    HStack {
                        ForEach(0 ..< frames.count, id: \.self) { idx in
                            let frame = frames[idx]
                            Button {
                                player.stop()
                                selectedFrameIndex = (selectedFrameIndex == idx) ? nil : idx
                            } label: {
                                Image(frame.image, scale: 1, label: Text(frame.id.uuidString))
                                    .resizable()
                                    .scaledToFill()
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(lineWidth: 6.0)
                                            .foregroundColor(idx == selectedFrameIndex ? .accentColor : .clear)
                                    }
                            }
                            .buttonStyle(.borderless)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .frame(height: 64)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if frames.count > 1 {
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: player.currentFrame == nil ? "play.fill" : "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: 32, maxHeight: 64)
                }
            }
        }
        .padding()
        .alert(isPresented: .constant(streamer.error != nil), error: streamer.error, actions: {
            Button("OK") {
                streamer.stop()
            }
        })
    }

    func togglePlayback() {
        if player.currentFrame != nil {
            player.stop()
        } else {
            selectedFrameIndex = nil
            player.play(frames: frames)
        }
    }
}

extension CGImage {
    static func withDataAsset(named name: String) -> CGImage? {
        guard let jpegData = NSDataAsset(name: name),
              let provider = CGDataProvider(data: jpegData.data as CFData),
              let cgImage = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        return cgImage
    }
}

class MockStreamer: MJPEGStreamer {
    init(mockImageDataNamed name: String) {
        super.init()
        image = CGImage.withDataAsset(named: name)
    }
    override func start(address: String) { }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let streamer = MockStreamer(mockImageDataNamed: "JPEGData")
        let image = CGImage.withDataAsset(named: "JPEGData")!
        let frame = Frame(image: image)
        let frames = Array(repeating: frame, count: 10)
        Group {
            ContentView(frames: frames, streamer: streamer, selectedFrameIndex: 1)
//                .frame(width: 320, height: 480)
//
//            ContentView(frames: frames, streamer: streamer)
//                .frame(width: 1024, height: 768)
        }
    }
}
