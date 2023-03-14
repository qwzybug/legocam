//
//  ContentView.swift
//  LegoCam
//
//  Created by devin chalmers on 2/15/23.
//

import Combine
import CoreGraphics
import SwiftUI

struct Frame: Identifiable {
    let id = UUID()
    let image: CGImage
}

class LegoStreamButton: ObservableObject {
    var action: ((Bool) -> Void)?

    private var streamer: MJPEGStreamer
    private var buttonReceiver: AnyCancellable?

    init(streamer: MJPEGStreamer) {
        self.streamer = streamer

    }

}

@MainActor
class LegoViewModel: ObservableObject {
    @Published var frames: [Frame] = []
    @Published var player = Player<Frame>()

    @Published var selectedFrameIndex: Int? = nil
    var selectedFrame: Frame? {
        if let idx = selectedFrameIndex, idx < frames.count {
            return frames[idx]
        } else {
            return nil
        }
    }

    private var streamer: MJPEGStreamer
    private var buttonReceiver: AnyCancellable?
    private var bulb: Bulb

    init(streamer: MJPEGStreamer, bulb: Bulb) {
        self.streamer = streamer
        self.bulb = bulb
        
        self.buttonReceiver = streamer.$latestResponseHeaders
            .receive(on: RunLoop.main)
            .map({ $0?["X-Button-Pressed"] as? String == "1" })
            .debounce(for: 0.01, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { buttonDown in
                if buttonDown {
                    self.takePicture()
                }
            }
    }

    func takePicture() {
        selectedFrameIndex = nil
        if let image = streamer.image {
            bulb.flash(illuminationTime: .seconds(0.05))
            withAnimation {
                frames.append(Frame(image: image))
            }
        }
    }
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

    @ObservedObject var model: LegoViewModel
    @ObservedObject var streamer: MJPEGStreamer
    @ObservedObject var bulb: Bulb

    @State var exportURL: URL?
    @State private var showShareSheet = false

    var flash: FlashOverlay

    init(model: LegoViewModel, streamer: MJPEGStreamer, bulb: Bulb) {
        self.model = model
        self.streamer = streamer
        self.bulb = bulb
        self.flash = FlashOverlay(bulb: bulb)
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
                    Button("Disconnect") {
                        streamer.stop()
                    }
                }
            }
            .padding()

            ZStack {
                let image = model.selectedFrame?.image ?? model.player.currentFrame?.image ?? streamer.image
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
                model.takePicture()
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
                        ForEach(0 ..< model.frames.count, id: \.self) { idx in
                            let frame = model.frames[idx]
                            FrameButton(frame: frame, selectAction: {
                                model.player.stop()
                                model.selectedFrameIndex = (model.selectedFrameIndex == idx) ? nil : idx
                            }, deleteAction: {
                                model.frames.remove(at: idx)
                                model.selectedFrameIndex = model.frames.count < 1 ? nil : min(idx, model.frames.count - 1)
                            }, isSelected: .constant(idx == model.selectedFrameIndex))
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
                    Image(systemName: model.player.currentFrame == nil ? "play.fill" : "stop.fill")
                        .imageScale(.large)
                }
                .disabled(model.frames.count < 1)

                Spacer()

                Button {
                    #if os(iOS)
                    Task {
                        self.exportURL = await exportVideo()
                    }
                    #else
                    if let url = showSavePanel() {
                        Task {
                            try await VideoWriter.write(sequence: model.frames.map(\.image), to: url)
                        }
                    }
                    #endif
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(model.frames.count < 1)
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
            try await VideoWriter.write(sequence: model.frames.map(\.image), to: outURL)
            return outURL
        } catch {
            print("Error! \(error.localizedDescription)")
            return nil
        }
    }

    func togglePlayback() {
        if model.player.currentFrame != nil {
            model.player.stop()
        } else {
            model.selectedFrameIndex = nil
            model.player.play(frames: model.frames, framerate: 15)
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
        let button = LegoStreamButton(streamer: streamer)
        let bulb = Bulb()
        let model = LegoViewModel(streamer: streamer, bulb: bulb)
//        model.frames = frames
//        model.selectedFrameIndex = 1
        Group {
            ContentView(model: model, streamer: streamer, bulb: bulb)
                .previewDevice(PreviewDevice(rawValue: "iPhone 13 mini"))
//                .frame(width: 320, height: 480)
//
//            ContentView(frames: frames, streamer: streamer)
//                .frame(width: 1024, height: 768)
        }
    }
}
