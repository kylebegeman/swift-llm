import Foundation
import SwiftLLM

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FoundationModelErrorNormalizer {
  public static func failure(from error: any Error) -> FoundationModelFailure {
    if let failure = error as? FoundationModelFailure {
      return failure
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
      if let generationError = error as? LanguageModelSession.GenerationError {
        return foundationModelFailure(from: generationError)
      }
      if let toolError = error as? LanguageModelSession.ToolCallError {
        return FoundationModelFailure(
          reason: .toolCallFailed,
          debugDescription: toolError.errorDescription ?? String(describing: toolError.underlyingError)
        )
      }
    }
    #endif

    return FoundationModelFailure(
      reason: .providerError,
      debugDescription: error.localizedDescription
    )
  }
}
