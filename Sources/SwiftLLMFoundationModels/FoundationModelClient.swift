import Foundation
import SwiftLLM

public struct FoundationModelClient: Sendable {
  public var checkAvailability: @Sendable (Locale?, FoundationModelUseCase) -> FoundationModelAvailability
  public var countTokens: @Sendable (FoundationModelTokenCountRequest) async throws -> Int
  public var prewarm: @Sendable (FoundationModelPrewarmRequest) async throws -> Void
  public var respond: @Sendable (FoundationModelGenerationRequest) async throws
    -> FoundationModelGenerationResponse<String>

  public init(
    checkAvailability: @escaping @Sendable (
      Locale?,
      FoundationModelUseCase
    ) -> FoundationModelAvailability,
    countTokens: @escaping @Sendable (FoundationModelTokenCountRequest) async throws -> Int,
    prewarm: @escaping @Sendable (FoundationModelPrewarmRequest) async throws -> Void,
    respond: @escaping @Sendable (FoundationModelGenerationRequest) async throws
      -> FoundationModelGenerationResponse<String>
  ) {
    self.checkAvailability = checkAvailability
    self.countTokens = countTokens
    self.prewarm = prewarm
    self.respond = respond
  }

  public func availability(
    locale: Locale? = nil,
    useCase: FoundationModelUseCase = .general
  ) -> FoundationModelAvailability {
    checkAvailability(locale, useCase)
  }

  public func tokenCounter(
    useCase: FoundationModelUseCase = .general
  ) -> TokenCounter {
    TokenCounter { text in
      // TokenCounter is synchronous. Use the live async `countTokens` API when exact
      // Foundation Models accounting is required.
      TokenCounter.latinHeuristic.count(text)
    }
  }

  public static let unavailable = Self(
    checkAvailability: { _, _ in .unavailableInBuild },
    countTokens: { request in
      TokenCounter.latinHeuristic.count(request.text)
    },
    prewarm: { _ in
      throw FoundationModelFailure(reason: .unavailable(.unavailableInBuild))
    },
    respond: { _ in
      throw FoundationModelFailure(reason: .unavailable(.unavailableInBuild))
    }
  )

  public static let live: Self = {
    #if canImport(FoundationModels)
    Self(
      checkAvailability: { locale, useCase in
        foundationModelAvailability(locale: locale, useCase: useCase)
      },
      countTokens: { request in
        try await foundationModelTokenCount(for: request)
      },
      prewarm: { request in
        try foundationModelPrewarm(for: request)
      },
      respond: { request in
        try await foundationModelStringResponse(for: request)
      }
    )
    #else
    Self.unavailable
    #endif
  }()
}
