import FlamingoCore
import PhotosUI
import SwiftUI

struct PlaylistAddition: Identifiable {
    let id = UUID()
    var trackIDs: [UUID]
}

struct PlaylistAdditionView: View {
    var request: PlaylistAddition
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section("新建歌单") {
                    TextField("歌单名称", text: $name)
                    Button("创建并添加") { library.createPlaylist(name, tracks: request.trackIDs); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("添加到现有歌单") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) { library.add(request.trackIDs, to: playlist.id); dismiss() }
                    }
                }
            }.navigationTitle("添加到歌单").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct PlaylistArtwork: View {
    var tracks: [Track]
    var custom: String? = nil
    private var images: [UIImage] {
        var seen = Set<String>()
        return tracks.compactMap { track in
            guard let name = track.artworkFilename, seen.insert(name).inserted else { return nil }
            return ArtworkCache.shared.image(name)
        }.prefix(4).map { $0 }
    }
    var body: some View {
        GeometryReader { geometry in
            let values = images
            Group {
                if let image = ArtworkCache.shared.image(custom) { Image(uiImage: image).resizable().scaledToFill() }
                else if values.isEmpty {
                    ZStack { Color(uiColor: .secondarySystemBackground); Image(systemName: "star.fill").resizable().scaledToFit().padding(geometry.size.width * 0.3).foregroundStyle(MusicDesign.accent) }
                } else {
                    collage(values, size: geometry.size)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
    private func picture(_ image: UIImage, width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: image).resizable().scaledToFill().frame(width: width, height: height).clipped()
    }
    @ViewBuilder private func collage(_ images: [UIImage], size: CGSize) -> some View {
        if images.count == 1 { picture(images[0], width: size.width, height: size.height) }
        else if images.count == 2 {
            HStack(spacing: 0) { picture(images[0], width: size.width / 2, height: size.height); picture(images[1], width: size.width / 2, height: size.height) }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) { picture(images[0], width: size.width / 2, height: size.height / 2); picture(images[1], width: size.width / 2, height: size.height / 2) }
                if images.count == 3 { picture(images[2], width: size.width, height: size.height / 2) }
                else { HStack(spacing: 0) { picture(images[2], width: size.width / 2, height: size.height / 2); picture(images[3], width: size.width / 2, height: size.height / 2) } }
            }
        }
    }
}

private struct PlaylistEditEntry: Identifiable {
    let id = UUID()
    var trackID: UUID
}

struct PlaylistEditor: View {
    var playlist: Playlist? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var cover: String?
    @State private var working: [PlaylistEditEntry] = []
    @State private var removed = Set<UUID>()
    @State private var adding = false
    @State private var photo: PhotosPickerItem?
    @State private var prepared = false
    @State private var cancelled = false
    @State private var committed = false
    private var tracks: [Track] { working.filter { !removed.contains($0.id) }.compactMap { library.track($0.trackID) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    PlaylistArtwork(tracks: tracks, custom: cover).frame(width: 180, height: 180).frame(maxWidth: .infinity)
                    PhotosPicker(selection: $photo, matching: .images) { Label("选择封面照片", systemImage: "photo") }
                    if cover != nil { Button("恢复自动拼图封面") { cover = nil } }
                    TextField("歌单名称", text: $name).accessibilityIdentifier("playlist-name")
                    TextField("描述", text: $description, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Button("添加歌曲", systemImage: "plus") { adding = true }.accessibilityIdentifier("playlist-add-songs")
                    if !removed.isEmpty { Button("移除所选 \(removed.count) 项", role: .destructive) { working.removeAll { removed.contains($0.id) }; removed = [] } }
                    ForEach(working) { entry in
                        if let track = library.track(entry.trackID) {
                            Button {
                                if removed.contains(entry.id) { removed.remove(entry.id) } else { removed.insert(entry.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: removed.contains(entry.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(MusicDesign.accent)
                                    ArtworkView(track: track).frame(width: 42, height: 42)
                                    VStack(alignment: .leading) { Text(track.title).foregroundStyle(Color.primary); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                                }.opacity(removed.contains(entry.id) ? 0.45 : 1)
                            }
                        }
                    }.onMove { from, to in working.move(fromOffsets: from, toOffset: to) }
                        .onDelete { offsets in working.remove(atOffsets: offsets) }
                } header: { Text("\(tracks.count) 首歌曲 · 可重复添加") }
            }.navigationTitle(playlist == nil ? "新建歌单" : "编辑歌单").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(playlist == nil ? "取消" : "关闭") {
                        cancelled = playlist == nil
                        Task { if !cancelled { save(); await library.saveNow() }; dismiss() }
                    } }
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { Task { save(); await library.saveNow(); dismiss() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear {
                    guard !prepared else { return }; prepared = true
                    name = playlist?.name ?? ""; description = playlist?.description ?? ""; cover = playlist?.artworkFilename
                    working = (playlist?.trackIDs ?? []).map { PlaylistEditEntry(trackID: $0) }
                }
                .onDisappear { if playlist != nil && !cancelled && !committed { save() } }
                .sheet(isPresented: $adding) { PlaylistSongPicker { working.append(PlaylistEditEntry(trackID: $0)) } }
                .onChange(of: photo) { _, value in Task {
                    do {
                        guard let data = try await value?.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                        let filename = "playlist-" + UUID().uuidString + ".jpg"
                        try jpeg.write(to: LibraryPaths.artwork.appending(path: filename), options: .atomic); cover = filename
                    } catch { library.errorMessage = "无法读取封面：\(error.localizedDescription)" }
                } }
        }
    }
    private func save() {
        guard !committed else { return }; committed = true
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        var value = playlist.flatMap { original in library.playlists.first { $0.id == original.id } } ?? Playlist(name: trimmed)
        value.name = trimmed.isEmpty ? value.name : trimmed
        value.description = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        value.artworkFilename = cover; value.trackIDs = tracks.map(\.id)
        if playlist != nil { library.updatePlaylist(value) } else if !value.name.isEmpty { library.restorePlaylist(value) }
    }
}

private struct PlaylistSongPicker: View {
    var add: (UUID) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var added: [UUID: Int] = [:]
    @State private var matches: [Track] = []
    var body: some View {
        NavigationStack {
            List(matches) { track in
                Button { add(track.id); added[track.id, default: 0] += 1 } label: {
                    HStack(spacing: 12) {
                        ArtworkView(track: track).frame(width: 42, height: 42)
                        VStack(alignment: .leading) { Text(track.title).foregroundStyle(Color.primary); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let count = added[track.id] { Text("+\(count)").font(.caption.monospacedDigit()) }
                        Image(systemName: "plus.circle.fill")
                    }
                }.accessibilityIdentifier("picker-song-\(track.title)")
            }.navigationTitle("添加歌曲").searchable(text: $query, prompt: "歌曲、艺人或标签")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .task(id: query) {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    let tracks = library.tracks, search = query
                    let result = await Task.detached { MusicSearch.ranked(tracks, query: search) }.value
                    if !Task.isCancelled { matches = result }
                }
        }
    }
}
