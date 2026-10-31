import Foundation
import Network

/// Experimental mobile callback transport. Bind only to this phone's IPv4 loopback.
@MainActor final class LoopbackCallback {
    private var listener: NWListener?
    private var starting: CheckedContinuation<UInt16, Error>?
    private var connections: [UUID: NWConnection] = [:]
    var onCallback: ((URL) throws -> Void)?
    var port: UInt16?

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        server.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = server.port?.rawValue else { return }
                    self.port = port; self.starting?.resume(returning: port); self.starting = nil
                case .failed:
                    self.starting?.resume(throwing: MobileAuthError.message("The iPhone callback listener could not start.")); self.starting = nil
                default: break
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            starting = continuation
            server.start(queue: .main)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if self?.starting != nil { self?.stop() }
            }
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        starting?.resume(throwing: CancellationError()); starting = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll(); port = nil
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 4 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, accumulated: Data())
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            self?.connections.removeValue(forKey: id)?.cancel()
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                let buffer = accumulated + (data ?? Data())
                guard buffer.count <= 16384, error == nil else { self.finish(connection, id: id, status: "400 Bad Request", body: "Invalid callback."); return }
                if let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") {
                    self.handle(request, connection: connection, id: id)
                } else if complete { self.finish(connection, id: id, status: "400 Bad Request", body: "Incomplete callback.") }
                else { self.receive(connection, id: id, accumulated: buffer) }
            }
        }
    }

    private func handle(_ request: String, connection: NWConnection, id: UUID) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard let port, parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/auth/callback?"),
              lines.contains(where: { $0.lowercased() == "host: 127.0.0.1:\(port)" }),
              let url = URL(string: "http://127.0.0.1:\(port)\(parts[1])") else {
            finish(connection, id: id, status: "404 Not Found", body: "Not found."); return
        }
        do {
            guard let onCallback else { throw MobileAuthError.message("No active sign-in.") }
            try onCallback(url)
            // OpenAI still redirects to the documented HTTP loopback callback.
            // This local response only ends Apple's authentication presentation.
            finish(connection, id: id, status: "302 Found", body: "Return to Bite by Bite.", location: "bitebybite-auth://complete")
        } catch {
            finish(connection, id: id, status: "400 Bad Request", body: "Sign-in was denied or the callback could not be validated. Return to Bite by Bite and try again.")
        }
    }

    private func finish(_ connection: NWConnection, id: UUID, status: String, body: String, location: String? = nil) {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n" + (location.map { "Location: \($0)\r\n" } ?? "") + "\r\n"
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { @MainActor in self?.connections.removeValue(forKey: id) }
        })
    }
}
