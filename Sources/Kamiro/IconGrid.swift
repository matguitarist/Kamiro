import AppKit
import KamiroKit
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The icon view (S-019): an NSCollectionView, which lays out and reuses only the visible
/// items, so a 10,000-file folder scrolls like a short one. Thumbnails load as items appear.
struct IconGrid: NSViewRepresentable {
    let model: BrowserModel
    let version: Int
    let selection: Set<URL>
    let reveal: Int
    let focus: Int
    let cutVersion: Int
    let renameToken: Int
    let cloudVersion: Int
    let iconSize: Double

    func makeCoordinator() -> GridCoordinator { GridCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let grid = FileGrid()
        grid.coordinator = context.coordinator
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Space.sm
        layout.minimumLineSpacing = Space.sm
        layout.sectionInset = NSEdgeInsets(top: Space.lg, left: Space.lg, bottom: Space.lg, right: Space.lg)
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.controlBackgroundColor]
        grid.register(IconItem.self, forItemWithIdentifier: IconItem.identifier)
        grid.dataSource = context.coordinator
        grid.delegate = context.coordinator
        grid.registerForDraggedTypes([.fileURL])
        grid.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        grid.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        context.coordinator.grid = grid
        model.grid = context.coordinator
        model.quickLook = { [weak grid] in grid?.toggleQuickLook() }

        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(iconSize: iconSize)
    }
}

final class GridCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let model: BrowserModel
    weak var grid: FileGrid?
    private(set) var items: [FileItem] = []
    private(set) var rowOf: [URL: Int] = [:]
    private var version = -1
    private var reveal = -1
    private var focus = -1
    private var cutVersion = -1
    private var cloudVersion = -1
    private var renameToken = 0
    private var pendingRename: URL?
    private(set) var iconSize: Double = 0
    private var applying = false
    var rename: InlineRename?
    var renaming: URL? { rename?.url }

    init(model: BrowserModel) { self.model = model }

    func url(at index: Int) -> URL? { items.indices.contains(index) ? items[index].url : nil }

    func update(iconSize size: Double) {
        guard let grid else { return }
        if renaming != nil {
            guard focus != model.focusToken else { return }
            grid.window?.makeFirstResponder(grid)
            rename?.end()
            return
        }
        applying = true
        defer { applying = false }
        if size != iconSize {
            iconSize = size
            (grid.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize = IconCell.itemSize(icon: size)
            if version == model.itemsVersion { refreshVisible() }
        }
        if version != model.itemsVersion {
            version = model.itemsVersion
            items = model.items
            rowOf = Dictionary(items.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
            grid.reloadData()
            cutVersion = FileClipboard.shared.version
            cloudVersion = model.cloudVersion
        }
        if cutVersion != FileClipboard.shared.version || cloudVersion != model.cloudVersion {
            cutVersion = FileClipboard.shared.version
            cloudVersion = model.cloudVersion
            refreshVisible()
        }
        let wanted = Set(model.selection.compactMap { rowOf[$0] }.map { IndexPath(item: $0, section: 0) })
        if wanted != grid.selectionIndexPaths { grid.selectionIndexPaths = wanted }
        if reveal != model.revealToken {
            reveal = model.revealToken
            if let first = wanted.min() {
                grid.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge)
            } else {
                grid.scroll(.zero)
            }
        }
        if focus != model.focusToken, let window = grid.window {
            focus = model.focusToken
            window.makeFirstResponder(grid)
        }
        if renameToken != model.renameToken {
            renameToken = model.renameToken
            pendingRename = model.renameTarget
        }
        if let target = pendingRename, rowOf[target] != nil {
            pendingRename = nil
            beginRename(target)
        }
    }

    /// Redraws the items on screen (cut items, a new icon size) without reading anything again.
    private func refreshVisible() {
        guard let grid else { return }
        for path in grid.indexPathsForVisibleItems() {
            if let item = grid.item(at: path) as? IconItem { configure(item, at: path.item) }
        }
    }

    private func configure(_ item: IconItem, at index: Int) {
        guard items.indices.contains(index) else { return }
        let file = items[index]
        item.show(file, size: iconSize, dimmed: file.isHidden || FileClipboard.shared.isCut(file.url),
                  cloud: model.cloud[file.url], scale: grid?.window?.backingScaleFactor ?? 2)
    }

    // MARK: Data source and delegate

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: IconItem.identifier, for: indexPath)
        if let item = item as? IconItem { configure(item, at: indexPath.item) }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }

    private func selectionChanged() {
        guard !applying, let grid else { return }
        model.selection = Set(grid.selectionIndexPaths.compactMap { url(at: $0.item) })
        QuickLookSource.reloadIfShown()
    }

    // MARK: Rename in place

    func beginRename(_ url: URL) {
        guard let grid, let index = rowOf[url], rename == nil else { return }
        let path = IndexPath(item: index, section: 0)
        grid.selectionIndexPaths = [path]
        grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        grid.layoutSubtreeIfNeeded()
        guard let item = grid.item(at: path) as? IconItem, let field = item.textField else { return }
        let session = InlineRename(url: url, field: field, model: model, isFolder: items[index].isFolder,
                                   neighbor: { [weak self] step in self?.neighbor(of: url, step: step) },
                                   finished: { [weak self] in self?.renameEnded() })
        rename = session
        item.isRenaming = true
        session.begin()
    }

    private func renameEnded() {
        if let grid, let url = rename?.url, let index = rowOf[url],
           let item = grid.item(at: IndexPath(item: index, section: 0)) as? IconItem {
            item.isRenaming = false
        }
        rename = nil
        grid?.window?.makeFirstResponder(grid)
        update(iconSize: iconSize)
    }

    private func neighbor(of url: URL, step: Int) -> URL? {
        guard let index = rowOf[url] else { return nil }
        return self.url(at: index + step)
    }

    // MARK: Drag and drop (S-018)

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        url(at: indexPath.item) as NSURL?
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let urls = FilePasteboard.read(from: draggingInfo.draggingPasteboard)
        guard !urls.isEmpty else { return [] }
        let destination = destination(proposedIndexPath.pointee as IndexPath, dropOperation.pointee, urls: urls)
        let kind = model.dropKind(urls, into: destination, info: draggingInfo)
        guard !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return [] }
        return kind == .copy ? .copy : .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let urls = FilePasteboard.read(from: draggingInfo.draggingPasteboard)
        let destination = destination(indexPath, dropOperation, urls: urls)
        let kind = model.dropKind(urls, into: destination, info: draggingInfo)
        guard !urls.isEmpty, !DropRule.isNoOp(sources: urls, destination: destination, kind: kind) else { return false }
        model.transfer(kind, urls, into: destination)
        return true
    }

    /// A drop on a folder goes into it; anywhere else, into the folder on screen.
    private func destination(_ path: IndexPath, _ operation: NSCollectionView.DropOperation, urls: [URL]) -> URL {
        if operation == .on, items.indices.contains(path.item), items[path.item].isFolder, !urls.contains(items[path.item].url) {
            return items[path.item].url
        }
        return model.folder
    }
}

/// The icon view's keys, Edit menu commands, right-click menu and Quick Look.
final class FileGrid: NSCollectionView, NSUserInterfaceValidations {
    weak var coordinator: GridCoordinator?
    private var model: BrowserModel? { coordinator?.model }
    private lazy var quickLookSource = QuickLookSource(
        urls: { [weak self] in self?.selectedURLs ?? [] },
        key: { [weak self] event in self?.keyDown(with: event) })

    private var selectedURLs: [URL] {
        selectionIndexPaths.sorted().compactMap { coordinator?.url(at: $0.item) }
    }

    override func keyDown(with event: NSEvent) {
        if FileKeys.handle(event, model: model) { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2, let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)),
              let url = coordinator?.url(at: path.item) else { return }
        model?.open([url], newWindow: event.modifierFlags.contains(.option), newTab: event.modifierFlags.contains(.command))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { coordinator?.update(iconSize: coordinator?.iconSize ?? IconSize.standard) }
    }

    /// Control-scroll (or Command-scroll) makes icons bigger or smaller.
    private var zoom = ZoomScroll()

    override func scrollWheel(with event: NSEvent) {
        guard ZoomKeys.zooms(event) else {
            zoom.reset()
            super.scrollWheel(with: event)
            return
        }
        let steps = zoom.steps(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        guard steps != 0 else { return }
        let current = Prefs.defaults.object(forKey: Prefs.iconSize) as? Double ?? IconSize.standard
        Prefs.defaults.set(IconSize.zoomed(current, by: steps), forKey: Prefs.iconSize)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { MenuState.shared.listFocused = true }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { MenuState.shared.listFocused = false }
        return resigned
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        if let path {
            if !selectionIndexPaths.contains(path) {
                selectionIndexPaths = [path]
                delegate?.collectionView?(self, didSelectItemsAt: [path])
            }
        } else if !selectionIndexPaths.isEmpty {
            let old = selectionIndexPaths
            selectionIndexPaths = []
            delegate?.collectionView?(self, didDeselectItemsAt: old)
        }
        window?.makeFirstResponder(self)
        return model?.contextMenu(onItems: path != nil)
    }

    // MARK: Edit menu, through the responder chain

    @objc func cut(_ sender: Any?) { model?.cutSelection() }
    @objc func copy(_ sender: Any?) { model?.copySelection() }
    @objc func paste(_ sender: Any?) { model?.paste() }
    @objc func undo(_ sender: Any?) { FileUndo.manager.undo() }
    @objc func redo(_ sender: Any?) { FileUndo.manager.redo() }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let undo = FileUndo.manager
        switch item.action {
        case #selector(cut(_:)), #selector(copy(_:)):
            return !(model?.selection.isEmpty ?? true)
        case #selector(paste(_:)):
            return model?.canPaste ?? false
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = undo.undoMenuItemTitle
            return undo.canUndo
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = undo.redoMenuItemTitle
            return undo.canRedo
        case #selector(selectAll(_:)):
            return !(coordinator?.items.isEmpty ?? true)
        default:
            return responds(to: item.action)
        }
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        QuickLookSource.toggle(from: self, in: window, hasSelection: !selectionIndexPaths.isEmpty)
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = quickLookSource
            panel.delegate = quickLookSource
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

/// One icon: the icon or thumbnail on a rounded tile, the name under it in up to two lines.
final class IconItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("icon")
    private var cell: IconCell { view as! IconCell }
    private(set) var url: URL?
    var isRenaming = false { didSet { cell.isRenaming = isRenaming; cell.needsLayout = true } }

    override func loadView() {
        let cell = IconCell()
        view = cell
        imageView = cell.icon
        textField = cell.label
    }

    override var isSelected: Bool {
        didSet { cell.isSelected = isSelected }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isRenaming = false
    }

    func show(_ file: FileItem, size: Double, dimmed: Bool, cloud: CloudStatus? = nil, scale: CGFloat) {
        url = file.url
        cell.iconSize = size
        cell.cloud = cloud
        cell.label.stringValue = file.name
        cell.toolTip = file.name
        cell.alphaValue = dimmed ? 0.5 : 1
        if let image = Thumbnails.shared.cached(file, size: size) {
            cell.icon.image = image
            return
        }
        cell.icon.image = IconCache.shared.icon(for: file, size: CGFloat(size))
        // Requests aren't cancelled when an item scrolls away: the thumbnail is kept for later.
        Thumbnails.shared.load(file, size: size, scale: scale) { [weak self] image in
            guard let self, url == file.url, let image else { return }
            cell.icon.image = image
        }
    }
}

/// The view of one icon; it lays itself out from the icon size.
final class IconCell: NSView {
    let tile = NSView()
    let icon = NSImageView()
    let label = NSTextField(wrappingLabelWithString: "")
    private let labelBack = NSView()
    /// The cloud status badge at the icon's corner (S-058).
    private let badge = NSImageView()
    var cloud: CloudStatus? {
        didSet {
            guard cloud != oldValue else { return }
            badge.image = cloud?.image
            badge.isHidden = badge.image == nil
            badge.toolTip = cloud?.title
        }
    }
    var iconSize: Double = IconSize.standard { didSet { if iconSize != oldValue { needsLayout = true } } }
    var isSelected = false { didSet { updateLook() } }
    var isRenaming = false
    /// What the last layout was for: when none of it changed, the frames are still right.
    private var laidOut: LayoutKey?

    private struct LayoutKey: Equatable {
        let size: NSSize, iconSize: Double, name: String, renaming: Bool
    }

    static let labelLines = 2

    /// The cell for an icon size: the icon with room around it, and two lines of name.
    static func itemSize(icon: Double) -> NSSize {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let line = ceil(font.ascender - font.descender + font.leading)
        let width = max(icon + Space.xxl * 2, 96)
        return NSSize(width: width, height: icon + Space.sm * 2 + Space.xs + line * CGFloat(labelLines) + Space.xs)
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = Radius.control
        labelBack.wantsLayer = true
        labelBack.layer?.cornerRadius = Space.xs
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.maximumNumberOfLines = Self.labelLines
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = Space.sm + Space.xs / 2
        badge.contentTintColor = .secondaryLabelColor
        badge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        badge.isHidden = true
        [tile, icon, badge, labelBack, label].forEach(addSubview)
        updateLook()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        // Scrolling lays out every reused cell; measuring its name again is most of the cost.
        let key = LayoutKey(size: bounds.size, iconSize: iconSize, name: label.stringValue, renaming: isRenaming)
        guard key != laidOut else { return }
        laidOut = key
        let size = CGFloat(iconSize)
        let tileSide = size + Space.sm * 2
        tile.frame = NSRect(x: (bounds.width - tileSide) / 2, y: 0, width: tileSide, height: tileSide)
        icon.frame = tile.frame.insetBy(dx: Space.sm, dy: Space.sm)
        let badgeSide = Space.lg + Space.xs
        badge.frame = NSRect(x: icon.frame.maxX - badgeSide + Space.xs, y: icon.frame.maxY - badgeSide + Space.xs,
                             width: badgeSide, height: badgeSide)
        let top = tile.frame.maxY + Space.xs
        let width = bounds.width - Space.xs * 2
        let fitted = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: bounds.height - top)) ?? .zero
        let labelWidth = isRenaming ? width : min(width, ceil(fitted.width))
        let labelHeight = min(ceil(fitted.height), bounds.height - top)
        label.frame = NSRect(x: (bounds.width - labelWidth) / 2, y: top, width: labelWidth, height: labelHeight)
        labelBack.frame = label.frame.insetBy(dx: -Space.xs, dy: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    /// Selected: a gray tile behind the icon and the name on the accent color, like the Finder.
    private func updateLook() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tile.layer?.backgroundColor = isSelected ? NSColor.quaternaryLabelColor.cgColor : nil
            labelBack.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : nil
            badge.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        label.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
    }
}

/// Thumbnails from Quick Look, made once per file, size step and change date, and kept in memory.
/// Documents get a page edge and a soft shadow, like the Finder's; pictures and movies stay bare.
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()
    /// Files Quick Look has no thumbnail for: their icon stays.
    private var none: Set<String> = []
    private var waiting: [String: [(NSImage?) -> Void]] = [:]
    /// How many thumbnails were asked for, for the self-test.
    private(set) var requested = 0

    init() { cache.countLimit = 2_000 }

    private func key(_ file: FileItem, _ size: Double) -> String {
        "\(file.url.path)|\(file.modified?.timeIntervalSince1970 ?? 0)|\(Int(IconSize.thumbnailStep(size)))"
    }

    func cached(_ file: FileItem, size: Double) -> NSImage? {
        cache.object(forKey: key(file, size) as NSString)
    }

    /// Asks Quick Look for a thumbnail; `done` runs on the main thread with it, or nil.
    func load(_ file: FileItem, size: Double, scale: CGFloat, done: @escaping (NSImage?) -> Void) {
        guard !file.isFolder else { return }
        let key = key(file, size)
        guard !none.contains(key) else { return }
        if waiting[key] != nil {
            waiting[key]?.append(done)
            return
        }
        waiting[key] = [done]
        requested += 1
        let side = IconSize.thumbnailStep(size)
        let url = file.url
        let bare = UTType(filenameExtension: url.pathExtension).map { $0.conforms(to: .image) || $0.conforms(to: .audiovisualContent) } ?? false
        // Asking Quick Look waits on its own queue: off the main thread, so scrolling doesn't.
        Self.queue.async {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                       scale: scale, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                // An icon (no thumbnail for this kind) is left to IconCache.
                let image = thumbnail?.type == .thumbnail ? thumbnail?.cgImage : nil
                Task { @MainActor in self.finish(key, image, page: !bare) }
            }
        }
    }

    private static let queue = DispatchQueue(label: "Kamiro.thumbnails", qos: .userInitiated)

    private func finish(_ key: String, _ cgImage: CGImage?, page: Bool) {
        var image: NSImage?
        if let cgImage {
            let made = page ? Self.page(cgImage) : NSImage(cgImage: cgImage, size: .zero)
            cache.setObject(made, forKey: key as NSString)
            image = made
        } else {
            none.insert(key)
        }
        let callbacks = waiting.removeValue(forKey: key) ?? []
        callbacks.forEach { $0(image) }
    }

    /// A document's thumbnail as a page: a hairline edge and a soft shadow, drawn in the
    /// current appearance each time it's shown.
    private static func page(_ cgImage: CGImage) -> NSImage {
        let inner = NSSize(width: cgImage.width, height: cgImage.height)
        let margin = max(inner.width, inner.height) * 0.04
        let size = NSSize(width: inner.width + margin * 2, height: inner.height + margin * 2)
        return NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(origin: NSPoint(x: margin, y: margin), size: inner)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = margin * 0.8
            shadow.shadowOffset = NSSize(width: 0, height: -margin * 0.2)
            shadow.set()
            NSColor.white.setFill()
            rect.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.current?.cgContext.draw(cgImage, in: rect)
            NSColor.separatorColor.setStroke()
            let edge = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            edge.stroke()
            return true
        }
    }
}
