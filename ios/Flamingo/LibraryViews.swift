import FlamingoCore
import SwiftUI

struct HomeView: View {
    var importAction: () -> Void
    var settingsAction: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var recommendationIDs: [UUID] = []
    private var suggestions: [Track] {
        recommendationIDs.compactMap(library.track)
    }
    var body: some View {
        Group {
            if library.tracks.isEmpty {
                MusicEmptyState(title: "音乐，就在这里", message: "把音乐移入“文件 → 我的 iPhone → music → Music”，然后扫描媒体库。",
                                symbol: "music.note.house", actionTitle: "扫描媒体库", action: importAction)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            shelf(title: "为你精选", tracks: suggestions, width: min(proxy.size.width * 0.72, 320), featured: true)
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("主页").font(MusicTypography.largeTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button("扫描媒体库", systemImage: "arrow.clockwise", action: importAction)
                    .labelStyle(.iconOnly).font(.system(size: 21))
                    .frame(width: 44, height: 44).disabled(library.importing)
                Button(action: settingsAction) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 30, weight: .regular))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("设置")
            }.tint(MusicDesign.accent)
                .padding(.leading, MusicDesign.pageInset).padding(.trailing, 13)
                .padding(.top, 8).padding(.bottom, 12)
                .background(Color(uiColor: .systemBackground))
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: library.tracks.map(\.id)) {
            if recommendationIDs.isEmpty || recommendationIDs.contains(where: { library.track($0) == nil }) { recommendationIDs = Array(library.tracks.shuffled().prefix(5).map(\.id)) }
        }
    }

    private func shelf(title: String, tracks: [Track], width: CGFloat, featured: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(MusicTypography.title).padding(.horizontal, MusicDesign.pageInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: featured ? 12 : 16) {
                    ForEach(tracks) { track in
                        Button { player.play(track, in: tracks) } label: {
                            VStack(alignment: featured ? .center : .leading, spacing: featured ? 0 : 6) {
                                ArtworkView(track: track, radius: featured ? 0 : 8).frame(width: width, height: width)
                                VStack(alignment: featured ? .center : .leading, spacing: 3) {
                                    Text(track.title).font(featured ? .headline : .body).lineLimit(1).foregroundStyle(featured ? Color.white : Color.primary)
                                    Text(track.artist).font(MusicTypography.subheadline).lineLimit(1).foregroundStyle(featured ? Color.white.opacity(0.6) : Color.secondary)
                                    if featured { Text(track.album).font(MusicTypography.subheadline).lineLimit(1).foregroundStyle(.white.opacity(0.6)) }
                                }.frame(maxWidth: .infinity, alignment: featured ? .center : .leading)
                                    .padding(featured ? 14 : 0)
                                    .background {
                                        if featured { ArtworkTint(track: track) }
                                    }
                            }.frame(width: width).background(featured ? Color(uiColor: .secondarySystemBackground) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: featured ? 16 : 0, style: .continuous))
                        }.buttonStyle(PressStyle()).contextMenu { TrackActions(track: track) }
                    }
                }.scrollTargetLayout().padding(.horizontal, MusicDesign.pageInset)
            }.scrollTargetBehavior(.viewAligned)
        }
    }
}

struct LibraryView: View {
    var importAction: () -> Void
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink { PlaylistsView() } label: { LibraryCategory(title: "歌单", symbol: "music.note.list") }.accessibilityIdentifier("library-playlists")
                NavigationLink { ArtistsView() } label: { LibraryCategory(title: "艺人", symbol: "music.mic") }.accessibilityIdentifier("library-artists")
                NavigationLink { AlbumsView() } label: { LibraryCategory(title: "专辑", symbol: "square.stack") }.accessibilityIdentifier("library-albums")
                NavigationLink { SongsView(title: "歌曲") } label: { LibraryCategory(title: "歌曲", symbol: "music.note") }.accessibilityIdentifier("library-songs")
                if library.tracks.isEmpty {
                    MusicEmptyState(title: "你的资料库", message: "把音乐移入“文件 → 我的 iPhone → music → Music”，然后扫描媒体库。", actionTitle: "扫描媒体库", action: importAction)
                        .frame(minHeight: 280)
                }
            }.padding(.horizontal, MusicDesign.pageInset).padding(.bottom, 24)
        }.buttonStyle(.plain).navigationTitle("资料库")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("扫描媒体库", systemImage: "arrow.clockwise", action: importAction).disabled(library.importing) } }
    }
}

private struct LibraryCategory: View {
    var title: String
    var symbol: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(MusicDesign.accent).frame(width: 30)
                Text(title).font(MusicTypography.title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(MusicTypography.compactHeadline).foregroundStyle(.tertiary)
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
                            Text(track.album).font(MusicTypography.body).foregroundStyle(.primary).lineLimit(1)
                            Text(track.albumArtist.isEmpty ? track.artist : track.albumArtist).font(MusicTypography.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.buttonStyle(PressStyle())
                }
            }
        }
    }
}

struct AlbumsView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ScrollView {
            AlbumGrid(albums: library.albums)
                .padding(MusicDesign.pageInset)
        }.navigationTitle("专辑")
            .overlay { if library.albums.isEmpty { MusicEmptyState(title: "还没有专辑", message: "导入带有专辑标签的音频后，会在这里自动整理。", symbol: "square.stack") } }
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
        }.font(MusicTypography.headline).buttonStyle(PressStyle())
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
    @State private var showingDeletion = false
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
                    .accessibilityIdentifier("song-\(track.filename)")
                    .contextMenu { TrackActions(track: track) }
                    .swipeActions(edge: .trailing) { Button("删除", role: .destructive) { pendingDeletion = track; showingDeletion = true }.accessibilityIdentifier("delete-song") }
                    .swipeActions(edge: .leading) { Button { library.toggleFavorite(track.id) } label: { Label("收藏", systemImage: track.isFavorite ? "star.slash" : "star") }.tint(MusicDesign.accent) }
            }
        }.listStyle(.plain).navigationTitle(title).searchable(text: $query, prompt: "歌曲、艺人或专辑")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SongSortMenu(sort: $songSort, descending: $descending) } }
            .overlay { if tracks.isEmpty { MusicEmptyState(title: query.isEmpty ? "还没有歌曲" : "没有找到结果", message: query.isEmpty ? "这里会显示你导入的音乐。" : "试试其他歌曲、艺人或专辑名称。", symbol: query.isEmpty ? "music.note" : "magnifyingglass") } }
            .confirmationDialog("删除这首歌曲及音乐源文件？", isPresented: $showingDeletion,
                                titleVisibility: .visible, presenting: pendingDeletion) { track in
                Button("删除歌曲及音乐文件", role: .destructive) { player.removeFromLibrary(track.id); pendingDeletion = nil }
            } message: { _ in Text("将同时删除 Music 文件夹中的音乐源文件，并从歌单中移除。此操作无法撤销。") }
    }
}

struct ArtistsView: View {
    @Environment(LibraryStore.self) private var library
    private var artists: [String] {
        Set(library.tracks.flatMap { library.artists(for: $0) }).sorted {
            let a = library.snapshot.followedArtists.contains($0), b = library.snapshot.followedArtists.contains($1)
            return a == b ? $0.localizedStandardCompare($1) == .orderedAscending : a
        }
    }
    var body: some View {
        List(artists, id: \.self) { artist in
            let tracks = library.tracks.filter { library.artists(for: $0).contains(artist) }
            NavigationLink { ArtistDetailView(artist: artist) } label: {
                HStack(spacing: 14) {
                    ArtworkView(track: tracks.first, radius: 100).frame(width: 54, height: 54)
                    Text(artist).font(.title3)
                    if library.snapshot.followedArtists.contains(artist) { Image(systemName: "star.fill").font(MusicTypography.caption).foregroundStyle(MusicDesign.accent) }
                }.padding(.vertical, 4)
            }
        }.listStyle(.plain).navigationTitle("艺人")
            .overlay { if artists.isEmpty { MusicEmptyState(title: "没有找到艺人", message: "导入带有艺人标签的音频后，会在这里自动整理。", symbol: "music.mic") } }
    }
}

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var creating = false
    @State private var deleted: Playlist?
    @State private var editingPlaylist: Playlist?
    @Environment(PlayerStore.self) private var player
    private var playlists: [Playlist] {
        library.playlists.sorted {
            if ($0.isPinned == true) != ($1.isPinned == true) { return $0.isPinned == true }
            if $0.isPinned == true { return ($0.pinOrder ?? .max) < ($1.pinOrder ?? .max) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var body: some View {
        List {
            Button("新建歌单", systemImage: "plus") { creating = true }.frame(minHeight: 44)
            NavigationLink { SongsView(title: "收藏的歌曲", favoritesOnly: true) } label: { Label("收藏的歌曲", systemImage: "star.fill") }
            ForEach(playlists) { playlist in
                NavigationLink { PlaylistDetailView(id: playlist.id) } label: {
                    HStack(spacing: 12) {
                        PlaylistArtwork(tracks: library.tracks(for: playlist), custom: playlist.artworkFilename).frame(width: 62, height: 62)
                        VStack(alignment: .leading, spacing: 4) { Text(playlist.name).font(MusicTypography.headline); Text("\(playlist.trackIDs.count) 首歌曲").font(MusicTypography.subheadline).foregroundStyle(.secondary) }
                        if playlist.isPinned == true { Spacer(); Image(systemName: "pin.fill").font(MusicTypography.caption).foregroundStyle(MusicDesign.accent) }
                    }.padding(.vertical, 5)
                }.contextMenu {
                    Button(playlist.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") { library.togglePin(playlist.id) }
                    Button("编辑歌单", systemImage: "pencil") { editingPlaylist = playlist }
                    Button("接下来播放", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(library.tracks(for: playlist).map(\.id), next: true) }
                    Button("添加到歌单", systemImage: "text.badge.plus") { library.playlistAddition = PlaylistAddition(trackIDs: playlist.trackIDs) }
                    Button("删除", role: .destructive) { deleted = playlist; library.deletePlaylist(playlist.id) }
                }.moveDisabled(playlist.isPinned != true)
            }.onDelete { offsets in
                let values = offsets.map { playlists[$0] }
                for value in values { deleted = value; library.deletePlaylist(value.id) }
            }.onMove { from, to in
                var pins = playlists.filter { $0.isPinned == true }
                let valid = IndexSet(from.filter { $0 < pins.count })
                pins.move(fromOffsets: valid, toOffset: min(to, pins.count)); library.reorderPins(pins.map(\.id))
            }
        }.listStyle(.plain).navigationTitle("歌单")
            .safeAreaInset(edge: .bottom) {
                if let value = deleted {
                    HStack { Text("已删除“\(value.name)”").lineLimit(1); Spacer(); Button("撤销") { library.restorePlaylist(value); deleted = nil }; Button("完成") { deleted = nil } }
                        .font(MusicTypography.subheadline).padding().background(.regularMaterial)
                }
            }
            .sheet(isPresented: $creating) { PlaylistEditor() }
            .sheet(item: $editingPlaylist) { PlaylistEditor(playlist: $0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }
}

private struct PlaylistTrackOccurrence: Identifiable {
    var position: Int
    var track: Track
    var id: Int { position }
}

struct PlaylistDetailView: View {
    let id: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var editing = false
    @State private var sort = "手动顺序"
    @State private var descending = false
    private var playlist: Playlist? { library.playlists.first { $0.id == id } }
    private var tracks: [Track] {
        let values = playlist.map(library.tracks(for:)) ?? []
        let sorted = sort == "最近添加" ? SongSort.modified.sorted(values, descending: descending) : SongSort(rawValue: sort)?.sorted(values, descending: descending) ?? (descending ? Array(values.reversed()) : values)
        return sorted
    }
    private var occurrences: [PlaylistTrackOccurrence] {
        let source = (playlist?.trackIDs ?? []).enumerated().compactMap { index, id in
            library.track(id).map { PlaylistTrackOccurrence(position: index, track: $0) }
        }
        var positions = Dictionary(grouping: source, by: { $0.track.id })
        return tracks.compactMap { track in
            guard var matches = positions[track.id], !matches.isEmpty else { return nil }
            let value = matches.removeFirst(); positions[track.id] = matches; return value
        }
    }
    var body: some View {
        List {
            if let playlist {
                PlaylistArtwork(tracks: library.tracks(for: playlist), custom: playlist.artworkFilename).frame(width: 230, height: 230).frame(maxWidth: .infinity).listRowSeparator(.hidden)
                if let description = playlist.description, !description.isEmpty { Text(description).font(MusicTypography.subheadline).foregroundStyle(.secondary).listRowSeparator(.hidden) }
            }
            CollectionPlayButtons(tracks: tracks).listRowSeparator(.hidden)
            ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
                TrackRow(track: occurrence.track) { player.play(occurrence.track, in: tracks, startingAt: index) }.contextMenu { TrackActions(track: occurrence.track) }
                    .moveDisabled(sort != "手动顺序" || descending)
            }.onDelete { offsets in
                guard var value = playlist else { return }
                let visible = occurrences
                let positions = IndexSet(offsets.map { visible[$0].position })
                value.trackIDs.remove(atOffsets: positions); library.updatePlaylist(value)
            }.onMove { from, to in
                guard var value = playlist, sort == "手动顺序", !descending else { return }
                let displayed = occurrences
                let positions = IndexSet(from.map { displayed[$0].position })
                let destination = to < displayed.count ? displayed[to].position : value.trackIDs.count
                value.trackIDs.move(fromOffsets: positions, toOffset: destination); library.updatePlaylist(value)
            }
        }.listStyle(.plain).navigationTitle(playlist?.name ?? "歌单")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SongSortMenu(sort: $sort, descending: $descending, manual: true) }
                ToolbarItem(placement: .topBarTrailing) { Button("编辑歌单", systemImage: "pencil") { editing = true } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let playlist {
                            Button(playlist.isPinned == true ? "取消置顶" : "置顶", systemImage: "pin") { library.togglePin(playlist.id) }
                            Button("接下来播放", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(library.tracks(for: playlist).map(\.id), next: true) }
                            Button("添加到歌单", systemImage: "text.badge.plus") { library.playlistAddition = PlaylistAddition(trackIDs: playlist.trackIDs) }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
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
                if manual { Text("手动顺序").tag("手动顺序"); Text("最近添加").tag("最近添加") }
                ForEach(SongSort.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }
            Toggle("降序", isOn: $descending)
        } label: { Label("排序", systemImage: "arrow.up.arrow.down") }
    }
}

