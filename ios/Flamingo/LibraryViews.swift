import FlamingoCore
import SwiftUI

struct HomeView: View {
    var importAction: () -> Void
    var settingsAction: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    private var recent: [Track] { library.tracks.filter { $0.lastPlayedAt != nil }.sorted { $0.lastPlayedAt! > $1.lastPlayedAt! } }
    private var suggestions: [Track] {
        let favorites = library.tracks.filter(\.isFavorite)
        return Array((favorites.isEmpty ? library.tracks.sorted { $0.addedAt > $1.addedAt } : favorites).prefix(12))
    }
    var body: some View {
        Group {
            if library.tracks.isEmpty {
                MusicEmptyState(title: "音乐，就在这里", message: "从“文件”导入你喜欢的音乐。\n专辑、歌单和歌词，全部留在你的设备上。",
                                symbol: "music.note.house", actionTitle: "导入音乐", action: importAction)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            shelf(title: "为你精选", tracks: suggestions, width: min(proxy.size.width * 0.72, 320), featured: true)
                            if !recent.isEmpty {
                                shelf(title: "最近播放", tracks: Array(recent.prefix(50)), width: min(proxy.size.width * 0.43, 200))
                            }
                            let followed = library.tracks.filter { !Set(library.artists(for: $0)).isDisjoint(with: library.snapshot.followedArtists) }
                            if !followed.isEmpty { shelf(title: "关注的艺人", tracks: Array(followed.prefix(20)), width: min(proxy.size.width * 0.43, 200)) }
                            shelf(title: "最近添加", tracks: Array(library.tracks.sorted { $0.addedAt > $1.addedAt }.prefix(12)), width: min(proxy.size.width * 0.43, 200))
                        }.padding(.vertical, 12)
                    }
                }
            }
        }.navigationTitle("主页")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("导入音乐", systemImage: "plus", action: importAction).disabled(library.importing) }
                ToolbarItem(placement: .topBarTrailing) { Button("设置", systemImage: "person.crop.circle", action: settingsAction).font(.title2) }
            }
    }
    private func shelf(title: String, tracks: [Track], width: CGFloat, featured: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold()).padding(.horizontal, MusicDesign.pageInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: featured ? 12 : 16) {
                    ForEach(tracks) { track in
                        Button { player.play(track, in: tracks) } label: {
                            VStack(alignment: featured ? .center : .leading, spacing: featured ? 0 : 6) {
                                ArtworkView(track: track, radius: featured ? 0 : 8).frame(width: width, height: width)
                                VStack(alignment: featured ? .center : .leading, spacing: 3) {
                                    Text(track.title).font(featured ? .headline : .body).lineLimit(1).foregroundStyle(.primary)
                                    Text(track.artist).font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                                    if featured { Text(track.album).font(.subheadline).lineLimit(1).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: featured ? .center : .leading)
                                    .padding(featured ? 14 : 0)
                            }.frame(width: width).background(featured ? Color(uiColor: .secondarySystemBackground) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: featured ? 16 : 0, style: .continuous))
                        }.buttonStyle(PressStyle()).contextMenu { TrackActions(track: track) }
                    }
                }.padding(.horizontal, MusicDesign.pageInset)
            }
        }
    }
}

struct LibraryView: View {
    var importAction: () -> Void
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink { PlaylistsView() } label: { LibraryCategory(title: "歌单", symbol: "music.note.list") }
                NavigationLink { ArtistsView() } label: { LibraryCategory(title: "艺人", symbol: "music.mic") }
                NavigationLink { AlbumsView() } label: { LibraryCategory(title: "专辑", symbol: "square.stack") }
                NavigationLink { SongsView(title: "歌曲") } label: { LibraryCategory(title: "歌曲", symbol: "music.note") }
                NavigationLink { SongsView(title: "收藏的歌曲", favoritesOnly: true) } label: { LibraryCategory(title: "收藏的歌曲", symbol: "star") }
                if !library.tracks.isEmpty {
                    Text("最近添加").font(.title2.bold()).padding(.top, 28).padding(.bottom, 16)
                    AlbumGrid(albums: Array(library.albums.sorted { ($0.map(\.addedAt).max() ?? .distantPast) > ($1.map(\.addedAt).max() ?? .distantPast) }.prefix(12)))
                } else {
                    MusicEmptyState(title: "你的资料库", message: "导入音频后，歌曲将自动按专辑和艺人整理。", actionTitle: "导入音乐", action: importAction)
                        .frame(minHeight: 280)
                }
            }.padding(.horizontal, MusicDesign.pageInset).padding(.bottom, 24)
        }.buttonStyle(.plain).navigationTitle("资料库")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("导入音乐", systemImage: "plus", action: importAction).disabled(library.importing) } }
    }
}

private struct LibraryCategory: View {
    var title: String
    var symbol: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(MusicDesign.accent).frame(width: 30)
                Text(title).font(.system(size: 22)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
            }.frame(minHeight: 58).contentShape(Rectangle())
            Divider().padding(.leading, 44)
        }
    }
}

struct AlbumGrid: View {
    var albums: [[Track]]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 18)], alignment: .leading, spacing: 22) {
            ForEach(albums, id: \.first!.albumKey) { tracks in
                if let track = tracks.first {
                    NavigationLink { AlbumDetailView(albumKey: track.albumKey) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            ArtworkView(track: track).shadow(color: .black.opacity(0.08), radius: 5, y: 2).padding(.bottom, 2)
                            Text(track.album).font(.body).foregroundStyle(.primary).lineLimit(1)
                            Text(track.albumArtist.isEmpty ? track.artist : track.albumArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.buttonStyle(PressStyle())
                }
            }
        }
    }
}

struct AlbumsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    var body: some View {
        ScrollView {
            AlbumGrid(albums: library.albums.filter { query.isEmpty || $0.contains { $0.matches(query) } })
                .padding(MusicDesign.pageInset)
        }.navigationTitle("专辑").searchable(text: $query, prompt: "搜索专辑")
            .overlay { if library.albums.isEmpty { MusicEmptyState(title: "还没有专辑", message: "导入带有专辑标签的音频后，会在这里自动整理。", symbol: "square.stack") } }
    }
}

struct AlbumDetailView: View {
    let albumKey: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    private var tracks: [Track] { library.albums.first { $0.first?.albumKey == albumKey } ?? [] }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ArtworkView(track: tracks.first, radius: 10).frame(maxWidth: 290).padding(.top, 20)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                VStack(spacing: 4) {
                    Text(tracks.first?.album ?? "专辑").font(.title2.bold()).multilineTextAlignment(.center)
                    Text(tracks.first.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist } ?? "").font(.title3).foregroundStyle(MusicDesign.accent)
                    Text("\(tracks.count) 首歌曲 · \(Int(tracks.reduce(0) { $0 + $1.duration }) / 60) 分钟").font(.caption).foregroundStyle(.secondary)
                }
                CollectionPlayButtons(tracks: tracks).padding(.vertical, 6)
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        VStack(spacing: 0) {
                            HStack {
                                TrackRow(track: track, showArtwork: false, number: track.trackNumber > 0 ? track.trackNumber : index + 1) { player.play(track, in: tracks) }
                                Menu { TrackActions(track: track) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                            }.contextMenu { TrackActions(track: track) }
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 30).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.navigationBarTitleDisplayMode(.inline)
    }
}

struct CollectionPlayButtons: View {
    var tracks: [Track]
    @Environment(PlayerStore.self) private var player
    var body: some View {
        HStack(spacing: 14) {
            Button { if let first = tracks.first { player.play(first, in: tracks) } } label: {
                Label("播放", systemImage: "play.fill").frame(maxWidth: .infinity).frame(height: 46)
            }
            Button { if let first = tracks.randomElement() { player.play(first, in: tracks, shuffled: true) } } label: {
                Label("随机播放", systemImage: "shuffle").frame(maxWidth: .infinity).frame(height: 46)
            }
        }.font(.headline).buttonStyle(PressStyle())
            .background { HStack(spacing: 14) { RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)); RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)) } }
            .disabled(tracks.isEmpty)
    }
}

struct SongsView: View {
    var title: String
    var ids: [UUID]? = nil
    var favoritesOnly = false
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var query = ""
    @State private var pendingDeletion: Track?
    @AppStorage("songSort") private var songSort = "标题"
    @AppStorage("sortDescending") private var descending = false
    private var tracks: [Track] {
        let source = ids.map { $0.compactMap(library.track) } ?? (SongSort(rawValue: songSort) ?? .title).sorted(library.tracks, descending: descending)
        return source.filter { (!favoritesOnly || $0.isFavorite) && $0.matches(query) }
    }
    var body: some View {
        List {
            if !tracks.isEmpty { CollectionPlayButtons(tracks: tracks).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20)) }
            ForEach(tracks) { track in
                TrackRow(track: track) { player.play(track, in: tracks) }
                    .contextMenu { TrackActions(track: track) }
                    .swipeActions(edge: .trailing) { Button("删除", role: .destructive) { pendingDeletion = track } }
                    .swipeActions(edge: .leading) { Button { library.toggleFavorite(track.id) } label: { Label("收藏", systemImage: track.isFavorite ? "star.slash" : "star") }.tint(MusicDesign.accent) }
            }
        }.listStyle(.plain).navigationTitle(title).searchable(text: $query, prompt: "歌曲、艺人或专辑")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SongSortMenu(sort: $songSort, descending: $descending) } }
            .overlay { if tracks.isEmpty { MusicEmptyState(title: query.isEmpty ? "还没有歌曲" : "没有找到结果", message: query.isEmpty ? "这里会显示你导入的音乐。" : "试试其他歌曲、艺人或专辑名称。", symbol: query.isEmpty ? "music.note" : "magnifyingglass") } }
            .confirmationDialog("从资料库删除这首歌曲？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button("删除导入的音频副本", role: .destructive) { if let track = pendingDeletion { player.removeFromLibrary(track.id) }; pendingDeletion = nil }
            } message: { Text("原始文件不受影响。该歌曲也会从歌单中移除。") }
    }
}

struct ArtistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    private var artists: [String] { Set(library.tracks.flatMap { library.artists(for: $0) }).sorted().filter { query.isEmpty || $0.localizedStandardContains(query) } }
    var body: some View {
        List(artists, id: \.self) { artist in
            let tracks = library.tracks.filter { library.artists(for: $0).contains(artist) }
            NavigationLink { ArtistDetailView(artist: artist) } label: {
                HStack(spacing: 14) {
                    ArtworkView(track: tracks.first, radius: 100).frame(width: 54, height: 54)
                    Text(artist).font(.title3)
                    if library.snapshot.followedArtists.contains(artist) { Image(systemName: "star.fill").font(.caption).foregroundStyle(MusicDesign.accent) }
                }.padding(.vertical, 4)
            }
        }.listStyle(.plain).navigationTitle("艺人").searchable(text: $query, prompt: "搜索艺人")
            .overlay { if artists.isEmpty { MusicEmptyState(title: "没有找到艺人", message: "导入音频或尝试其他搜索词。", symbol: "music.mic") } }
    }
}

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var creating = false
    @State private var query = ""
    @State private var deleted: Playlist?
    private var playlists: [Playlist] { library.playlists.filter { query.isEmpty || $0.name.localizedStandardContains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        List {
            Button("新建歌单", systemImage: "plus") { creating = true }.frame(minHeight: 44)
            ForEach(playlists) { playlist in
                NavigationLink { PlaylistDetailView(id: playlist.id) } label: {
                    HStack(spacing: 12) {
                        PlaylistArtwork(tracks: library.tracks(for: playlist)).frame(width: 62, height: 62)
                        VStack(alignment: .leading, spacing: 4) { Text(playlist.name).font(.headline); Text("\(playlist.trackIDs.count) 首歌曲").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }
            }.onDelete { offsets in
                let values = offsets.map { playlists[$0] }
                for value in values { deleted = value; library.deletePlaylist(value.id) }
            }
        }.listStyle(.plain).navigationTitle("歌单")
            .searchable(text: $query, prompt: "搜索歌单")
            .safeAreaInset(edge: .bottom) {
                if let value = deleted {
                    HStack { Text("已删除“\(value.name)”").lineLimit(1); Spacer(); Button("撤销") { library.restorePlaylist(value); deleted = nil }; Button("完成") { deleted = nil } }
                        .font(.subheadline).padding().background(.regularMaterial)
                }
            }
            .sheet(isPresented: $creating) { PlaylistEditor() }
    }
}

struct PlaylistDetailView: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var editing = false
    @State private var query = ""
    @State private var sort = "手动顺序"
    @State private var descending = false
    private var playlist: Playlist? { library.playlists.first { $0.id == id } }
    private var tracks: [Track] {
        let values = playlist.map(library.tracks(for:)) ?? []
        return (SongSort(rawValue: sort)?.sorted(values, descending: descending) ?? values).filter { $0.matches(query) }
    }
    var body: some View {
        List {
            if let playlist { PlaylistArtwork(tracks: library.tracks(for: playlist)).frame(width: 200, height: 200).frame(maxWidth: .infinity).listRowSeparator(.hidden) }
            CollectionPlayButtons(tracks: tracks).listRowSeparator(.hidden)
            ForEach(tracks) { track in
                TrackRow(track: track) { player.play(track, in: tracks) }.contextMenu { TrackActions(track: track) }
            }.onDelete { offsets in
                guard var value = playlist else { return }
                let removed = Set(offsets.map { tracks[$0].id })
                value.trackIDs.removeAll { removed.contains($0) }; library.updatePlaylist(value)
            }.onMove { from, to in
                guard var value = playlist, query.isEmpty, sort == "手动顺序" else { return }
                value.trackIDs.move(fromOffsets: from, toOffset: to); library.updatePlaylist(value)
            }
        }.listStyle(.plain).navigationTitle(playlist?.name ?? "歌单")
            .searchable(text: $query, prompt: "搜索歌单中的歌曲")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SongSortMenu(sort: $sort, descending: $descending, manual: true) }
                ToolbarItem(placement: .topBarTrailing) { Button("编辑歌单", systemImage: "pencil") { editing = true } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }.sheet(isPresented: $editing) { PlaylistEditor(playlist: playlist) }
    }
}

struct SongSortMenu: View {
    @Binding var sort: String
    @Binding var descending: Bool
    var manual = false
    var body: some View {
        Menu {
            Picker("排序", selection: $sort) {
                if manual { Text("手动顺序").tag("手动顺序") }
                ForEach(SongSort.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }
            Toggle("降序", isOn: $descending)
        } label: { Label("排序", systemImage: "arrow.up.arrow.down") }
    }
}

struct ArtistDetailView: View {
    let artist: String
    @Environment(LibraryStore.self) private var library
    var body: some View {
        SongsView(title: artist, ids: library.tracks.filter { library.artists(for: $0).contains(artist) }.map(\.id))
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button(library.snapshot.followedArtists.contains(artist) ? "取消关注" : "关注", systemImage: library.snapshot.followedArtists.contains(artist) ? "star.fill" : "star") { library.toggleFollow(artist) }
            } }
    }
}

struct PlaylistArtwork: View {
    var tracks: [Track]
    var body: some View {
        if tracks.count < 4 { ArtworkView(track: tracks.first) }
        else {
            GeometryReader { proxy in
                VStack(spacing: 1) {
                    HStack(spacing: 1) { ArtworkView(track: tracks[0], radius: 0); ArtworkView(track: tracks[1], radius: 0) }
                    HStack(spacing: 1) { ArtworkView(track: tracks[2], radius: 0); ArtworkView(track: tracks[3], radius: 0) }
                }.frame(width: proxy.size.width, height: proxy.size.height).clipShape(RoundedRectangle(cornerRadius: 8))
            }.aspectRatio(1, contentMode: .fit)
        }
    }
}

struct PlaylistEditor: View {
    var playlist: Playlist? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Section { TextField("歌单名称", text: $name) }
                Section("选择歌曲") {
                    ForEach(library.tracks.filter { $0.matches(query) }) { track in
                        Button {
                            if selected.contains(track.id) { selected.remove(track.id) } else { selected.insert(track.id) }
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(track: track).frame(width: 42, height: 42)
                                VStack(alignment: .leading) { Text(track.title).foregroundStyle(.primary); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: selected.contains(track.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(MusicDesign.accent)
                            }
                        }.accessibilityAddTraits(selected.contains(track.id) ? .isSelected : [])
                    }
                }
            }.navigationTitle(playlist == nil ? "新建歌单" : "编辑歌单").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "搜索歌曲")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { save(); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear { name = playlist?.name ?? ""; selected = Set(playlist?.trackIDs ?? []) }
        }
    }
    private func save() {
        let existing = playlist?.trackIDs.filter { selected.contains($0) } ?? []
        let added = library.tracks.map(\.id).filter { selected.contains($0) && !existing.contains($0) }
        if var value = playlist { value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.trackIDs = existing + added; library.updatePlaylist(value) }
        else { library.createPlaylist(name, tracks: existing + added) }
    }
}
