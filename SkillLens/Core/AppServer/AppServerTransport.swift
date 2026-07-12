import Foundation

actor AppServerTransport {
    nonisolated let events: AsyncStream<AppServerEvent>

    private let eventContinuation: AsyncStream<AppServerEvent>.Continuation
    private var process: Process?
    private var inputHandle: FileHandle?
    private var pending: [Int: PendingRequest] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var nextRequestID = 1
    private var outputReader: PipeLineReader?
    private var errorReader: PipeLineReader?
    private var isStopping = false

    init() {
        let pair = AsyncStream.makeStream(of: AppServerEvent.self)
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func start(executableURL: URL, environment: [String: String] = [:]) throws {
        guard process == nil else { throw AppServerTransportError.alreadyStarted }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        isStopping = false
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { await self?.processDidExit(status: status) }
        }

        let outputHandle = outputPipe.fileHandleForReading
        let outputReader = PipeLineReader(handle: outputHandle) { [weak self] line in
            Task { await self?.receive(line: line) }
        } onEnd: { [weak self] in
            Task { await self?.finish(with: AppServerTransportError.processExited) }
        }
        self.outputReader = outputReader
        outputReader.start()

        let stderrHandle = errorPipe.fileHandleForReading
        let errorReader = PipeLineReader(handle: stderrHandle) { _ in
            // Drain stderr so Codex cannot block. Diagnostics are intentionally not retained here.
        } onEnd: {
            // stdout/process termination owns lifecycle completion.
        }
        self.errorReader = errorReader
        errorReader.start()
    }

    func request<Response: Decodable & Sendable>(
        method: String,
        params: JSONValue = .object([:]),
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let value = try await requestValue(method: method, params: params)
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    func sendNotification(method: String, params: JSONValue? = nil) throws {
        guard let inputHandle else { throw AppServerTransportError.notStarted }
        let notification = AppServerNotification(method: method, params: params)
        var data = try JSONEncoder().encode(notification)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    func stop() {
        isStopping = true
        outputReader?.stop()
        errorReader?.stop()
        outputReader = nil
        errorReader = nil
        process?.terminate()
        process = nil
        inputHandle = nil
        finish(with: AppServerTransportError.processExited)
    }

    private func requestValue(method: String, params: JSONValue) async throws -> JSONValue {
        guard let inputHandle else { throw AppServerTransportError.notStarted }
        let id = nextRequestID
        nextRequestID += 1
        let request = AppServerRequest(method: method, id: id, params: params)
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = PendingRequest(method: method, continuation: continuation)
            timeoutTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                await self?.expireRequest(id: id)
            }
            do {
                try inputHandle.write(contentsOf: data)
            } catch {
                pending.removeValue(forKey: id)
                timeoutTasks.removeValue(forKey: id)?.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private func receive(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            let message = try JSONDecoder().decode(AppServerIncomingMessage.self, from: data)
            if let id = message.id, let request = pending.removeValue(forKey: id) {
                timeoutTasks.removeValue(forKey: id)?.cancel()
                if let error = message.error {
                    request.continuation.resume(
                        throwing: AppServerTransportError.requestFailed(
                            code: error.code,
                            message: error.message
                        )
                    )
                } else if let result = message.result {
                    request.continuation.resume(returning: result)
                } else {
                    request.continuation.resume(throwing: AppServerTransportError.invalidResponse)
                }
            } else if let method = message.method {
                eventContinuation.yield(AppServerEvent(method: method, params: message.params))
            }
        } catch {
            eventContinuation.yield(
                AppServerEvent(
                    method: "client/malformedMessage",
                    params: .object(["message": .string(error.localizedDescription)])
                )
            )
        }
    }

    private func finish(with error: Error) {
        let requests = pending.values
        pending.removeAll()
        let timeouts = timeoutTasks.values
        timeoutTasks.removeAll()
        for timeout in timeouts { timeout.cancel() }
        for request in requests {
            request.continuation.resume(throwing: error)
        }
    }

    private func expireRequest(id: Int) {
        timeoutTasks.removeValue(forKey: id)
        guard let request = pending.removeValue(forKey: id) else { return }
        request.continuation.resume(throwing: AppServerTransportError.timedOut(method: request.method))
    }

    private func processDidExit(status: Int32) {
        guard !isStopping else { return }
        process = nil
        inputHandle = nil
        finish(with: AppServerTransportError.processExited)
        eventContinuation.yield(
            AppServerEvent(
                method: "client/processExited",
                params: .object(["status": .number(Double(status))])
            )
        )
    }
}

private final class PipeLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let onLine: @Sendable (String) -> Void
    private let onEnd: @Sendable () -> Void
    private let lock = NSLock()
    private var buffer = Data()
    private var isStopped = false

    init(
        handle: FileHandle,
        onLine: @escaping @Sendable (String) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        self.handle = handle
        self.onLine = onLine
        self.onEnd = onEnd
    }

    func start() {
        handle.readabilityHandler = { [weak self] readableHandle in
            self?.consume(readableHandle.availableData)
        }
    }

    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true
        lock.unlock()
        handle.readabilityHandler = nil
    }

    private func consume(_ data: Data) {
        var lines: [String] = []
        var reachedEnd = false

        lock.lock()
        if !isStopped {
            if data.isEmpty {
                isStopped = true
                reachedEnd = true
                if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8) {
                    lines.append(tail)
                }
                buffer.removeAll(keepingCapacity: false)
            } else {
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    if let line = String(data: lineData, encoding: .utf8) {
                        lines.append(line.trimmingCharacters(in: .newlines))
                    }
                }
            }
        }
        lock.unlock()

        for line in lines where !line.isEmpty { onLine(line) }
        if reachedEnd {
            handle.readabilityHandler = nil
            onEnd()
        }
    }
}

private struct PendingRequest {
    let method: String
    let continuation: CheckedContinuation<JSONValue, Error>
}
