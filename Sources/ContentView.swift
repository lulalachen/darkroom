import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class GrayDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 1 }

    override func drawDivider(in rect: NSRect) {
        let dividerColor = NSColor.separatorColor.blended(withFraction: 0.35, of: .systemGray) ?? .systemGray
        dividerColor.setFill()
        rect.fill()
    }
}

struct GrayHSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    let leading: Leading
    let trailing: Trailing
    let initialLeadingFraction: CGFloat?
    let minLeadingWidth: CGFloat?
    let minTrailingWidth: CGFloat?
    let maxTrailingWidth: CGFloat?

    init(
        initialLeadingFraction: CGFloat? = nil,
        minLeadingWidth: CGFloat? = nil,
        minTrailingWidth: CGFloat? = nil,
        maxTrailingWidth: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
        self.initialLeadingFraction = initialLeadingFraction
        self.minLeadingWidth = minLeadingWidth
        self.minTrailingWidth = minTrailingWidth
        self.maxTrailingWidth = maxTrailingWidth
    }

    func makeNSView(context: Context) -> GrayDividerSplitView {
        let split = GrayDividerSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = context.coordinator
        split.addArrangedSubview(context.coordinator.leadingHosting)
        split.addArrangedSubview(context.coordinator.trailingHosting)
        return split
    }

    func updateNSView(_ nsView: GrayDividerSplitView, context: Context) {
        context.coordinator.leadingHosting.rootView = AnyView(leading)
        context.coordinator.trailingHosting.rootView = AnyView(trailing)
        context.coordinator.minLeadingWidth = minLeadingWidth
        context.coordinator.minTrailingWidth = minTrailingWidth
        context.coordinator.maxTrailingWidth = maxTrailingWidth
        guard !context.coordinator.didApplyInitialSplit,
              let fraction = initialLeadingFraction,
              nsView.bounds.width > 0 else { return }
        let clampedFraction = min(max(fraction, 0.1), 0.9)
        nsView.setPosition(nsView.bounds.width * clampedFraction, ofDividerAt: 0)
        context.coordinator.didApplyInitialSplit = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        let leadingHosting = NSHostingView(rootView: AnyView(EmptyView()))
        let trailingHosting = NSHostingView(rootView: AnyView(EmptyView()))
        var didApplyInitialSplit = false
        var minLeadingWidth: CGFloat?
        var minTrailingWidth: CGFloat?
        var maxTrailingWidth: CGFloat?

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard splitView.isVertical, dividerIndex == 0 else {
                return proposedPosition
            }

            let availableWidth = splitView.bounds.width
            let divider = splitView.dividerThickness
            var minimumPosition: CGFloat = 0
            var maximumPosition: CGFloat = max(0, availableWidth - divider)

            if let minLeadingWidth {
                minimumPosition = max(minimumPosition, minLeadingWidth)
            }
            if let minTrailingWidth {
                maximumPosition = min(maximumPosition, availableWidth - divider - minTrailingWidth)
            }
            if let maxTrailingWidth {
                minimumPosition = max(minimumPosition, availableWidth - divider - maxTrailingWidth)
            }

            if maximumPosition < minimumPosition {
                maximumPosition = minimumPosition
            }

            return min(max(proposedPosition, minimumPosition), maximumPosition)
        }
    }
}

struct GrayVSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let top: Top
    let bottom: Bottom

    init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
    }

    func makeNSView(context: Context) -> GrayDividerSplitView {
        let split = GrayDividerSplitView()
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(context.coordinator.topHosting)
        split.addArrangedSubview(context.coordinator.bottomHosting)
        return split
    }

    func updateNSView(_ nsView: GrayDividerSplitView, context: Context) {
        context.coordinator.topHosting.rootView = AnyView(top)
        context.coordinator.bottomHosting.rootView = AnyView(bottom)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let topHosting = NSHostingView(rootView: AnyView(EmptyView()))
        let bottomHosting = NSHostingView(rootView: AnyView(EmptyView()))
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: BrowserViewModel
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility, sidebar: {
            VolumeSidebar(viewModel: viewModel)
        }, detail: {
            BrowserDetailView(
                viewModel: viewModel,
                splitViewVisibility: $splitViewVisibility
            )
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
            Section {
                if viewModel.allLibraryVolumes.isEmpty {
                    Text("Add a library folder to browse photos")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.allLibraryVolumes) { volume in
                        VolumeRow(volume: volume)
                            .contextMenu {
                                if volume.isUserLibrary {
                                    Button("Remove Library") {
                                        viewModel.removeUserLibrary(volume)
                                    }
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Libraries")
                    Spacer()
                    Button(action: chooseLibraryFolder) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add library folder")
                    .accessibilityLabel("Add library folder")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add Library"
        panel.message = "Choose one or more folders that contain your photo folders."
        if panel.runModal() == .OK {
            viewModel.addUserLibraryFolders(panel.urls)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(volume.displayName), \(volume.subtitle)")
    }
}

struct BrowserDetailView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var splitViewVisibility: NavigationSplitViewVisibility
    @State private var keyMonitor: Any?
    @State private var showsExportQueue = false
    @State private var showsAdjustmentsPanel = false
    @State private var showsShortcutHelp = false
    @State private var showsToolbarShootNameHint = false
    @State private var thumbnailDisplayMode: PhotoGridPane.ThumbnailDisplayMode = .fit
    @State private var thumbnailColumns: Double = 4
    @FocusState private var toolbarShootNameFocused: Bool

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
                GrayHSplitView(initialLeadingFraction: 0.4) {
                    PhotoGridPane(
                        viewModel: viewModel,
                        thumbnailDisplayMode: $thumbnailDisplayMode,
                        thumbnailColumns: $thumbnailColumns
                    )
                        .frame(minWidth: 260)
                } trailing: {
                    PreviewPane(
                        viewModel: viewModel,
                        showsAdjustmentsPanel: $showsAdjustmentsPanel
                    )
                        .frame(minWidth: 360)
                }
            }

            ExportStatusBar(viewModel: viewModel)
            Divider()
        }
        .contentShape(Rectangle())
        .background(Color(NSColor.windowBackgroundColor))
        .simultaneousGesture(
            TapGesture().onEnded {
                clearTextInputFocus()
            }
        )
        .onAppear {
            installKeyMonitor()
            // Prevent toolbar text field from becoming first responder on initial load.
            DispatchQueue.main.async {
                clearTextInputFocus()
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .toolbar {
            if let volume = viewModel.selectedVolume {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 4) {
                        Image(systemName: volume.iconName)
                            .padding(.horizontal, 4)
                            .foregroundStyle(volume.isLikelyCameraCard ? .blue : .secondary)

                        Text(volume.url.path)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button(action: viewModel.refreshVolumes) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .padding(.horizontal, 4)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Re-scan mounted volumes")
                        .accessibilityLabel("Refresh volumes")
                    }
                    .help(volume.url.path)
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                FilterSegmentedControl(selected: $viewModel.assetFilter)
                    .frame(width: 300)
                    .padding(.horizontal, 4)
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    Text("Folder")
                        .padding(.horizontal, 4)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField(
                        "Folder name",
                        text: Binding(
                            get: { viewModel.exportDestination.shootName },
                            set: { viewModel.exportDestination.shootName = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .accessibilityLabel("Shoot name")
                    .focused($toolbarShootNameFocused)
                    .popover(isPresented: $showsToolbarShootNameHint, arrowEdge: .top) {
                        Text("Enter folder name before export.")
                            .padding(10)
                    }
                    .onChange(of: viewModel.exportDestination.shootName) { value in
                        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showsToolbarShootNameHint = false
                        }
                    }

                    Button {
                        runQuickExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .padding(.leading, 4)
                    .help("Export with current settings")
                    .accessibilityLabel("Export with current settings")
                    .disabled(viewModel.selectedAsset == nil || viewModel.isExporting)

                }
                .layoutPriority(2)
                .padding(.horizontal, 6)
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Customize Exports") {
                    showsExportQueue = true
                }
                .accessibilityLabel("Open export config")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showsShortcutHelp.toggle()
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("Keyboard shortcuts (Cmd+H)")
                .accessibilityLabel("Show keyboard shortcuts")
            }
        }
        .sheet(isPresented: $showsExportQueue) {
            ExportQueueSheet(viewModel: viewModel)
        }
        .overlay(alignment: .topTrailing) {
            if showsShortcutHelp {
                ShortcutHelpOverlay(
                    shortcutProfile: viewModel.shortcutProfile,
                    onClose: { showsShortcutHelp = false }
                )
                .padding(.top, 12)
                .padding(.trailing, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let banner = viewModel.exportCompletionBanner {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Complete")
                            .font(.subheadline.weight(.semibold))
                        Text("\(banner.exportedCount) photo(s) exported")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("Open") {
                        viewModel.openExportCompletionFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        viewModel.dismissExportCompletionBanner()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(.trailing, 14)
                .padding(.bottom, 36)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if isTextInputFocused() { return false }

        if handleCommandShortcut(event) {
            return true
        }

        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(blockedModifiers).isEmpty {
            return false
        }

        switch event.keyCode {
        case 123:
            viewModel.selectLeftAsset()
            return true
        case 124:
            viewModel.selectRightAsset()
            return true
        case 126:
            viewModel.selectUpAsset()
            return true
        case 125:
            viewModel.selectDownAsset()
            return true
        default:
            if let key = event.charactersIgnoringModifiers?.lowercased(), key == "p" {
                togglePreviewMode()
                return true
            }
            if viewModel.handleTagHotkey(event.charactersIgnoringModifiers) {
                return true
            }
            return false
        }
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "h":
            if event.modifierFlags.contains(.shift) { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                showsShortcutHelp.toggle()
            }
            return true
        case "s":
            if event.modifierFlags.contains(.shift) {
                return false
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                splitViewVisibility = (splitViewVisibility == .all) ? .detailOnly : .all
            }
            return true
        case "1":
            if event.modifierFlags.contains(.shift) { return false }
            viewModel.assetFilter = .all
            return true
        case "2":
            if event.modifierFlags.contains(.shift) { return false }
            viewModel.assetFilter = .keep
            return true
        case "3":
            if event.modifierFlags.contains(.shift) { return false }
            viewModel.assetFilter = .reject
            return true
        case "4":
            if event.modifierFlags.contains(.shift) { return false }
            viewModel.assetFilter = .untagged
            return true
        case "e":
            if event.modifierFlags.contains(.shift) {
                return false
            }
            showsAdjustmentsPanel.toggle()
            return true
        case "a":
            if event.modifierFlags.contains(.shift) {
                return false
            }
            viewModel.selectAllVisibleAssets()
            return true
        case "=", "+":
            increasePreviewSize()
            return true
        case "-", "_":
            decreasePreviewSize()
            return true
        case "0":
            resetPreviewSize()
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                guard viewModel.canRedoTagEdit else { return false }
                viewModel.redoTagEdit()
            } else {
                guard viewModel.canUndoTagEdit else { return false }
                viewModel.undoTagEdit()
            }
            return true
        default:
            return false
        }
    }

    private func runQuickExport() {
        guard isFolderNameValid else {
            showToolbarShootNamePrompt()
            return
        }
        viewModel.enqueueGreenTaggedForExport()
        viewModel.startExportQueue()
    }

    private var isFolderNameValid: Bool {
        !viewModel.exportDestination.shootName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func showToolbarShootNamePrompt() {
        showsToolbarShootNameHint = true
        toolbarShootNameFocused = true
    }

    private func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        if let textView = responder as? NSTextView {
            return textView.isFieldEditor || textView.isEditable
        }
        return responder is NSTextField
    }

    private func clearTextInputFocus() {
        toolbarShootNameFocused = false
        showsToolbarShootNameHint = false
        NSApp.keyWindow?.makeFirstResponder(nil)
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

    private func togglePreviewMode() {
        thumbnailDisplayMode = (thumbnailDisplayMode == .fit) ? .aspectRatio : .fit
    }

    private func increasePreviewSize() {
        thumbnailColumns = max(1, thumbnailColumns.rounded() - 1)
    }

    private func decreasePreviewSize() {
        thumbnailColumns = thumbnailColumns.rounded() + 1
    }

    private func resetPreviewSize() {
        thumbnailColumns = 4
    }
}

struct FilterSegmentedControl: View {
    @Binding var selected: BrowserViewModel.AssetFilter

    private var items: [(filter: BrowserViewModel.AssetFilter, shortcut: String)] {
        [
            (.all, "Cmd+1"),
            (.keep, "Cmd+2"),
            (.reject, "Cmd+3"),
            (.untagged, "Cmd+4")
        ]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.filter) { item in
                Button {
                    selected = item.filter
                } label: {
                    Text(item.filter.title)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(selected == item.filter ? Color.secondary.opacity(0.24) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("\(item.filter.title) (\(item.shortcut))")
            }
        }
        .help("Filters: Cmd+1 All, Cmd+2 Selected, Cmd+3 Rejected, Cmd+4 Untagged")
    }
}

struct ShortcutHelpOverlay: View {
    let shortcutProfile: KeyboardShortcutProfile
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            Group {
                shortcutLine("Cmd+1", "Filter: All")
                shortcutLine("Cmd+2", "Filter: Selected")
                shortcutLine("Cmd+3", "Filter: Rejected")
                shortcutLine("Cmd+4", "Filter: Untagged")
                shortcutLine("Cmd+A", "Select all visible photos")
                shortcutLine("Cmd++ / Cmd+-", "Increase / decrease preview size")
                shortcutLine("Cmd+0", "Reset preview size")
                shortcutLine("Cmd+E", "Toggle adjustments panel")
                shortcutLine("Cmd+S", "Show sidebar")
                shortcutLine("Cmd+H", "Toggle this help")
                shortcutLine("P", "Toggle preview mode")
                shortcutLine("Cmd+Z", "Undo tag edit")
                shortcutLine("Cmd+Shift+Z", "Redo tag edit")
                shortcutLine("Arrow keys", "Move selection")
                shortcutLine("Shift+Click", "Range select")
                shortcutLine("R", "Cycle star rating")
                switch shortcutProfile {
                case .classicZXC:
                    shortcutLine("Z / X / C", "Tag Selected / Rejected / Clear")
                case .numeric120:
                    shortcutLine("1 / 2 / 0", "Tag Selected / Rejected / Clear")
                }
            }
            .font(.subheadline)
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    @ViewBuilder
    private func shortcutLine(_ key: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .frame(width: 110, alignment: .leading)
            Text(action)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
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
                Text("Select an SD card or add a library folder")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PhotoGridPane: View {
    enum ThumbnailDisplayMode: String, CaseIterable, Identifiable {
        case aspectRatio = "Aspect ratio"
        case fit = "Fit"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: BrowserViewModel
    private let spacing: CGFloat = 10
    private let horizontalPadding: CGFloat = 24
    private let sectionSpacing: CGFloat = 12
    @Binding var thumbnailDisplayMode: ThumbnailDisplayMode
    @Binding var thumbnailColumns: Double
    @State private var lastGridWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: sectionSpacing, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedAssets) { section in
                                Section {
                                    LazyVGrid(columns: columns(for: geometry.size.width), spacing: spacing) {
                                        ForEach(section.assets) { asset in
                                            ThumbnailCell(
                                                asset: asset,
                                                isSelected: viewModel.selectedAssetIDs.contains(asset.id),
                                                tag: viewModel.tag(for: asset),
                                                rating: viewModel.rating(for: asset),
                                                displayMode: thumbnailDisplayMode
                                            )
                                            .id(asset.id)
                                            .onTapGesture {
                                                let flags = NSApp.currentEvent?.modifierFlags ?? []
                                                if flags.contains(.shift) {
                                                    viewModel.selectRange(to: asset)
                                                } else {
                                                    viewModel.select(asset)
                                                }
                                            }
                                            .contextMenu {
                                                Button("Tag Selected") {
                                                    viewModel.select(asset)
                                                    viewModel.tagSelectedAsKeep()
                                                }
                                                Button("Tag Rejected") {
                                                    viewModel.select(asset)
                                                    viewModel.tagSelectedAsReject()
                                                }
                                                Button("Clear Tag") {
                                                    viewModel.select(asset)
                                                    viewModel.clearSelectedTag()
                                                }
                                                Divider()
                                                Button("Queue For Export") {
                                                    viewModel.select(asset)
                                                    viewModel.enqueueSelectedForExport()
                                                }
                                                Divider()
                                                Menu("Rating") {
                                                    ForEach(1...5, id: \.self) { rating in
                                                        Button(String(repeating: "★", count: rating)) {
                                                            viewModel.select(asset)
                                                            viewModel.setSelectedRating(rating)
                                                        }
                                                    }
                                                    Button("Clear Rating") {
                                                        viewModel.select(asset)
                                                        viewModel.clearSelectedRating()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                header: {
                                    sectionHeader(for: section.date)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .onAppear {
                        lastGridWidth = geometry.size.width
                        clampColumnsToRange()
                        updateGridConfig(for: geometry.size.width)
                        scrollToSelection(with: proxy)
                    }
                    .onChange(of: viewModel.selectedAssetID) { _ in
                        scrollToSelection(with: proxy)
                    }
                    .onChange(of: geometry.size.width) { newWidth in
                        lastGridWidth = newWidth
                        clampColumnsToRange()
                        updateGridConfig(for: newWidth)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Picker("Preview", selection: $thumbnailDisplayMode) {
                    ForEach(ThumbnailDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Text("Size")
                    .font(.body.weight(.bold))

                Slider(value: sizeSliderBinding, in: columnSliderRange)
                .frame(minWidth: 140, maxWidth: 220)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: thumbnailColumns) { _ in
                // Keep the control discrete by row count while preserving a smooth slider track.
                thumbnailColumns = thumbnailColumns.rounded()
                if lastGridWidth > 0 {
                    updateGridConfig(for: lastGridWidth)
                }
            }
        }
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let count = currentColumnCount(for: width)
        return Array(repeating: GridItem(.flexible(minimum: 80), spacing: spacing), count: count)
    }

    private var columnSliderRange: ClosedRange<Double> {
        let maxColumns = maxColumnsForWidth(lastGridWidth)
        return 1...Double(maxColumns)
    }

    private func clampColumnsToRange() {
        let range = columnSliderRange
        if thumbnailColumns < range.lowerBound {
            thumbnailColumns = range.lowerBound
        } else if thumbnailColumns > range.upperBound {
            thumbnailColumns = range.upperBound
        }
    }

    private func scrollToSelection(with proxy: ScrollViewProxy) {
        guard let selectedID = viewModel.selectedAssetID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }

    private func updateGridConfig(for width: CGFloat) {
        viewModel.setGridColumnCount(currentColumnCount(for: width))
    }

    private func currentColumnCount(for width: CGFloat) -> Int {
        let maxColumns = maxColumnsForWidth(width)
        return min(max(1, Int(thumbnailColumns.rounded())), maxColumns)
    }

    private func maxColumnsForWidth(_ width: CGFloat) -> Int {
        let minCellWidth: CGFloat = 110
        let availableWidth = max(0, width - horizontalPadding)
        let count = Int((availableWidth + spacing) / (minCellWidth + spacing))
        return max(1, count)
    }

    private var sizeSliderBinding: Binding<Double> {
        Binding(
            get: {
                invertedSliderValue(for: thumbnailColumns, in: columnSliderRange)
            },
            set: { newValue in
                thumbnailColumns = invertedSliderValue(for: newValue, in: columnSliderRange)
            }
        )
    }

    private func invertedSliderValue(for value: Double, in range: ClosedRange<Double>) -> Double {
        range.upperBound - (value - range.lowerBound)
    }

    private var groupedAssets: [PhotoSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.visiblePhotoAssets) { asset in
            asset.captureDate.map { calendar.startOfDay(for: $0) }
        }

        let orderedDates = grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (left?, right?):
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return false
            }
        }

        return orderedDates.map { date in
            let assets = (grouped[date] ?? []).sorted { lhs, rhs in
                switch (lhs.captureDate, rhs.captureDate) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate < rightDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
                }
            }
            return PhotoSection(date: date, assets: assets)
        }
    }

    @ViewBuilder
    private func sectionHeader(for date: Date?) -> some View {
        Text(Self.sectionDateFormatter.string(from: date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(.thinMaterial)
    }

    private struct PhotoSection: Identifiable {
        let date: Date?
        let assets: [PhotoAsset]

        var id: String {
            guard let date else { return "unknown-date" }
            return String(Int(date.timeIntervalSinceReferenceDate))
        }
    }

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension DateFormatter {
    func string(from date: Date?) -> String {
        guard let date else { return "Unknown Date" }
        return string(from: date)
    }
}

struct PreviewPane: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var showsAdjustmentsPanel: Bool
    @State private var sourceImage: NSImage?
    @State private var sourcePixelSize: CGSize = .zero
    @State private var previewImage: NSImage?
    @State private var settings: AdjustmentSettings = .default
    @State private var presets: [AdjustmentPreset] = AdjustmentPreset.builtIns
    @State private var selectedPresetID: AdjustmentPreset.ID?
    @State private var savePresetName = ""
    @State private var showSavePresetPrompt = false
    @State private var undoStack: [AdjustmentSettings] = []
    @State private var redoStack: [AdjustmentSettings] = []
    @State private var luts: [LUTRecord] = []
    @State private var lutImportError: String?
    @State private var versionBSnapshot: AdjustmentSettings?
    @State private var showOriginal = false
    @State private var previewZoom: CGFloat = 1
    @GestureState private var magnifyScale: CGFloat = 1
    @GestureState private var gestureRotation: Angle = .zero
    @State private var renderTask: Task<Void, Never>?
    @State private var persistTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.selectedAsset != nil {
                if showsAdjustmentsPanel {
                    GrayHSplitView(
                        minLeadingWidth: 280,
                        minTrailingWidth: 260,
                        maxTrailingWidth: 420
                    ) {
                        previewSection
                            .padding(.trailing, 6)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } trailing: {
                        adjustmentsSection
                            .padding(.leading, 6)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 420)
                            .layoutPriority(1)
                    }
                } else {
                    previewSection
                }
            } else {
                Text("Select a photo to preview")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .alert("Save Preset", isPresented: $showSavePresetPrompt) {
            TextField("Preset name", text: $savePresetName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let name = savePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    await AdjustmentStore.shared.savePreset(name: name, settings: settings)
                    await reloadPresetsAndSelection(named: name)
                }
            }
        }
        .alert("LUT Import Failed", isPresented: Binding(
            get: { lutImportError != nil },
            set: { newValue in
                if !newValue {
                    lutImportError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lutImportError ?? "Unknown error")
        }
        .task(id: viewModel.selectedAssetID) {
            renderTask?.cancel()
            persistTask?.cancel()
            guard let asset = viewModel.selectedAsset else {
                sourceImage = nil
                sourcePixelSize = .zero
                previewImage = nil
                settings = .default
                presets = AdjustmentPreset.builtIns
                luts = []
                selectedPresetID = nil
                undoStack = []
                redoStack = []
                versionBSnapshot = nil
                previewZoom = 1
                return
            }
            async let loadedImage = FullImageLoader.shared.image(for: asset.url)
            async let loadedSettings = AdjustmentStore.shared.adjustment(for: asset.url.path)
            async let loadedPresets = AdjustmentStore.shared.presets()
            async let loadedLUTs = LUTLibrary.shared.allLUTs()
            async let versionBBookmark = AdjustmentStore.shared.bookmark(named: "Version B", for: asset.url.path)
            let (image, storedSettings, availablePresets, availableLUTs, versionB) = await (loadedImage, loadedSettings, loadedPresets, loadedLUTs, versionBBookmark)
            sourcePixelSize = image?.size ?? .zero
            sourceImage = Self.downscaledPreviewImage(from: image, maxLongEdge: 2048)
            settings = storedSettings
            presets = availablePresets
            luts = availableLUTs
            selectedPresetID = availablePresets.first(where: { $0.settings == storedSettings })?.id
            undoStack = []
            redoStack = []
            versionBSnapshot = versionB?.settings
            showOriginal = false
            previewZoom = 1
            schedulePreviewRender()
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset = viewModel.selectedAsset {
                HStack(spacing: 8) {
                    Text(asset.filename)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.quaternary.opacity(0.25), in: Capsule())

                    if let tag = viewModel.tag(for: asset) {
                        PreviewTagBadge(tag: tag)
                            .frame(height: 30)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(selectButtonTitle) {
                            viewModel.tagSelectedAsKeep()
                        }

                        Button(rejectButtonTitle) {
                            viewModel.tagSelectedAsReject()
                        }

                        Button(clearButtonTitle) {
                            viewModel.clearSelectedTag()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                ZStack {
                    Rectangle()
                        .foregroundStyle(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(max(1, min(8, previewZoom * magnifyScale)))
                            .rotationEffect(gestureRotation)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .gesture(previewGesture)
                    } else {
                        ProgressView("Loading preview...")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !showsAdjustmentsPanel {
                    HStack {
                        Spacer()
                        Button {
                            showsAdjustmentsPanel = true
                        } label: {
                            Image(systemName: "sidebar.right")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show adjustments (⌘E)")
                        .accessibilityLabel("Show adjustments")
                        Spacer()
                    }
                }
            }
        }
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Adjustments", systemImage: "slider.horizontal.3")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Toggle(showOriginal ? "Original" : "Adjusted", isOn: $showOriginal)
                        .toggleStyle(.switch)
                        .onChange(of: showOriginal) { _ in
                            schedulePreviewRender()
                        }
                }

                HStack(spacing: 8) {
                    Button("Undo") {
                        undo()
                    }
                    .disabled(undoStack.isEmpty)

                    Button("Redo") {
                        redo()
                    }
                    .disabled(redoStack.isEmpty)

                    Button("Reset") {
                        applySettings(.default)
                    }

                    Button("Save Version B") {
                        versionBSnapshot = settings
                        if let asset = viewModel.selectedAsset {
                            Task {
                                await AdjustmentStore.shared.saveBookmark(
                                    name: "Version B",
                                    settings: settings,
                                    for: asset.url.path
                                )
                            }
                        }
                    }

                    Button("Apply Version B") {
                        if let versionBSnapshot {
                            applySettings(versionBSnapshot)
                        }
                    }
                    .disabled(versionBSnapshot == nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Picker("Preset", selection: $selectedPresetID) {
                    Text("Custom").tag(Optional<UUID>(nil))
                    ForEach(presets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .frame(maxWidth: 260)
                .onChange(of: selectedPresetID) { id in
                    guard let id, let preset = presets.first(where: { $0.id == id }) else { return }
                    applySettings(preset.settings)
                }

                Button("Save Preset") {
                    savePresetName = ""
                    showSavePresetPrompt = true
                }
                if let id = selectedPresetID,
                   let preset = presets.first(where: { $0.id == id }),
                   !preset.isBuiltIn {
                    Button("Delete Preset") {
                        Task {
                            await AdjustmentStore.shared.deleteUserPreset(id: id)
                            await reloadPresetsAndSelection()
                        }
                    }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

            ScrollView {
                VStack(spacing: 14) {
                    adjustmentGroup(title: "Exposure") {
                        adjustmentSlider(
                            title: "Exposure",
                            value: Binding(
                                get: { settings.exposureEV },
                                set: { newValue in
                                    updateSettings { $0.exposureEV = min(max(newValue, -3), 3) }
                                }
                            ),
                            range: -3...3,
                            step: 0.1,
                            valueText: String(format: "%.1f EV", settings.exposureEV)
                        )
                        adjustmentSlider(
                            title: "Contrast",
                            value: Binding(
                                get: { settings.contrast },
                                set: { newValue in
                                    updateSettings { $0.contrast = min(max(newValue, 0.6), 1.8) }
                                }
                            ),
                            range: 0.6...1.8,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.contrast)
                        )
                        adjustmentSlider(
                            title: "Highlights Recover",
                            value: Binding(
                                get: { settings.highlightsRecover },
                                set: { newValue in
                                    updateSettings { $0.highlightsRecover = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.highlightsRecover)
                        )
                        adjustmentSlider(
                            title: "Shadows Lift",
                            value: Binding(
                                get: { settings.shadowsLift },
                                set: { newValue in
                                    updateSettings { $0.shadowsLift = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.shadowsLift)
                        )
                    }

                    Divider()

                    adjustmentGroup(title: "White Balance") {
                        adjustmentSlider(
                            title: "Temp (Mired)",
                            value: Binding(
                                get: { settings.temperatureMired },
                                set: { newValue in
                                    updateSettings { $0.temperatureMired = min(max(newValue, -150), 150) }
                                }
                            ),
                            range: -150...150,
                            step: 1,
                            valueText: String(format: "%.0f", settings.temperatureMired)
                        )
                        adjustmentSlider(
                            title: "Tint",
                            value: Binding(
                                get: { settings.tintShift },
                                set: { newValue in
                                    updateSettings { $0.tintShift = min(max(newValue, -150), 150) }
                                }
                            ),
                            range: -150...150,
                            step: 1,
                            valueText: String(format: "%.0f", settings.tintShift)
                        )
                    }

                    Divider()

                    adjustmentGroup(title: "Color") {
                        adjustmentSlider(
                            title: "Vibrance",
                            value: Binding(
                                get: { settings.vibrance },
                                set: { newValue in
                                    updateSettings { $0.vibrance = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.vibrance)
                        )
                        adjustmentSlider(
                            title: "Saturation",
                            value: Binding(
                                get: { settings.saturation },
                                set: { newValue in
                                    updateSettings { $0.saturation = min(max(newValue, 0), 2) }
                                }
                            ),
                            range: 0...2,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.saturation)
                        )
                    }

                    Divider()

                    adjustmentGroup(title: "Creative") {
                        adjustmentSlider(
                            title: "Vintage Amount",
                            value: Binding(
                                get: { settings.vintageAmount },
                                set: { newValue in
                                    updateSettings { $0.vintageAmount = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.vintageAmount)
                        )
                        adjustmentSlider(
                            title: "Fade",
                            value: Binding(
                                get: { settings.fade },
                                set: { newValue in
                                    updateSettings { $0.fade = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.fade)
                        )
                        adjustmentSlider(
                            title: "Warm Highlights",
                            value: Binding(
                                get: { settings.splitToneWarmHighlights },
                                set: { newValue in
                                    updateSettings { $0.splitToneWarmHighlights = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.splitToneWarmHighlights)
                        )
                        adjustmentSlider(
                            title: "Cool Shadows",
                            value: Binding(
                                get: { settings.splitToneCoolShadows },
                                set: { newValue in
                                    updateSettings { $0.splitToneCoolShadows = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.splitToneCoolShadows)
                        )
                    }

                    Divider()

                    adjustmentGroup(title: "Effects") {
                        adjustmentSlider(
                            title: "Grain Amount",
                            value: Binding(
                                get: { settings.grainAmount },
                                set: { newValue in
                                    updateSettings { $0.grainAmount = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.grainAmount)
                        )
                        adjustmentSlider(
                            title: "Grain Size",
                            value: Binding(
                                get: { settings.grainSize },
                                set: { newValue in
                                    updateSettings { $0.grainSize = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.grainSize)
                        )
                        adjustmentSlider(
                            title: "Vignette",
                            value: Binding(
                                get: { settings.vignetteAmount },
                                set: { newValue in
                                    updateSettings { $0.vignetteAmount = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.vignetteAmount)
                        )
                        adjustmentSlider(
                            title: "Contrast Soft",
                            value: Binding(
                                get: { settings.contrastSoftening },
                                set: { newValue in
                                    updateSettings { $0.contrastSoftening = min(max(newValue, 0), 1) }
                                }
                            ),
                            range: 0...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.contrastSoftening)
                        )
                    }

                    Divider()

                    adjustmentGroup(title: "LUT") {
                        lutSection
                    }

                    Divider()

                    adjustmentGroup(title: "Geometry") {
                        adjustmentSlider(
                            title: "Rotate",
                            value: Binding(
                                get: { settings.rotateDegrees },
                                set: { newValue in
                                    updateSettings { $0.rotateDegrees = min(max(newValue, -180), 180) }
                                }
                            ),
                            range: -180...180,
                            step: 0.25,
                            valueText: String(format: "%.1f°", settings.rotateDegrees)
                        )
                        adjustmentSlider(
                            title: "Straighten",
                            value: Binding(
                                get: { settings.straightenDegrees },
                                set: { newValue in
                                    updateSettings { $0.straightenDegrees = min(max(newValue, -15), 15) }
                                }
                            ),
                            range: -15...15,
                            step: 0.1,
                            valueText: String(format: "%.1f°", settings.straightenDegrees)
                        )
                        adjustmentSlider(
                            title: "Crop Scale",
                            value: Binding(
                                get: { settings.cropScale },
                                set: { newValue in
                                    updateSettings { $0.cropScale = min(max(newValue, 0.4), 1) }
                                }
                            ),
                            range: 0.4...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.cropScale)
                        )
                        adjustmentSlider(
                            title: "Crop X",
                            value: Binding(
                                get: { settings.cropOffsetX },
                                set: { newValue in
                                    updateSettings { $0.cropOffsetX = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.cropOffsetX)
                        )
                        adjustmentSlider(
                            title: "Crop Y",
                            value: Binding(
                                get: { settings.cropOffsetY },
                                set: { newValue in
                                    updateSettings { $0.cropOffsetY = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.cropOffsetY)
                        )
                    }
                }
            }

        }
        .padding(.horizontal, 10)
    }

    private var selectButtonTitle: String {
        switch viewModel.shortcutProfile {
        case .classicZXC:
            return "Select (Z)"
        case .numeric120:
            return "Select (1)"
        }
    }

    private var rejectButtonTitle: String {
        switch viewModel.shortcutProfile {
        case .classicZXC:
            return "Reject (X)"
        case .numeric120:
            return "Reject (2)"
        }
    }

    private var clearButtonTitle: String {
        switch viewModel.shortcutProfile {
        case .classicZXC:
            return "Clear (C)"
        case .numeric120:
            return "Clear (0)"
        }
    }

    @ViewBuilder
    private var lutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker(
                    "LUT",
                    selection: Binding(
                        get: { settings.lutID ?? "__none__" },
                        set: { selectedID in
                            updateSettings { draft in
                                draft.lutID = (selectedID == "__none__") ? nil : selectedID
                            }
                        }
                    )
                ) {
                    Text("None").tag("__none__")
                    ForEach(luts) { lut in
                        Text(lut.name).tag(lut.id)
                    }
                }
                .frame(maxWidth: .infinity)
                Button("Import") {
                    importLUT()
                }
            }
            adjustmentSlider(
                title: "LUT Intensity",
                value: Binding(
                    get: { settings.lutIntensity },
                    set: { newValue in
                        updateSettings { $0.lutIntensity = min(max(newValue, 0), 1) }
                    }
                ),
                range: 0...1,
                step: 0.01,
                valueText: String(format: "%.2f", settings.lutIntensity)
            )
            if let lutID = settings.lutID, !luts.contains(where: { $0.id == lutID }) {
                Text("Selected LUT is missing and will be skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func schedulePreviewRender() {
        renderTask?.cancel()
        guard let sourceImage else {
            previewImage = nil
            return
        }
        if showOriginal {
            previewImage = sourceImage
            return
        }

        let currentSettings = settings
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if Task.isCancelled {
                return
            }
            let adjusted = await AdjustmentEngine.shared.apply(currentSettings, to: sourceImage)
            if Task.isCancelled {
                return
            }
            await MainActor.run {
                self.previewImage = adjusted
            }
        }
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "cube")].compactMap { $0 }
        panel.prompt = "Import LUT"
        panel.message = "Choose a .cube file to import."
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        Task {
            do {
                _ = try await LUTLibrary.shared.importCube(from: sourceURL)
                let updated = await LUTLibrary.shared.allLUTs()
                await MainActor.run {
                    luts = updated
                }
            } catch {
                await MainActor.run {
                    lutImportError = error.localizedDescription
                }
            }
        }
    }

    private func updateSettings(_ update: (inout AdjustmentSettings) -> Void) {
        var proposed = settings
        update(&proposed)
        guard proposed != settings else { return }
        undoStack.append(settings)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        redoStack = []
        settings = proposed
        selectedPresetID = presets.first(where: { $0.settings == settings })?.id
        schedulePreviewRender()
        schedulePersist()
    }

    private func applySettings(_ value: AdjustmentSettings) {
        guard value != settings else { return }
        undoStack.append(settings)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        redoStack = []
        settings = value
        selectedPresetID = presets.first(where: { $0.settings == settings })?.id
        schedulePreviewRender()
        schedulePersist()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(settings)
        settings = previous
        selectedPresetID = presets.first(where: { $0.settings == settings })?.id
        schedulePreviewRender()
        schedulePersist()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(settings)
        settings = next
        selectedPresetID = presets.first(where: { $0.settings == settings })?.id
        schedulePreviewRender()
        schedulePersist()
    }

    private func schedulePersist() {
        persistTask?.cancel()
        guard let asset = viewModel.selectedAsset else { return }
        let assetPath = asset.url.path
        let current = settings
        let currentSourceSize = sourcePixelSize
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            await AdjustmentStore.shared.saveAdjustment(current, for: assetPath)
            await AdjustmentStore.shared.syncDerivedMetadata(
                for: assetPath,
                sourceSize: currentSourceSize,
                settings: current
            )
            await EditedThumbnailCache.shared.invalidate(assetPath: assetPath)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .darkroomAdjustmentDidChange,
                    object: nil,
                    userInfo: ["assetPath": assetPath]
                )
            }
        }
    }

    private func reloadPresetsAndSelection(named selectedName: String? = nil) async {
        let updated = await AdjustmentStore.shared.presets()
        await MainActor.run {
            presets = updated
            if let selectedName, let match = updated.first(where: { $0.name == selectedName }) {
                selectedPresetID = match.id
            } else {
                selectedPresetID = updated.first(where: { $0.settings == settings })?.id
            }
        }
    }

    private static func downscaledPreviewImage(from image: NSImage?, maxLongEdge: CGFloat) -> NSImage? {
        guard let image else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let target = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let output = NSImage(size: target)
        output.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        return output
    }

    private var previewGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .updating($magnifyScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    previewZoom = max(1, min(8, previewZoom * value))
                },
            RotationGesture()
                .updating($gestureRotation) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    let delta = value.degrees
                    guard abs(delta) > 0.1 else { return }
                    updateSettings { draft in
                        draft.straightenDegrees = min(max(draft.straightenDegrees + delta, -15), 15)
                    }
                }
        )
    }

    @ViewBuilder
    private func adjustmentSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.callout.monospacedDigit())
            }
            Slider(value: value, in: range)
                .controlSize(.large)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func adjustmentGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

struct ExportStatusBar: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Total: \(viewModel.photoAssets.count)")
            Text("Visible: \(viewModel.visiblePhotoAssets.count)")
            Text("Selected: \(viewModel.keepCount)")
            Text("Rejected: \(viewModel.rejectCount)")
            Text("Queued: \(viewModel.exportQueueCounts.queued)")
            Spacer()
            if let exportStatus = viewModel.exportStatus {
                Text(exportStatus)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

struct TagChip: View {
    let tag: PhotoTag?

    var body: some View {
        switch tag {
        case .keep:
            Label("Selected", systemImage: PhotoTag.keep.symbolName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.2), in: Capsule())
        case .reject:
            Label("Rejected", systemImage: PhotoTag.reject.symbolName)
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

struct PreviewTagBadge: View {
    let tag: PhotoTag

    private var fillColor: Color {
        switch tag {
        case .keep:
            return .green
        case .reject:
            return .red
        }
    }

    var body: some View {
        Label(tag.title, systemImage: tag.symbolName)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .foregroundStyle(.white)
            .frame(height: 30)
            .background(fillColor.gradient, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
    }
}

struct ThumbnailCell: View {
    let asset: PhotoAsset
    let isSelected: Bool
    let tag: PhotoTag?
    let rating: Int
    let displayMode: PhotoGridPane.ThumbnailDisplayMode

    @State private var image: NSImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .foregroundStyle(.quaternary)
                    .aspectRatio(containerAspectRatio, contentMode: .fit)
                    .overlay {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .if(displayMode == .fit) { view in
                                    view.scaledToFill()
                                }
                                .if(displayMode == .aspectRatio) { view in
                                    view.scaledToFit()
                                }
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

                if rating > 0 {
                    Text(String(repeating: "★", count: rating))
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }

            if let tag {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                    Image(systemName: tag == .keep ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tag == .keep ? .white : .red)
                }
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(7)
            }
        }
        .saturation(tag == .reject ? 0 : 1)
        .brightness(tag == .reject ? -0.1 : 0)
        .opacity(tag == .reject ? 0.9 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? .green : .clear, lineWidth: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .task(id: asset.id) {
            reloadThumbnail()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .darkroomAdjustmentDidChange)) { notification in
            guard let changedPath = notification.userInfo?["assetPath"] as? String,
                  changedPath == asset.url.path else {
                return
            }
            reloadThumbnail()
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = [asset.filename]
        if let tag {
            parts.append(tag == .keep ? "Selected tagged" : "Rejected tagged")
        } else {
            parts.append("Untagged")
        }
        if rating > 0 {
            parts.append("Rating \(rating) stars")
        }
        return parts.joined(separator: ", ")
    }

    private var containerAspectRatio: CGFloat {
        switch displayMode {
        case .fit:
            return 4 / 3
        case .aspectRatio:
            guard let image, image.size.width > 0, image.size.height > 0 else {
                return 4 / 3
            }
            return image.size.width / image.size.height
        }
    }

    private func reloadThumbnail() {
        loadTask?.cancel()
        loadTask = Task {
            guard let base = await ThumbnailCache.shared.thumbnail(for: asset.url, size: CGSize(width: 320, height: 320)) else {
                await MainActor.run { image = nil }
                return
            }
            let settings = await AdjustmentStore.shared.adjustment(for: asset.url.path)
            let rendered = await EditedThumbnailCache.shared.thumbnail(
                for: asset.url.path,
                baseImage: base,
                settings: settings
            ) ?? base
            if Task.isCancelled {
                return
            }
            await MainActor.run {
                image = rendered
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct ExportQueueSheet: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsPresetEditor = false
    @State private var presetDraft = ExportPreset(name: "New Preset", fileFormat: .jpeg, longEdgePixels: 3000, quality: 0.9)
    @State private var showsShootNameHint = false
    @FocusState private var shootNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Queue")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Picker("Preset", selection: $viewModel.selectedExportPresetID) {
                    ForEach(viewModel.exportPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .frame(width: 220)

                Button("New Preset") {
                    presetDraft = ExportPreset(name: "New Preset", fileFormat: .jpeg, longEdgePixels: 3000, quality: 0.9)
                    showsPresetEditor = true
                }
                .accessibilityLabel("Create export preset")

                Button("Edit Preset") {
                    if let preset = viewModel.selectedExportPreset {
                        presetDraft = preset
                        showsPresetEditor = true
                    }
                }
                .disabled(viewModel.selectedExportPreset == nil)
                .accessibilityLabel("Edit selected export preset")

                Button("Delete Preset") {
                    viewModel.deleteSelectedExportPreset()
                }
                .disabled(viewModel.exportPresets.count <= 1)
                .accessibilityLabel("Delete selected export preset")
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                TextField("Shoot name", text: $viewModel.exportDestination.shootName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .focused($shootNameFocused)
                    .popover(isPresented: $showsShootNameHint, arrowEdge: .top) {
                        Text("Enter folder name before export.")
                            .padding(10)
                    }
                    .onChange(of: viewModel.exportDestination.shootName) { value in
                        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showsShootNameHint = false
                        }
                    }

                TextField("Subfolder template", text: $viewModel.exportDestination.subfolderTemplate)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)

                Button("Choose Path") {
                    chooseExportPath()
                }
                .accessibilityLabel("Choose export destination path")

                if !viewModel.recentExportDestinations.isEmpty {
                    Menu("Recent") {
                        ForEach(viewModel.recentExportDestinations, id: \.self) { path in
                            Button(path) {
                                viewModel.useRecentExportDestination(path)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if !viewModel.exportDestination.basePath.isEmpty {
                Text("Base path: \(viewModel.exportDestination.basePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Base path not set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Enqueue Selected Tagged") {
                            viewModel.enqueueGreenTaggedForExport()
                        }
                        .accessibilityLabel("Add selected-tagged photos to export queue")
                        Button("Start Queue") {
                            startQueueWithValidation()
                        }
                        .disabled(!viewModel.hasValidExportDestination || viewModel.isExporting)
                        .accessibilityLabel("Start export queue")

                        Button("Cancel") {
                            viewModel.cancelExportQueue()
                        }
                        .disabled(!viewModel.isExporting)
                        .accessibilityLabel("Cancel export queue")

                        Button("Retry Failed") {
                            viewModel.retryFailedExports()
                        }
                        .accessibilityLabel("Retry failed exports")

                        Button("Clear Completed") {
                            viewModel.clearCompletedExports()
                        }
                        .accessibilityLabel("Clear completed exports")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                let counts = viewModel.exportQueueCounts
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Pending \(counts.queued) • Done \(counts.done) • Failed \(counts.failed) • Cancelled \(counts.cancelled)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let eta = viewModel.estimatedExportRemaining {
                        Text("ETA \(formattedETA(eta))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            List(viewModel.exportQueue) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.asset.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(statusLabel(item.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.asset.url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let destinationPath = item.destinationPath {
                        HStack(spacing: 8) {
                            Text(destinationPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Reveal") {
                                viewModel.revealExportedItem(item)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    if let bytes = item.bytesWritten {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let warningMessage = item.warningMessage {
                        Text(warningMessage)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("Remove") {
                            viewModel.removeExportItem(id: item.id)
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(minWidth: 920, minHeight: 500)
        .sheet(isPresented: $showsPresetEditor) {
            ExportPresetEditorSheet(
                draft: $presetDraft,
                onCancel: { showsPresetEditor = false },
                onSave: {
                    if viewModel.exportPresets.contains(where: { $0.id == presetDraft.id }) {
                        viewModel.updateSelectedExportPreset(presetDraft)
                    } else {
                        viewModel.addExportPreset(presetDraft)
                    }
                    showsPresetEditor = false
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }

    private func startQueueWithValidation() {
        guard !viewModel.exportDestination.shootName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showsShootNameHint = true
            shootNameFocused = true
            return
        }
        viewModel.startExportQueue()
    }

    private func chooseExportPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose base export directory"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setExportBasePath(url.path)
        }
    }

    private func statusLabel(_ state: ExportItemState) -> String {
        switch state {
        case .queued: return "Queued"
        case .rendering: return "Rendering"
        case .writing: return "Writing"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private func formattedETA(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        let minutes = rounded / 60
        let remainder = rounded % 60
        return String(format: "%dm %02ds", minutes, remainder)
    }
}

struct ExportPresetEditorSheet: View {
    @Binding var draft: ExportPreset
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Preset")
                .font(.headline)

            TextField("Preset name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Format", selection: $draft.fileFormat) {
                    ForEach(ExportFileFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Picker("Color Space", selection: $draft.colorSpace) {
                    ForEach(ExportColorSpace.allCases) { space in
                        Text(space.title).tag(space)
                    }
                }
            }

            HStack {
                Text("Long edge")
                TextField("Pixels (0 = original)", value: $draft.longEdgePixels, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            HStack {
                Text("Quality")
                Slider(value: $draft.quality, in: 0.35...1.0, step: 0.01)
                Text(String(format: "%.2f", draft.quality))
                    .frame(width: 48)
            }

            HStack {
                Text("Max size")
                TextField("KB (0 = disabled)", value: $draft.maxFileSizeKB, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Toggle("Strip metadata", isOn: $draft.stripMetadata)
            Toggle("Watermark", isOn: $draft.watermarkEnabled)
            if draft.watermarkEnabled {
                TextField("Watermark text", text: $draft.watermarkText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 460)
    }
}

extension Notification.Name {
    static let darkroomAdjustmentDidChange = Notification.Name("darkroom.adjustment.didChange")
}
