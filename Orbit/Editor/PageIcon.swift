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

/// The full Unicode emoji set, derived at runtime from
/// `Unicode.Scalar.Properties` rather than shipped as a hand-written table.
///
/// The stdlib already knows which scalars render as emoji by default and what
/// each one is called, so the catalog stays correct as Apple ships new Unicode
/// revisions instead of drifting against a frozen list.
enum EmojiCatalog {
    struct Entry: Hashable, Identifiable {
        let emoji: String
        /// Lowercased Unicode name plus any aliases, used for searching.
        let keywords: String
        var id: String { emoji }
    }

    enum Category: String, CaseIterable, Identifiable {
        case suggested = "Suggested"
        case smileys = "Smileys & People"
        case nature = "Animals & Nature"
        case food = "Food & Drink"
        case activity = "Activity"
        case travel = "Travel & Places"
        case objects = "Objects"
        case symbols = "Symbols"
        case flags = "Flags"

        var id: String { rawValue }
    }

    struct Group: Identifiable {
        let category: Category
        let entries: [Entry]
        var id: String { category.rawValue }
    }

    // MARK: build

    static let groups: [Group] = build()

    static let all: [Entry] = groups.flatMap(\.entries)

    private static func build() -> [Group] {
        var buckets: [Category: [Entry]] = [:]

        for range in scanRanges {
            for value in range {
                guard let scalar = Unicode.Scalar(value),
                      scalar.properties.isEmoji,
                      !skipped(value),
                      let name = scalar.properties.name else { continue }

                // Emoji that default to *text* presentation (✏️ ❤️ ☺️ ⚙️ …) need
                // U+FE0F to render as emoji. Requiring `isEmojiPresentation`
                // dropped every one of them — several hundred icons.
                let emoji = scalar.properties.isEmojiPresentation
                    ? String(scalar)
                    : String(scalar) + "\u{FE0F}"
                let lower = name.lowercased()
                let keywords = ([lower] + (aliases[emoji].map { [$0] } ?? [])).joined(separator: " ")
                buckets[classify(value: value, name: lower), default: []].append(
                    Entry(emoji: emoji, keywords: keywords)
                )
            }
        }

        // ZWJ sequences are composed of several scalars joined by U+200D, so
        // scalar enumeration cannot see them. They have to be listed.
        for (emoji, keywords, category) in zwjSequences {
            buckets[category, default: []].append(Entry(emoji: emoji, keywords: keywords))
        }

        // Append, never assign — the ZWJ flags above land in this same bucket.
        buckets[.flags, default: []].append(contentsOf: flagEntries())
        buckets[.suggested] = suggested.map { emoji in
            Entry(emoji: emoji, keywords: (aliases[emoji] ?? "") + " " + (unicodeName(of: emoji) ?? ""))
        }

        return Category.allCases.compactMap { category in
            guard let entries = buckets[category], !entries.isEmpty else { return nil }
            return Group(category: category, entries: entries)
        }
    }

    private static func unicodeName(of emoji: String) -> String? {
        emoji.unicodeScalars.first?.properties.name?.lowercased()
    }

    /// Blocks that actually contain emoji-presentation scalars. Scanning the
    /// whole plane would work but wastes a few hundred thousand lookups.
    private static let scanRanges: [ClosedRange<UInt32>] = [
        0x00A9...0x00AE,     // © ®
        0x203C...0x2049,     // ‼️ ⁉️
        0x2100...0x21FF,     // Letterlike symbols and arrows
        0x2300...0x23FF,     // ⌚ ⌨️ ⏰ ⏳ and media controls
        0x2460...0x24FF,     // Enclosed alphanumerics (Ⓜ️)
        0x25A0...0x25FF,     // Geometric shapes
        0x2600...0x27BF,     // Miscellaneous symbols and dingbats
        0x2900...0x297F,     // Supplemental arrows
        0x2B00...0x2BFF,     // Additional arrows and shapes
        0x3030...0x303D,     // 〰️ 〽️
        0x3297...0x3299,     // ㊗️ ㊙️
        0x1F000...0x1F0FF,   // Mahjong, dominoes, playing cards
        0x1F100...0x1F2FF,   // Enclosed alphanumerics and ideographs
        0x1F300...0x1F5FF,   // Miscellaneous symbols and pictographs
        0x1F600...0x1F64F,   // Emoticons
        0x1F650...0x1F67F,   // Ornamental dingbats
        0x1F680...0x1F6FF,   // Transport and map
        0x1F780...0x1F7FF,   // Geometric shapes extended (🟠 🟥 …)
        0x1F900...0x1F9FF,   // Supplemental symbols and pictographs
        0x1FA00...0x1FA6F,   // Chess, symbols extended
        0x1FA70...0x1FAFF    // Symbols and pictographs extended-A (newest emoji)
    ]

    /// Scalars that are technically emoji but must not appear as pickable icons:
    /// skin-tone and hair modifiers, and the regional letters that only mean
    /// something when paired into a flag (those are built separately).
    private static func skipped(_ value: UInt32) -> Bool {
        switch value {
        case 0x1F3FB...0x1F3FF: true   // skin tone modifiers
        case 0x1F9B0...0x1F9B3: true   // hair components
        case 0x1F1E6...0x1F1FF: true   // regional indicators
        case 0x200D, 0xFE0F, 0x20E3: true
        default: false
        }
    }

    /// Unicode blocks are not semantic, so the block only decides the obvious
    /// cases and the scalar's own name settles the rest.
    private static func classify(value: UInt32, name: String) -> Category {
        switch value {
        case 0x1F600...0x1F64F: return .smileys
        case 0x1F680...0x1F6FF: return .travel
        case 0x1F000...0x1F0FF: return .activity
        case 0x1F100...0x1F2FF: return .symbols
        case 0x2B00...0x2BFF: return .symbols
        default: break
        }

        for (category, terms) in nameHints {
            if terms.contains(where: { name.contains($0) }) { return category }
        }

        return value >= 0x2600 && value <= 0x27BF ? .symbols : .objects
    }

    /// Ordered — the first matching category wins, so narrow terms come first.
    private static let nameHints: [(Category, [String])] = [
        (.food, ["apple", "banana", "grape", "pizza", "burger", "bread", "cheese", "meat", "rice",
                 "sushi", "cake", "cookie", "candy", "chocolate", "coffee", "tea", "beer", "wine",
                 "cocktail", "drink", "bottle", "egg", "milk", "ice cream", "doughnut", "popcorn",
                 "salad", "soup", "taco", "burrito", "noodle", "honey", "peach", "pear", "cherry",
                 "strawberry", "lemon", "melon", "pineapple", "coconut", "avocado", "tomato",
                 "potato", "carrot", "corn", "pepper", "cucumber", "broccoli", "peanut", "bacon",
                 "pancake", "waffle", "croissant", "pretzel", "sandwich", "fries", "lollipop",
                 "cupcake", "pie", "chopsticks", "fork", "spoon", "cup", "mug", "teapot", "juice",
                 "champagne", "whisky", "sake", "mate", "olive", "onion", "garlic", "beans"]),
        (.nature, ["cat", "dog", "mouse", "hamster", "rabbit", "fox", "bear", "panda", "bird",
                   "fish", "whale", "dolphin", "monkey", "horse", "cow", "pig", "sheep", "goat",
                   "camel", "elephant", "tiger", "lion", "wolf", "bug", "ant", "bee", "spider",
                   "snake", "turtle", "lizard", "dinosaur", "flower", "plant", "tree", "leaf",
                   "herb", "cactus", "mushroom", "seedling", "blossom", "rose", "tulip", "sun",
                   "moon", "star", "cloud", "rain", "snow", "wind", "wave", "globe", "earth",
                   "volcano", "shell", "feather", "paw", "penguin", "frog", "chicken", "duck",
                   "eagle", "owl", "bat", "shark", "octopus", "crab", "butterfly", "dragon",
                   "unicorn", "deer", "zebra", "giraffe", "rhino", "hippo", "koala", "sloth",
                   "otter", "skunk", "badger", "squirrel", "hedgehog", "kangaroo", "llama",
                   "tornado", "fog", "thunder", "lightning", "droplet", "comet", "milky way"]),
        (.smileys, ["face", "person", "man", "woman", "boy", "girl", "baby", "hand", "finger",
                    "arm", "leg", "foot", "ear", "nose", "eye", "mouth", "tongue", "tooth",
                    "people", "family", "police", "worker", "adult", "older", "pregnant", "kiss",
                    "couple", "santa", "elf", "fairy", "vampire", "zombie", "genie", "merperson",
                    "superhero", "supervillain", "ninja", "detective", "guard", "student",
                    "teacher", "judge", "farmer", "cook", "mechanic", "scientist", "artist",
                    "pilot", "astronaut", "firefighter", "bride", "tuxedo", "prince", "princess",
                    "monkey face", "cat face", "smil", "wink", "cry", "angry", "hugging",
                    "thinking", "shrug", "clap", "wave", "muscle", "brain", "skull", "ghost",
                    "alien", "robot", "poo", "footprint", "bust", "silhouette", "speaking head"]),
        (.activity, ["ball", "sport", "trophy", "medal", "game", "dice", "puzzle", "guitar",
                     "drum", "piano", "trumpet", "violin", "saxophone", "banjo", "accordion",
                     "microphone", "headphone", "palette", "circus", "ticket", "party", "balloon",
                     "gift", "firework", "sparkler", "mask", "kimono", "ski", "snowboard",
                     "skate", "fishing", "bow and arrow", "kite", "yo-yo", "juggling", "climbing",
                     "surfing", "swimming", "rowing", "cycling", "running", "dancing", "wrestling",
                     "fencing", "boxing", "karate", "golf", "bowling", "cricket", "hockey",
                     "badminton", "goal net", "flag in hole", "reminder ribbon", "confetti"]),
        (.travel, ["car", "bus", "train", "plane", "rocket", "ship", "boat", "bicycle",
                   "motorcycle", "truck", "taxi", "helicopter", "satellite", "anchor", "fuel",
                   "traffic", "house", "building", "hotel", "school", "hospital", "bank",
                   "church", "mosque", "temple", "synagogue", "castle", "bridge", "tower",
                   "statue", "map", "compass", "tent", "beach", "island", "desert", "park",
                   "cityscape", "sunrise", "sunset", "night with stars", "fountain", "stadium",
                   "factory", "office", "post office", "convenience store", "department store",
                   "railway", "station", "motorway", "roller coaster", "ferris wheel", "carousel",
                   "camping", "mountain", "volcano", "moai", "luggage", "passport", "hut"]),
        (.objects, ["phone", "computer", "laptop", "keyboard", "printer", "camera", "television",
                    "radio", "battery", "plug", "bulb", "flashlight", "book", "newspaper",
                    "money", "dollar", "yen", "euro", "pound", "credit card", "envelope", "mail",
                    "pencil", "pen", "paper", "folder", "file", "clipboard", "scissors", "lock",
                    "key", "hammer", "wrench", "screw", "gear", "tool", "magnet", "telescope",
                    "microscope", "pill", "syringe", "bed", "chair", "toilet", "shower", "bath",
                    "soap", "broom", "basket", "clothes", "shirt", "dress", "shoe", "boot",
                    "hat", "glasses", "ring", "gem", "crown", "bag", "briefcase", "umbrella",
                    "clock", "watch", "hourglass", "bell", "candle", "trash", "package", "label",
                    "scroll", "chart", "calendar", "card index", "abacus", "balance scale",
                    "test tube", "petri", "dna", "bandage", "stethoscope", "crutch", "x-ray",
                    "mirror", "window", "door", "chain", "hook", "ladder", "brick", "rock",
                    "wood", "nut and bolt", "gun", "bomb", "knife", "shield", "axe", "saw",
                    "sponge", "bucket", "plunger", "mouse trap", "razor", "lotion", "thread",
                    "sewing", "knot", "yarn", "safety pin", "paperclip", "pushpin", "straight ruler",
                    "triangular ruler", "wastebasket", "ballot", "inbox", "outbox", "speaker",
                    "megaphone", "postbox", "horn", "videocassette", "film", "projector", "dvd",
                    "cd", "floppy", "minidisc", "joystick", "trackball", "battery", "electric plug"])
    ]

    /// Unicode names are precise but rarely what a person types. A short alias
    /// table covers the searches people actually make.
    private static let aliases: [String: String] = [
        "😀": "smile happy grin", "😂": "laugh lol funny tears", "🙂": "smile slight",
        "😍": "love heart eyes adore", "😎": "cool sunglasses", "🤔": "think hmm question",
        "😢": "sad cry tear", "😡": "angry mad rage", "😴": "sleep tired",
        "🎉": "party celebrate congrats tada", "🔥": "fire hot urgent lit",
        "✅": "check done complete tick yes ok", "❌": "cross no fail wrong",
        "⚠️": "warning caution alert", "💡": "idea insight lightbulb",
        "🚀": "launch ship fast growth", "🎯": "goal target objective aim",
        "📌": "pin important stick", "⭐": "star favourite favorite rating",
        "❤️": "love heart red", "💰": "money cash budget finance",
        "📊": "chart data stats analytics graph", "📈": "growth up increase trend",
        "📉": "decline down decrease loss", "🧠": "brain think mind smart",
        "💻": "laptop computer dev code work", "📝": "note write memo edit doc",
        "📄": "page document file paper", "🗂️": "folder files archive organise organize",
        "🔒": "lock private secure closed", "🔓": "unlock open public",
        "🔍": "search find magnify look", "⚙️": "settings config gear options",
        "🐛": "bug defect issue error", "🌱": "seedling grow start new",
        "🏆": "trophy win award first", "⏰": "clock time deadline alarm",
        "📅": "calendar date schedule plan", "🤝": "deal partner agree meeting",
        "🙏": "thanks please pray grateful", "👋": "wave hello hi bye",
        "👍": "yes good approve thumbs up like", "👎": "no bad reject thumbs down",
        "🎨": "design art creative colour color", "🧪": "experiment test lab try",
        "📦": "package box ship release", "🚧": "wip construction blocked progress",
        "🏠": "home house main", "✈️": "plane travel flight trip",
        "🍕": "pizza food lunch", "☕": "coffee cafe morning break"
    ]

    /// Multi-scalar emoji (professions, couples, families, gendered variants).
    /// Skin-tone modifiers are deliberately left out — they would multiply this
    /// fivefold for no gain as a page icon.
    private static let zwjSequences: [(String, String, Category)] = [
        ("\u{1F9D1}\u{200D}\u{1F4BB}", "technologist developer engineer coder programmer", .smileys),
        ("\u{1F468}\u{200D}\u{1F4BB}", "man technologist developer engineer coder", .smileys),
        ("\u{1F469}\u{200D}\u{1F4BB}", "woman technologist developer engineer coder", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F3A8}", "artist designer creative painter", .smileys),
        ("\u{1F468}\u{200D}\u{1F3A8}", "man artist designer painter", .smileys),
        ("\u{1F469}\u{200D}\u{1F3A8}", "woman artist designer painter", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F52C}", "scientist researcher lab science", .smileys),
        ("\u{1F468}\u{200D}\u{1F52C}", "man scientist researcher science", .smileys),
        ("\u{1F469}\u{200D}\u{1F52C}", "woman scientist researcher science", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F393}", "student graduate study school learn", .smileys),
        ("\u{1F468}\u{200D}\u{1F393}", "man student graduate study", .smileys),
        ("\u{1F469}\u{200D}\u{1F393}", "woman student graduate study", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F3EB}", "teacher professor educator school", .smileys),
        ("\u{1F468}\u{200D}\u{1F3EB}", "man teacher professor educator", .smileys),
        ("\u{1F469}\u{200D}\u{1F3EB}", "woman teacher professor educator", .smileys),
        ("\u{1F9D1}\u{200D}\u{2696}\u{FE0F}", "judge justice law legal court", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F33E}", "farmer agriculture crop field", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F373}", "cook chef kitchen restaurant", .smileys),
        ("\u{1F468}\u{200D}\u{1F373}", "man cook chef kitchen", .smileys),
        ("\u{1F469}\u{200D}\u{1F373}", "woman cook chef kitchen", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F527}", "mechanic engineer repair fix tools", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F3ED}", "factory worker industry manufacturing", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F4BC}", "office worker business manager executive", .smileys),
        ("\u{1F468}\u{200D}\u{1F4BC}", "man office worker business manager", .smileys),
        ("\u{1F469}\u{200D}\u{1F4BC}", "woman office worker business manager", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F680}", "astronaut space rocket explorer", .smileys),
        ("\u{1F468}\u{200D}\u{1F680}", "man astronaut space rocket", .smileys),
        ("\u{1F469}\u{200D}\u{1F680}", "woman astronaut space rocket", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F692}", "firefighter fire rescue emergency", .smileys),
        ("\u{1F9D1}\u{200D}\u{2695}\u{FE0F}", "health worker doctor nurse medical", .smileys),
        ("\u{1F468}\u{200D}\u{2695}\u{FE0F}", "man doctor health medical", .smileys),
        ("\u{1F469}\u{200D}\u{2695}\u{FE0F}", "woman doctor health medical", .smileys),
        ("\u{1F9D1}\u{200D}\u{2708}\u{FE0F}", "pilot aviation plane fly", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F9BD}", "wheelchair accessibility manual", .smileys),
        ("\u{1F9D1}\u{200D}\u{1F9AF}", "blind cane accessibility white", .smileys),
        ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}", "family parents child", .smileys),
        ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "family parents daughter", .smileys),
        ("\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F466}", "family two mothers child", .smileys),
        ("\u{1F468}\u{200D}\u{1F468}\u{200D}\u{1F466}", "family two fathers child", .smileys),
        ("\u{1F469}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F468}", "couple heart love partners", .smileys),
        ("\u{1F468}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F468}", "couple heart love men", .smileys),
        ("\u{1F469}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F469}", "couple heart love women", .smileys),
        ("\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", "rainbow flag pride lgbt", .flags),
        ("\u{1F3F4}\u{200D}\u{2620}\u{FE0F}", "pirate flag jolly roger skull", .flags),
        ("\u{1F3F3}\u{FE0F}\u{200D}\u{26A7}\u{FE0F}", "transgender flag pride", .flags),
        ("\u{1F441}\u{FE0F}\u{200D}\u{1F5E8}\u{FE0F}", "eye speech witness testimony", .symbols),
        ("\u{2764}\u{FE0F}\u{200D}\u{1F525}", "heart on fire burning love passion", .symbols),
        ("\u{2764}\u{FE0F}\u{200D}\u{1FA79}", "mending heart healing broken recovery", .symbols),
        ("\u{1F408}\u{200D}\u{2B1B}", "black cat animal", .nature),
        ("\u{1F415}\u{200D}\u{1F9BA}", "service dog assistance animal", .nature),
        ("\u{1F426}\u{200D}\u{2B1B}", "black bird crow raven", .nature),
        ("\u{1F43B}\u{200D}\u{2744}\u{FE0F}", "polar bear arctic white", .nature),
        ("\u{1F344}\u{200D}\u{1F7EB}", "brown mushroom fungus", .nature)
    ]

    private static let suggested = [
        "📄", "📝", "📌", "⭐", "🔥", "✅", "🎯", "💡", "🚀", "📊", "🗂️", "🔖",
        "🧠", "✨", "💼", "📅", "🏆", "🤝", "🐛", "⚙️", "🌱", "❤️", "🔒", "🎨",
        "\u{1F9D1}\u{200D}\u{1F4BB}", "\u{1F680}", "\u{1F4CA}", "\u{1F393}"
    ]

    // MARK: flags

    private static func flagEntries() -> [Entry] {
        let base: UInt32 = 0x1F1E6
        let letterA = Character("A").asciiValue.map(UInt32.init) ?? 65

        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy { $0.isLetter && $0.isUppercase } }
            .sorted()
            .compactMap { code -> Entry? in
                // Regions without a display name are aggregates, not countries.
                guard let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
                var flag = ""
                for character in code {
                    guard let ascii = character.asciiValue.map(UInt32.init),
                          let scalar = Unicode.Scalar(base + ascii - letterA) else { return nil }
                    flag.unicodeScalars.append(scalar)
                }
                return Entry(emoji: flag, keywords: "\(name.lowercased()) \(code.lowercased()) flag")
            }
    }

    // MARK: search

    static func search(_ query: String) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }

        var seen = Set<String>()
        var exact: [Entry] = []
        var partial: [Entry] = []

        for entry in all where !seen.contains(entry.emoji) {
            guard entry.keywords.contains(needle) else { continue }
            seen.insert(entry.emoji)
            // Whole-word hits rank above mid-word ones so "cat" beats "caterpillar".
            if entry.keywords.split(separator: " ").contains(where: { $0 == needle }) {
                exact.append(entry)
            } else {
                partial.append(entry)
            }
        }

        return exact + partial
    }
}

// MARK: - Picker

struct PageIconPicker: View {
    let current: String?
    let pick: (String?) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 2), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(OrbitTheme.ink3(scheme))
                    TextField("Search all emoji…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12))
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.orbitRow).foregroundStyle(OrbitTheme.ink3(scheme))
                    }
                }
                .padding(.horizontal, 9).frame(height: 28)
                .background(OrbitTheme.sunken(scheme), in: RoundedRectangle(cornerRadius: 7))

                if current != nil {
                    Button("Remove") { pick(nil); dismiss() }
                        .buttonStyle(.orbitRow)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OrbitTheme.rose)
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    if query.isEmpty {
                        ForEach(EmojiCatalog.groups) { group in
                            Section {
                                cells(group.entries)
                            } header: {
                                header(group.category.rawValue)
                            }
                        }
                    } else {
                        let matches = EmojiCatalog.search(query)
                        Section {
                            cells(matches)
                        } header: {
                            header(matches.isEmpty ? "No match" : "\(matches.count) results")
                        }
                    }
                }
            }
            .frame(height: 268)
        }
        .padding(12)
        .frame(width: 360)
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold)).tracking(0.8)
            .foregroundStyle(OrbitTheme.ink3(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 7).padding(.bottom, 3)
            .background(OrbitTheme.surface(scheme))
            .gridCellColumns(10)
    }

    @ViewBuilder
    private func cells(_ entries: [EmojiCatalog.Entry]) -> some View {
        ForEach(entries) { entry in
            Button {
                pick(entry.emoji)
                dismiss()
            } label: {
                Text(entry.emoji)
                    .font(.system(size: 19))
                    .frame(width: 32, height: 32)
                    .background(
                        current == entry.emoji ? OrbitTheme.accentSoft(scheme) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.orbitRow)
            .help(entry.keywords)
        }
    }
}
