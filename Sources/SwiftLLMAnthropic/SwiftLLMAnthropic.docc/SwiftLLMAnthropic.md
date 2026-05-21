# ``SwiftLLMAnthropic``

Anthropic Messages API adapter for SwiftLLM.

## Overview

`SwiftLLMAnthropic` provides `AnthropicClient`, an `LLMClient` implementation that translates SwiftLLM requests into Anthropic Messages API calls.

The adapter supports:

- text generation
- system/developer instruction folding
- JSON response-format instructions
- tool definitions
- tool choice
- native tool-use and tool-result history
- token usage parsing
- tool use parsing
- injectable response and streaming HTTP transport for tests

Apps provide API keys at initialization time and own credential storage.

## Topics

### Client

- ``AnthropicClient``
- ``AnthropicHTTPTransport``
- ``AnthropicHTTPRequest``
- ``AnthropicHTTPResponse``
- ``AnthropicHTTPStreamResponse``
