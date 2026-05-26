import Foundation
import SwiftLLM

// MARK: - Client

/// OpenAI Responses API adapter for the provider-neutral `LLMClient` protocol.
public struct OpenAIClient: LLMClient {
  var apiKey: String
  public var baseURL: URL
  public var model: String
  public var organizationID: String?
  public var projectID: String?
  public var promptVersion: String
  public var transport: OpenAIHTTPTransport

  public init(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    organizationID: String? = nil,
    projectID: String? = nil,
    promptVersion: String = "openai-responses-v1",
    transport: OpenAIHTTPTransport = .live
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.model = model
    self.organizationID = organizationID
    self.projectID = projectID
    self.promptVersion = promptVersion
    self.transport = transport
  }

  public var metadata: LLMProviderMetadata {
    LLMProviderMetadata(
      modelIdentifier: model,
      privacyMode: .externalOptIn,
      promptVersion: promptVersion,
      providerDisplayName: "OpenAI",
      providerKind: .openAI
    )
  }

  public var capabilities: LLMClientCapabilities {
    .openAIResponses
  }
}

// MARK: - AnyLLMClient Convenience

extension AnyLLMClient {
  public static func openAI(
    apiKey: String,
    model: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    organizationID: String? = nil,
    projectID: String? = nil
  ) -> Self {
    Self(
      OpenAIClient(
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        organizationID: organizationID,
        projectID: projectID
      )
    )
  }
}
