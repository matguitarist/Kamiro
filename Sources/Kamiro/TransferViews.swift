import AppKit
import KamiroKit
import Synchronization
import SwiftUI

/// One copy or move, as the transfers popover shows it.
@Observable
final class TransferTask: Identifiable {
    enum State: Equatable { case running, done, cancelled, failed(String) }

    let id = UUID()
    let kind: TransferKind
    let count: Int
    let destination: URL
    let started = Date.now
    var progress = TransferProgress()
    var state = State.running
    @ObservationIgnored let cancelFlag = CancelFlag()
    /// A job other than a copy or move (Compress, Extract) names itself and has no byte count.
    private let label: String?

    init(kind: TransferKind, count: Int, destination: URL, label: String? = nil) {
        self.kind = kind
        self.count = count
        self.destination = destination
        self.label = label
    }

    /// A job that tells how far it has got (an FFmpeg conversion) counts in thousandths.
    var isIndeterminate: Bool { label != nil && progress.totalItems == 0 }

    var title: String {
        if let label { return label }
        let place = Cloud.displayName(of: destination)
        return kind == .copy ? String(localized: "Copying \(count) items to “\(place)”")
            : String(localized: "Moving \(count) items to “\(place)”")
    }

    /// "12 MB of 40 MB, about a minute left".
    var detail: String {
        switch state {
        case .done: return String(localized: "Done")
        case .cancelled: return String(localized: "Stopped")
        case .failed(let message): return message
        case .running:
            if isIndeterminate { return "" }
            if label != nil {
                let elapsed = Date.now.timeIntervalSince(started)
                guard progress.fraction > 0.02, elapsed > 1 else { return "" }
                let left = elapsed / progress.fraction - elapsed
                let time = Duration.seconds(max(1, left)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
                return String(localized: "About \(time) left")
            }
            let done = ByteCountFormatter.string(fromByteCount: progress.doneBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
            let elapsed = Date.now.timeIntervalSince(started)
            guard progress.fraction > 0.02, elapsed > 1 else { return String(localized: "\(done) of \(total)") }
            let left = elapsed / progress.fraction - elapsed
            let time = Duration.seconds(max(1, left)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
            return String(localized: "\(done) of \(total), about \(time) left")
        }
    }

    func cancel() { cancelFlag.cancel() }
}

/// Every running transfer, in one popover from a toolbar button (S-012). A transfer
/// appears after half a second, so quick ones never flash.
@Observable
final class TransferCenter {
    static let shared = TransferCenter()

    private(set) var tasks: [TransferTask] = []
    var popoverShown = false
    @ObservationIgnored private var running = 0

    var isIdle: Bool { running == 0 }
    var fraction: Double {
        let live = tasks.filter { $0.state == .running }
        let total = live.reduce(Int64(0)) { $0 + $1.progress.totalBytes }
        return total > 0 ? Double(live.reduce(Int64(0)) { $0 + $1.progress.doneBytes }) / Double(total) : 0
    }

    func start(_ kind: TransferKind, sources: [URL], into destination: URL, browser: BrowserModel) {
        let task = TransferTask(kind: kind, count: sources.count, destination: destination)
        FolderHistory.record(destination)
        running += 1
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if task.state == .running { tasks.append(task) }
        }
        let throttle = ProgressThrottle(task)
        Task {
            let outcome = await TransferEngine.run(
                kind, sources: sources, into: destination, copyWord: String(localized: "copy"),
                trash: FileUndo.trash, cancel: task.cancelFlag,
                ask: { conflict in await browser.ask(conflict, kind: kind) },
                progress: { throttle.send($0) })
            running -= 1
            finish(task, outcome: outcome, kind: kind, browser: browser)
        }
    }

    private func finish(_ task: TransferTask, outcome: TransferOutcome, kind: TransferKind, browser: BrowserModel) {
        let moved = outcome.placed.count
        let name = kind == .copy ? String(localized: "Copy of \(moved) Items") : String(localized: "Move of \(moved) Items")
        FileUndo.record(outcome.change, name: name)
        let verb = kind == .copy ? "Copied" : "Moved"
        Store.log.post(.info, "\(verb) \(moved) items to \(task.destination.path)", source: "Transfer")
        for failure in outcome.failures {
            Store.log.post(.error, "Couldn't \(kind == .copy ? "copy" : "move") \(failure)", source: "Transfer")
        }
        if let first = outcome.failures.first {
            task.state = .failed(first)
            NSSound.beep()
        } else {
            task.state = outcome.cancelled ? .cancelled : .done
        }
        if browser.folder == task.destination.canonical, !outcome.placed.isEmpty {
            browser.show(outcome.placed)
        } else {
            browser.refresh()
        }
        Task {
            try? await Task.sleep(for: .seconds(outcome.failures.isEmpty ? 2 : 10))
            tasks.removeAll { $0.id == task.id }
            if tasks.isEmpty { popoverShown = false }
        }
    }

    /// Compress and Extract: `work` runs off the main thread and returns what it made, which
    /// is selected and can be undone. Shown like a transfer, with Stop.
    func startJob(_ title: String, undoName: String, in folder: URL, browser: BrowserModel,
                  work: @escaping @Sendable (CancelFlag, _ progress: @escaping @Sendable (Double) -> Void) async throws -> URL) {
        let task = TransferTask(kind: .copy, count: 1, destination: folder, label: title)
        running += 1
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if task.state == .running { tasks.append(task) }
        }
        let cancel = task.cancelFlag
        Task {
            let result: Result<URL, any Error>
            let progress: @Sendable (Double) -> Void = { fraction in
                Task { @MainActor in
                    task.progress.totalItems = 1000
                    task.progress.doneItems = Int(fraction * 1000)
                }
            }
            do { result = .success(try await work(cancel, progress)) } catch { result = .failure(error) }
            running -= 1
            switch result {
            case .success(let made):
                task.state = .done
                FileUndo.record(.made([made]), name: undoName)
                Store.log.post(.info, "\(undoName): made \(made.path)", source: "Archive")
                if browser.folder == folder.canonical { browser.show([made]) } else { browser.refresh() }
            case .failure(let error) where error is CancellationError:
                task.state = .cancelled
            case .failure(let error):
                task.state = .failed(error.localizedDescription)
                Store.log.post(.error, "\(undoName) failed in \(folder.path): \(error.localizedDescription)", source: "Archive")
                NSSound.beep()
            }
            let failed = if case .failed = task.state { true } else { false }
            try? await Task.sleep(for: .seconds(failed ? 10 : 2))
            tasks.removeAll { $0.id == task.id }
            if tasks.isEmpty { popoverShown = false }
        }
    }

    /// For the self-test: wait until every transfer has finished.
    func waitUntilIdle() async {
        while running > 0 { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// For snapshots: two transfers part way, with the popover open.
    func showSample() {
        let seed = Store.seedFolder
        let first = TransferTask(kind: .copy, count: 240, destination: seed.appending(path: "Photos"))
        first.progress.totalBytes = 1_840_000_000
        first.progress.doneBytes = 712_000_000
        let second = TransferTask(kind: .move, count: 3, destination: seed.appending(path: "Music"))
        second.progress.totalBytes = 52_000_000
        second.progress.doneBytes = 9_000_000
        let third = TransferTask(kind: .copy, count: 1, destination: seed,
                                 label: String(localized: "Compressing “\("Photos")”"))
        tasks = [first, second, third]
        popoverShown = true
    }

    func hideSample() {
        popoverShown = false
        tasks = []
    }
}

/// Hands progress to the main thread ten times a second at most.
nonisolated private final class ProgressThrottle: Sendable {
    private let task: TransferTask
    private let last = Mutex(Date.distantPast)

    init(_ task: TransferTask) { self.task = task }

    func send(_ progress: TransferProgress) {
        let now = Date.now
        let due = last.withLock { last in
            guard now.timeIntervalSince(last) > 0.1 || progress.doneItems == progress.totalItems else { return false }
            last = now
            return true
        }
        guard due else { return }
        let task = task
        Task { @MainActor in task.progress = progress }
    }
}

/// The toolbar button: a ring that fills as transfers go, opening the list.
struct TransferButton: View {
    @Bindable var center: TransferCenter

    var body: some View {
        Button {
            center.popoverShown.toggle()
        } label: {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2)
                Circle().trim(from: 0, to: center.fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Space.lg, height: Space.lg)
            .animation(.default, value: center.fraction)
        }
        .help("Show transfers")
        .accessibilityLabel("Transfers")
        .accessibilityValue(Text(center.fraction, format: .percent.precision(.fractionLength(0))))
        .popover(isPresented: $center.popoverShown, arrowEdge: .bottom) {
            TransferList(center: center)
        }
    }
}

struct TransferList: View {
    let center: TransferCenter

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ForEach(center.tasks) { task in
                TransferRow(task: task)
            }
        }
        .padding(Space.lg)
        .frame(width: 360)
    }
}

private struct TransferRow: View {
    let task: TransferTask

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(task.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: task.state == .running ? (task.isIndeterminate ? nil : task.progress.fraction) : 1)
                    .tint(failed ? .red : nil)
                // Compress and Extract have no byte count: their bar moves, with no line under it.
                if !task.detail.isEmpty {
                    Label {
                        Text(task.detail)
                    } icon: {
                        if failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
            if task.state == .running {
                Button("Stop", systemImage: "xmark.circle.fill") { task.cancel() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Stop this transfer; nothing half-copied stays behind")
            }
        }
    }

    private var failed: Bool { if case .failed = task.state { true } else { false } }
}

/// A pasted or dropped item whose name is taken where it goes (S-013).
struct ConflictQuestion: Identifiable {
    let id = UUID()
    let conflict: Conflict
    let kind: TransferKind
    let answer: (ConflictAnswer) -> Void
    let source: FileItem?
    let existing: FileItem?

    init(conflict: Conflict, kind: TransferKind, answer: @escaping (ConflictAnswer) -> Void) {
        self.conflict = conflict
        self.kind = kind
        self.answer = answer
        source = FolderReader.item(at: conflict.source)
        existing = FolderReader.item(at: conflict.existing)
    }
}

struct ConflictSheet: View {
    let question: ConflictQuestion
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("An item named “\(question.conflict.existing.lastPathComponent)” already exists in this location.")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(question.kind == .copy ? "Do you want to replace it with the one you’re copying?"
                                            : "Do you want to replace it with the one you’re moving?")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Space.md) {
                FileSummary(title: "Already there", item: question.existing)
                FileSummary(title: question.kind == .copy ? "Copying" : "Moving", item: question.source)
            }
            if question.conflict.remaining > 0 {
                Toggle("Apply to All (\(question.conflict.remaining + 1) items)", isOn: $applyToAll)
                    .toggleStyle(.checkbox)
            }
            HStack(spacing: Space.sm) {
                Button("Stop") { reply(.stop) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip") { reply(.skip) }
                Button("Replace") { reply(.replace) }
                    .help("The item already there goes to the Trash")
                Button("Keep Both") { reply(.keepBoth) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .noInitialFocus()
    }

    private func reply(_ choice: ConflictChoice) {
        question.answer(ConflictAnswer(choice, applyToAll: applyToAll))
    }
}

/// An item's icon, name, size and date, to compare two items.
private struct FileSummary: View {
    let title: LocalizedStringKey
    let item: FileItem?

    var body: some View {
        HStack(spacing: Space.md) {
            if let item {
                Image(nsImage: IconCache.shared.icon(for: item, size: 32))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: item?.name ?? "").lineLimit(1).truncationMode(.middle)
                Text(verbatim: facts).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var facts: String {
        guard let item else { return "" }
        let size = item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
        let date = item.modified?.formatted(date: .abbreviated, time: .shortened) ?? ""
        return "\(size), \(date)"
    }
}

/// New Folder and the New File templates, for the File menu and the toolbar.
struct NewItemsMenu: View {
    let newFolder: () -> Void
    let newFile: (FileTemplate) -> Void
    let fromClipboard: () -> Void

    var body: some View {
        Button("New Folder", systemImage: "folder.badge.plus", action: newFolder)
        Divider()
        NewFileItems(newFile: newFile)
        Divider()
        Button("New File from Clipboard", systemImage: "doc.on.clipboard", action: fromClipboard)
    }
}

struct NewFileItems: View {
    let newFile: (FileTemplate) -> Void

    var body: some View {
        ForEach(FileTemplate.Group.allCases, id: \.self) { group in
            Section(group.title) {
                ForEach(FileTemplate.all.filter { $0.group == group }) { template in
                    Button(template.title, systemImage: template.symbol) { newFile(template) }
                }
            }
        }
    }
}
