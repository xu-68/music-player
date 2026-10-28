import FlamingoCore
import SwiftUI

struct AlbumDetailView: View {
    let albumKey: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @State private var titleOrder = false
    @State private var descending = false
    private var album: [Track] { library.albums.first { $0.first?.albumKey == albumKey } ?? [] }
    private var tracks: [Track] {
        let sorted = titleOrder ? SongSort.title.sorted(album, descending: descending) : descending ? Array(album.reversed()) : album
        return sorted
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                CollectionHero(track: album.first, title: album.first?.album ?? "专辑",
                               subtitle: album.first.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist } ?? "",
                               detail: "\(album.count) 首歌曲 · \(Int(album.reduce(0) { $0 + $1.duration }) / 60) 分钟", tracks: tracks)
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        TrackRow(track: track, showArtwork: false, number: track.trackNumber > 0 ? track.trackNumber : index + 1) { player.play(track, in: tracks) }
                        Menu { TrackActions(track: track) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                    }.padding(.horizontal, 22).contextMenu { TrackActions(track: track) }
                    Divider().padding(.leading, 58)
                }
            }.padding(.bottom, 24)
        }.navigationTitle(album.first?.album ?? "专辑").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(album.allSatisfy(\.isFavorite) ? "取消收藏专辑" : "收藏专辑", systemImage: album.allSatisfy(\.isFavorite) ? "star.fill" : "star") { library.setFavorite(album.map(\.id), value: !album.allSatisfy(\.isFavorite)) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("按标题排序", isOn: $titleOrder); Toggle("降序", isOn: $descending)
                        CollectionActions(tracks: album)
                    } label: { Image(systemName: "ellipsis") }
                }
            }
    }
}

struct ArtistDetailView: View {
    let artist: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    private var catalog: ArtistCatalog { ArtistCatalog.build(library.tracks, artist: artist, separators: AppPreferences.defaults.string(forKey: "artistSeparators") ?? ",") }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                CollectionHero(track: catalog.songs.first, title: artist, subtitle: "", detail: "\(catalog.songs.count) 首歌曲", tracks: catalog.songs, artist: artist)
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink { SongsView(title: artist, ids: catalog.songs.map(\.id)) } label: {
                        HStack { Text("歌曲").font(MusicTypography.title).foregroundStyle(Color.primary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                    ForEach(Array(catalog.songs.prefix(5))) { track in
                        TrackRow(track: track) { player.play(track, in: catalog.songs) }.contextMenu { TrackActions(track: track) }
                    }
                }.padding(.horizontal, 20)
                releases("专辑", groups: catalog.albums)
                releases("单曲与 EP", groups: catalog.singles)
                releases("参与的专辑", groups: catalog.featured)
            }.padding(.bottom, 24)
        }.navigationTitle(artist).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(library.snapshot.followedArtists.contains(artist) ? "取消关注" : "关注", systemImage: library.snapshot.followedArtists.contains(artist) ? "star.fill" : "star") { library.toggleFollow(artist) }
                }
                ToolbarItem(placement: .topBarTrailing) { Menu { CollectionActions(tracks: catalog.songs) } label: { Image(systemName: "ellipsis") } }
            }
    }
    @ViewBuilder private func releases(_ title: String, groups: [[Track]]) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(MusicTypography.title).padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(groups, id: \.first!.albumKey) { tracks in
                            if let track = tracks.first {
                                NavigationLink { AlbumDetailView(albumKey: track.albumKey) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ArtworkView(track: track).frame(width: 156, height: 156)
                                        Text(track.album).font(MusicTypography.body).foregroundStyle(Color.primary).lineLimit(1)
                                        if let year = track.year { Text(String(year.prefix(4))).font(MusicTypography.caption).foregroundStyle(.secondary) }
                                    }.frame(width: 156, alignment: .leading)
                                }.buttonStyle(PressStyle())
                            }
                        }
                    }.padding(.horizontal, 20)
                }
            }
        }
    }
}

struct CollectionHero: View {
    var track: Track?
    var title: String
    var subtitle: String
    var detail: String
    var tracks: [Track]
    var artist: String? = nil
    @Environment(PlayerStore.self) private var player
    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                if let image = ArtworkCache.shared.image(track?.artworkFilename) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else { Color(uiColor: .secondarySystemBackground) }
                LinearGradient(stops: [.init(color: .black.opacity(0.22), location: 0), .init(color: .black.opacity(0.46), location: 0.4), .init(color: Color(uiColor: .systemBackground).opacity(0.92), location: 0.85), .init(color: Color(uiColor: .systemBackground), location: 1)], startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: 8) {
                Text(title).font(MusicTypography.largeTitle).multilineTextAlignment(.center).foregroundStyle(.white).shadow(radius: 12)
                if !subtitle.isEmpty { Text(subtitle).font(.title3).foregroundStyle(.white.opacity(0.8)) }
                Text(detail).font(MusicTypography.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 32) {
                    Button { if let first = tracks.randomElement() { player.play(first, in: tracks, shuffled: true) } } label: { Image(systemName: "shuffle").font(.system(size: 27)).frame(width: 55, height: 55) }.accessibilityLabel("随机播放")
                    Button { if let first = tracks.first { player.play(first, in: tracks) } } label: { Image(systemName: "play.fill").font(.system(size: 29)).frame(width: 55, height: 55) }.accessibilityLabel("播放")

                }.foregroundStyle(Color.primary).buttonStyle(PressStyle()).padding(.top, 18).disabled(tracks.isEmpty)
            }.padding(24)
        }.frame(height: min(468, max(320, UIScreen.main.bounds.height * 0.52)))
    }
}

struct CollectionActions: View {
    var tracks: [Track]
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    var body: some View {
        Button("添加到歌单", systemImage: "text.badge.plus") { library.playlistAddition = PlaylistAddition(trackIDs: tracks.map(\.id)) }
        Button("接下来播放", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(tracks.map(\.id), next: true) }
        Button("最后播放", systemImage: "text.line.last.and.arrowtriangle.forward") { player.enqueue(tracks.map(\.id), next: false) }
    }
}
