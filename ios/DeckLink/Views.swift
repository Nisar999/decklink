import SwiftUI
import PhotosUI

extension Color {
    static let bg = Color(red: 0.106, green: 0.133, blue: 0.188)
    static let panel = Color(red: 0.137, green: 0.173, blue: 0.247)
    static let keyFill = Color(red: 0.18, green: 0.227, blue: 0.32)
    static let hit = Color(red: 0.435, green: 0.608, blue: 1.0)
    static let ok = Color(red: 0.373, green: 0.831, blue: 0.627)
}

struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 22).fill(configuration.isPressed ? Color.hit : Color.keyFill))
            .foregroundStyle(.white)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @EnvironmentObject var link: PCLink
    @Environment(\.scenePhase) private var phase
    @AppStorage("autoSend") private var autoSend = false

    var body: some View {
        Group {
            if link.host.isEmpty || link.token.isEmpty {
                PairView()
            } else {
                TabView {
                    DeckView().tabItem { Label("Deck", systemImage: "square.grid.3x3.fill") }
                    ClipboardView().tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
                    PhotosView().tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: phase) { _, p in
            if p == .active {
                link.connectIfNeeded()
                if autoSend { link.sendPhoneClipboard() }
            }
        }
    }
}

struct PairView: View {
    @EnvironmentObject var link: PCLink
    @State private var host = ""
    @State private var token = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to your PC").font(.title.bold())
            Text("Run DeckLink.exe on your PC, then scan the first QR code in its window with the Camera app. This app opens and pairs by itself.")
                .foregroundStyle(.secondary)
            Text("Or enter the details by hand").font(.headline).padding(.top, 12)
            TextField("PC address, e.g. 192.168.1.20:8765", text: $host)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation)
                .padding().background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
            TextField("Pairing code", text: $token)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding().background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
            Button("Connect") { link.host = host; link.token = token; link.connect() }
                .buttonStyle(.borderedProminent).disabled(host.isEmpty || token.isEmpty)
            Spacer()
        }.padding(20)
    }
}

struct DeckView: View {
    @EnvironmentObject var link: PCLink
    @AppStorage("follow") private var follow = true
    @State private var page: Int?

    var body: some View {
        GeometryReader { geo in
            if link.decks.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(link.connected ? "Waiting for decks…" : "Connecting to your PC…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(link.decks) { deck in
                            DeckPage(deck: deck)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(deck.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .overlay(alignment: .trailing) {
                    VStack(spacing: 6) {
                        ForEach(link.decks) { d in
                            Circle()
                                .fill(d.id == (page ?? link.decks.first?.id) ? Color.hit : Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }.padding(.trailing, 5)
                }
                .onChange(of: link.active) { _, new in
                    if follow { withAnimation { page = new } }
                }
            }
        }
    }
}

struct DeckPage: View {
    @EnvironmentObject var link: PCLink
    let deck: Deck
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(deck.icon).font(.system(size: 34))
                VStack(alignment: .leading) {
                    Text(deck.name).font(.title2.bold())
                    Text(deck.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Circle().fill(link.connected ? Color.ok : Color.red).frame(width: 10, height: 10)
            }
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(Array(deck.buttons.enumerated()), id: \.offset) { i, b in
                    Button { link.press(deck: deck.id, index: i) } label: {
                        VStack(spacing: 6) {
                            Text(b.icon).font(.system(size: 34))
                            Text(b.label).font(.footnote.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                        }.padding(4)
                    }.buttonStyle(KeyStyle())
                }
            }
            Spacer()
            Label("Swipe up or down for the next deck", systemImage: "chevron.up.chevron.down")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }
}

struct ClipboardView: View {
    @EnvironmentObject var link: PCLink
    @AppStorage("autoSend") private var autoSend = false
    @AppStorage("autoReceive") private var autoReceive = true
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Send to PC") {
                    TextEditor(text: $text).frame(minHeight: 100)
                    Button("Send typed text") { link.sendClip(text) }
                    Button("Send iPhone clipboard") { link.sendPhoneClipboard() }
                }
                Section("Copied on PC") {
                    Text(link.pcClip.isEmpty ? "Nothing yet" : link.pcClip).lineLimit(8)
                    Button("Copy to iPhone") { UIPasteboard.general.string = link.pcClip }
                }
                Section {
                    Toggle("Copy from PC to iPhone automatically", isOn: $autoReceive)
                    Toggle("Send iPhone clipboard when app opens", isOn: $autoSend)
                } header: { Text("Automatic") } footer: {
                    Text("iOS may ask permission each time an app reads the clipboard. Choose Allow Paste, or set Paste from Other Apps to Allow in Settings.")
                }
            }
            .scrollContentBackground(.hidden).background(Color.bg)
            .navigationTitle("Clipboard")
        }
    }
}

struct PickedFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedFile(url: dest)
        }
    }
}

struct PhotosView: View {
    @EnvironmentObject var link: PCLink
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Send to PC") {
                    PhotosPicker(selection: $items, matching: .any(of: [.images, .videos])) {
                        Label("Choose photos and videos", systemImage: "photo.on.rectangle")
                    }
                    if !link.uploadStatus.isEmpty { Text(link.uploadStatus).font(.footnote) }
                }
                Section("From PC") {
                    ForEach(link.remoteFiles, id: \.self) { f in
                        if let u = link.downloadURL(f) { Link(f, destination: u) }
                    }
                    if link.remoteFiles.isEmpty { Text("Drop files into DeckLink\\outgoing on your PC.").foregroundStyle(.secondary) }
                    Button("Refresh") { Task { await link.refreshFiles() } }
                }
            }
            .scrollContentBackground(.hidden).background(Color.bg)
            .navigationTitle("Photos and files")
            .task { await link.refreshFiles() }
            .onChange(of: items) { _, new in
                guard !new.isEmpty else { return }
                Task {
                    var urls: [URL] = []
                    for it in new {
                        if let f = try? await it.loadTransferable(type: PickedFile.self) { urls.append(f.url) }
                    }
                    items = []
                    await link.upload(urls)
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var link: PCLink
    @AppStorage("follow") private var follow = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Jump to the deck of the PC window in front", isOn: $follow)
                } footer: { Text("Pressing a button always brings that deck's window to the front first.") }
                Section("PC") {
                    LabeledContent("Address", value: link.host)
                    LabeledContent("Status", value: link.connected ? "Connected" : "Not connected")
                    Button("Reconnect") { link.connect() }
                    Button("Pair a different PC", role: .destructive) { link.unpair() }
                }
            }
            .scrollContentBackground(.hidden).background(Color.bg)
            .navigationTitle("Settings")
        }
    }
}
