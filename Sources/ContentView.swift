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
    @State private var keyMonitor: Any?
    @State private var showsExportQueue = false
    @State private var showsAdjustmentsPanel = false
    @State private var showsToolbarShootNameHint = false
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
                HSplitView {
                    PhotoGridPane(viewModel: viewModel)
                        .frame(minWidth: 260)
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
        .onTapGesture {
            clearTextInputFocus()
        }
        .onAppear {
            installKeyMonitor()
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

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Filter", selection: $viewModel.assetFilter) {
                    ForEach(BrowserViewModel.AssetFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

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
                    .padding(.horizontal, 4)
                    .help("Export with current settings")
                    .accessibilityLabel("Export with current settings")
                    .disabled(viewModel.selectedAsset == nil || viewModel.isExporting)

                }
                .layoutPriority(2)
                
                Button("Custom Export") {
                    showsExportQueue = true
                }
                .accessibilityLabel("Open export config")
            }
        }
        .sheet(isPresented: $showsExportQueue) {
            ExportQueueSheet(viewModel: viewModel)
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
        viewModel.enqueueSelectedForExport()
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
        guard isTextInputFocused() else { return }
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
    @ObservedObject var viewModel: BrowserViewModel
    private let spacing: CGFloat = 10
    private let horizontalPadding: CGFloat = 24
    private let sectionSpacing: CGFloat = 12

    var body: some View {
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
                                            rating: viewModel.rating(for: asset)
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
                                            Button("Tag Green") {
                                                viewModel.select(asset)
                                                viewModel.tagSelectedAsKeep()
                                            }
                                            Button("Tag Red") {
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
                    updateGridConfig(for: geometry.size.width)
                    scrollToSelection(with: proxy)
                }
                .onChange(of: viewModel.selectedAssetID) { _ in
                    scrollToSelection(with: proxy)
                }
                .onChange(of: geometry.size.width) { newWidth in
                    updateGridConfig(for: newWidth)
                }
            }
        }
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let minimumCellWidth = max(120, min(180, width / 2.6))
        return [GridItem(.adaptive(minimum: minimumCellWidth), spacing: spacing)]
    }

    private func scrollToSelection(with proxy: ScrollViewProxy) {
        guard let selectedID = viewModel.selectedAssetID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }

    private func updateGridConfig(for width: CGFloat) {
        let minimumCellWidth = max(120, min(180, width / 2.6))
        let availableWidth = max(0, width - horizontalPadding)
        let count = Int((availableWidth + spacing) / (minimumCellWidth + spacing))
        viewModel.setGridColumnCount(max(1, count))
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
                    VSplitView {
                        previewSection
                            .padding(.bottom, 6)
                            .frame(minHeight: 240)
                        adjustmentsSection
                            .padding(.top, 6)
                            .frame(minHeight: 240, idealHeight: 360)
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
        .task(id: viewModel.selectedAssetID) {
            renderTask?.cancel()
            persistTask?.cancel()
            guard let asset = viewModel.selectedAsset else {
                sourceImage = nil
                sourcePixelSize = .zero
                previewImage = nil
                settings = .default
                presets = AdjustmentPreset.builtIns
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
            async let versionBBookmark = AdjustmentStore.shared.bookmark(named: "Version B", for: asset.url.path)
            let (image, storedSettings, availablePresets, versionB) = await (loadedImage, loadedSettings, loadedPresets, versionBBookmark)
            sourcePixelSize = image?.size ?? .zero
            sourceImage = Self.downscaledPreviewImage(from: image, maxLongEdge: 2048)
            settings = storedSettings
            presets = availablePresets
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

                HStack {
                    Text(asset.filename)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    TagChip(tag: viewModel.tag(for: asset))
                }

                if !showsAdjustmentsPanel {
                    HStack {
                        Spacer()
                        Button {
                            showsAdjustmentsPanel = true
                        } label: {
                            Image(systemName: "chevron.up.circle.fill")
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
            HStack(spacing: 8) {
                Toggle(showOriginal ? "Original" : "Adjusted", isOn: $showOriginal)
                    .toggleStyle(.switch)
                    .onChange(of: showOriginal) { _ in
                        schedulePreviewRender()
                    }
                Spacer()
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

            ScrollView {
                VStack(spacing: 10) {
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
                            title: "Highlights",
                            value: Binding(
                                get: { settings.highlights },
                                set: { newValue in
                                    updateSettings { $0.highlights = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.highlights)
                        )
                        adjustmentSlider(
                            title: "Shadows",
                            value: Binding(
                                get: { settings.shadows },
                                set: { newValue in
                                    updateSettings { $0.shadows = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.shadows)
                        )
                        adjustmentSlider(
                            title: "Temp",
                            value: Binding(
                                get: { settings.temperature },
                                set: { newValue in
                                    updateSettings { $0.temperature = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.temperature)
                        )
                        adjustmentSlider(
                            title: "Tint",
                            value: Binding(
                                get: { settings.tint },
                                set: { newValue in
                                    updateSettings { $0.tint = min(max(newValue, -1), 1) }
                                }
                            ),
                            range: -1...1,
                            step: 0.01,
                            valueText: String(format: "%.2f", settings.tint)
                        )
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

            Text(viewModel.shortcutLegend)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Green") {
                    viewModel.tagSelectedAsKeep()
                }

                Button("Red") {
                    viewModel.tagSelectedAsReject()
                }

                Button("Clear") {
                    viewModel.clearSelectedTag()
                }
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
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .controlSize(.large)
            Text(valueText)
                .font(.callout.monospacedDigit())
                .frame(width: 82, alignment: .trailing)
        }
        .frame(minHeight: 34)
        .padding(.vertical, 3)
    }
}

struct ExportStatusBar: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Total: \(viewModel.photoAssets.count)")
            Text("Visible: \(viewModel.visiblePhotoAssets.count)")
            Text("Green: \(viewModel.keepCount)")
            Text("Red: \(viewModel.rejectCount)")
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
            Label("Green", systemImage: PhotoTag.keep.symbolName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.2), in: Capsule())
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
    let rating: Int

    @State private var image: NSImage?
    @State private var loadTask: Task<Void, Never>?

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
                Image(systemName: tag.symbolName)
                    .font(.title3)
                    .foregroundStyle(tag == .keep ? .green : .red)
                    .padding(8)
            }
        }
        .saturation(tag == .reject ? 0 : 1)
        .brightness(tag == .reject ? -0.15 : 0)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? .green : .clear, lineWidth: 3)
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
            parts.append(tag == .keep ? "Green tagged" : "Red tagged")
        } else {
            parts.append("Untagged")
        }
        if rating > 0 {
            parts.append("Rating \(rating) stars")
        }
        return parts.joined(separator: ", ")
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
                        Button("Enqueue Green Tagged") {
                            viewModel.enqueueGreenTaggedForExport()
                        }
                        .accessibilityLabel("Add green-tagged photos to export queue")
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
