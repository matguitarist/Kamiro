import AppKit
import KamiroKit

/// The mounted disks and cloud folders the sidebars show, read once for every window and again
/// when a disk comes, goes or is renamed. Read off the main thread: a network disk whose server
/// went away can take a long time to answer, and the window must not wait for it.
@MainActor @Observable
final class VolumeStore {
    static let shared = VolumeStore()

    private(set) var volumes: [Volume] = []
    /// iCloud Drive and the sync apps' folders (S-057).
    private(set) var clouds: [Cloud.Place] = []
    @ObservationIgnored private var generation = 0

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        // A sync app set up meanwhile shows up.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        generation += 1
        let mine = generation
        Task {
            let (volumes, clouds) = await Task.detached(priority: .userInitiated) { (Volumes.mounted(), Cloud.places()) }.value
            // A later look wins over one that answered late.
            guard mine == generation else { return }
            if volumes != self.volumes { self.volumes = volumes }
            if clouds != self.clouds { self.clouds = clouds }
        }
    }
}
