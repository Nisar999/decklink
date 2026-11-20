import SwiftUI
import UIKit

struct Key: Codable, Hashable { let label: String; let icon: String }
struct Deck: Codable, Identifiable, Hashable {
    let id: Int; let name: String; let icon: String; let title: String; let buttons: [Key]
}
struct Msg: Codable { let t: String; var decks: [Deck]?; var active: Int?; var text: String? }

@MainActor
final class PCLink: ObservableObject {
    @Published var decks: [Deck] = []
    @Published var active = 0
    @Published var connected = false
    @Published var pcClip = ""
    @Published var uploadStatus = ""
    @Published var remoteFiles: [String] = []
    @Published var host: String = UserDefaults.standard.string(forKey: "host") ?? "" {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    @Published var token: String = UserDefaults.standard.string(forKey: "token") ?? "" {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    private var task: URLSessionWebSocketTask?

    init() { connect() }

    func pair(from url: URL) {
        guard url.scheme == "decklink",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var q: [String: String] = [:]
        for i in c.queryItems ?? [] { if let v = i.value { q[i.name] = v } }
        if let h = q["host"], let t = q["token"] { host = h; token = t; connect() }
    }

    func unpair() {
        task?.cancel(with: .goingAway, reason: nil); task = nil
        host = ""; token = ""; decks = []; connected = false
    }

    func connectIfNeeded() { if !connected { connect() } }

    func connect() {
        task?.cancel(with: .goingAway, reason: nil)
        guard !host.isEmpty, !token.isEmpty,
              let url = URL(string: "ws://\(host)/ws?k=\(token)") else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        Task { await listen(t) }
    }

    private func listen(_ t: URLSessionWebSocketTask) async {
        do {
            while true {
                let m = try await t.receive()
                guard t === task else { return }
                connected = true
                if case .string(let s) = m, let d = s.data(using: .utf8),
                   let msg = try? JSONDecoder().decode(Msg.self, from: d) { handle(msg) }
            }
        } catch {
            guard t === task else { return }
            connected = false
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if t === task { connect() }
        }
    }

    private func handle(_ m: Msg) {
        switch m.t {
        case "decks":
            decks = m.decks ?? []
            active = m.active ?? 0
        case "clip":
            pcClip = m.text ?? ""
            let auto = UserDefaults.standard.object(forKey: "autoReceive") as? Bool ?? true
            if auto, !pcClip.isEmpty, UIPasteboard.general.string != pcClip {
                UIPasteboard.general.string = pcClip
            }
        default: break
        }
    }

    private func send(_ o: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    func press(deck: Int, index: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        send(["t": "press", "deck": deck, "i": index])
    }

    func sendClip(_ text: String) {
        guard !text.isEmpty else { return }
        send(["t": "clip", "text": text])
    }

    func sendPhoneClipboard() {
        guard UIPasteboard.general.hasStrings, let s = UIPasteboard.general.string, s != pcClip else { return }
        sendClip(s)
    }

    // MARK: files
    private func url(_ path: String) -> URL? { URL(string: "http://\(host)\(path)") }

    func downloadURL(_ name: String) -> URL? {
        guard let n = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return url("/dl/\(n)?k=\(token)")
    }

    func refreshFiles() async {
        guard let u = url("/files?k=\(token)"),
              let (data, _) = try? await URLSession.shared.data(from: u),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return }
        remoteFiles = names
    }

    func upload(_ files: [URL]) async {
        guard let u = url("/upload?k=\(token)") else { return }
        var done = 0
        for f in files {
            uploadStatus = "Sending \(done + 1) of \(files.count)…"
            do {
                let boundary = UUID().uuidString
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                let out = try FileHandle(forWritingTo: tmp)
                out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(f.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                let inp = try FileHandle(forReadingFrom: f)
                while let chunk = try inp.read(upToCount: 1 << 20), !chunk.isEmpty { out.write(chunk) }
                try inp.close()
                out.write(Data("\r\n--\(boundary)--\r\n".utf8))
                try out.close()
                var req = URLRequest(url: u)
                req.httpMethod = "POST"
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                _ = try await URLSession.shared.upload(for: req, fromFile: tmp)
                try? FileManager.default.removeItem(at: tmp)
                done += 1
            } catch {
                uploadStatus = "Upload failed. Check that your PC is on and on the same Wi-Fi."
                return
            }
        }
        uploadStatus = "Sent \(done) file(s) to DeckLink\\incoming on your PC."
    }
}
