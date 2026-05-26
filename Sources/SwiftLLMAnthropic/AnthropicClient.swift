import Foundation
import SwiftLLM

// MARK: - Client

/// Anthropic Messages API adapter for the provider-neutral `LLMClient` protocol.
public struct AnthropicClient: LLMClient {
  var apiKey: String
  public var apiVersion: String
  public var baseURL: URL
  public var defaultMaxTokens: Int
  public var model: String
  public var promptVersion: String
  public var transport: AnthropicHTTPTransport

  public init(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
    apiVersion: String = "2023-06-01",
    defaultMaxTokens: Int = 1_024,
    promptVersion: String = "anthropic-messages-v1",
    transport: AnthropicHTTPTransport = .live
  ) {
    self.apiKey = apiKey
    self.apiVersion = apiVersion
    self.baseURL = baseURL
    self.defaultMaxTokens = defaultMaxTokens
    self.model = model
    self.promptVersion = promptVersion
    self.transport = transport
  }

  public var metadata: LLMProviderMetadata {
    LLMProviderMetadata(
      modelIdentifier: model,
      privacyMode: .externalOptIn,
      promptVersion: promptVersion,
      providerDisplayName: "Anthropic",
      providerKind: .anthropic
    )
  }

  public var capabilities: LLMClientCapabilities {
    .anthropicMessages
  }
}

// MARK: - AnyLLMClient Convenience

extension AnyLLMClient {
  public static func anthropic(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
    apiVersion: String = "2023-06-01"
  ) -> Self {
    Self(
      AnthropicClient(
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        apiVersion: apiVersion
      )
    )
  }
}
