import Foundation
import SwiftLLM
import Testing

@Suite("Endpoint registry")
struct EndpointRegistryTests {
  @Test
  func registryBuildsPriorityRouterFromEnabledEndpoints() async throws {
    let local = AnyLLMClient(metadata: Self.metadata(name: "Local")) { _ in
      throw LLMClientError(reason: .unavailable)
    }
    let cloud = AnyLLMClient(metadata: Self.metadata(name: "Cloud", providerKind: .testDouble)) { _ in
      LLMResponse(
        text: "cloud fallback",
        metadata: Self.metadata(name: "Cloud", providerKind: .testDouble)
      )
    }
    let registry = LLMEndpointRegistry(
      endpoints: [
        LLMEndpoint(id: "cloud", client: cloud, priority: 20),
        LLMEndpoint(id: "local", client: local, priority: 10),
      ]
    )

    let router = try registry.router()
    let response = try await router.respond(
      to: LLMRequest(messages: [.user("route")])
    )

    #expect(router.primary.metadata.providerDisplayName == "Local")
    #expect(router.fallbacks.map(\.metadata.providerDisplayName) == ["Cloud"])
    #expect(response.text == "cloud fallback")
    #expect(response.metadata.providerKind == .testDouble)
  }

  @Test
  func registryUsesExplicitFallbackOrder() throws {
    let registry = LLMEndpointRegistry(
      endpoints: [
        LLMEndpoint(id: "primary", client: Self.client(name: "Primary")),
        LLMEndpoint(id: "second", client: Self.client(name: "Second"), priority: 1),
        LLMEndpoint(id: "first", client: Self.client(name: "First"), priority: 2),
      ]
    )

    let router = try registry.router(
      primaryID: "primary",
      fallbackIDs: ["first", "second"]
    )

    #expect(router.primary.metadata.providerDisplayName == "Primary")
    #expect(router.fallbacks.map(\.metadata.providerDisplayName) == ["First", "Second"])
  }

  @Test
  func registryRejectsDisabledExplicitEndpoints() throws {
    let registry = LLMEndpointRegistry(
      endpoints: [
        LLMEndpoint(id: "local", client: Self.client(name: "Local"), isEnabled: false),
        LLMEndpoint(id: "cloud", client: Self.client(name: "Cloud")),
      ]
    )

    #expect(throws: LLMEndpointRegistryError.endpointDisabled("local")) {
      _ = try registry.router(primaryID: "local")
    }
  }

  private static func client(name: String) -> AnyLLMClient {
    AnyLLMClient(metadata: metadata(name: name)) { _ in
      LLMResponse(text: name, metadata: metadata(name: name))
    }
  }

  private static func metadata(
    name: String,
    providerKind: LLMProviderKind = .external
  ) -> LLMProviderMetadata {
    LLMProviderMetadata(
      privacyMode: .externalOptIn,
      promptVersion: "test-v1",
      providerDisplayName: name,
      providerKind: providerKind
    )
  }
}
