import Foundation
import Combine

enum JournalPeriod: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }
enum JournalDates {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func valid(_ string: String) -> Bool {
        let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return string.count == 10 && f.date(from: string).map { key($0) == string } == true
    }
    static func keys(_ date: Date, _ period: JournalPeriod) -> [String] {
        let c = calendar, today = c.startOfDay(for: date)
        let start: Date; let days: Int
        switch period {
        case .day: start = today; days = 1
        case .week: start = c.date(byAdding: .day, value: -((c.component(.weekday, from: today) + 5) % 7), to: today)!; days = 7
        case .month: start = c.date(from: c.dateComponents([.year, .month], from: today))!; days = c.range(of: .day, in: .month, for: today)!.count
        }
        return (0..<days).map { key(c.date(byAdding: .day, value: $0, to: start)!) }
    }
}

extension PhotoEstimate.Nutrients {
    static var unknown: Self { .init(protein: nil, fiber: nil, sugar: nil, fat: nil, carbs: nil) }
    static let fields = [("protein", "Protein"), ("fiber", "Fiber"), ("sugar", "Sugar"), ("fat", "Fat / oils"), ("carbs", "Carbs")]
    func value(_ key: String) -> Double? {
        switch key { case "protein": return protein; case "fiber": return fiber; case "sugar": return sugar; case "fat": return fat; case "carbs": return carbs; default: return nil }
    }
}

struct JournalEntry: Codable, Identifiable {
    var id = UUID().uuidString
    var type: String
    var name: String
    var date: String
    var calories: Int
    var note: String?
    var source: String?
    var created: Double? = Date().timeIntervalSince1970 * 1000
    var nutrients: PhotoEstimate.Nutrients?
    var portionDetails: String?
    var activity: String?
    var minutes: Double?
    var weight: Double?
}
struct WaterEntry: Codable, Identifiable { var id = UUID().uuidString; var date: String; var ml: Int }
struct Supplement: Codable, Identifiable { var id = UUID().uuidString; var name: String; var archived: Bool? = false }
struct SupplementTick: Codable { var date: String; var supplementId: String }
struct MovementReminder: Codable {
    var enabled = false; var minutes = 60; var startHour = 9; var endHour = 20
    var lastMovedAt: Double?; var snoozedUntil: Double?
}
struct JournalWellness: Codable {
    var water: [WaterEntry] = []; var waterGoal: Int?; var supplements: [Supplement] = []; var taken: [SupplementTick] = []; var reminder = MovementReminder()
    init() {}
    enum CodingKeys: String, CodingKey { case water, waterGoal, supplements, taken, reminder }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        water = try c.decodeIfPresent([WaterEntry].self, forKey: .water) ?? []
        waterGoal = try c.decodeIfPresent(Int.self, forKey: .waterGoal)
        supplements = try c.decodeIfPresent([Supplement].self, forKey: .supplements) ?? []
        taken = try c.decodeIfPresent([SupplementTick].self, forKey: .taken) ?? []
        reminder = try c.decodeIfPresent(MovementReminder.self, forKey: .reminder) ?? MovementReminder()
    }
}
struct PersonalProfile: Codable {
    var age: Double; var height: Double; var weight: Double; var targetWeight: Double; var sex: String; var pace: Double; var excluded: Bool?
    func plan() throws -> (maintenance: Int, target: Int, weeks: Int?) {
        guard (18...100).contains(age), (120...230).contains(height), (35...350).contains(weight), (35...350).contains(targetWeight), ["female", "male"].contains(sex), [0, 0.25, 0.5].contains(pace) else { throw MobileAuthError.message("Check your age, height, weights, and weight-loss pace.") }
        guard excluded != true else { throw MobileAuthError.message("Use a clinician-agreed manual target during pregnancy or breastfeeding. Leave the optional profile empty.") }
        guard targetWeight <= weight, targetWeight / pow(height / 100, 2) >= 18.5 else { throw MobileAuthError.message("Choose a goal at or below your current weight and within the adult healthy-weight range.") }
        let maintenance = Int(((10 * weight + 6.25 * height - 5 * age + (sex == "male" ? 5 : -161)) * 1.2).rounded())
        let deficit = targetWeight < weight ? min(pace * 7700 / 7, Double(maintenance) * 0.2) : 0
        let target = max(sex == "male" ? 1500 : 1200, Int((Double(maintenance) - deficit).rounded()))
        let actual = maintenance - target
        let weeks = actual > 0 ? Int(ceil((weight - targetWeight) * 7700 / Double(actual * 7))) : nil
        return (maintenance, target, weeks)
    }
}
struct JournalState: Codable {
    var entries: [JournalEntry] = []; var goal = 2000; var weight: Double = 70; var profile: PersonalProfile?
    var notifications = true; var wellness = JournalWellness()
    init() {}
    enum CodingKeys: String, CodingKey { case entries, goal, weight, profile, notifications, wellness }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([JournalEntry].self, forKey: .entries)
        goal = try c.decode(Int.self, forKey: .goal)
        weight = try c.decode(Double.self, forKey: .weight)
        profile = try c.decodeIfPresent(PersonalProfile.self, forKey: .profile)
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? true
        wellness = try c.decodeIfPresent(JournalWellness.self, forKey: .wellness) ?? JournalWellness()
    }
    func validate() throws {
        guard (1...20000).contains(goal), weight.isFinite, (20...500).contains(weight), entries.count <= 20000, Set(entries.map(\.id)).count == entries.count else { throw MobileAuthError.message("Invalid journal or calorie target.") }
        for e in entries {
            guard !e.id.isEmpty, !e.name.trimmingCharacters(in: .whitespaces).isEmpty, e.name.count <= 120, ["food", "activity", "adjustment"].contains(e.type), JournalDates.valid(e.date), (-50000...50000).contains(e.calories), e.type == "adjustment" || e.calories >= 0 else { throw MobileAuthError.message("A journal entry contains invalid values.") }
            if let n = e.nutrients { for (key, _) in PhotoEstimate.Nutrients.fields { if let v = n.value(key), !v.isFinite || !(0...2000).contains(v) { throw MobileAuthError.message("Nutrients must be between 0 and 2,000 grams.") } } }
            if let details = e.portionDetails, details.count > 1000 { throw MobileAuthError.message("Keep portion details under 1,000 characters.") }
        }
        let w = wellness, r = w.reminder
        guard w.water.count <= 20000, Set(w.water.map(\.id)).count == w.water.count, w.water.allSatisfy({ !$0.id.isEmpty && JournalDates.valid($0.date) && (1...5000).contains($0.ml) }), w.waterGoal == nil || (100...10000).contains(w.waterGoal!), w.supplements.count <= 200, Set(w.supplements.map(\.id)).count == w.supplements.count, w.supplements.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.name.count <= 80 }) else { throw MobileAuthError.message("Check the water entries, water goal, and supplement names.") }
        let ids = Set(w.supplements.map(\.id))
        guard w.taken.count <= 50000, w.taken.allSatisfy({ JournalDates.valid($0.date) && ids.contains($0.supplementId) }), Set(w.taken.map { "\($0.date):\($0.supplementId)" }).count == w.taken.count,
              (15...240).contains(r.minutes), (0...23).contains(r.startHour), (1...24).contains(r.endHour), r.startHour < r.endHour else { throw MobileAuthError.message("Check your supplement history and movement reminder hours.") }
        if let profile { _ = try profile.plan() }
    }
}

struct JournalSummary {
    let entries: [JournalEntry]
    var food: Int { entries.filter { $0.type == "food" }.reduce(0) { $0 + $1.calories } }
    var activity: Int { entries.filter { $0.type == "activity" }.reduce(0) { $0 + $1.calories } }
    var adjustment: Int { entries.filter { $0.type == "adjustment" }.reduce(0) { $0 + $1.calories } }
    var net: Int { food + adjustment - activity }
    var intake: Int { max(0, food + adjustment) }
    var meals: [JournalEntry] { entries.filter { $0.type == "food" } }
    func nutrient(_ key: String) -> (grams: Double?, count: Int) {
        let known = meals.compactMap { $0.nutrients?.value(key) }
        return (known.isEmpty ? nil : known.reduce(0, +), known.count)
    }
}

@MainActor final class JournalStore: ObservableObject {
    @Published private(set) var state = JournalState()
    @Published var error: String?
    private let url: URL
    private var unreadable = false
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BiteByBite/journal.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let loaded = try JSONDecoder().decode(JournalState.self, from: Data(contentsOf: self.url)); try loaded.validate(); state = loaded
            }
        } catch { unreadable = true; self.error = "The saved journal could not be read. It has been preserved. Import a backup to restore access." }
    }
    @discardableResult func update(_ change: (inout JournalState) throws -> Void) -> Bool {
        do {
            guard !unreadable else { throw MobileAuthError.message("Your unreadable journal is preserved. Restore a backup before saving new entries.") }
            var next = state; try change(&next); try write(next); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func write(_ next: JournalState) throws {
        try next.validate(); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(next)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        state = next; unreadable = false
    }
    func importBackup(_ data: Data) -> Bool {
        do {
            guard data.count <= 10_000_000 else { throw MobileAuthError.message("Choose a backup smaller than 10 MB.") }
            let value = try JSONDecoder().decode(JournalState.self, from: data); try value.validate()
            if FileManager.default.fileExists(atPath: url.path) {
                let copy = url.deletingLastPathComponent().appendingPathComponent("before-import-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: copy)
            }
            try write(value); return true
        } catch { self.error = "Could not import this backup: \(error.localizedDescription)"; return false }
    }
    func exportBackup() throws -> Data { try JSONEncoder().encode(state) }
    func summary(_ date: Date, _ period: JournalPeriod) -> JournalSummary { let days = Set(JournalDates.keys(date, period)); return JournalSummary(entries: state.entries.filter { days.contains($0.date) }) }
    func saveEntry(_ value: JournalEntry) -> Bool {
        update { s in s.entries.removeAll { $0.id == value.id }; s.entries.append(value)
            if value.type == "activity", value.date == JournalDates.key(Date()) { s.wellness.reminder.lastMovedAt = Date().timeIntervalSince1970 * 1000; s.wellness.reminder.snoozedUntil = nil }
        }
    }
    func deleteEntry(_ id: String) { update { $0.entries.removeAll { $0.id == id } } }
    func addWater(_ ml: Int, date: Date) { update { $0.wellness.water.append(WaterEntry(date: JournalDates.key(date), ml: ml)) } }
    func tick(_ id: String, date: Date) { update { s in let key = JournalDates.key(date); if s.wellness.taken.contains(where: { $0.date == key && $0.supplementId == id }) { s.wellness.taken.removeAll { $0.date == key && $0.supplementId == id } } else { s.wellness.taken.append(.init(date: key, supplementId: id)) } } }
    func moved() { update { $0.wellness.reminder.lastMovedAt = Date().timeIntervalSince1970 * 1000; $0.wellness.reminder.snoozedUntil = nil } }
    static let activities: [(String, Double)] = [("Walking", 3.5), ("Running", 8), ("Cycling", 6), ("Swimming", 6), ("Strength training", 3.5), ("Yoga", 2.5), ("Dancing", 5)]
    static func activityCalories(_ name: String, minutes: Double, weight: Double) -> Int { Int(((activities.first { $0.0 == name }?.1 ?? 3.5) * 3.5 * weight / 200 * minutes).rounded()) }
}
