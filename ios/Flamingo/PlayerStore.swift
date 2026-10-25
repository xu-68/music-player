import AVFoundation
import FlamingoCore
import MediaPlayer
import Observation

@MainActor @Observable final class PlayerStore {
    private(set) var queue = PlaybackQueue()
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var lines: [LyricLine] = []
    var errorMessage: String?
    var sleepDeadline: Date?
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var controlObservation: NSKeyValueObservation?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var unrecorded: Double = 0
    @ObservationIgnored private var lastUptime = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var lastMediaTime: Double = 0
    @ObservationIgnored private var pendingSeek: UUID?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    var current: Track? { queue.current.flatMap { library.track($0.trackID) } }

    init(library: LibraryStore) {
        self.library = library
        player.automaticallyWaitsToMinimizeStalling = false
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio) }
        catch { errorMessage = "无法配置音频会话：\(error.localizedDescription)" }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.updateNowPlaying()
            }
        }
        observeNotifications()
        configureRemoteCommands()
        if let idString = AppPreferences.defaults.string(forKey: "lastTrack"), let id = UUID(uuidString: idString), library.track(id) != nil {
            queue.replace(with: [id]); loadCurrent(autoplay: false)
        }
    }
    func play(_ track: Track, in tracks: [Track]? = nil, shuffled: Bool = false) {
        flushListening()
        var source = tracks ?? library.tracks
        if !source.contains(where: { $0.id == track.id }) { source.append(track) }
        let index = source.firstIndex(where: { $0.id == track.id }) ?? 0
        queue.replace(with: source.isEmpty ? [track.id] : source.map(\.id), startingAt: index, shuffled: shuffled)
        loadCurrent(autoplay: true)
    }
    func toggle() { player.rate > 0 ? pause() : resume() }
    func resume() {
        guard current != nil else { return }
        if let deadline = sleepDeadline, deadline <= Date() { sleepDeadline = nil }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            lastUptime = ProcessInfo.processInfo.systemUptime
            if elapsed >= duration, duration > 0 { seek(to: 0) }
            if let id = current?.id { library.markPlayed(id) }
            wantsPlayback = true
            player.play()
        } catch { errorMessage = "无法开始播放：\(error.localizedDescription)" }
    }
    func pause() { wantsPlayback = false; player.pause(); isPlaying = false; flushListening(); updateNowPlaying() }
    func next(automatic: Bool = false) {
        flushListening()
        if queue.advance(automatic: automatic) { loadCurrent(autoplay: true) }
        else { pause() }
    }
    func previous() {
        if elapsed > 3 { seek(to: 0); return }
        flushListening()
        if queue.previous() { loadCurrent(autoplay: true) } else { seek(to: 0) }
    }
    func seek(to value: Double) {
        guard value.isFinite else { return }
        elapsed = min(max(0, value), max(duration, 0))
        let token = UUID()
        pendingSeek = token
        player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pendingSeek == token else { return }
                self.pendingSeek = nil
                let seconds = self.player.currentTime().seconds
                self.lastMediaTime = seconds.isFinite ? seconds : 0
                self.lastUptime = ProcessInfo.processInfo.systemUptime
                self.updateNowPlaying()
            }
        }
        lastUptime = ProcessInfo.processInfo.systemUptime
        updateNowPlaying()
    }
    func toggleShuffle() { queue.toggleShuffle() }
    func cycleRepeat() { queue.repeatMode = queue.repeatMode.next }
    func enqueue(_ id: UUID, next: Bool) {
        let wasEmpty = queue.current == nil
        queue.insert(id, next: next)
        if wasEmpty { loadCurrent(autoplay: false) }
    }
    func removeQueueEntry(_ id: UUID) { queue.remove(id) }
    func selectQueueEntry(_ id: UUID) { flushListening(); queue.select(id); loadCurrent(autoplay: true) }
    func refreshLyrics() { lines = current.map { library.lyrics(for: $0) } ?? [] }
    func removeFromLibrary(_ id: UUID) {
        if current?.id == id {
            let shouldResume = wantsPlayback
            pause()
            queue.removeTrack(id)
            if queue.current != nil { loadCurrent(autoplay: shouldResume) }
            else {
                player.replaceCurrentItem(with: nil); lines = []; elapsed = 0; duration = 0; pendingSeek = nil
                AppPreferences.defaults.removeObject(forKey: "lastTrack")
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
        } else { queue.removeTrack(id) }
        library.deleteTrack(id)
    }
    func flushListening() {
        if let id = current?.id, unrecorded > 0 { library.recordListening(id, seconds: unrecorded) }
        unrecorded = 0
    }
    func setSleepTimer(minutes: Int?) { sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) } }

    private func loadCurrent(autoplay: Bool) {
        guard let track = current else { return }
        let item = AVPlayerItem(url: LibraryPaths.audio.appending(path: track.filename))
        statusObservation?.invalidate()
        player.replaceCurrentItem(with: item)
        elapsed = 0; duration = track.duration; isPlaying = false; lastMediaTime = 0; pendingSeek = nil
        lastUptime = ProcessInfo.processInfo.systemUptime
        refreshLyrics()
        AppPreferences.defaults.set(track.id.uuidString, forKey: "lastTrack")
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.pause(); self.errorMessage = "无法播放此文件：\(item.error?.localizedDescription ?? "格式不受支持")"
                }
            }
        }
        updateNowPlaying()
        if autoplay { resume() }
    }
    private func tick() {
        let uptime = ProcessInfo.processInfo.systemUptime
        let delta = uptime - lastUptime
        lastUptime = uptime
        let seconds = player.currentTime().seconds
        let mediaDelta = seconds.isFinite ? seconds - lastMediaTime : 0
        if seconds.isFinite {
            if pendingSeek == nil { elapsed = seconds }
            lastMediaTime = seconds
        }
        if let value = player.currentItem?.duration.seconds, value.isFinite, value > 0 { duration = value }
        if player.timeControlStatus == .playing, pendingSeek == nil {
            unrecorded += min(max(mediaDelta, 0), max(delta, 0) + 0.25)
            if unrecorded >= 15 { flushListening() }
        }
        if let deadline = sleepDeadline, Date() >= deadline { sleepDeadline = nil; pause() }
    }
    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title,
                                  MPMediaItemPropertyArtist: track.artist,
                                  MPMediaItemPropertyAlbumTitle: track.album,
                                  MPMediaItemPropertyPlaybackDuration: duration,
                                  MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
                                  MPNowPlayingInfoPropertyPlaybackRate: player.rate,
                                  MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0]
        if let image = ArtworkCache.shared.image(track.artworkFilename) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func observeNotifications() {
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.next(automatic: true)
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.wantsPlayback; self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    let shouldResume = self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if shouldResume { self.resume() }
                }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
    }
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            remoteTargets.append((command, target))
        }
        bind(commands.playCommand) { [weak self] in self?.resume() }
        bind(commands.pauseCommand) { [weak self] in self?.pause() }
        bind(commands.togglePlayPauseCommand) { [weak self] in self?.toggle() }
        bind(commands.nextTrackCommand) { [weak self] in self?.next() }
        bind(commands.previousTrackCommand) { [weak self] in self?.previous() }
        let target = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: position.positionTime) }
            return .success
        }
        commands.changePlaybackPositionCommand.isEnabled = true
        remoteTargets.append((commands.changePlaybackPositionCommand, target))
    }
}
