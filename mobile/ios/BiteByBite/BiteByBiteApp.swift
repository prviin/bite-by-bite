import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

@main struct BiteByBiteApp: App {
    var body: some Scene { WindowGroup { JournalHome() } }
}
private let biteTint = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.60, green: 0.80, blue: 0.57, alpha: 1) : UIColor(red: 0.15, green: 0.31, blue: 0.25, alpha: 1) })
private func grams(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " g" } ?? "—" }
struct EditorRequest: Identifiable { let id = UUID(); let type: String; var entry: JournalEntry?; var photo = false }

struct JournalHome: View {
    @StateObject private var store = JournalStore()
    @StateObject private var connection = PhoneConnection()
    @StateObject private var reminders = PhoneReminders()
    @State private var date = Date()
    @State private var period: JournalPeriod = .day
    @State private var settings = false
    @State private var editor: EditorRequest?
    @State private var waterAmount = "250"
    @State private var supplementName = ""
    private var summary: JournalSummary { store.summary(date, period) }
    private var day: String { JournalDates.key(date) }
    private var days: [String] { JournalDates.keys(date, period) }
    private var dailyWater: Int { store.state.wellness.water.filter { $0.date == day }.reduce(0) { $0 + $1.ml } }
    private var today: JournalSummary { store.summary(Date(), .day) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("One meal at a time.").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Period", selection: $period) { ForEach(JournalPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous period")
                        DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden().frame(maxWidth: .infinity)
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next period")
                        Button("Today") { date = Date() }.font(.caption)
                    }.buttonStyle(.borderless)
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(period == .day ? "Your daily balance" : "Your \(period.rawValue.lowercased()) in view").font(.headline)
                        HStack(alignment: .firstTextBaseline) { Text(summary.net.formatted()).font(.system(size: 43, weight: .semibold, design: .rounded)); Text("net kcal").foregroundStyle(.secondary) }
                        HStack { metric("Food", summary.food); Spacer(); metric("Burned", summary.activity); Spacer(); metric("Adjusted", summary.adjustment) }
                        let target = store.state.goal * days.count
                        ProgressView(value: min(Double(summary.intake), Double(target)), total: Double(target)).tint(biteTint)
                        Text("\(summary.intake) / \(target) kcal food target · \(abs(target - summary.intake)) \(summary.intake > target ? "above target" : "remaining")").font(.caption).foregroundStyle(.secondary)
                        Text("Net = food + adjustments − activity. Exercise does not increase the food target.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if store.state.notifications && today.intake >= Int(ceil(Double(store.state.goal) * 0.85)) {
                    Section { Label("You’ve logged \(Int((Double(today.intake) / Double(store.state.goal) * 100).rounded()))% of today’s food target. Keep your next meals in mind and listen to your hunger.", systemImage: "bell.badge").font(.callout).foregroundStyle(.orange) }
                }
                Section("Add to your journal") {
                    HStack {
                        action("Meal photo", "camera") { editor = EditorRequest(type: "food", photo: true) }
                        Spacer(); action("Food", "fork.knife") { editor = EditorRequest(type: "food") }
                        Spacer(); action("Activity", "figure.walk") { editor = EditorRequest(type: "activity") }
                        Spacer(); action("Adjust", "plusminus") { editor = EditorRequest(type: "adjustment") }
                    }.buttonStyle(.borderless).padding(.vertical, 5)
                }
                Section("Nutrients · selected \(period.rawValue.lowercased())") {
                    ForEach(PhotoEstimate.Nutrients.fields, id: \.0) { key, label in
                        let value = summary.nutrient(key)
                        HStack { Text(label); Spacer(); VStack(alignment: .trailing) { Text(grams(value.grams)).fontWeight(.medium); Text("\(value.count)/\(summary.meals.count) meals recorded").font(.caption2).foregroundStyle(.secondary) } }
                    }
                    Text("Unknown is shown as —. Totals include recorded values only. Carbs include fiber and sugar; fat includes oils.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if summary.entries.isEmpty { ContentEmpty() }
                    ForEach(summary.entries.sorted { $0.date == $1.date ? ($0.created ?? 0) > ($1.created ?? 0) : $0.date > $1.date }) { e in
                        Button { editor = EditorRequest(type: e.type, entry: e) } label: {
                            HStack(alignment: .top) {
                                Image(systemName: e.type == "activity" ? "figure.walk" : e.type == "food" ? "fork.knife" : "plusminus").foregroundStyle(biteTint).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) { Text(e.name).fontWeight(.medium); Text([e.date, e.minutes.map { "\(Int($0)) min" }, e.source == "photo" ? "Photo estimate" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    if let n = e.nutrients { Text(PhotoEstimate.Nutrients.fields.map { "\($0.1): \(grams(n.value($0.0)))" }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
                                    if let details = e.portionDetails, !details.isEmpty { Text("You ate: \(details)").font(.caption).foregroundStyle(.secondary) }
                                    if let note = e.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                }
                                Spacer(); Text("\(e.type == "activity" ? "−" : e.calories < 0 ? "−" : "+")\(abs(e.calories))").monospacedDigit().foregroundStyle(e.type == "activity" ? Color.orange : Color.primary)
                            }.foregroundStyle(.primary).padding(.vertical, 4)
                        }.swipeActions { Button("Delete", role: .destructive) { store.deleteEntry(e.id) } }
                    }
                } header: { Text("Journal · \(summary.entries.count) entries") } footer: { Text("Tap an entry to edit. Swipe left to delete.") }
                if period != .day {
                    Section("Daily rhythm") {
                        ForEach(days, id: \.self) { key in
                            let s = JournalSummary(entries: store.state.entries.filter { $0.date == key })
                            HStack { Text(String(key.suffix(5))).font(.caption); ProgressView(value: min(Double(max(0, s.net)), Double(store.state.goal * 2)), total: Double(store.state.goal * 2)); Text("\(s.net)").font(.caption).monospacedDigit().frame(width: 50, alignment: .trailing) }
                        }
                    }
                }
                Section("Water · \(day)") {
                    LabeledContent("Logged", value: "\(dailyWater) ml")
                    if let goal = store.state.wellness.waterGoal { ProgressView(value: Double(min(dailyWater, goal)), total: Double(goal)); Text("Your personal goal: \(goal) ml").font(.caption).foregroundStyle(.secondary) }
                    HStack { Button("+250 ml") { store.addWater(250, date: date) }; Spacer(); Button("+500 ml") { store.addWater(500, date: date) } }.buttonStyle(.borderless)
                    HStack { TextField("Custom ml", text: $waterAmount).keyboardType(.numberPad); Button("Add") { if let ml = Int(waterAmount), (1...5000).contains(ml) { store.addWater(ml, date: date) } else { store.error = "Enter 1–5,000 ml." } } }.buttonStyle(.borderless)
                    ForEach(store.state.wellness.water.filter { $0.date == day }) { entry in HStack { Text("\(entry.ml) ml"); Spacer(); Button("Remove") { store.update { $0.wellness.water.removeAll { $0.id == entry.id } } }.font(.caption) }.buttonStyle(.borderless) }
                    if period != .day { Text("Selected \(period.rawValue.lowercased()): \(store.state.wellness.water.filter { days.contains($0.date) }.reduce(0) { $0 + $1.ml }) ml total").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Supplements · \(day)") {
                    let taken = Set(store.state.wellness.taken.filter { $0.date == day }.map(\.supplementId))
                    ForEach(store.state.wellness.supplements.filter { $0.archived != true || taken.contains($0.id) }) { s in
                        Button { store.tick(s.id, date: date) } label: { HStack { Image(systemName: taken.contains(s.id) ? "checkmark.circle.fill" : "circle"); Text(s.name).foregroundStyle(.primary) } }.buttonStyle(.borderless)
                        .swipeActions { if s.archived != true { Button("Archive") { store.update { state in if let i = state.wellness.supplements.firstIndex(where: { $0.id == s.id }) { state.wellness.supplements[i].archived = true } } } } }
                    }
                    HStack { TextField("Your supplement name", text: $supplementName); Button("Add") { let name = supplementName.trimmingCharacters(in: .whitespaces); if !name.isEmpty, store.update({ $0.wellness.supplements.append(Supplement(name: name)) }) { supplementName = "" } } }.buttonStyle(.borderless)
                    Text("A checklist for supplements you already take. Swipe to archive while keeping previous ticks.").font(.caption).foregroundStyle(.secondary)
                }
                Section("A moment to move") {
                    Button { store.moved() } label: { Label("I moved · reset my timer", systemImage: "figure.walk") }
                    Text(store.state.wellness.reminder.enabled ? "Reminders every \(store.state.wellness.reminder.minutes) min during your active hours. The next 24 hours are scheduled each time you use the app." : "Turn on movement reminders in Settings if you’d like a nudge.").font(.caption).foregroundStyle(.secondary)
                    Text("Uses check-ins, not motion sensing. No exercise calories are deducted automatically.").font(.caption2).foregroundStyle(.secondary)
                }
                Section { Text("Saved privately on this iPhone. No laptop is needed to log meals, water, supplements, or activity.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Bite by Bite")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") } }
            .sheet(item: $editor) { request in EntryEditor(store: store, connection: connection, request: request, date: date) }
            .sheet(isPresented: $settings) { PhoneSettings(store: store, connection: connection, reminders: reminders) }
            .alert("Could not save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
            .task { await reminders.apply(store.state) }
            .onReceive(store.$state.dropFirst()) { value in Task { await reminders.apply(value) } }
        }.tint(biteTint)
    }
    private func metric(_ title: String, _ value: Int) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value.formatted()).font(.headline).monospacedDigit() } }
    private func action(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 7) { Image(systemName: icon).font(.title3); Text(title).font(.caption) } } }
    private func shift(_ amount: Int) { date = JournalDates.calendar.date(byAdding: period == .month ? .month : .day, value: amount * (period == .week ? 7 : 1), to: date) ?? date }
}
private struct ContentEmpty: View { var body: some View { VStack(alignment: .leading, spacing: 8) { Label("A fresh page for your day", systemImage: "leaf").font(.headline); Text("Add a photo, a meal, movement, or a manual adjustment above.").foregroundStyle(.secondary).font(.callout) }.padding(.vertical, 16) } }

struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: JournalStore
    @ObservedObject var connection: PhoneConnection
    let request: EditorRequest
    @State private var entryDate: Date
    @State private var name: String
    @State private var calories: String
    @State private var note: String
    @State private var nutrientValues: [String: String]
    @State private var direction = 1
    @State private var activity: String
    @State private var minutes: String
    @State private var weight: String
    @State private var selection: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var jpeg: Data?
    @State private var message = ""
    @State private var camera = false
    @State private var photoGeneration = UUID()
    @State private var portionDetails: String
    @State private var estimatedDetails: String?
    init(store: JournalStore, connection: PhoneConnection, request: EditorRequest, date: Date) {
        self.store = store; self.connection = connection; self.request = request
        let e = request.entry
        _portionDetails = State(initialValue: e?.portionDetails ?? "")
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        _entryDate = State(initialValue: e.flatMap { f.date(from: $0.date) } ?? date)
        _name = State(initialValue: e?.name ?? (request.type == "activity" ? "Walking" : ""))
        _calories = State(initialValue: e.map { String(abs($0.calories)) } ?? "")
        _direction = State(initialValue: (e?.calories ?? 0) < 0 ? -1 : 1)
        _note = State(initialValue: e?.note ?? "")
        _nutrientValues = State(initialValue: Dictionary(uniqueKeysWithValues: PhotoEstimate.Nutrients.fields.map { ($0.0, e?.nutrients?.value($0.0).map { String($0) } ?? "") }))
        _activity = State(initialValue: e?.activity ?? "Walking"); _minutes = State(initialValue: String(Int(e?.minutes ?? 30))); _weight = State(initialValue: String(e?.weight ?? store.state.weight))
    }
    var body: some View {
        NavigationStack {
            Form {
                if request.photo {
                    Section("Meal photo") {
                        HStack { PhotosPicker(selection: $selection, matching: .images) { Label("Choose photo", systemImage: "photo") }; Spacer(); if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Image(systemName: "camera") }.accessibilityLabel("Take meal photo") } }.buttonStyle(.borderless).disabled(connection.estimating)
                        if let preview { Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 230).clipShape(RoundedRectangle(cornerRadius: 10)) }
                        TextField("What did you actually eat? e.g. Half the cake, only the rice, no sauce", text: $portionDetails, axis: .vertical).lineLimit(3...6).disabled(connection.estimating)
                        Text("Optional: describe the portion or name the items you ate. Without details, the whole pictured serving is estimated.").font(.caption).foregroundStyle(.secondary)
                        if let estimatedDetails, estimatedDetails != portionDetails.trimmingCharacters(in: .whitespacesAndNewlines) { Text("Details changed. Tap Estimate again to update calories and nutrients before saving.").font(.caption).foregroundStyle(.orange) }
                        if connection.estimating {
                            ProgressView(connection.estimatePhase)
                            TimelineView(.periodic(from: .now, by: 1)) { context in Text("\(Int(context.date.timeIntervalSince(connection.estimateStartedAt ?? context.date))) seconds · up to 90 seconds").font(.caption).foregroundStyle(.secondary) }
                            Button("Cancel estimate", role: .cancel) { connection.cancelEstimate() }
                        } else if connection.connected {
                            Button("Estimate calories & nutrients") { if let jpeg { message = ""; let details = portionDetails.trimmingCharacters(in: .whitespacesAndNewlines); Task { await connection.analyze(jpeg, details: details); if connection.estimate != nil { estimatedDetails = details } } } }.disabled(jpeg == nil || connection.busy)
                        } else {
                            Button("Continue with ChatGPT") { Task { await connection.connect() } }.disabled(connection.busy)
                        }
                        if !connection.status.isEmpty { Text(connection.status).font(.callout).foregroundStyle(.secondary) }
                        if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                        Text("Your photo is uploaded only when you tap Estimate. Review portions and edit the fields below before saving.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Entry") {
                    DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                    TextField(request.type == "food" ? "Meal name" : "Description", text: $name)
                    if request.type == "activity" {
                        Picker("Activity", selection: $activity) { ForEach(JournalStore.activities, id: \.0) { Text($0.0).tag($0.0) } }
                        HStack { Text("Minutes"); TextField("30", text: $minutes).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Weight (kg)"); TextField("70", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        Button("Calculate activity calories") { recalculate() }
                    }
                    if request.type == "adjustment" { Picker("Adjustment", selection: $direction) { Text("Add calories (+)").tag(1); Text("Subtract calories (−)").tag(-1) } }
                    HStack { Text(request.type == "activity" ? "Calories burned" : "Calories (kcal)"); TextField("0", text: $calories).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }
                if request.type == "food" {
                    Section { ForEach(PhotoEstimate.Nutrients.fields, id: \.0) { key, label in HStack { Text("\(label) (g)"); TextField("Unknown", text: Binding(get: { nutrientValues[key] ?? "" }, set: { nutrientValues[key] = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } } } header: { Text("Nutrients · optional") } footer: { Text("Leave unknown values blank. Sugar and fiber are already part of carbs; fat includes oils.") }
                }
                Section("Note") { TextField("Portions, ingredients, or anything to remember", text: $note, axis: .vertical).lineLimit(3...6) }
                if !message.isEmpty && !request.photo { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle(request.entry == nil ? (request.photo ? "Meal photo" : request.type == "activity" ? "Add activity" : request.type == "adjustment" ? "Adjust calories" : "Add food") : "Edit entry")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { connection.cancelEstimate(); dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(connection.estimating || (request.photo && estimatedDetails != nil && estimatedDetails != portionDetails.trimmingCharacters(in: .whitespacesAndNewlines))) } }
            .interactiveDismissDisabled(connection.estimating)
            .sheet(isPresented: $camera) { MealCamera { image in prepare(image) } }
            .onAppear { connection.clearEstimate(); if request.type == "activity" && request.entry == nil { recalculate() } }
            .onChange(of: connection.estimate?.name) { _ in if let result = connection.estimate { name = result.name; calories = String(result.calories); note = result.notes; for (key, _) in PhotoEstimate.Nutrients.fields { nutrientValues[key] = result.nutrients.value(key).map { String($0) } ?? "" }; message = "Estimate filled in. Check the portion, then Save to your journal." } }
            .onChange(of: portionDetails) { value in if value.count > 1000 { portionDetails = String(value.prefix(1000)) } }
            .onChange(of: selection) { item in let id = UUID(); photoGeneration = id; Task { @MainActor in do { guard let raw = try await item?.loadTransferable(type: Data.self), raw.count < 20_000_000, let image = UIImage(data: raw) else { throw MobileAuthError.message("Choose a readable photo smaller than 20 MB.") }; if photoGeneration == id { prepare(image) } } catch { message = error.localizedDescription } } }
        }.tint(biteTint)
    }
    private func prepare(_ image: UIImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        connection.clearEstimate(); estimatedDetails = nil; let scale = min(1, 1400 / max(image.size.width, image.size.height)), size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        jpeg = resized.jpegData(compressionQuality: 0.82); preview = resized; message = "Photo ready. Tap Estimate to send it to ChatGPT."
    }
    private func recalculate() { if let m = number(minutes), let w = number(weight), (1...1440).contains(m), (20...500).contains(w) { calories = String(JournalStore.activityCalories(activity, minutes: m, weight: w)); name = activity } else { message = "Check duration and weight." } }
    private func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private func save() {
        guard let kcal = Int(calories), (0...50000).contains(kcal), !name.trimmingCharacters(in: .whitespaces).isEmpty else { message = "Enter a name and calories from 0 to 50,000."; return }
        for (_, value) in nutrientValues where !value.isEmpty { guard let n = number(value), (0...2000).contains(n) else { message = "Nutrients must be 0–2,000 grams or blank."; return } }
        var entry = JournalEntry(type: request.type, name: name.trimmingCharacters(in: .whitespaces), date: JournalDates.key(entryDate), calories: kcal * (request.type == "adjustment" ? direction : 1), note: note, source: request.photo && connection.estimate != nil ? "photo" : request.entry?.source ?? "manual")
        entry.portionDetails = request.type == "food" && !portionDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? portionDetails.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if let old = request.entry { entry.id = old.id; entry.created = old.created }
        if request.type == "food" { entry.nutrients = .init(protein: number(nutrientValues["protein"] ?? ""), fiber: number(nutrientValues["fiber"] ?? ""), sugar: number(nutrientValues["sugar"] ?? ""), fat: number(nutrientValues["fat"] ?? ""), carbs: number(nutrientValues["carbs"] ?? "")) }
        if request.type == "activity" { guard let m = number(minutes), let w = number(weight), (1...1440).contains(m), (20...500).contains(w) else { message = "Check activity duration and weight."; return }; entry.activity = activity; entry.minutes = m; entry.weight = w }
        if store.saveEntry(entry) { dismiss() } else { message = store.error ?? "Could not save entry." }
    }
}

struct MealCamera: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let selected: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MealCamera; init(_ parent: MealCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage { parent.selected(image) }; parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct JournalDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PhoneSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: JournalStore
    @ObservedObject var connection: PhoneConnection
    @ObservedObject var reminders: PhoneReminders
    @State private var goal: String
    @State private var weight: String
    @State private var useProfile: Bool
    @State private var age: String
    @State private var height: String
    @State private var targetWeight: String
    @State private var sex: String
    @State private var pace: Double
    @State private var excluded = false
    @State private var alerts: Bool
    @State private var waterGoal: String
    @State private var movement: Bool
    @State private var movementMinutes: Int
    @State private var startHour: Int
    @State private var endHour: Int
    @State private var message = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var document = JournalDocument(data: Data())
    @State private var pendingImport: Data?
    @State private var confirmImport = false
    init(store: JournalStore, connection: PhoneConnection, reminders: PhoneReminders) {
        self.store = store; self.connection = connection; self.reminders = reminders
        let state = store.state, p = state.profile, r = state.wellness.reminder
        _goal = State(initialValue: String(state.goal)); _weight = State(initialValue: String(state.weight)); _useProfile = State(initialValue: p != nil)
        _age = State(initialValue: p.map { String(Int($0.age)) } ?? ""); _height = State(initialValue: p.map { String($0.height) } ?? "")
        _targetWeight = State(initialValue: p.map { String($0.targetWeight) } ?? ""); _sex = State(initialValue: p?.sex ?? "female"); _pace = State(initialValue: p?.pace ?? 0.25); _excluded = State(initialValue: p?.excluded ?? false)
        _alerts = State(initialValue: state.notifications); _waterGoal = State(initialValue: state.wellness.waterGoal.map(String.init) ?? "")
        _movement = State(initialValue: r.enabled); _movementMinutes = State(initialValue: r.minutes); _startHour = State(initialValue: r.startHour); _endHour = State(initialValue: r.endHour)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your daily target") {
                    numberField("Food target (kcal)", $goal)
                    numberField("Current weight (kg)", $weight)
                    Toggle("Use my personal profile", isOn: $useProfile)
                    if useProfile {
                        numberField("Age (years)", $age); numberField("Height (cm)", $height); numberField("Goal weight (kg)", $targetWeight)
                        Picker("Formula", selection: $sex) { Text("Female").tag("female"); Text("Male").tag("male") }
                        Picker("Desired pace", selection: $pace) { Text("Maintain").tag(0.0); Text("0.25 kg per week").tag(0.25); Text("0.5 kg per week").tag(0.5) }
                        Toggle("Pregnant or breastfeeding", isOn: $excluded)
                        Button("Estimate daily calorie target") { do { let p = try profile(), plan = try p.plan(); goal = String(plan.target); message = "Estimated maintenance: \(plan.maintenance) kcal/day. Food target: \(plan.target) kcal/day. \(plan.weeks.map { "Rough initial timeline: \($0) weeks. Update your weight regularly." } ?? "No weight-loss timeline at this target.")" } catch { message = error.localizedDescription } }
                        Text("Adult estimate using Mifflin–St Jeor with a sedentary baseline, a deficit capped at 20%, and 1,200/1,500 kcal minimums. Actual needs and progress vary. Automatic targets exclude pregnancy/breastfeeding and underweight goals.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("You can leave the optional profile off and enter a target agreed with your clinician.").font(.caption).foregroundStyle(.secondary)
                }
                Section("ChatGPT photo estimates") {
                    Text(connection.status).font(.callout).foregroundStyle(.secondary)
                    if connection.busy { ProgressView() }
                    Button(connection.connected ? "Reconnect with ChatGPT" : "Continue with ChatGPT") { Task { await connection.connect() } }.disabled(connection.busy)
                    if connection.signingIn { Button("Cancel sign-in") { connection.cancelSignIn() } }
                    if connection.connected {
                        Button("Refresh available models") { Task { await connection.loadModels() } }.disabled(connection.busy)
                        if !connection.models.isEmpty { Picker("Photo model", selection: $connection.selectedModel) { ForEach(connection.models) { Text($0.name).tag($0.id) } }.disabled(connection.busy) }
                        Button("Disconnect ChatGPT", role: .destructive) { Task { await connection.disconnect() } }.disabled(connection.busy)
                    }
                    Link("Manage plan usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                    Text("Uses your Plus plan allowance. Choose an image-capable model. Credentials stay in your phone’s Keychain; no paid API-key fallback is used.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Reminders") {
                    Toggle("85% and 100% intake reminders", isOn: $alerts)
                    Button("Enable iPhone notifications") { Task { await reminders.requestPermission(); await reminders.apply(store.state) } }
                    Text(reminders.permission).font(.caption).foregroundStyle(.secondary)
                    Toggle("Movement check-ins", isOn: $movement)
                    if movement {
                        Stepper("Every \(movementMinutes) minutes", value: $movementMinutes, in: 15...240, step: 15)
                        Stepper("Start: \(startHour):00", value: $startHour, in: 0...23)
                        Stepper("End: \(endHour):00", value: $endHour, in: 1...24)
                    }
                    Text("Movement is not detected automatically. Reminders for the next 24 hours are scheduled while you use the app and can appear when it is closed. Tap “I moved” or log activity to reset them.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Water") { numberField("Personal goal (ml, optional)", $waterGoal) }
                Section("Your journal data") {
                    Button("Export journal backup") { do { document = JournalDocument(data: try store.exportBackup()); exporting = true } catch { message = error.localizedDescription } }
                    Button("Import laptop or phone backup") { importing = true }
                    Text("To move your laptop journal here, export a JSON backup from its Settings, send the file to your iPhone, then import it here. Journal files contain no ChatGPT credentials. The phone journal is stored locally and does not automatically sync with the laptop.").font(.caption).foregroundStyle(.secondary)
                }
                if !message.isEmpty { Section { Text(message).font(.callout).textSelection(.enabled) } }
                Section("Installation") { Text("Free Apple development signing expires after seven days. Reinstall with Xcode to renew it. Your journal and connection stay on this iPhone when you update the same app; deleting the app can remove its journal, so keep backups.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
            .task { if connection.connected && connection.models.isEmpty { await connection.loadModels() } }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "bite-by-bite-\(JournalDates.key(Date()))") { result in if case .failure(let error) = result { message = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10_000_000 else { throw MobileAuthError.message("Choose a backup smaller than 10 MB.") }; pendingImport = try Data(contentsOf: url); confirmImport = true } catch { message = error.localizedDescription }
            }
            .confirmationDialog("Replace this phone’s journal with the backup? A copy of the current journal will be kept on this phone.", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Import backup", role: .destructive) { if let data = pendingImport, store.importBackup(data) { pendingImport = nil; dismiss() } else { message = store.error ?? "Import failed." } }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            }
        }.tint(biteTint)
    }
    private func numberField(_ label: String, _ binding: Binding<String>) -> some View { HStack { Text(label); Spacer(); TextField("Optional", text: binding).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120) } }
    private func value(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private func profile() throws -> PersonalProfile {
        guard let age = value(age), let height = value(height), let weight = value(weight), let target = value(targetWeight) else { throw MobileAuthError.message("Complete age, height, current weight, and goal weight.") }
        return PersonalProfile(age: age, height: height, weight: weight, targetWeight: target, sex: sex, pace: pace, excluded: excluded)
    }
    private func save() {
        do {
            guard let kcal = Int(goal), let kg = value(weight), (20...500).contains(kg), (useProfile && sex == "male" ? 1500 : 1200)...20000 ~= kcal else { throw MobileAuthError.message("Check your daily target and weight. Minimum food target: 1,200 kcal, or 1,500 with the male formula.") }
            let p = useProfile ? try profile() : nil; if let p { _ = try p.plan() }
            guard startHour < endHour else { throw MobileAuthError.message("Movement end hour must be after its start hour.") }
            let water: Int? = waterGoal.isEmpty ? nil : Int(waterGoal)
            if !waterGoal.isEmpty && (water == nil || !(100...10000).contains(water!)) { throw MobileAuthError.message("Water goal must be 100–10,000 ml or blank.") }
            if store.update({ s in s.goal = kcal; s.weight = kg; s.profile = p; s.notifications = alerts; s.wellness.waterGoal = water
                if movement && !s.wellness.reminder.enabled { s.wellness.reminder.lastMovedAt = Date().timeIntervalSince1970 * 1000 }
                s.wellness.reminder.enabled = movement; s.wellness.reminder.minutes = movementMinutes; s.wellness.reminder.startHour = startHour; s.wellness.reminder.endHour = endHour
            }) { dismiss() } else { message = store.error ?? "Could not save settings." }
        } catch { message = error.localizedDescription }
    }
}
