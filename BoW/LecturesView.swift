import SwiftUI

struct LecturesView: View {
    @ObservedObject private var store = LectureStore.shared
    @ObservedObject private var player = PlayerEngine.shared
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let hero = player.current ?? store.featured {
                        HeroCard(lecture: hero, store: store, player: player, downloads: downloads)
                    } else {
                        emptyState
                    }
                    listSection
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Лекции")
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await store.refresh(trigger: "pull") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.text2)
            Text(store.lastError == nil ? "Пока ничего не скачано" : "Нет связи с сервером")
                .font(.headline)
            Text("Список берётся с bodywithoutorgans.cc: то, что слушаешь, и следующее из очереди. Потяни вниз, чтобы обновить.")
                .font(.footnote)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .card()
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("На телефоне")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                    .textCase(.uppercase)
                Spacer()
                Text("\(store.downloadedCount) из \(store.items.count)")
                    .font(.footnote)
                    .foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { i, lecture in
                    LectureRow(lecture: lecture, store: store, player: player, downloads: downloads)
                    if i < store.items.count - 1 { Divider().overlay(Theme.line).padding(.leading, 84) }
                }
            }
            .card()
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let e = store.lastError {
                Label(e, systemImage: "wifi.slash").foregroundStyle(Theme.warn)
            }
            if let t = store.lastRefresh {
                Text("Список обновлён \(Fmt.time.string(from: t))")
            }
            Text("Держу две лекции: текущую и следующую. Прослушанная удаляется сама, следующая докачивается.")
                .multilineTextAlignment(.center)
        }
        .font(.caption)
        .foregroundStyle(Theme.text3)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Hero

struct HeroCard: View {
    let lecture: Lecture
    @ObservedObject var store: LectureStore
    @ObservedObject var player: PlayerEngine
    @ObservedObject var downloads: DownloadManager
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var isCurrent: Bool { player.current?.id == lecture.id }
    private var total: Double { isCurrent && player.duration > 0 ? player.duration : Double(lecture.duration) }
    private var position: Double { scrubbing ? scrubValue : (isCurrent ? player.time : Double(lecture.position)) }
    private var downloaded: Bool { store.isDownloaded(lecture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: lecture.artwork, square: lecture.source == "soundcloud")
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: 200)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lecture.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Text(lecture.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                }
                .padding(16)
            }

            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Slider(value: Binding(get: { position }, set: { scrubValue = $0 }),
                           in: 0...max(total, 1)) { editing in
                        if editing {
                            scrubValue = position
                            scrubbing = true
                        } else {
                            scrubbing = false
                            if isCurrent { player.seek(to: scrubValue) } else if downloaded { player.play(lecture, from: scrubValue) }
                        }
                    }
                    .tint(.white)
                    .disabled(!downloaded)
                    HStack {
                        Text(Fmt.clock(position))
                        Spacer()
                        Text("−" + Fmt.clock(max(0, total - position)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.text2)
                }

                HStack {
                    Menu {
                        ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { r in
                            Button { player.rate = Float(r) } label: {
                                if player.rate == Float(r) { Label(rateLabel(r), systemImage: "checkmark") } else { Text(rateLabel(r)) }
                            }
                        }
                    } label: {
                        Text(rateLabel(Double(player.rate)))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 52, height: 36)
                            .background(Theme.surface2, in: Capsule())
                    }
                    Spacer()
                    Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.title2) }
                        .disabled(!isCurrent)
                    Spacer()
                    Button {
                        if isCurrent { player.toggle() } else if downloaded { player.play(lecture) }
                    } label: {
                        Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 64, height: 64)
                            .background(downloaded ? Color.white : Theme.text3, in: Circle())
                    }
                    .disabled(!downloaded)
                    Spacer()
                    Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.title2) }
                        .disabled(!isCurrent)
                    Spacer()
                    Button {
                        Task { await store.markListened(lecture) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 52, height: 36)
                            .background(Theme.surface2, in: Capsule())
                    }
                    .disabled(!downloaded)
                }
                .foregroundStyle(.white)

                if !downloaded {
                    DownloadState(lecture: lecture, downloads: downloads)
                }
            }
            .padding(16)
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func rateLabel(_ r: Double) -> String {
        r == r.rounded() ? "\(Int(r))×" : String(format: "%.2g×", r)
    }
}

// MARK: - Row

struct LectureRow: View {
    let lecture: Lecture
    @ObservedObject var store: LectureStore
    @ObservedObject var player: PlayerEngine
    @ObservedObject var downloads: DownloadManager

    private var isCurrent: Bool { player.current?.id == lecture.id }
    private var downloaded: Bool { store.isDownloaded(lecture) }
    private var progress: Double {
        let pos = isCurrent ? player.time : Double(lecture.position)
        return lecture.duration > 0 ? min(1, pos / Double(lecture.duration)) : 0
    }

    var body: some View {
        Button {
            if isCurrent { player.toggle() } else if downloaded { player.play(lecture) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Artwork(url: lecture.artwork, square: lecture.source == "soundcloud")
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if isCurrent && player.isPlaying {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.45))
                        Image(systemName: "waveform").foregroundStyle(.white).symbolEffect(.variableColor.iterative, isActive: true)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(lecture.title).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.white)
                    Text(lecture.subtitle).font(.caption).foregroundStyle(Theme.text2).lineLimit(1)
                    HStack(spacing: 6) {
                        if progress > 0 {
                            ProgressView(value: progress).tint(.white).frame(width: 60)
                        }
                        Text(progress > 0 ? "\(Fmt.clock(isCurrent ? player.time : Double(lecture.position))) из \(Fmt.duration(lecture.duration))" : Fmt.duration(lecture.duration))
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.text3)
                    }
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var trailing: some View {
        if downloaded {
            Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
        } else if let p = downloads.progress[lecture.id] {
            ZStack {
                Circle().stroke(Theme.surface2, lineWidth: 3)
                Circle().trim(from: 0, to: p).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(p * 100))").font(.system(size: 9, weight: .semibold).monospacedDigit())
            }
            .frame(width: 30, height: 30)
        } else if lecture.audio == nil {
            Image(systemName: "icloud.and.arrow.down").foregroundStyle(Theme.text3).font(.title3)
        } else {
            Button { downloads.start(lecture) } label: {
                Image(systemName: "arrow.down.circle").font(.title).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

struct DownloadState: View {
    let lecture: Lecture
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        HStack(spacing: 10) {
            if let p = downloads.progress[lecture.id] {
                ProgressView(value: p).tint(Theme.accent)
                Text("\(Int(p * 100))%").font(.caption.monospacedDigit()).foregroundStyle(Theme.text2)
            } else if lecture.audio == nil {
                Image(systemName: "icloud.and.arrow.down").foregroundStyle(Theme.text2)
                Text("Сервер ещё скачивает звук — появится при следующем обновлении").font(.caption).foregroundStyle(Theme.text2)
            } else {
                Button { downloads.start(lecture) } label: {
                    Label("Скачать \(Fmt.megabytes(lecture.size))", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
    }
}

// MARK: - Artwork

struct Artwork: View {
    let url: String?
    var square = false

    var body: some View {
        ZStack {
            Theme.surface2
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "waveform").foregroundStyle(Theme.text3)
                    }
                }
            } else {
                Image(systemName: "waveform").font(.title).foregroundStyle(Theme.text3)
            }
        }
    }
}

#Preview("Лекции") {
    LecturesPreviewHost()
}

private struct LecturesPreviewHost: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HeroCard(lecture: PreviewData.lectures[0], store: LectureStore.preview, player: PlayerEngine.preview, downloads: DownloadManager.shared)
                    VStack(spacing: 0) {
                        ForEach(PreviewData.lectures) { l in
                            LectureRow(lecture: l, store: LectureStore.preview, player: PlayerEngine.preview, downloads: DownloadManager.shared)
                        }
                    }
                    .card()
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Лекции")
        }
        .preferredColorScheme(.dark)
    }
}
