import Foundation

@MainActor @main enum AuthCoreChecks {
    static func rejects(_ name: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected rejection: \(name)") } catch { }
    }
    static func tryResult(_ parser: inout EstimateStreamParser) -> Int { (try? parser.finish().calories) ?? -1 }
    static func main() throws {
        let attempt = OAuthAttempt(state: "expected-state", nonce: "test-nonce", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", redirectURI: "http://127.0.0.1:1455/auth/callback", clientID: nil, subject: nil)
        precondition(attempt.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let url = try attempt.authorizationURL(hostID: "urn:uuid:test-host", credential: nil)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.first { $0.name == "client_id" }?.value == "dynamic_agent_client")
        precondition(query.first { $0.name == "redirect_uri" }?.value == attempt.redirectURI)
        precondition(query.first { $0.name == "scope" }!.value!.contains("chatgpt.tokens.use.direct"))
        let callback = URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state&code=test-code&client_id=oaiapp_test")!
        let returned = try attempt.validateCallback(callback); precondition(returned.clientID == "oaiapp_test")
        rejects("state") { _ = try attempt.validateCallback(URL(string: "http://127.0.0.1:1455/auth/callback?state=wrong&code=x&client_id=oaiapp_test")!) }
        rejects("duplicate state") { _ = try attempt.validateCallback(URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state&state=wrong&code=x&client_id=oaiapp_test")!) }
        rejects("denied consent") { _ = try attempt.validateCallback(URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state&error=access_denied")!) }
        rejects("unissued client") { _ = try attempt.validateCallback(URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state&code=x&client_id=dynamic_agent_client")!) }
        let random = try OAuthAttempt.random(); precondition(Data(base64URL: random)?.count == 32)
        let anotherRandom = try OAuthAttempt.random(); precondition(anotherRandom != random)

        let fixtureFile = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureFile)) as! [String: Any]
        let key = fixture["jwk"] as! [String: Any], good = fixture["good"] as! String
        let claims = try IdentityVerifier.validate(good, clientID: "oaiapp_test", nonce: "test-nonce", subject: "test-person", keys: [key])
        precondition(claims["sub"] as? String == "test-person")
        rejects("nonce") { _ = try IdentityVerifier.validate(good, clientID: "oaiapp_test", nonce: "wrong", subject: nil, keys: [key]) }
        rejects("audience") { _ = try IdentityVerifier.validate(good, clientID: "wrong-client", nonce: "test-nonce", subject: nil, keys: [key]) }
        rejects("subject") { _ = try IdentityVerifier.validate(good, clientID: "oaiapp_test", nonce: "test-nonce", subject: "another-person", keys: [key]) }
        for name in ["expired", "wrongIssuer"] {
            rejects(name) { _ = try IdentityVerifier.validate(fixture[name] as! String, clientID: "oaiapp_test", nonce: "test-nonce", subject: nil, keys: [key]) }
        }
        var parts = good.components(separatedBy: ".")
        parts[1] = Data("{\"sub\":\"tampered\"}".utf8).base64URL
        rejects("signature") { _ = try IdentityVerifier.validate(parts.joined(separator: "."), clientID: "oaiapp_test", nonce: nil, subject: nil, keys: [key]) }

        let wholePrompt = try MealPhotoPrompt.make(details: "  ")
        precondition(wholePrompt.contains("estimate the whole pictured serving"))
        let portionPrompt = try MealPhotoPrompt.make(details: "  Half the cake; only the rice, no sauce.\n\"My portion\"  ")
        precondition(portionPrompt.contains("calories AND every nutrient only for that consumed amount"))
        let context = portionPrompt.components(separatedBy: "User-provided consumption context:\n").last!
        let decodedContext = try JSONSerialization.jsonObject(with: Data(context.utf8)) as! [String: String]
        precondition(decodedContext["consumption_details"] == "Half the cake; only the rice, no sauce.\n\"My portion\"")
        rejects("overlong portion details") { _ = try MealPhotoPrompt.make(details: String(repeating: "a", count: 1001)) }
        let json = Data("{\"name\":\"Meal\",\"calories\":400,\"notes\":\"Approximate\",\"nutrients\":{\"protein\":20,\"fiber\":null,\"sugar\":2,\"fat\":15,\"carbs\":40}}".utf8)
        let estimate = try JSONDecoder().decode(PhotoEstimate.self, from: json)
        try estimate.validate(); precondition(estimate.nutrients.fiber == nil)
        let bad = PhotoEstimate(name: "Meal", calories: -1, notes: "", nutrients: estimate.nutrients)
        rejects("negative estimate") { try bad.validate() }
        var parser = EstimateStreamParser()
        let full: [String: Any] = ["type": "response.completed", "response": ["status": "completed", "output": [["content": [["type": "output_text", "text": String(data: json, encoding: .utf8)!]]]]]]
        let completedEvent = "data: " + String(data: try JSONSerialization.data(withJSONObject: full), encoding: .utf8)!
        let earlyCompletion = try parser.push(completedEvent); precondition(earlyCompletion)
        let stopped = try parser.push(""); precondition(stopped)
        let fromCompleted = try parser.finish(); precondition(fromCompleted.calories == 400)
        var deltaParser = EstimateStreamParser()
        let delta: [String: Any] = ["type": "response.output_text.delta", "delta": String(data: json, encoding: .utf8)!]
        _ = try deltaParser.push("data: " + String(data: try JSONSerialization.data(withJSONObject: delta), encoding: .utf8)!); _ = try deltaParser.push("")
        _ = try deltaParser.push("data: {\"type\":\"response.completed\"}"); let complete = try deltaParser.push(""); precondition(complete)
        precondition(tryResult(&deltaParser) == 400)
        var partial = EstimateStreamParser(); _ = try partial.push("data: " + String(data: try JSONSerialization.data(withJSONObject: delta), encoding: .utf8)!); _ = try partial.push("")
        rejects("incomplete stream") { _ = try partial.finish() }
        var failure = EstimateStreamParser(); rejects("failed stream") { _ = try failure.push("data: {\"type\":\"response.failed\"}") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bite-journal-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("journal.json"), store = JournalStore(url: file)
        let today = JournalDates.key(Date())
        var meal = JournalEntry(type: "food", name: "Lunch", date: today, calories: 600, nutrients: estimate.nutrients)
        meal.portionDetails = "Only half the rice"
        precondition(store.saveEntry(meal))
        precondition(store.saveEntry(JournalEntry(type: "activity", name: "Walk", date: today, calories: 100)))
        precondition(store.saveEntry(JournalEntry(type: "adjustment", name: "Correction", date: today, calories: -50)))
        store.addWater(250, date: Date())
        precondition(store.update { $0.wellness.supplements = [Supplement(id: "zinc", name: "My zinc")] })
        store.tick("zinc", date: Date())
        let restored = JournalStore(url: file)
        precondition(restored.state.entries.first(where: { $0.id == meal.id })?.portionDetails == "Only half the rice")
        precondition(restored.summary(Date(), .day).net == 450)
        precondition(restored.summary(Date(), .day).nutrient("protein").grams == 20)
        precondition(restored.summary(Date(), .day).nutrient("fiber").grams == nil)
        precondition(restored.state.wellness.water[0].ml == 250 && restored.state.wellness.taken.count == 1)
        restored.tick("zinc", date: Date()); precondition(restored.state.wellness.taken.isEmpty)
        precondition(!restored.saveEntry(JournalEntry(type: "food", name: "Invalid", date: today, calories: -100)))
        precondition(JournalStore(url: file).state.entries.count == 3)
        let backup = try restored.exportBackup()
        precondition(!String(data: backup, encoding: .utf8)!.contains("accessToken"))
        let other = JournalStore(url: root.appendingPathComponent("other.json"))
        precondition(other.importBackup(backup) && other.state.entries.count == 3)
        precondition(other.state.entries.first(where: { $0.id == meal.id })?.portionDetails == "Only half the rice")
        precondition(!other.importBackup(Data("{}".utf8)))
        precondition(other.state.entries.count == 3)
        precondition(!JournalDates.valid("2026-02-30"))
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        precondition(JournalDates.keys(formatter.date(from: "2026-01-01")!, .week).first == "2025-12-29")
        precondition(JournalDates.keys(formatter.date(from: "2024-02-10")!, .month).count == 29)
        precondition(JournalStore.activityCalories("Walking", minutes: 30, weight: 70) == 129)
        print("Passed native core checks: PKCE, callback state/registration, random values, real RSA signature verification, token claims, nutrient validation, stream completion/failure, durable journal reloads, summaries, habits, calendar boundaries, and backups. No Keychain writes or network requests performed.")
    }
}
