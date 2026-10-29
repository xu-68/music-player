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
    private(set) var seekRevision = 0
    var errorMessage: String?
    private(set) var sleepPlan: SleepPlan?
    var sleepDeadline: Date? { sleepPlan?.deadline }
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored private var player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var controlObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var cachedNowPlayingTrack: Track?
    @ObservationIgnored private var cachedNowPlayingInfo: [String: Any] = [:]
    @ObservationIgnored private var cachedArtworkName: String?
    @ObservationIgnored private var cachedMediaArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var lastSystemSync: TimeInterval = 0
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingSeek: UUID?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var sleepFiring = false
    @ObservationIgnored private var lastPersistedPosition: Double = 0
    var current: Track? { queue.current.flatMap { library.track($0.trackID) } }
    // Read the media clock for visible karaoke frames, including rate changes and
    // buffering. Never extrapolate wall time beyond the actual audio position.
    var lyricPlaybackTime: Double {
        // Observe elapsed even while the timeline is paused so a seek within
        // the same lyric line redraws its word masks immediately.
        let position = elapsed
        guard pendingSeek == nil, player.currentItem?.status == .readyToPlay else { return position }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : position
    }
    var canGoNext: Bool {
        var candidate = queue
        return candidate.advance() && candidate.current.flatMap { library.track($0.trackID) } != nil
    }
    var canGoPrevious: Bool {
        var candidate = queue
        return candidate.previous() && candidate.current.flatMap { library.track($0.trackID) } != nil
    }

    init(library: LibraryStore) {
        self.library = library
        configureAudioSession()
        observeEngine()
        observeNotifications()
        configureRemoteCommands()
        if let data = AppPreferences.defaults.data(forKey: "playbackQueue"),
           let restored = try? JSONDecoder().decode(PlaybackQueue.self, from: data) {
            let position = AppPreferences.defaults.double(forKey: "playbackPosition")
            queue = restored
            for id in Set(queue.entries.map(\.trackID)) where library.track(id) == nil { queue.removeTrack(id) }
            loadCurrent(autoplay: false)
            seek(to: position)
        } else if let idString = AppPreferences.defaults.string(forKey: "lastTrack"), let id = UUID(uuidString: idString), library.track(id) != nil {
            queue.replace(with: [id]); loadCurrent(autoplay: false)
        }
    }
    private func configureAudioSession() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio) }
        catch { errorMessage = "无法配置音频会话：\(error.localizedDescription)" }
    }
    private func observeEngine() {
        player.automaticallyWaitsToMinimizeStalling = false
        let engine = player
        timeObserver = engine.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self, weak engine] _ in
            Task { @MainActor [weak self, weak engine] in
                guard let self, self.player === engine else { return }
                self.tick()
            }
        }
        controlObservation = engine.observe(\.timeControlStatus, options: [.new]) { [weak self, weak engine] _, _ in
            Task { @MainActor [weak self, weak engine] in
                guard let self, self.player === engine else { return }
                self.isPlaying = self.wantsPlayback && self.player.timeControlStatus == .playing
                self.updateNowPlaying()
            }
        }
        rateObservation = engine.observe(\.rate, options: [.new]) { [weak self, weak engine] _, _ in
            Task { @MainActor [weak self, weak engine] in
                guard let self, self.player === engine else { return }
                self.updateNowPlaying()
            }
        }
    }
    private func recoverMediaServices() {
        let position = elapsed
        pause(immediate: true)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        controlObservation?.invalidate(); rateObservation?.invalidate(); statusObservation?.invalidate()
        player = AVPlayer()
        configureAudioSession()
        observeEngine()
        if current != nil { loadCurrent(autoplay: false); seek(to: position) }
        // A media-services reset must never restart audio without user input.
    }
    func synchronizeSystemPlayback() {
        tick()
        updateNowPlaying()
    }
    func play(_ track: Track, in tracks: [Track]? = nil, shuffled: Bool = false, startingAt: Int? = nil) {
        var source = tracks ?? library.tracks
        if !source.contains(where: { $0.id == track.id }) { source.append(track) }
        let index = startingAt.flatMap { source.indices.contains($0) && source[$0].id == track.id ? $0 : nil } ?? source.firstIndex(where: { $0.id == track.id }) ?? 0
        queue.replace(with: source.isEmpty ? [track.id] : source.map(\.id), startingAt: index, shuffled: shuffled)
        loadCurrent(autoplay: true)
    }
    func toggle() { wantsPlayback ? pause() : resume() }
    func resume() {
        guard current != nil else { return }
        resumeAfterInterruption = false
        if let deadline = sleepDeadline, deadline <= Date() { cancelSleepTimer() }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if elapsed >= duration, duration > 0 { seek(to: 0) }
            wantsPlayback = true
            fadeTask?.cancel()
            player.volume = AppPreferences.defaults.bool(forKey: "fadePlayback") ? 0 : 1
            player.play()
            fade(to: 1, seconds: AppPreferences.defaults.bool(forKey: "fadePlayback") ? 0.2 : 0) {}
        } catch { errorMessage = "无法开始播放：\(error.localizedDescription)" }
    }
    func pause(immediate: Bool = false) {
        resumeAfterInterruption = false
        wantsPlayback = false; isPlaying = false
        let duration = !immediate && AppPreferences.defaults.bool(forKey: "fadePlayback") ? 0.2 : 0
        fade(to: 0, seconds: duration) { [weak self] in
            guard let self else { return }
            self.player.pause(); self.player.volume = 1; self.updateNowPlaying()
        }
        persistQueue(); updateNowPlaying()
    }
    @discardableResult func next(automatic: Bool = false) -> Bool {
        if automatic, sleepPlan?.mode == .endOfTrack || automatic && sleepPlan?.mode == .endOfQueue && queue.upcoming.isEmpty {
            fireSleepTimer(); return false
        }
        // An unavailable manual skip must not pause the current song.
        guard automatic || canGoNext else { return false }
        if queue.advance(automatic: automatic) { loadCurrent(autoplay: true); return true }
        pause(); return false
    }
    @discardableResult func previous() -> Bool {
        guard canGoPrevious else { return false }
        if queue.previous() { loadCurrent(autoplay: true); return true }
        return false
    }
    func seek(to value: Double) {
        guard value.isFinite, player.currentItem != nil else { return }
        elapsed = min(max(0, value), max(duration, 0))
        let token = UUID()
        pendingSeek = token
        seekRevision &+= 1
        player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pendingSeek == token else { return }
                self.pendingSeek = nil
                // Reconcile with the audio clock even when the engine interrupts a seek.
                let actual = self.player.currentTime().seconds
                if actual.isFinite { self.elapsed = max(0, actual) }
                self.seekRevision &+= 1
                self.persistQueue()
                self.updateNowPlaying()
            }
        }
        persistQueue(); updateNowPlaying()
    }
    func toggleShuffle() { queue.toggleShuffle(); persistQueue() }
    func cycleRepeat() { queue.repeatMode = queue.repeatMode.next; persistQueue() }
    func enqueue(_ id: UUID, next: Bool) {
        enqueue([id], next: next)
    }
    func enqueue(_ ids: [UUID], next: Bool) {
        let wasEmpty = queue.current == nil
        queue.insert(ids, next: next)
        if wasEmpty { loadCurrent(autoplay: false) }
        persistQueue()
    }
    func removeQueueEntry(_ id: UUID) { queue.remove(id); persistQueue() }
    func moveQueueEntries(from: IndexSet, to: Int) { queue.move(from: from, to: to); persistQueue() }
    func moveQueueEntryNext(_ id: UUID) { queue.moveNext(id); persistQueue() }
    func clearUpcoming() { queue.clearUpcoming(); persistQueue() }
    func clearNextInQueue() { queue.clearNextInQueue(); persistQueue() }
    func selectQueueEntry(_ id: UUID) { queue.select(id); loadCurrent(autoplay: true) }
    func refreshLyrics() { lines = current.map { library.lyrics(for: $0) } ?? [] }
    func removeFromLibrary(_ id: UUID) {
        let wasCurrent = queue.current?.trackID == id
        guard library.deleteTrack(id) else { return }
        if wasCurrent {
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
        persistQueue()
    }
    func reconcileLibrary() {
        let missing = Set(queue.entries.map(\.trackID)).filter { library.track($0) == nil }
        let lostCurrent = queue.current.map { library.track($0.trackID) == nil } ?? false
        if lostCurrent { pause(); player.replaceCurrentItem(with: nil) }
        for id in missing { queue.removeTrack(id) }
        if lostCurrent {
            if queue.current != nil { loadCurrent(autoplay: false) }
            else { lines = []; elapsed = 0; duration = 0; pendingSeek = nil; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        }
        if !missing.isEmpty { persistQueue() }
    }
    func setSleepTimer(minutes: Int?) {
        if let minutes { setSleepTimer(mode: .duration, minutes: Double(minutes)) } else { cancelSleepTimer() }
    }
    func setSleepTimer(mode: SleepMode, minutes: Double = 30) {
        cancelSleepTimer()
        sleepPlan = SleepPlan(mode: mode, minutes: minutes, fadeSeconds: AppPreferences.defaults.double(forKey: "sleepFade"))
        scheduleSleepDeadline()
    }
    func extendSleepTimer(minutes: Double) {
        guard var plan = sleepPlan, let deadline = plan.deadline else { return }
        plan.deadline = deadline.addingTimeInterval(minutes * 60); sleepPlan = plan
        scheduleSleepDeadline()
    }
    func cancelSleepTimer() {
        sleepTask?.cancel(); sleepTask = nil; sleepPlan = nil
        if sleepFiring { fadeTask?.cancel(); player.volume = 1; sleepFiring = false }
    }
    private func scheduleSleepDeadline() {
        sleepTask?.cancel()
        guard let deadline = sleepPlan?.deadline else { return }
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            self?.fireSleepTimer()
        }
    }
    private func fireSleepTimer() {
        guard let plan = sleepPlan, !sleepFiring else { return }
        sleepFiring = true; sleepTask?.cancel()
        fade(to: 0, seconds: isPlaying ? plan.fadeSeconds : 0) { [weak self] in
            guard let self else { return }
            self.sleepPlan = nil; self.sleepFiring = false; self.pause(immediate: true)
        }
    }
    private func fade(to volume: Float, seconds: Double, completion: @escaping @MainActor () -> Void) {
        fadeTask?.cancel()
        guard seconds > 0 else { player.volume = volume; completion(); return }
        let start = player.volume
        fadeTask = Task { [weak self] in
            let began = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let fraction = min(1, (ProcessInfo.processInfo.systemUptime - began) / seconds)
                self?.player.volume = start + (volume - start) * Float(fraction)
                if fraction >= 1 { completion(); return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }
    func persistQueue() {
        if let data = try? JSONEncoder().encode(queue) { AppPreferences.defaults.set(data, forKey: "playbackQueue") }
        AppPreferences.defaults.set(elapsed, forKey: "playbackPosition")
        updateRemoteCommandAvailability()
    }

    private func loadCurrent(autoplay: Bool) {
        guard let track = current else { return }
        fadeTask?.cancel(); player.volume = 1
        let url = track.decodedFilename.map { LibraryPaths.decoded.appending(path: $0) } ?? LibraryPaths.audio.appending(path: track.filename)
        let item = AVPlayerItem(url: url)
        statusObservation?.invalidate()
        player.replaceCurrentItem(with: item)
        elapsed = 0; duration = track.duration; isPlaying = false; pendingSeek = nil
        persistQueue()
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
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            if pendingSeek == nil { elapsed = seconds }
        }
        if let value = player.currentItem?.duration.seconds, value.isFinite, value > 0 { duration = value }
        if abs(elapsed - lastPersistedPosition) >= 5 { lastPersistedPosition = elapsed; persistQueue() }
        if ProcessInfo.processInfo.systemUptime - lastSystemSync >= 5 { updateNowPlaying() }
    }
    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = current else {
            cachedNowPlayingTrack = nil; cachedNowPlayingInfo = [:]
            cachedMediaArtwork = nil; cachedArtworkName = nil
            center.nowPlayingInfo = nil
            updateRemoteCommandAvailability()
            return
        }
        if cachedNowPlayingTrack != track {
            cachedNowPlayingTrack = track
            cachedNowPlayingInfo = [MPMediaItemPropertyTitle: track.title,
                                    MPMediaItemPropertyArtist: track.artist,
                                    MPMediaItemPropertyAlbumTitle: track.album,
                                    MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                                    MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0]
            if cachedArtworkName != track.artworkFilename {
                cachedArtworkName = track.artworkFilename
                cachedMediaArtwork = ArtworkCache.shared.image(track.artworkFilename).map { image in
                    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
            }
            cachedNowPlayingInfo[MPMediaItemPropertyArtwork] = cachedMediaArtwork
        }
        // iOS advances elapsed time using this rate; periodic correction is
        // throttled and never recreates static metadata or the artwork object.
        cachedNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        cachedNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        cachedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = wantsPlayback && isPlaying ? player.rate : 0
        cachedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queue.index
        cachedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.entries.count
        center.nowPlayingInfo = cachedNowPlayingInfo
        lastSystemSync = ProcessInfo.processInfo.systemUptime
        updateRemoteCommandAvailability()
    }
    private func observeNotifications() {
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                if self.sleepFiring { self.sleepPlan = nil; self.sleepFiring = false; self.pause(immediate: true) }
                else { self.next(automatic: true) }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    let requestedResume = self.wantsPlayback
                    self.pause(immediate: true)
                    self.resumeAfterInterruption = requestedResume
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
                Task { @MainActor [weak self] in self?.pause(immediate: true) }
            } else {
                Task { @MainActor [weak self] in self?.synchronizeSystemPlayback() }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recoverMediaServices() }
        })
    }
    private func configureRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> MPRemoteCommandHandlerStatus) {
            let target = command.addTarget { _ in
                // Return the result after dispatching the action, rather than
                // acknowledging a Task that has not selected its track yet.
                if Thread.isMainThread { return MainActor.assumeIsolated { action() } }
                return DispatchQueue.main.sync { MainActor.assumeIsolated { action() } }
            }
            remoteTargets.append((command, target))
        }
        bind(commands.playCommand) { [weak self] in
            guard let self, self.current != nil else { return .noSuchContent }
            self.resume(); return self.wantsPlayback ? .success : .commandFailed
        }
        bind(commands.pauseCommand) { [weak self] in
            guard let self, self.current != nil else { return .noSuchContent }
            self.pause(); return .success
        }
        bind(commands.togglePlayPauseCommand) { [weak self] in
            guard let self, self.current != nil else { return .noSuchContent }
            self.toggle(); return .success
        }
        bind(commands.nextTrackCommand) { [weak self] in
            self?.next() == true ? .success : .noSuchContent
        }
        bind(commands.previousTrackCommand) { [weak self] in
            self?.previous() == true ? .success : .noSuchContent
        }
        let target = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let action: @MainActor () -> MPRemoteCommandHandlerStatus = {
                guard let self, self.current != nil, position.positionTime.isFinite else { return .noSuchContent }
                self.seek(to: position.positionTime); return .success
            }
            if Thread.isMainThread { return MainActor.assumeIsolated { action() } }
            return DispatchQueue.main.sync { MainActor.assumeIsolated { action() } }
        }
        remoteTargets.append((commands.changePlaybackPositionCommand, target))
        commands.skipForwardCommand.isEnabled = false
        commands.skipBackwardCommand.isEnabled = false
        updateRemoteCommandAvailability()
    }
    private func updateRemoteCommandAvailability() {
        let commands = MPRemoteCommandCenter.shared()
        let loaded = current != nil
        commands.playCommand.isEnabled = loaded
        commands.pauseCommand.isEnabled = loaded
        commands.togglePlayPauseCommand.isEnabled = loaded
        commands.changePlaybackPositionCommand.isEnabled = loaded
        commands.nextTrackCommand.isEnabled = canGoNext
        commands.previousTrackCommand.isEnabled = canGoPrevious
    }
    deinit {
        fadeTask?.cancel(); sleepTask?.cancel()
        statusObservation?.invalidate(); controlObservation?.invalidate(); rateObservation?.invalidate()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        for observer in notifications { NotificationCenter.default.removeObserver(observer) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}
