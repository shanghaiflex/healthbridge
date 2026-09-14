import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// Plays downloaded lectures with the screen locked: AVPlayer over a local file, lock-screen controls and
/// artwork via MPNowPlayingInfoCenter, position pushed to the server every 15 s and on every pause.
@MainActor
final class PlayerEngine: ObservableObject {
    static let shared = PlayerEngine()

    @Published private(set) var current: Lecture?
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float {
        didSet {
            UserDefaults.standard.set(rate, forKey: "playbackRate")
            if isPlaying { player?.rate = rate }
            updateNowPlaying()
        }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastSaved: Double = -100
    private var artwork: MPMediaItemArtwork?
    private var configured = false

    private init() {
        let saved = UserDefaults.standard.float(forKey: "playbackRate")
        rate = saved > 0 ? saved : 1.0
    }

    init(preview lecture: Lecture, time: Double, playing: Bool) {
        rate = 1.0
        current = lecture
        self.time = time
        duration = Double(lecture.duration)
        isPlaying = playing
    }

    static let preview = PlayerEngine(preview: PreviewData.lectures[0], time: 3600, playing: true)

    // MARK: - Session & remote controls

    func configure() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(by: 30) }; return .success }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(by: -15) }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = [1.0, 1.25, 1.5, 1.75, 2.0]
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let r = e.playbackRate
            Task { @MainActor in self?.rate = r }
            return .success
        }

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let info = note.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                if type == .began {
                    self?.pause()
                } else if let opt = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                          AVAudioSession.InterruptionOptions(rawValue: opt).contains(.shouldResume) {
                    self?.resume()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.pause() }   // headphones pulled out
        }
    }

    // MARK: - Transport

    func play(_ lecture: Lecture, from seconds: Double? = nil) {
        guard let file = DownloadManager.localFile(for: lecture) else { return }
        if current?.id == lecture.id, player != nil {
            if let seconds { seek(to: seconds) }
            resume()
            return
        }
        flushPosition(force: true)
        tearDown()

        let item = AVPlayerItem(url: file)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        player = p
        current = lecture
        LectureStore.shared.rememberFeatured(lecture)
        duration = Double(lecture.duration)
        artwork = nil
        loadArtwork(for: lecture)

        let start = seconds ?? Double(lecture.position)
        time = start
        lastSaved = start
        if start > 1 {
            p.seek(to: CMTime(seconds: start, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 10), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
        ActivityLog.shared.log("Играет", detail: "\(lecture.title) с \(Fmt.clock(start))")
        resume()
    }

    func resume() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = rate
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
        flushPosition(force: true)
        updateNowPlaying()
    }

    func toggle() { isPlaying ? pause() : resume() }

    func skip(by seconds: Double) { seek(to: time + seconds) }

    func seek(to seconds: Double) {
        guard let player else { return }
        let target = max(0, min(seconds, duration > 0 ? duration - 1 : seconds))
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        flushPosition(force: true)
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        time = seconds
        if let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if isPlaying, seconds - lastSaved >= 15 { flushPosition(force: false) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
    }

    private func finished() {
        guard let lecture = current else { return }
        isPlaying = false
        let next = LectureStore.shared.next(after: lecture)
        tearDown()
        current = nil
        Task {
            await LectureStore.shared.markListened(lecture)
            if let next, next.id != lecture.id {
                play(next)
            }
        }
    }

    /// Pushes the position to the server (at most every 15 s while playing; always when forced).
    func flushPosition(force: Bool) {
        guard let lecture = current, time > 0 else { return }
        let pos = time
        guard force || pos - lastSaved >= 15 else { return }
        lastSaved = pos
        Task { await LectureStore.shared.savePosition(lecture, seconds: Int(pos)) }
    }

    private func tearDown() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: - Lock screen

    private func updateNowPlaying() {
        guard let lecture = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: lecture.title,
            MPMediaItemPropertyArtist: lecture.channelLabel ?? "BoW",
            MPMediaItemPropertyAlbumTitle: lecture.series ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for lecture: Lecture) {
        guard let s = lecture.artwork, let url = URL(string: s) else { return }
        let cache = DownloadManager.directory.appendingPathComponent("\(lecture.safeId).jpg")
        Task.detached { [weak self] in
            var data = try? Data(contentsOf: cache)
            if data == nil, let fetched = try? await URLSession.shared.data(from: url) {
                data = fetched.0
                try? fetched.0.write(to: cache)
            }
            guard let data, let image = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard let self, self.current?.id == lecture.id else { return }
                self.artwork = art
                self.updateNowPlaying()
            }
        }
    }
}
