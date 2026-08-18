import Foundation
import Network

struct OpenAIOAuthCallback: @unchecked Sendable {
    let code: String?
    let state: String?
    let error: String?
    let errorDescription: String?
    fileprivate let connection: NWConnection
}

final class OpenAILocalCallbackServer: @unchecked Sendable {
    private(set) var port: UInt16

    private let listener: NWListener
    private let queue: DispatchQueue
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<OpenAIOAuthCallback, Error>?
    private var pendingCallback: Result<OpenAIOAuthCallback, Error>?
    private var isCancelled = false

    init(port: UInt16) throws {
        self.port = port
        self.queue = DispatchQueue(label: "AIUsageMonitor.OpenAIOAuthCallback.\(port)")
        let parameters = NWParameters.tcp
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw OpenAIOAuthLoginError.callbackPortUnavailable
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: networkPort)
        self.listener = try NWListener(using: parameters)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                self.readyContinuation = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.receiveRequest(on: connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback() async throws -> OpenAIOAuthCallback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.queue.async {
                    if let result = self.pendingCallback {
                        self.pendingCallback = nil
                        continuation.resume(with: result)
                    } else if self.isCancelled {
                        continuation.resume(throwing: OpenAIOAuthLoginError.cancelled)
                    } else {
                        self.callbackContinuation = continuation
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func respond(to callback: OpenAIOAuthCallback, success: Bool, message: String) {
        let title = success ? "OpenAI connected" : "OpenAI login failed"
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font-family:-apple-system;padding:40px"><h2>\(title)</h2><p>\(message)</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        callback.connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            callback.connection.cancel()
        })
        self.listener.cancel()
    }

    func cancel() {
        self.queue.async {
            guard !self.isCancelled else { return }
            self.isCancelled = true
            self.listener.cancel()
            self.readyContinuation?.resume(throwing: OpenAIOAuthLoginError.cancelled)
            self.readyContinuation = nil
            self.callbackContinuation?.resume(throwing: OpenAIOAuthLoginError.cancelled)
            self.callbackContinuation = nil
        }
    }

    static func parseCallbackRequest(_ request: String, connection: NWConnection) throws -> OpenAIOAuthCallback {
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            throw OpenAIOAuthLoginError.invalidCallback
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://localhost\(parts[1])"),
              components.path == "/auth/callback"
        else {
            throw OpenAIOAuthLoginError.invalidCallback
        }
        let values = Dictionary(
            components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        return OpenAIOAuthCallback(
            code: values["code"],
            state: values["state"],
            error: values["error"],
            errorDescription: values["error_description"],
            connection: connection
        )
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let actualPort = self.listener.port?.rawValue {
                self.port = actualPort
            }
            self.readyContinuation?.resume()
            self.readyContinuation = nil
        case .failed(let error):
            self.readyContinuation?.resume(throwing: error)
            self.readyContinuation = nil
            self.finishCallback(.failure(error))
        case .cancelled:
            if !self.isCancelled {
                self.finishCallback(.failure(OpenAIOAuthLoginError.cancelled))
            }
        default:
            break
        }
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.start(queue: self.queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finishCallback(.failure(error))
                connection.cancel()
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.finishCallback(.failure(OpenAIOAuthLoginError.invalidCallback))
                connection.cancel()
                return
            }
            do {
                let callback = try Self.parseCallbackRequest(request, connection: connection)
                self.finishCallback(.success(callback))
            } catch {
                self.finishCallback(.failure(error))
                connection.cancel()
            }
        }
    }

    private func finishCallback(_ result: Result<OpenAIOAuthCallback, Error>) {
        if let continuation = self.callbackContinuation {
            self.callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            self.pendingCallback = result
        }
    }
}
