import SwiftData
import SwiftUI

/// Page icons are stored in the existing `AppSetting` key/value table instead of
/// a new stored property on `Idea`.
///
/// The app has no `VersionedSchema` or `MigrationPlan` and `OrbitApp` calls
/// `fatalError` when the container fails to open, so adding a stored property
/// would risk locking someone out of their own notes for the sake of a
/// decoration. `AppSetting` is also already covered by export and restore, so
/// icons survive a backup round trip for free.
enum PageIcon {
    static let keyPrefix = "icon:"

    static func key(for id: UUID) -> String { keyPrefix + id.uuidString }

    static func read(_ id: UUID, from settings: [AppSetting]) -> String? {
        guard let value = settings.first(where: { $0.key == key(for: id) })?.value,
              !value.isEmpty else { return nil }
        return value
    }

    static func write(_ emoji: String?, for id: UUID, settings: [AppSetting], context: ModelContext) {
        let settingKey = key(for: id)
        let existing = settings.first { $0.key == settingKey }

        guard let emoji, !emoji.isEmpty else {
            if let existing { context.delete(existing) }
            try? context.save()
            return
        }

        if let existing {
            existing.value = emoji
        } else {
            context.insert(AppSetting(key: settingKey, value: emoji))
        }
        try? context.save()
    }

    /// Removes an idea's icon row so deleted pages leave nothing behind.
    static func clear(_ id: UUID, settings: [AppSetting], context: ModelContext) {
        guard let existing = settings.first(where: { $0.key == key(for: id) }) else { return }
        context.delete(existing)
    }
}

// MARK: - Catalog

enum EmojiCatalog {
    struct Entry: Hashable {
        let emoji: String
        let keywords: String
    }

    struct Group: Identifiable {
        let name: String
        let entries: [Entry]
        var id: String { name }
    }

    static let groups: [Group] = [
        Group(name: "Suggested", entries: make([
            ("📄", "page document file note"), ("📝", "note write memo"), ("📌", "pin important"),
            ("⭐", "star favorite"), ("🔥", "fire hot urgent"), ("✅", "check done complete"),
            ("🎯", "target goal objective"), ("💡", "idea lightbulb insight"), ("🚀", "rocket launch ship"),
            ("📊", "chart data stats"), ("🗂️", "folder archive files"), ("🔖", "bookmark tag")
        ])),
        Group(name: "Work", entries: make([
            ("💼", "briefcase work job"), ("📈", "growth chart up"), ("📉", "decline chart down"),
            ("🏢", "office building company"), ("🤝", "deal partner meeting"), ("📅", "calendar date plan"),
            ("⏰", "clock time deadline"), ("📋", "clipboard list task"), ("🧾", "receipt invoice bill"),
            ("💰", "money budget finance"), ("🏆", "trophy win award"), ("🎓", "school study learn")
        ])),
        Group(name: "Ideas", entries: make([
            ("🧠", "brain think mind"), ("✨", "sparkles magic new"), ("🔮", "crystal future vision"),
            ("🧩", "puzzle piece solve"), ("🔬", "science research lab"), ("🧪", "experiment test try"),
            ("📚", "books read library"), ("🗺️", "map plan roadmap"), ("🧭", "compass direction"),
            ("🎨", "art design creative"), ("🎬", "film video movie"), ("🎵", "music audio song")
        ])),
        Group(name: "People", entries: make([
            ("👤", "person user profile"), ("👥", "people team group"), ("🧑‍💻", "developer engineer code"),
            ("👨‍🎨", "designer artist"), ("🗣️", "speak talk voice"), ("💬", "chat message comment"),
            ("📣", "announce megaphone"), ("❤️", "heart love"), ("🙏", "thanks please"),
            ("👋", "wave hello hi"), ("🤔", "think hmm question"), ("😀", "smile happy")
        ])),
        Group(name: "Status", entries: make([
            ("🟢", "green good ok active"), ("🟡", "yellow warning pending"), ("🔴", "red bad blocked"),
            ("🔵", "blue info"), ("⚪", "white neutral"), ("⚫", "black off"),
            ("⚠️", "warning caution alert"), ("❌", "cross no fail"), ("❗", "important exclaim"),
            ("❓", "question unknown"), ("🔒", "lock private secure"), ("🔓", "unlock open public")
        ])),
        Group(name: "Objects", entries: make([
            ("💻", "laptop computer"), ("📱", "phone mobile"), ("⌨️", "keyboard type"),
            ("🖥️", "desktop monitor screen"), ("🗄️", "cabinet storage"), ("📦", "box package ship"),
            ("🔧", "tool fix wrench"), ("⚙️", "settings gear config"), ("🔑", "key access"),
            ("🧰", "toolbox kit"), ("🪄", "wand magic auto"), ("🔍", "search find magnify")
        ])),
        Group(name: "Nature", entries: make([
            ("🌱", "seedling grow start"), ("🌳", "tree nature"), ("🌊", "wave water sea"),
            ("🌍", "earth world global"), ("☀️", "sun day sunny"), ("🌙", "moon night"),
            ("⚡", "lightning fast power"), ("❄️", "snow cold winter"), ("🍀", "luck clover"),
            ("🌸", "flower bloom spring"), ("🔆", "bright light"), ("🌈", "rainbow color")
        ])),
        Group(name: "Travel", entries: make([
            ("✈️", "plane flight travel"), ("🚗", "car drive"), ("🏠", "home house"),
            ("🏝️", "island vacation holiday"), ("🗼", "tower landmark"), ("🚧", "construction wip"),
            ("🧳", "luggage trip"), ("🛫", "departure takeoff"), ("🛬", "arrival landing"),
            ("🌇", "city sunset"), ("⛰️", "mountain peak"), ("🚩", "flag milestone")
        ]))
    ]

    private static func make(_ pairs: [(String, String)]) -> [Entry] {
        pairs.map { Entry(emoji: $0.0, keywords: $0.1) }
    }

    static func search(_ query: String) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [Entry] = []
        for group in groups {
            for entry in group.entries where entry.keywords.contains(needle) && !seen.contains(entry.emoji) {
                seen.insert(entry.emoji)
                result.append(entry)
            }
        }
        return result
    }
}

// MARK: - Picker

struct PageIconPicker: View {
    let current: String?
    let pick: (String?) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 3), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(OrbitTheme.ink3(scheme))
                    TextField("Filter…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 9).frame(height: 28)
                .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 7))

                if current != nil {
                    Button("Remove") { pick(nil); dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OrbitTheme.rose)
                }
            }

            ScrollView {
                let matches = EmojiCatalog.search(query)
                if !query.isEmpty {
                    if matches.isEmpty {
                        Text("No icon matches “\(query)”.")
                            .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink3(scheme))
                            .padding(.vertical, 14)
                    } else {
                        grid(matches)
                    }
                } else {
                    ForEach(EmojiCatalog.groups) { group in
                        Text(group.name.uppercased())
                            .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(OrbitTheme.ink3(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6).padding(.bottom, 2)
                        grid(group.entries)
                    }
                }
            }
            .frame(height: 250)
        }
        .padding(12)
        .frame(width: 348)
    }

    private func grid(_ entries: [EmojiCatalog.Entry]) -> some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(entries, id: \.self) { entry in
                Button {
                    pick(entry.emoji)
                    dismiss()
                } label: {
                    Text(entry.emoji)
                        .font(.system(size: 20))
                        .frame(width: 34, height: 34)
                        .background(
                            current == entry.emoji ? OrbitTheme.accentSoft(scheme) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.keywords)
            }
        }
    }
}
