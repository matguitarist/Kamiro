import KamiroKit
import SwiftUI

extension BrowserModel {
    /// The search the window shows, if it shows one.
    var search: Search? {
        if case .search(let search) = place { search } else { nil }
    }

    /// Return in the search field (S-029): search this folder and its subfolders for the words
    /// typed; from a search, search again with the new words.
    func searchEverywhere() {
        let text = filterText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if var search {
            search.text = text
            changeSearch(to: search)
        } else {
            searchFolder = folder.isFileURL ? folder : searchFolder
            go(to: VirtualPlace.search(Search(text: text, scope: searchFolder)).url)
        }
    }

    /// The scope, Kind or Date changed: show the new results in place of the old ones.
    func changeSearch(to search: Search) {
        replace(with: VirtualPlace.search(search).url)
    }

    /// Show in Enclosing Folder: the folder holding the selected result, with it selected.
    func showInEnclosingFolder() {
        guard isVirtual, let url = selection.first, selection.count == 1 else { return }
        go(to: url.deletingLastPathComponent(), select: [url])
    }
}

/// Above the results: where to search, and Kind and Date.
struct SearchScopeBar: View {
    let model: BrowserModel
    let search: Search

    var body: some View {
        HStack(spacing: Space.md) {
            Picker("Search In", selection: scope) {
                Text("This Mac").tag(URL?.none)
                if let folder = search.scope ?? model.searchFolder {
                    Text(String(localized: "“\(Cloud.displayName(of: folder))”")).tag(URL?.some(folder))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Search the whole Mac, or this folder and its subfolders")
            Spacer(minLength: Space.md)
            Picker("Kind", selection: binding(\.kind)) {
                ForEach(SearchKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Picker("Date", selection: binding(\.date)) {
                ForEach(SearchDate.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var scope: Binding<URL?> {
        Binding { search.scope } set: { url in
            var changed = search
            changed.scope = url
            model.changeSearch(to: changed)
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<Search, Value>) -> Binding<Value> {
        Binding { search[keyPath: path] } set: { value in
            var changed = search
            changed[keyPath: path] = value
            model.changeSearch(to: changed)
        }
    }
}

extension SearchKind {
    var title: String {
        switch self {
        case .any: String(localized: "Any Kind")
        case .folder: String(localized: "Folders")
        case .document: String(localized: "Documents")
        case .image: String(localized: "Images")
        case .movie: String(localized: "Movies")
        case .audio: String(localized: "Music and Audio")
        case .pdf: String(localized: "PDFs")
        case .app: String(localized: "Apps")
        }
    }
}

extension SearchDate {
    var title: String {
        switch self {
        case .any: String(localized: "Any Date")
        case .today: String(localized: "Today")
        case .week: String(localized: "Last 7 Days")
        case .month: String(localized: "Last 30 Days")
        case .year: String(localized: "This Year")
        }
    }
}
