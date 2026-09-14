import Foundation

/// One row of `GET /api/lectures/preload` — what the phone keeps offline.
struct Lecture: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var status: String
    var position: Int
    var duration: Int
    var channel: String?
    var channelLabel: String?
    var series: String?
    var source: String?
    var url: String?
    var artwork: String?
    /// Server path of the audio file (`/audio/<id>.m4a`), nil while the mini is still fetching it.
    var audio: String?
    var size: Int?
    var audioStatus: String?
    var touchedAt: Int?
    var queuedAt: Int?

    var subtitle: String {
        [series, channelLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// File-system-safe id: `sc:123` → `sc_123`, same rule as the server.
    var safeId: String { id.replacingOccurrences(of: ":", with: "_") }
}

struct PreloadResponse: Codable {
    let items: [Lecture]
    let count: Int
}
