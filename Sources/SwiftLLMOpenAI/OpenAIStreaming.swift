import Foundation
import SwiftLLM

extension OpenAIClient {
  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = metadata(for: request)
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try responsesHTTPRequest(for: request, stream: true)
          let streamResponse = try await transport.stream(httpRequest)
          guard 200..<300 ~= streamResponse.statusCode else {
            throw LLMClientError(
              reason: Self.errorReason(forStatusCode: streamResponse.statusCode, providerMessage: nil),
              statusCode: streamResponse.statusCode
            )
          }

          var accumulatedText = ""
          var completedResponse: LLMResponse?
          var dataLines: [String] = []
          for try await line in streamResponse.lines {
            if line.isEmpty {
              try Self.processStreamDataLines(
                dataLines,
                accumulatedText: &accumulatedText,
                completedResponse: &completedResponse,
                continuation: continuation,
                metadata: metadata
              )
              dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("data:") {
              dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
          }

          try Self.processStreamDataLines(
            dataLines,
            accumulatedText: &accumulatedText,
            completedResponse: &completedResponse,
            continuation: continuation,
            metadata: metadata
          )
          continuation.yield(
            .completed(
              completedResponse ?? LLMResponse(
                text: accumulatedText,
                finishReason: .stop,
                model: model,
                metadata: metadata
              )
            )
          )
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private static func processStreamDataLines(
    _ dataLines: [String],
    accumulatedText: inout String,
    completedResponse: inout LLMResponse?,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation,
    metadata: LLMProviderMetadata
  ) throws {
    // OpenAI Responses streams encode text, tool calls, completion, and failures as typed SSE events.
    for dataLine in dataLines where dataLine != "[DONE]" && !dataLine.isEmpty {
      let data = Data(dataLine.utf8)
      let event = try JSONDecoder.provider.decode(OpenAIStreamEvent.self, from: data)
      switch event.type {
      case "response.output_text.delta":
        if let delta = event.delta {
          accumulatedText += delta
          continuation.yield(.textDelta(delta))
        }
      case "response.output_item.done":
        if let toolCall = event.item?.toolCall {
          continuation.yield(.toolCall(toolCall))
        }
      case "response.completed", "response.done":
        if let response = try event.response?.llmResponse(metadata: metadata) {
          completedResponse = response
        }
      case "error", "response.failed":
        let message = event.error?.message ?? event.response?.error?.message ?? "OpenAI stream failed."
        throw LLMClientError(
          reason: .provider(message),
          debugDescription: message
        )
      default:
        break
      }
    }
  }
}
