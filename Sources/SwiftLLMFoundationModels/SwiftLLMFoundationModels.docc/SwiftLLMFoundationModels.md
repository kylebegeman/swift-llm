# ``SwiftLLMFoundationModels``

Adapt Apple Foundation Models into SwiftLLM's provider-neutral metadata, generation, token counting, and fallback shapes.

## Overview

SwiftLLMFoundationModels is the only product that should import Apple's Foundation Models framework. It normalizes framework availability, generation responses, token counts, prewarming, and errors into SwiftLLM types so app code does not need to duplicate provider-specific handling.

Use this product to:

- check model availability before generation
- prewarm Foundation Models sessions where available
- count tokens with the system tokenizer when possible
- generate strings and guided typed outputs
- call Foundation Models through the shared `LLMClient` protocol
- map Foundation Models failures into fallback reasons
- test unavailable and fake-client paths without importing Foundation Models in the app's core logic

## Topics

### Client

- ``FoundationModelClient``
- ``FoundationModelGenerationRequest``
- ``FoundationModelGenerationResponse``
- ``FoundationModelGenerationOptions``

### Availability

- ``FoundationModelAvailability``
- ``FoundationModelUseCase``
- ``FoundationModelDefaults``

### Token Counting And Prewarming

- ``FoundationModelTokenCountRequest``
- ``FoundationModelPrewarmRequest``

### Failures

- ``FoundationModelFailure``
- ``FoundationModelFailureReason``
- ``FoundationModelErrorNormalizer``
