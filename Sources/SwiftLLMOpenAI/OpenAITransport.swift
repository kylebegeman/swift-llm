import Foundation
import SwiftLLM

// MARK: - Public Transport

/// HTTP request shape used by `OpenAIHTTPTransport`.
public struct OpenAIHTTPRequest: Sendable {
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

/// HTTP response shape returned by `OpenAIHTTPTransport`.
public struct OpenAIHTTPResponse: Sendable {
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
public struct OpenAIHTTPStreamResponse: Sendable {
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

/// Injectable OpenAI transport for production networking, tests, and app-specific policy.
public struct OpenAIHTTPTransport: Sendable {
  public var send: @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse
  public var stream: @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse

  public init(
    send: @escaping @Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse,
    stream: (@Sendable (OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse)? = nil
  ) {
    self.send = send
    self.stream = stream ?? { _ in
      throw LLMClientError(
        reason: .unsupported,
        debugDescription: "OpenAI streaming transport was not configured."
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

  private static func liveSend(_ request: OpenAIHTTPRequest) async throws -> OpenAIHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "OpenAI returned a non-HTTP response.")
    }
    return OpenAIHTTPResponse(
      statusCode: httpResponse.statusCode,
      headers: stringHeaders(from: httpResponse),
      body: data
    )
  }

  private static func liveStream(_ request: OpenAIHTTPRequest) async throws -> OpenAIHTTPStreamResponse {
    let (bytes, response) = try await URLSession.shared.bytes(for: request.urlRequest())
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError(reason: .network, debugDescription: "OpenAI returned a non-HTTP response.")
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
    return OpenAIHTTPStreamResponse(
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
