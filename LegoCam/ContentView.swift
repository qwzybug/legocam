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
    static var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }

    @AppStorage("streamingAddress") var address: String = ""
    @State var frames: [Frame] = []

    @ObservedObject var streamer: MJPEGStreamer
    @ObservedObject var player = Player<Frame>()

    @State var exportURL: URL?

    @State var selectedFrameIndex: Int? = nil
    var selectedFrame: Frame? {
        if let idx = selectedFrameIndex, idx < frames.count {
            return frames[idx]
        } else {
            return nil
        }
    }

    @State private var showShareSheet = false

    var flash = FlashOverlay()

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
            .padding()

            ZStack {
                let image = selectedFrame?.image ?? player.currentFrame?.image ?? streamer.image
                if let image = image {
                    Image(image, scale: 1, label: Text("Image"))
                        .resizable()
                        .scaledToFit()
                        .overlay(flash)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(lineWidth: 2)
                                .foregroundColor(image == streamer.image ? .accentColor : .secondary)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .foregroundColor(.secondary)
                        .aspectRatio(4 / 3, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                selectedFrameIndex = nil
                if let image = streamer.image {
                    flash.bulb.flash(illuminationTime: 0.05)
                    withAnimation {
                        frames.append(Frame(image: image))
                    }
                }
            } label: {
                Image(systemName: "camera")
                    .imageScale(.large)
            }
            .frame(width: 48, height: 48)
            .buttonStyle(.borderless)
            .background(.red)
            .foregroundColor(.primary)
            .clipShape(Circle())
            .opacity(streamer.image != nil ? 1.0 : 0.5)
            .disabled(streamer.image == nil)
            .padding()

            HStack(spacing: 0) {
                ScrollView([.horizontal]) {
                    HStack {
                        ForEach(0 ..< frames.count, id: \.self) { idx in
                            let frame = frames[idx]
                            FrameButton(frame: frame, selectAction: {
                                player.stop()
                                selectedFrameIndex = (selectedFrameIndex == idx) ? nil : idx
                            }, deleteAction: {
                                frames.remove(at: idx)
                                selectedFrameIndex = frames.count < 1 ? nil : min(idx, frames.count - 1)
                            }, isSelected: .constant(idx == selectedFrameIndex))
                        }
                    }
                    .padding(.leading)
                    .frame(height: 64)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
        .alert(isPresented: .constant(streamer.error != nil), error: streamer.error, actions: {
            Button("OK") {
                streamer.stop()
            }
        })
        .toolbar {
            ToolbarItemGroup(placement: Self.toolbarPlacement) {
                // empty button, for centering
                Button { } label: { }

                Spacer()

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: player.currentFrame == nil ? "play.fill" : "stop.fill")
                        .imageScale(.large)
                }
                .disabled(frames.count < 1)

                Spacer()

                Button {
                    #if os(iOS)
                    Task {
                        self.exportURL = await exportVideo()
                    }
                    #else
                    if let url = showSavePanel() {
                        Task {
                            try await VideoWriter.write(sequence: frames.map(\.image), to: url)
                        }
                    }
                    #endif
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(frames.count < 1)
            }
        }
        #if os(iOS)
        .sheet(isPresented: .constant(exportURL != nil), onDismiss: {
            exportURL = nil
        }) {
            ShareSheet(activityItems: [exportURL!])
        }
        #endif
    }

    func exportVideo() async -> URL? {
        let outFname = String(format: "Lego movie - %@.mp4", Date().ISO8601Format(.init(timeSeparator: .omitted)))
        let outPath = NSTemporaryDirectory().appending(outFname)
        let outURL = URL(filePath: outPath)
        do {
            try await VideoWriter.write(sequence: frames.map(\.image), to: outURL)
            return outURL
        } catch {
            print("Error! \(error.localizedDescription)")
            return nil
        }
    }

    func togglePlayback() {
        if player.currentFrame != nil {
            player.stop()
        } else {
            selectedFrameIndex = nil
            player.play(frames: frames, framerate: 15)
        }
    }

    #if os(macOS)
    func showSavePanel() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.allowsOtherFileTypes = false
        savePanel.title = "Save your movie"
        savePanel.nameFieldLabel = "File name:"
        let response = savePanel.runModal()
        return response == .OK ? savePanel.url : nil
    }
    #endif
}

struct FrameButton: View {
    let frame: Frame
    let selectAction: () -> Void
    let deleteAction: () -> Void

    @Binding var isSelected: Bool

    var body: some View {
        ZStack {
            Button {
                selectAction()
            } label: {
                Image(frame.image, scale: 1, label: Text(frame.id.uuidString))
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(lineWidth: 6.0)
                            .foregroundColor(isSelected ? .accentColor : .clear)
                    }
            }
            .buttonStyle(.borderless)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if isSelected {
                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .padding(8)
                }
                .foregroundColor(.primary)
                .buttonStyle(.borderless)
                .frame(width: 64, height: 64)
                .position(x: 16, y: 16)
            }
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
                .previewDevice(PreviewDevice(rawValue: "iPhone 13 mini"))
//                .frame(width: 320, height: 480)
//
//            ContentView(frames: frames, streamer: streamer)
//                .frame(width: 1024, height: 768)
        }
    }
}
