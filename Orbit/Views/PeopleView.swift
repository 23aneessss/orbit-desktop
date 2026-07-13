import AppKit
import SwiftData
import SwiftUI

private enum PeopleFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"
    case followUps = "Due follow-up"
    var id: String { rawValue }
}

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Contact.name) private var contacts: [Contact]
    @Query(sort: \Interaction.dateKey, order: .reverse) private var interactions: [Interaction]

    @AppStorage("orbit:people-seeded") private var peopleSeeded = false
    @State private var query = ""
    @State private var filter: PeopleFilter = .all
    @State private var selectedContactID: UUID?
    @State private var editingContact: Contact?
    @State private var showingNewContact = false

    private var filteredContacts: [Contact] {
        contacts.filter { contact in
            let searchable = [contact.name, contact.company ?? "", contact.role ?? "", contact.email ?? ""] + contact.tags
            let matchesQuery = query.isEmpty || searchable.contains { $0.localizedStandardContains(query) }
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = contact.favorite
            case .followUps: matchesFilter = contact.nextFollowUpKey.map { $0 <= OrbitDate.key() } ?? false
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        if let selectedContactID, let contact = contacts.first(where: { $0.id == selectedContactID }) {
            PersonDetailView(
                contact: contact,
                interactions: interactions.filter { $0.contactID == selectedContactID },
                close: { self.selectedContactID = nil },
                edit: { editingContact = contact },
                delete: { delete(contact) }
            )
            .sheet(item: $editingContact) { contact in
                ContactFormView(contact: contact, isNew: false, onCancel: { editingContact = nil }, onSave: { _ in try? modelContext.save(); editingContact = nil })
            }
        } else {
            browser
                .task { seedPeopleIfNeeded() }
                .sheet(isPresented: $showingNewContact) {
                    ContactFormView(contact: Contact(name: ""), isNew: true, onCancel: { showingNewContact = false }) { contact in
                        modelContext.insert(contact); try? modelContext.save(); showingNewContact = false; selectedContactID = contact.id
                    }
                }
        }
    }

    private var browser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("People").font(.system(size: 27, weight: .semibold))
                        Text("Remember the context, not just the contact details.")
                            .font(.system(size: 13.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }
                    Spacer()
                    Button { showingNewContact = true } label: { Label("New person", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(OrbitTheme.accent)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(OrbitTheme.ink3(scheme))
                        TextField("Search people, companies, roles, or tags", text: $query).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 13).frame(height: 40).frame(maxWidth: 430)
                    .background(OrbitTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(OrbitTheme.line(scheme)) }
                    Picker("Filter", selection: $filter) {
                        ForEach(PeopleFilter.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 310)
                    Spacer()
                }

                if filteredContacts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2").font(.system(size: 22)).foregroundStyle(OrbitTheme.accent)
                            .frame(width: 50, height: 50).background(OrbitTheme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: 14))
                        Text(contacts.isEmpty ? "Add someone you want to remember" : "No people match")
                            .font(.system(size: 17, weight: .semibold))
                        Text(contacts.isEmpty ? "Orbit keeps relationship context private and local." : "Try another search or filter.")
                            .font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    }.frame(maxWidth: .infinity, minHeight: 350)
                } else {
                    contactsTable
                }
            }
            .padding(32).frame(maxWidth: 1160, alignment: .leading).frame(maxWidth: .infinity)
        }.background(OrbitTheme.canvas(scheme))
    }

    private var contactsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("PERSON").frame(maxWidth: .infinity, alignment: .leading)
                Text("COMPANY").frame(width: 170, alignment: .leading)
                Text("LAST CONTACT").frame(width: 130, alignment: .leading)
                Text("FOLLOW-UP").frame(width: 140, alignment: .leading)
                Spacer().frame(width: 28)
            }
            .font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(OrbitTheme.ink3(scheme))
            .padding(.horizontal, 16).frame(height: 42).background(OrbitTheme.sunken(scheme).opacity(0.5))

            ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                Button { selectedContactID = contact.id } label: {
                    HStack(spacing: 16) {
                        HStack(spacing: 11) {
                            PersonAvatar(name: contact.name, size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(contact.name).font(.system(size: 13, weight: .medium)).foregroundStyle(OrbitTheme.ink(scheme))
                                Text(contact.role ?? contact.email ?? "No details yet").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(contact.company ?? "—").frame(width: 170, alignment: .leading)
                        Text(relativeDate(contact.lastContactedKey, fallback: "Never")).frame(width: 130, alignment: .leading)
                        FollowUpBadge(dateKey: contact.nextFollowUpKey).frame(width: 140, alignment: .leading)
                        Button { contact.favorite.toggle(); try? modelContext.save() } label: {
                            Image(systemName: contact.favorite ? "star.fill" : "star").foregroundStyle(contact.favorite ? OrbitTheme.amber : OrbitTheme.ink3(scheme))
                        }.buttonStyle(.plain).frame(width: 28)
                    }
                    .font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme))
                    .padding(.horizontal, 16).frame(height: 62).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if index < filteredContacts.count - 1 { Divider().padding(.leading, 60) }
            }
        }.orbitCard()
    }

    private func relativeDate(_ key: String?, fallback: String) -> String {
        guard let key, let date = OrbitDate.keyFormatter.date(from: key) else { return fallback }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }

    private func delete(_ contact: Contact) {
        interactions.filter { $0.contactID == contact.id }.forEach(modelContext.delete)
        modelContext.delete(contact); try? modelContext.save(); selectedContactID = nil
    }

    private func seedPeopleIfNeeded() {
        guard !peopleSeeded else { return }
        guard contacts.isEmpty else { peopleSeeded = true; return }
        let people = [
            Contact(name: "Sara Mansouri", email: "sara@example.com", company: "Figma", role: "Product Designer", tags: ["design", "friend"], favorite: true, lastContactedKey: OrbitDate.key(OrbitDate.date(daysFromToday: -5)), nextFollowUpKey: OrbitDate.key(OrbitDate.date(daysFromToday: -3))),
            Contact(name: "Yassine Berrada", email: "yassine@example.com", company: "Stripe", role: "Engineer", tags: ["engineering"], favorite: true, lastContactedKey: OrbitDate.key(OrbitDate.date(daysFromToday: -12)), nextFollowUpKey: OrbitDate.key(OrbitDate.date(daysFromToday: -8))),
            Contact(name: "Lina Haddad", email: "lina@example.com", company: "Notion", role: "Product Manager", tags: ["product"], lastContactedKey: OrbitDate.key(OrbitDate.date(daysFromToday: -19)), nextFollowUpKey: OrbitDate.key(OrbitDate.date(daysFromToday: -6))),
            Contact(name: "Marc Dubois", email: "marc@example.com", role: "Founder", tags: ["founder"], lastContactedKey: OrbitDate.key(OrbitDate.date(daysFromToday: -3)), nextFollowUpKey: OrbitDate.key(OrbitDate.date(daysFromToday: 7))),
            Contact(name: "Nadia El Fassi", email: "nadia@example.com", company: "INRIA", role: "Researcher", tags: ["research"], lastContactedKey: OrbitDate.key(OrbitDate.date(daysFromToday: -10)), nextFollowUpKey: OrbitDate.key(OrbitDate.date(daysFromToday: 4)))
        ]
        people.forEach(modelContext.insert)
        for (index, person) in people.enumerated() {
            modelContext.insert(Interaction(contactID: person.id, kind: ["meeting", "call", "message", "email", "note"][index], note: "Caught up and recorded the context for next time.", dateKey: person.lastContactedKey ?? OrbitDate.key()))
        }
        try? modelContext.save(); peopleSeeded = true
    }
}

private struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Bindable var contact: Contact
    let interactions: [Interaction]
    let close: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    @State private var interactionKind = "note"
    @State private var interactionNote = ""
    @State private var interactionDate = Date.now
    @State private var followUpDate = Date.now

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) { Label("People", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Button("Edit", action: edit).buttonStyle(.bordered)
                Button("Delete", role: .destructive, action: delete).buttonStyle(.bordered)
            }.padding(.horizontal, 28).frame(height: 54)
            Divider().overlay(OrbitTheme.line(scheme))

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 15) {
                            PersonAvatar(name: contact.name, size: 64)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(contact.name).font(.system(size: 24, weight: .semibold))
                                Text([contact.role, contact.company].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(OrbitTheme.ink2(scheme))
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach(contact.tags, id: \.self) { Text("#\($0)").font(.system(size: 10.5)).padding(.horizontal, 8).padding(.vertical, 5).background(OrbitTheme.sunken(scheme), in: Capsule()) }
                        }
                        Divider().overlay(OrbitTheme.line(scheme))
                        if let email = contact.email, !email.isEmpty { contactLink("envelope", email, url: "mailto:\(email)") }
                        if let phone = contact.phone, !phone.isEmpty { contactLink("phone", phone, url: "tel:\(phone)") }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("FOLLOW-UP").font(.system(size: 9.5, weight: .semibold)).tracking(0.9).foregroundStyle(OrbitTheme.ink3(scheme))
                            DatePicker("Next", selection: $followUpDate, displayedComponents: .date).labelsHidden()
                                .onChange(of: followUpDate) { contact.nextFollowUpKey = OrbitDate.key(followUpDate); try? modelContext.save() }
                            if contact.nextFollowUpKey != nil {
                                Button("Mark done") { contact.nextFollowUpKey = nil; try? modelContext.save() }.buttonStyle(.plain).foregroundStyle(OrbitTheme.accent)
                            }
                        }
                        Spacer()
                    }.padding(28)
                }
                .frame(width: 300).background(OrbitTheme.sunken(scheme).opacity(0.35))
                Divider().overlay(OrbitTheme.line(scheme))

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        interactionComposer
                        VStack(alignment: .leading, spacing: 0) {
                            Text("History").font(.system(size: 16, weight: .semibold)).padding(.bottom, 14)
                            ForEach(interactions.sorted { $0.dateKey > $1.dateKey }) { item in
                                InteractionRow(interaction: item) { modelContext.delete(item); try? modelContext.save() }
                            }
                        }
                    }.padding(32).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
        }
        .background(OrbitTheme.canvas(scheme))
        .onAppear {
            if let key = contact.nextFollowUpKey, let date = OrbitDate.keyFormatter.date(from: key) { followUpDate = date }
        }
    }

    private var interactionComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log an interaction").font(.system(size: 15, weight: .semibold))
            Picker("Kind", selection: $interactionKind) {
                ForEach(["note", "call", "meeting", "message", "email"], id: \.self) { Text($0.capitalized).tag($0) }
            }.pickerStyle(.segmented)
            TextEditor(text: $interactionNote).font(.system(size: 13)).frame(minHeight: 90)
                .padding(7).background(OrbitTheme.sunken(scheme).opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                DatePicker("Date", selection: $interactionDate, in: ...Date.now, displayedComponents: .date)
                Spacer()
                Button("Log it") { addInteraction() }.buttonStyle(.borderedProminent).tint(OrbitTheme.accent).disabled(interactionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).orbitCard()
    }

    private func contactLink(_ symbol: String, _ label: String, url: String) -> some View {
        Button { if let url = URL(string: url) { NSWorkspace.shared.open(url) } } label: {
            Label(label, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).foregroundStyle(OrbitTheme.ink2(scheme))
    }

    private func addInteraction() {
        let note = interactionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        let key = OrbitDate.key(interactionDate)
        modelContext.insert(Interaction(contactID: contact.id, kind: interactionKind, note: note, dateKey: key))
        if contact.lastContactedKey == nil || key > contact.lastContactedKey! { contact.lastContactedKey = key }
        interactionNote = ""; interactionDate = .now; try? modelContext.save()
    }
}

private struct InteractionRow: View {
    @Environment(\.colorScheme) private var scheme
    let interaction: Interaction
    let delete: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: interactionSymbol(interaction.kind)).font(.system(size: 12)).foregroundStyle(OrbitTheme.accent)
                .frame(width: 30, height: 30).background(OrbitTheme.accentSoft(scheme), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(interaction.kind.capitalized).font(.system(size: 12.5, weight: .semibold)); Text(interaction.dateKey).font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)); Spacer(); Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(OrbitTheme.ink3(scheme)) }
                Text(interaction.note).font(.system(size: 12.5)).foregroundStyle(OrbitTheme.ink2(scheme)).textSelection(.enabled)
            }
        }.padding(.vertical, 11)
    }

    private func interactionSymbol(_ kind: String) -> String {
        switch kind { case "call": "phone.fill"; case "meeting": "person.3.fill"; case "message": "message.fill"; case "email": "envelope.fill"; default: "doc.text.fill" }
    }
}

private struct ContactFormView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var contact: Contact
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (Contact) -> Void
    @State private var tagsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New person" : "Edit person").font(.system(size: 21, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                fieldRow("Name", text: $contact.name)
                fieldRow("Role", text: optionalBinding(\Contact.role))
                fieldRow("Company", text: optionalBinding(\Contact.company))
                fieldRow("Email", text: optionalBinding(\Contact.email))
                fieldRow("Phone", text: optionalBinding(\Contact.phone))
                fieldRow("Tags", text: $tagsText)
            }
            HStack { Spacer(); Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction); Button(isNew ? "Add person" : "Save") { contact.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }; onSave(contact) }.buttonStyle(.borderedProminent).tint(OrbitTheme.accent).keyboardShortcut(.defaultAction).disabled(contact.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 480).onAppear { tagsText = contact.tags.joined(separator: ", ") }
    }

    private func fieldRow(_ label: String, text: Binding<String>) -> some View {
        GridRow { Text(label).font(.system(size: 11.5)).foregroundStyle(OrbitTheme.ink2(scheme)).frame(width: 72, alignment: .trailing); TextField(label, text: text).textFieldStyle(.roundedBorder) }
    }
    private func optionalBinding(_ keyPath: ReferenceWritableKeyPath<Contact, String?>) -> Binding<String> {
        Binding(get: { contact[keyPath: keyPath] ?? "" }, set: { contact[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }
}

struct PersonAvatar: View {
    let name: String
    let size: CGFloat
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    private var hue: Double { Double(name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) }
    var body: some View {
        Text(initials.isEmpty ? "?" : initials).font(.system(size: size * 0.31, weight: .semibold))
            .foregroundStyle(Color(hue: hue / 360, saturation: 0.58, brightness: 0.42))
            .frame(width: size, height: size).background(Color(hue: hue / 360, saturation: 0.22, brightness: 0.94), in: Circle())
            .accessibilityLabel(name)
    }
}

struct FollowUpBadge: View {
    @Environment(\.colorScheme) private var scheme
    let dateKey: String?
    var body: some View {
        if let dateKey {
            Text(label(dateKey)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(color(dateKey))
                .padding(.horizontal, 8).padding(.vertical, 4).background(color(dateKey).opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
        } else { Text("None").font(.system(size: 10.5)).foregroundStyle(OrbitTheme.ink3(scheme)) }
    }
    private func label(_ key: String) -> String {
        let today = OrbitDate.key()
        if key == today { return "Today" }
        guard let date = OrbitDate.keyFormatter.date(from: key) else { return key }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
    private func color(_ key: String) -> Color { key < OrbitDate.key() ? OrbitTheme.rose : key == OrbitDate.key() ? OrbitTheme.amber : OrbitTheme.ink2(scheme) }
}
