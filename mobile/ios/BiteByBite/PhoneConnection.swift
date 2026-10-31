import Foundation
import AuthenticationServices
import Combine
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct AccountModel: Identifiable { let id: String; let name: String }

@MainActor final class PhoneConnection: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var connected = false
    @Published var busy = false
    @Published var signingIn = false
    @Published var estimating = false
    @Published var estimateStartedAt: Date?
    @Published var estimatePhase = ""
    private var estimateSession: URLSession?
    private var estimateID = UUID()
    private var estimateDeadline: Task<Void, Never>?
    private var renewal: Task<ChatGPTCredential, Error>?
    @Published var status = "Connect ChatGPT in Settings to estimate meal photos."
    @Published var models: [AccountModel] = []
    @Published var selectedModel = ""
    @Published var estimate: PhotoEstimate?
    private var credential: ChatGPTCredential?
    private var browser: ASWebAuthenticationSession?
    private var callback: LoopbackCallback?
    private var generation = 0
    private var timeout: Task<Void, Never>?
    private let network: URLSession = { let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 30; c.timeoutIntervalForResource = 45; return URLSession(configuration: c) }()

    override init() {
        super.init()
        do {
            if let data = try DeviceVault.read("connection") {
                credential = try JSONDecoder().decode(ChatGPTCredential.self, from: data)
                connected = true
                status = "ChatGPT connected\(credential?.email.map { " for \($0)" } ?? ""). Ready for meal photos."
            }
        } catch { status = error.localizedDescription }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? UIWindow()
        #else
        return NSApp.keyWindow ?? NSWindow()
        #endif
    }

    func connect() async {
        guard !busy else { return }; busy = true; signingIn = true; generation += 1
        let current = generation
        do {
            let listener = LoopbackCallback(); callback = listener
            let port = try await listener.start()
            let savedClient = credential?.clientID ?? UserDefaults.standard.string(forKey: "chatgpt-client")
            let attempt = OAuthAttempt(state: try OAuthAttempt.random(), nonce: try OAuthAttempt.random(), verifier: try OAuthAttempt.random(), redirectURI: "http://127.0.0.1:\(port)/auth/callback", clientID: savedClient, subject: credential?.subject ?? UserDefaults.standard.string(forKey: "chatgpt-subject"))
            var result: (code: String, clientID: String)?
            listener.onCallback = { url in result = try attempt.validateCallback(url) }
            let url = try attempt.authorizationURL(hostID: hostID(), credential: credential)
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "bitebybite-auth") { [weak self] url, _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.signingIn = false; self.timeout?.cancel(); self.callback?.stop(); self.callback = nil; self.browser = nil
                    guard url?.scheme == "bitebybite-auth", url?.host == "complete", let result else {
                        self.busy = false; self.status = "Sign-in was cancelled, timed out, or the mobile callback failed. No new connection was saved."; return
                    }
                    do {
                        UserDefaults.standard.set(result.clientID, forKey: "chatgpt-client")
                        let tokens = try await self.tokenRequest(["grant_type": "authorization_code", "client_id": result.clientID, "code": result.code, "code_verifier": attempt.verifier, "redirect_uri": attempt.redirectURI, "resource": "https://api.openai.com/v1"])
                        let saved = try await self.validateTokens(tokens, clientID: result.clientID, nonce: attempt.nonce, subject: attempt.subject, previous: nil)
                        guard self.generation == current else { return }
                        try self.save(saved); self.connected = true
                        try await self.loadModelsInternal()
                        self.status = "ChatGPT connected. You can estimate meal photos now."
                    } catch { self.status = error.localizedDescription }
                    self.busy = false
                }
            }
            session.presentationContextProvider = self
            browser = session
            status = "Sign in on OpenAI’s page and approve use of your ChatGPT plan."
            guard session.start() else { throw MobileAuthError.message("The iPhone could not open the system sign-in session.") }
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
                self?.cancelSignIn()
            }
        } catch { signingIn = false; callback?.stop(); callback = nil; browser = nil; busy = false; status = error.localizedDescription }
    }

    func cancelSignIn() {
        guard signingIn else { return }; signingIn = false
        generation += 1; timeout?.cancel(); browser?.cancel(); browser = nil; callback?.stop(); callback = nil; busy = false
        status = "Sign-in stopped. Your existing connection was kept."
    }

    func loadModels() async {
        guard !busy else { return }; busy = true
        do { try await loadModelsInternal(); status = "Models updated. Choose a model that accepts images." }
        catch { status = error.localizedDescription }; busy = false
    }

    private func loadModelsInternal() async throws {
        let token = try await access()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!); request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await network.data(for: request); try check(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        models = (json?["models"] as? [[String: Any]] ?? []).compactMap { m in
            guard m["visibility"] as? String == "list", let id = m["slug"] as? String else { return nil }
            return AccountModel(id: id, name: m["display_name"] as? String ?? id)
        }
        guard !models.isEmpty else { throw MobileAuthError.message("No usable models were returned for this ChatGPT account.") }
        if !models.contains(where: { $0.id == selectedModel }) { selectedModel = models[0].id }
    }

    func analyze(_ jpeg: Data, details: String = "") async {
        guard !busy else { return }; busy = true; estimating = true; estimate = nil; estimateStartedAt = Date(); estimatePhase = "Preparing photo…"
        let operation = UUID(); estimateID = operation
        estimateDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 90_000_000_000) } catch { return }
            guard let self, self.estimateID == operation else { return }; self.cancelEstimate(); self.status = "The estimate reached its 90-second limit and was stopped. Your photo is still here. Try again or choose a different model in Settings."
        }
        defer { if estimateID == operation { estimateDeadline?.cancel(); estimateSession?.invalidateAndCancel(); estimateSession = nil; estimating = false; busy = false } }
        do {
            guard jpeg.count <= 5_000_000 else { throw MobileAuthError.message("Choose a smaller photo.") }
            if models.isEmpty { try await loadModelsInternal() }
            let token = try await access()
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!); request.httpMethod = "POST"; request.timeoutInterval = 90
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let prompt = try MealPhotoPrompt.make(details: details)
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": selectedModel, "store": false, "stream": true, "text": ["format": ["type": "json_object"]], "input": [["role": "user", "content": [["type": "input_text", "text": prompt], ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]]]])
            guard estimateID == operation else { return }
            let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 90
            let session = URLSession(configuration: configuration); estimateSession = session
            status = "Sending your photo to ChatGPT…"; estimatePhase = "Sending photo…"
            let (bytes, response) = try await session.bytes(for: request); try check(response)
            var parser = EstimateStreamParser()
            estimatePhase = "Estimating portions and nutrients…"; status = "Estimating portions and nutrients…"
            for try await line in bytes.lines {
                guard estimateID == operation else { return }
                if try parser.push(line) { break }
            }
            guard estimateID == operation else { return }
            estimate = try parser.finish()
            status = "Estimate ready. Review the portion and save it to your journal."
        } catch {
            guard estimateID == operation else { return }
            if let error = error as? URLError, error.code == .timedOut { status = "The estimate took too long and was stopped. Your photo is still here. Try again or choose a different model in Settings." }
            else { status = error.localizedDescription }
        }
    }

    func cancelEstimate() {
        guard estimating else { return }; estimateID = UUID(); estimateDeadline?.cancel(); estimateSession?.invalidateAndCancel(); estimateSession = nil
        estimating = false; busy = false; status = "Estimate cancelled. Your photo has been kept."
    }
    func clearEstimate() { estimate = nil }

    func disconnect() async {
        guard !busy else { return }; busy = true
        let previous = credential
        do {
            try DeviceVault.delete("connection"); credential = nil; connected = false; models = []; selectedModel = ""; estimate = nil
            var revoked = false
            if let previous, let refresh = previous.refreshToken {
                do {
                    let metadata = try await getJSON(URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
                    if let endpoint = metadata["revocation_endpoint"] as? String, let url = URL(string: endpoint), url.scheme == "https", url.host == "auth.openai.com" {
                        let request = formRequest(url, ["token": refresh, "token_type_hint": "refresh_token", "client_id": previous.clientID])
                        let (_, response) = try await network.data(for: request); revoked = (response as? HTTPURLResponse)?.statusCode == 200
                    }
                } catch { /* Local removal still succeeds; report unconfirmed remote revocation. */ }
            }
            status = revoked ? "ChatGPT disconnected." : "Removed from this phone. Remote revocation was not confirmed; remove the app in ChatGPT Settings → Usage."
        } catch { status = error.localizedDescription }; busy = false
    }

    private func hostID() throws -> String {
        if let data = try DeviceVault.read("host"), let id = String(data: data, encoding: .utf8) { return id }
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"; try DeviceVault.write(Data(id.utf8), account: "host"); return id
    }
    private func save(_ value: ChatGPTCredential) throws {
        try DeviceVault.write(JSONEncoder().encode(value), account: "connection"); credential = value
        UserDefaults.standard.set(value.clientID, forKey: "chatgpt-client"); UserDefaults.standard.set(value.subject, forKey: "chatgpt-subject")
    }
    private func access() async throws -> String {
        guard let old = credential else { throw MobileAuthError.message("Connect your ChatGPT plan first.") }
        if old.expiresAt > Date().addingTimeInterval(60) { return old.accessToken }
        guard let refresh = old.refreshToken else { throw MobileAuthError.message("Your connection expired. Continue with ChatGPT again.") }
        if let renewal { return try await renewal.value.accessToken }
        let task = Task { @MainActor in
            let tokens = try await self.tokenRequest(["grant_type": "refresh_token", "client_id": old.clientID, "refresh_token": refresh, "resource": "https://api.openai.com/v1"])
            let next = try await self.validateTokens(tokens, clientID: old.clientID, nonce: nil, subject: old.subject, previous: old)
            guard self.credential?.accessToken == old.accessToken, self.credential?.clientID == old.clientID else { throw MobileAuthError.message("The ChatGPT connection changed. Try again.") }
            try self.save(next); return next
        }
        renewal = task; defer { renewal = nil }
        return try await task.value.accessToken
    }

    private func validateTokens(_ tokens: [String: Any], clientID: String, nonce: String?, subject: String?, previous: ChatGPTCredential?) async throws -> ChatGPTCredential {
        let scopes = (tokens["scope"] as? String)?.split(separator: " ").map(String.init) ?? previous?.scopes ?? []
        guard scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke"),
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let seconds = tokens["expires_in"] as? Double, seconds > 0 else { throw MobileAuthError.message("OpenAI did not grant usable ChatGPT plan access. Reconnect and approve the plan permission.") }
        var sub = previous?.subject ?? "", email = previous?.email, idToken = previous?.idToken ?? ""
        if let issuedToken = tokens["id_token"] as? String {
            let metadata = try await getJSON(URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
            guard metadata["issuer"] as? String == "https://auth.openai.com", let uri = metadata["jwks_uri"] as? String, let url = URL(string: uri), url.scheme == "https", url.host == "auth.openai.com" else { throw MobileAuthError.message("Cannot verify OpenAI’s identity keys.") }
            let keys = try await getJSON(url)
            let claims = try IdentityVerifier.validate(issuedToken, clientID: clientID, nonce: nonce, subject: subject, keys: keys["keys"] as? [[String: Any]] ?? [])
            sub = claims["sub"] as! String; email = claims["email"] as? String; idToken = issuedToken
        } else if previous == nil { throw MobileAuthError.message("OpenAI returned no identity token.") }
        return ChatGPTCredential(clientID: clientID, subject: sub, email: email, accessToken: access, refreshToken: tokens["refresh_token"] as? String ?? previous?.refreshToken, idToken: idToken, expiresAt: Date().addingTimeInterval(seconds), scopes: scopes)
    }
    private func tokenRequest(_ values: [String: String]) async throws -> [String: Any] {
        let (data, response) = try await network.data(for: formRequest(URL(string: "https://auth.openai.com/api/accounts/oauth/token")!, values)); try check(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MobileAuthError.message("Invalid authorization response.") }; return object
    }
    private func getJSON(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (data, response) = try await network.data(for: request); try check(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MobileAuthError.message("Invalid service response.") }; return object
    }
    private func formRequest(_ url: URL, _ values: [String: String]) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").data(using: .utf8)
        return request
    }
    private func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw MobileAuthError.message("No response from OpenAI.") }
        guard (200...299).contains(status) else { throw MobileAuthError.message(status == 429 ? "Your ChatGPT plan usage limit was reached. Check ChatGPT Settings → Usage or wait for the limit to reset." : status == 401 ? "ChatGPT access was rejected. Reconnect your account." : "OpenAI returned HTTP \(status). The mobile flow or selected model may not support this request.") }
    }
}
