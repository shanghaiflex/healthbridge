import Foundation

enum PreviewData {
    static let lectures: [Lecture] = [
        Lecture(id: "DmYS9ZmZClA", title: "Повседневная жизнь римского легионера. Семья, религия, развлечения.",
                status: "listening", position: 3600, duration: 10493, channel: "UC", channelLabel: "Макаров · Средневековье",
                series: "Повседневная жизнь людей Античности и Средних веков", source: "youtube", url: nil,
                artwork: "https://i.ytimg.com/vi/DmYS9ZmZClA/hqdefault.jpg", audio: "/audio/DmYS9ZmZClA.m4a",
                size: 169_809_692, audioStatus: "done", touchedAt: nil, queuedAt: nil),
        Lecture(id: "G5CB5MehT_k", title: "Экономика крестьянской жизни в Средневековье.",
                status: "listening", position: 2569, duration: 11372, channel: "UC", channelLabel: "Макаров · Средневековье",
                series: "Экономика Европы в «Темные века»", source: "youtube", url: nil,
                artwork: "https://i.ytimg.com/vi/G5CB5MehT_k/hqdefault.jpg", audio: "/audio/G5CB5MehT_k.m4a",
                size: 184_044_945, audioStatus: "done", touchedAt: nil, queuedAt: nil),
        Lecture(id: "sc:839825944", title: "Додинастический Древний Египет",
                status: "queued", position: 0, duration: 6955, channel: "sc", channelLabel: "Bushwacker · Древний Египет",
                series: "Древний Египет", source: "soundcloud", url: nil, artwork: nil, audio: nil,
                size: nil, audioStatus: "running", touchedAt: nil, queuedAt: nil),
    ]
}
