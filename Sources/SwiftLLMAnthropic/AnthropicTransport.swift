import Foundation
import SwiftLLM

// MARK: - Public Transport

/// HTTP request shape used by `AnthropicHTTPTransport`.
public struct AnthropicHTTPRequest: Sendable {
  public var body: Data
  public var headers: [String: String]
  public var method: String
  public var url: URL

  public init(
    url: URL,
    method: String = "POST",
    headers: [String: String] = [:],
    body: Data = Data()
  ) {
    self.body = body
    self.headers = headers
    self.method = method
    self.url = url
  }

  public func urlRequest() -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    for (field, value) in headers {
      request.setValue(value, forHTTPHeaderField: field)
    }
    return request
  }
}

/// HTTP response shape returned by `AnthropicHTTPTransport`.
public struct AnthropicHTTPResponse: Sendable {
  public var body: Data
  public var headers: [String: String]
  public var statusCode: Int

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    body: Data
  ) {
    self.body = body
    self.headers = headers
    self.statusCode = statusCode
  }
}

/// Streaming HTTP response that yields server-sent-event lines.
public struct AnthropicHTTPStreamResponse: Sendable {
  public var headers: [String: String]
  public var lines: AsyncThrowingStream<String, any Error>
  public var statusCode: Int

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    lines: AsyncThrowingStream<String, any Error>
  ) {
    self.headers = headers
    self.lines = lines
    self.statusCode = statusCode
  }
}

/// Injectable Anthropic transport for production networking, tests, and app-specific policy.
public struct AnthropicHTTPTransport: Sendable {
  public var send: @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse
  public var stream: @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPStreamResponse

  public init(
    send: @escaping @Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse,
    stream: (@Sendable (AnthropicHTTPRequest) async throws -> AnthropicHTTPStreamResponse)? = nil
  ) {
    self.send = send
    self.stream = stream ?? { _ in
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "Anthropic streaming transport was not configured."
      )
    }
  }

  public static let live = Self(
    send: { request in
      try await liveSend(request)
    },
    stream: { request in
      try await liveStream(request)
    }
  )

  private static func liveSend(_ request: AnthropicHTTPRequest) async throws -> AnthropicHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "Anthropic returned a non-HTTP response.")
    }
    return AnthropicHTTPResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      body: data
    )
  }

  private static func liveStream(_ request: AnthropicHTTPRequest) async throws -> AnthropicHTTPStreamResponse {
    let (bytes, response) = try await URLSession.shared.bytes(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "Anthropic returned a non-HTTP response.")
    }
    let lines = AsyncThrowingStream<String, any Error> { continuation in
      let task = Task {
        do {
          for try await line in bytes.lines {
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
    return AnthropicHTTPStreamResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      lines: lines
    )
  }
}

private func stringHeaders(from response: HTTPURLResponse) -> [String: String] {
  response.allHeaderFields.reduce(into: [:]) { headers, field in
    if let key = field.key as? String,
       let value = field.value as? String
    {
      headers[key] = value
    }
  }
}
