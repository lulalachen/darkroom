import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: BrowserViewModel

    var body: some View {
        NavigationSplitView(sidebar: {
            VolumeSidebar(viewModel: viewModel)
        }, detail: {
            BrowserDetailView(viewModel: viewModel)
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

struct BrowserDetailView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingAssets {
                ProgressView("Loading photos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.photoAssets.isEmpty {
                EmptyStateView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.visiblePhotoAssets.isEmpty {
                FilterEmptyStateView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    PhotoGridPane(viewModel: viewModel)
                        .frame(minWidth: 260)
                    PreviewPane(viewModel: viewModel)
                        .frame(minWidth: 360)
                }
            }

            Divider()
            ImportStatusBar(viewModel: viewModel)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Filter", selection: $viewModel.assetFilter) {
                    ForEach(BrowserViewModel.AssetFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Button("Gray (Z)") {
                    viewModel.tagSelectedAsKeep()
                }
                .keyboardShortcut("z", modifiers: [])

                Button("Red (X)") {
                    viewModel.tagSelectedAsReject()
                }
                .keyboardShortcut("x", modifiers: [])

                Button("Clear (C)") {
                    viewModel.clearSelectedTag()
                }
                .keyboardShortcut("c", modifiers: [])

                Button {
                    viewModel.importMarkedPhotos()
                } label: {
                    if viewModel.isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Import Gray (\(viewModel.keepCount))", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(viewModel.keepCount == 0 || viewModel.isImporting)
            }

            if let volume = viewModel.selectedVolume {
                ToolbarItem(placement: .automatic) {
                    Text(volume.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(blockedModifiers).isEmpty {
            return false
        }

        switch event.keyCode {
        case 123, 126:
            viewModel.selectPreviousAsset()
            return true
        case 124, 125:
            viewModel.selectNextAsset()
            return true
        case 6:
            viewModel.tagSelectedAsKeep()
            return true
        case 7:
            viewModel.tagSelectedAsReject()
            return true
        case 8:
            viewModel.clearSelectedTag()
            return true
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                viewModel.tagSelectedAsKeep()
                return true
            case "x":
                viewModel.tagSelectedAsReject()
                return true
            case "c":
                viewModel.clearSelectedTag()
                return true
            default:
                return false
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

struct FilterEmptyStateView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No photos in \(viewModel.assetFilter.title) filter")
                .foregroundStyle(.secondary)
            Button("Show All") {
                viewModel.assetFilter = .all
            }
        }
    }
}

struct EmptyStateView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
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
    }
}

struct PhotoGridPane: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns(for: geometry.size.width), spacing: 10) {
                        ForEach(viewModel.visiblePhotoAssets) { asset in
                            ThumbnailCell(
                                asset: asset,
                                isSelected: asset.id == viewModel.selectedAssetID,
                                tag: viewModel.tag(for: asset)
                            )
                            .id(asset.id)
                            .onTapGesture {
                                viewModel.select(asset)
                            }
                        }
                    }
                    .padding(12)
                }
                .onAppear {
                    scrollToSelection(with: proxy)
                }
                .onChange(of: viewModel.selectedAssetID) { _ in
                    scrollToSelection(with: proxy)
                }
            }
        }
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let minimumCellWidth = max(120, min(180, width / 2.6))
        return [GridItem(.adaptive(minimum: minimumCellWidth), spacing: 10)]
    }

    private func scrollToSelection(with proxy: ScrollViewProxy) {
        guard let selectedID = viewModel.selectedAssetID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }
}

struct PreviewPane: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset = viewModel.selectedAsset {
                ZStack {
                    Rectangle()
                        .foregroundStyle(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ProgressView("Loading preview...")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Text(asset.filename)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    TagChip(tag: viewModel.tag(for: asset))
                }

                Text("Shortcuts: Z = Gray, X = Red, C = Clear")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Gray (Z)") {
                        viewModel.tagSelectedAsKeep()
                    }
                    .keyboardShortcut("z", modifiers: [])

                    Button("Red (X)") {
                        viewModel.tagSelectedAsReject()
                    }
                    .keyboardShortcut("x", modifiers: [])

                    Button("Clear (C)") {
                        viewModel.clearSelectedTag()
                    }
                    .keyboardShortcut("c", modifiers: [])
                }
            } else {
                Text("Select a photo to preview")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .task(id: viewModel.selectedAssetID) {
            guard let asset = viewModel.selectedAsset else {
                previewImage = nil
                return
            }
            previewImage = await FullImageLoader.shared.image(for: asset.url)
        }
    }
}

struct ImportStatusBar: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Total: \(viewModel.photoAssets.count)")
            Text("Visible: \(viewModel.visiblePhotoAssets.count)")
            Text("Gray: \(viewModel.keepCount)")
            Text("Red: \(viewModel.rejectCount)")
            Spacer()
            if let importStatus = viewModel.importStatus {
                Text(importStatus)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.caption)
    }
}

struct TagChip: View {
    let tag: PhotoTag?

    var body: some View {
        switch tag {
        case .keep:
            Label("Gray", systemImage: PhotoTag.keep.symbolName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.gray.opacity(0.2), in: Capsule())
        case .reject:
            Label("Red", systemImage: PhotoTag.reject.symbolName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.2), in: Capsule())
        case .none:
            Label("Untagged", systemImage: "circle")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.gray.opacity(0.2), in: Capsule())
        }
    }
}

struct ThumbnailCell: View {
    let asset: PhotoAsset
    let isSelected: Bool
    let tag: PhotoTag?

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

            if let tag {
                Image(systemName: tag.symbolName)
                    .font(.title3)
                    .foregroundStyle(tag == .keep ? .gray : .red)
                    .padding(8)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.thumbnail(for: asset.url, size: CGSize(width: 320, height: 320))
        }
    }
}
