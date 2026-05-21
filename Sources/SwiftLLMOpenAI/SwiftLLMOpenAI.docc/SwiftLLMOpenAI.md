# ``SwiftLLMOpenAI``

OpenAI Responses API adapter for SwiftLLM.

## Overview

`SwiftLLMOpenAI` provides `OpenAIClient`, an `LLMClient` implementation that translates SwiftLLM requests into OpenAI Responses API calls.

The adapter supports:

- text generation
- JSON object and JSON schema response formats
- function tool definitions
- tool choice
- token usage parsing
- function call parsing
- injectable HTTP transport for tests

Apps provide API keys at initialization time and own credential storage.

## Topics

### Client

- ``OpenAIClient``
- ``OpenAIHTTPTransport``
- ``OpenAIHTTPRequest``
- ``OpenAIHTTPResponse``
