import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: BrowserViewModel

    var body: some View {
        NavigationSplitView(sidebar: {
            VolumeSidebar(viewModel: viewModel)
        }, detail: {
            PhotoGridView(viewModel: viewModel)
        })
        .navigationSplitViewStyle(.balanced)
    }
}

struct VolumeSidebar: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        List(selection: $viewModel.selectedVolume) {
            Section("Removable Media") {
                if viewModel.filteredVolumes.isEmpty {
                    Text("Connect an SD card to get started")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.filteredVolumes) { volume in
                        VolumeRow(volume: volume)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: viewModel.refreshVolumes) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-scan mounted volumes")
            }
        }
    }
}

struct VolumeRow: View {
    let volume: Volume

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.iconName)
                .foregroundStyle(volume.isLikelyCameraCard ? .blue : .secondary)
            VStack(alignment: .leading) {
                Text(volume.displayName)
                Text(volume.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(volume)
    }
}

struct PhotoGridView: View {
    @ObservedObject var viewModel: BrowserViewModel

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        Group {
            if viewModel.isLoadingAssets {
                ProgressView("Loading photos…")
            } else if viewModel.photoAssets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    if let selectedVolume = viewModel.selectedVolume {
                        Text("No supported photos found on \(selectedVolume.displayName)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Select an SD card to preview photos")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.photoAssets) { asset in
                            ThumbnailCell(asset: asset)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            if let volume = viewModel.selectedVolume {
                Text(volume.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ThumbnailCell: View {
    let asset: PhotoAsset
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .foregroundStyle(.quaternary)
                .aspectRatio(4/3, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .clipped()

            Text(asset.filename)
                .font(.caption2)
                .lineLimit(1)
                .padding(4)
                .background(.thinMaterial, in: Capsule())
                .padding(6)
        }
        .contentShape(Rectangle())
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.thumbnail(for: asset.url, size: CGSize(width: 256, height: 256))
        }
    }
}
