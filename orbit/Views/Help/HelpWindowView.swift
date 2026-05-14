import SwiftUI

/// The Orbit Help window. Triggered by Help → Orbit Help (⌘?).
///
/// Layout: NavigationSplitView with a sidebar of sections and articles on the
/// left, and the article body on the right. Free-text search filters articles.
struct HelpWindowView: View {
    @State private var selection: HelpArticle? = HelpContent.allArticles.first
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            if let article = selection {
                HelpArticleView(article: article)
            } else {
                HelpEmptyState(
                    symbol: "book",
                    title: "Choose a topic",
                    message: "Pick an article from the sidebar to read it here."
                )
            }
        }
        .navigationTitle("Orbit Help")
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                // Browse mode: section -> article hierarchy
                ForEach(HelpContent.sections) { section in
                    Section {
                        ForEach(section.articles) { article in
                            NavigationLink(value: article) {
                                Text(article.title)
                            }
                        }
                    } header: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.headline)
                    }
                }
            } else {
                // Search mode: flat list of matching articles
                let matches = HelpContent.search(searchText)
                if matches.isEmpty {
                    HelpEmptyState(
                        symbol: "magnifyingglass",
                        title: "No results",
                        message: "No help articles match \"\(searchText)\"."
                    )
                } else {
                    Section("Results (\(matches.count))") {
                        ForEach(matches) { article in
                            NavigationLink(value: article) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(article.title)
                                    Text(article.summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search help")
        .listStyle(.sidebar)
    }
}

// MARK: - Empty state (manual; ContentUnavailableView is macOS 14+)

private struct HelpEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Article rendering

/// Renders a single help article's body as a scrollable column of blocks.
struct HelpArticleView: View {
    let article: HelpArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.largeTitle.weight(.semibold))
                    Text(article.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                ForEach(article.body) { block in
                    HelpBlockView(block: block)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Renders one HelpBlock structurally — no Markdown parser needed.
struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.title2.weight(.semibold))
                .padding(.top, 8)

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(item)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numberedSteps(let steps):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 22, alignment: .trailing)
                        Text(step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .codeBlock(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

        case .note(let severity, let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: noteSymbol(for: severity))
                    .foregroundStyle(noteColor(for: severity))
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(noteColor(for: severity).opacity(0.10))
            .overlay(
                Rectangle()
                    .fill(noteColor(for: severity))
                    .frame(width: 3),
                alignment: .leading
            )
            .cornerRadius(6)

        case .shortcutTable(let rows):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack {
                        Text(row.label).font(.body)
                        Spacer()
                        Text(row.keys)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    if idx < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    private func noteSymbol(for severity: NoteSeverity) -> String {
        switch severity {
        case .tip:    return "lightbulb.fill"
        case .warn:   return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    private func noteColor(for severity: NoteSeverity) -> Color {
        switch severity {
        case .tip:    return .blue
        case .warn:   return .yellow
        case .danger: return .red
        }
    }
}
