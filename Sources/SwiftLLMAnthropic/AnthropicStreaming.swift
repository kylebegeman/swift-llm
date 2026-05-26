import Foundation
import SwiftLLM

extension AnthropicClient {
  public func stream(to request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
    AsyncThrowingStream { continuation in
      let metadata = metadata(for: request)
      continuation.yield(.started(metadata))
      let task = Task {
        do {
          let httpRequest = try messagesHTTPRequest(for: request, stream: true)
          let streamResponse = try await transport.stream(httpRequest)
          guard 200..<300 ~= streamResponse.statusCode else {
            throw LLMClientError(
              reason: Self.errorReason(forStatusCode: streamResponse.statusCode, providerMessage: nil),
              statusCode: streamResponse.statusCode
            )
          }

          var streamState = AnthropicStreamState()
          var dataLines: [String] = []
          for try await line in streamResponse.lines {
            if line.isEmpty {
              try Self.processStreamDataLines(
                dataLines,
                streamState: &streamState,
                continuation: continuation
              )
              dataLines.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("data:") {
              dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
          }

          try Self.processStreamDataLines(
            dataLines,
            streamState: &streamState,
            continuation: continuation
          )
          continuation.yield(
            .completed(
              LLMResponse(
                text: streamState.accumulatedText,
                toolCalls: streamState.toolCalls,
                finishReason: streamState.finishReason ?? .stop,
                tokenUsage: streamState.tokenUsage,
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
    streamState: inout AnthropicStreamState,
    continuation: AsyncThrowingStream<LLMStreamEvent, any Error>.Continuation
  ) throws {
    // Anthropic streams tool arguments as JSON fragments, so state is required until a block stops.
    for dataLine in dataLines where dataLine != "[DONE]" && !dataLine.isEmpty {
      let event = try JSONDecoder.provider.decode(AnthropicStreamEvent.self, from: Data(dataLine.utf8))
      switch event.type {
      case "message_start":
        streamState.recordUsage(event.message?.usage)

      case "content_block_start":
        if let index = event.index,
           let contentBlock = event.contentBlock,
           contentBlock.type == "tool_use",
           let id = contentBlock.id,
           let name = contentBlock.name
        {
          streamState.startToolCall(
            index: index,
            id: id,
            name: name,
            input: contentBlock.input
          )
        }

      case "content_block_delta":
        if event.delta?.type == "text_delta",
           let text = event.delta?.text
        {
          streamState.accumulatedText += text
          continuation.yield(.textDelta(text))
        } else if event.delta?.type == "input_json_delta",
                  let index = event.index,
                  let partialJSON = event.delta?.partialJSON
        {
          streamState.appendToolInputDelta(partialJSON, index: index)
        }

      case "content_block_stop":
        if let index = event.index,
           let toolCall = streamState.finishToolCall(index: index)
        {
          continuation.yield(.toolCall(toolCall))
        }

      case "message_delta":
        streamState.recordUsage(event.usage)
        if let stopReason = event.delta?.stopReason {
          streamState.finishReason = stopReason.anthropicFinishReason
        }

      case "error":
        let message = event.error?.message ?? "Anthropic stream failed."
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

// MARK: - Stream State

private struct AnthropicStreamState {
  var accumulatedText = ""
  var finishReason: LLMFinishReason?
  var inputTokens: Int?
  var outputTokens: Int?
  private var completedToolCalls: [LLMToolCall] = []
  private var pendingToolCalls: [Int: PendingAnthropicToolCall] = [:]

  var toolCalls: [LLMToolCall] {
    completedToolCalls
  }

  var tokenUsage: LLMTokenUsage? {
    guard inputTokens != nil || outputTokens != nil else { return nil }
    return LLMTokenUsage(
      estimatedInputTokens: inputTokens ?? 0,
      estimatedOutputTokens: outputTokens ?? 0,
      measuredInputTokens: inputTokens,
      measuredOutputTokens: outputTokens
    )
  }

  mutating func recordUsage(_ usage: AnthropicUsage?) {
    if let inputTokens = usage?.inputTokens {
      self.inputTokens = inputTokens
    }
    if let outputTokens = usage?.outputTokens {
      self.outputTokens = outputTokens
    }
  }

  mutating func startToolCall(
    index: Int,
    id: String,
    name: String,
    input: JSONValue?
  ) {
    let inputJSON = input.flatMap { input in
      try? JSONEncoder.provider.encode(input)
    }
    .map { String(decoding: $0, as: UTF8.self) }
    pendingToolCalls[index] = PendingAnthropicToolCall(
      id: id,
      initialArgumentsJSON: inputJSON ?? "{}",
      name: name
    )
  }

  mutating func appendToolInputDelta(
    _ partialJSON: String,
    index: Int
  ) {
    pendingToolCalls[index]?.partialArgumentsJSON += partialJSON
  }

  mutating func finishToolCall(index: Int) -> LLMToolCall? {
    guard let pendingToolCall = pendingToolCalls.removeValue(forKey: index) else {
      return nil
    }
    let toolCall = pendingToolCall.toolCall
    completedToolCalls.append(toolCall)
    return toolCall
  }
}

private struct PendingAnthropicToolCall {
  var id: String
  var initialArgumentsJSON: String
  var name: String
  var partialArgumentsJSON = ""

  var toolCall: LLMToolCall {
    LLMToolCall(
      id: id,
      name: name,
      argumentsJSON: partialArgumentsJSON.isEmpty ? initialArgumentsJSON : partialArgumentsJSON
    )
  }
}
