import Foundation

public enum TextChunkBoundary: Equatable, Sendable {
  case word
  case sentence
  case paragraph
}

public struct BoundaryAwareTextChunker: Sendable {
  public var boundary: TextChunkBoundary
  public var counter: TokenCounter
  public var maxTokensPerChunk: Int
  public var overlapUnitCount: Int

  public init(
    boundary: TextChunkBoundary,
    maxTokensPerChunk: Int,
    overlapUnitCount: Int = 0,
    counter: TokenCounter = .latinHeuristic
  ) {
    self.boundary = boundary
    self.counter = counter
    self.maxTokensPerChunk = max(1, maxTokensPerChunk)
    self.overlapUnitCount = max(0, overlapUnitCount)
  }

  public func chunks(for text: String) -> [TextChunk] {
    let units = text.units(splitBy: boundary)
    guard !units.isEmpty else { return [] }

    var chunks: [TextChunk] = []
    var cursor = 0

    while cursor < units.count {
      var chunkUnits: [(text: String, range: Range<String.Index>)] = []
      var tokenCount = 0
      var index = cursor

      while index < units.count {
        let candidateUnits = chunkUnits + [units[index]]
        let candidateText = candidateUnits.map(\.text).joined(separator: " ").normalizedWhitespace
        let candidateTokens = counter.count(candidateText)
        guard candidateTokens <= maxTokensPerChunk || chunkUnits.isEmpty else { break }
        chunkUnits = candidateUnits
        tokenCount = candidateTokens
        index += 1
      }

      let chunkText = chunkUnits.map(\.text).joined(separator: " ").normalizedWhitespace
      let chunkRange = chunkUnits[0].range.lowerBound..<chunkUnits[chunkUnits.count - 1].range.upperBound
      chunks.append(
        TextChunk(
          id: chunks.count,
          text: chunkText,
          characterRange: chunkRange,
          tokenCount: tokenCount
        )
      )

      guard index < units.count else { break }
      cursor = max(cursor + 1, index - overlapUnitCount)
    }

    return chunks
  }
}

public struct TranscriptSegment: Equatable, Identifiable, Sendable {
  public var confidence: Double?
  public var endTime: TimeInterval
  public var id: String
  public var speakerID: String?
  public var startTime: TimeInterval
  public var text: String

  public init(
    id: String,
    text: String,
    startTime: TimeInterval,
    endTime: TimeInterval,
    speakerID: String? = nil,
    confidence: Double? = nil
  ) {
    self.confidence = confidence
    self.endTime = endTime
    self.id = id
    self.speakerID = speakerID
    self.startTime = startTime
    self.text = text
  }
}

public struct TranscriptChunk: Equatable, Identifiable, Sendable {
  public var endTime: TimeInterval?
  public var id: Int
  public var segmentIDs: [TranscriptSegment.ID]
  public var sourceID: String
  public var startTime: TimeInterval?
  public var text: String
  public var tokenCount: Int

  public init(
    id: Int,
    sourceID: String,
    text: String,
    segmentIDs: [TranscriptSegment.ID],
    tokenCount: Int,
    startTime: TimeInterval? = nil,
    endTime: TimeInterval? = nil
  ) {
    self.endTime = endTime
    self.id = id
    self.segmentIDs = segmentIDs
    self.sourceID = sourceID
    self.startTime = startTime
    self.text = text
    self.tokenCount = tokenCount
  }

  public var evidenceSource: EvidenceSource {
    EvidenceSource(
      id: "\(sourceID)-chunk-\(id)",
      text: text,
      displayName: "Chunk \(id + 1)",
      kind: "transcriptChunk"
    )
  }
}

public struct TranscriptChunker: Sendable {
  public var counter: TokenCounter
  public var maxTokensPerChunk: Int
  public var overlapSegmentCount: Int
  public var sourceID: String

  public init(
    maxTokensPerChunk: Int,
    overlapSegmentCount: Int = 1,
    sourceID: String = "transcript",
    counter: TokenCounter = .latinHeuristic
  ) {
    self.counter = counter
    self.maxTokensPerChunk = max(1, maxTokensPerChunk)
    self.overlapSegmentCount = max(0, overlapSegmentCount)
    self.sourceID = sourceID
  }

  public func chunks(for segments: [TranscriptSegment]) -> [TranscriptChunk] {
    guard !segments.isEmpty else { return [] }

    var chunks: [TranscriptChunk] = []
    var cursor = 0

    while cursor < segments.count {
      var chunkSegments: [TranscriptSegment] = []
      var tokenCount = 0
      var index = cursor

      while index < segments.count {
        let candidateSegments = chunkSegments + [segments[index]]
        let candidateText = candidateSegments.map(\.text).joined(separator: " ").normalizedWhitespace
        let candidateTokens = counter.count(candidateText)
        guard candidateTokens <= maxTokensPerChunk || chunkSegments.isEmpty else { break }
        chunkSegments = candidateSegments
        tokenCount = candidateTokens
        index += 1
      }

      chunks.append(
        TranscriptChunk(
          id: chunks.count,
          sourceID: sourceID,
          text: chunkSegments.map(\.text).joined(separator: " ").normalizedWhitespace,
          segmentIDs: chunkSegments.map(\.id),
          tokenCount: tokenCount,
          startTime: chunkSegments.first?.startTime,
          endTime: chunkSegments.last?.endTime
        )
      )

      guard index < segments.count else { break }
      cursor = max(cursor + 1, index - overlapSegmentCount)
    }

    return chunks
  }
}

public struct ChunkProcessingResult<Chunk: Sendable, Partial: Sendable>: Sendable {
  public var chunk: Chunk
  public var evidence: [EvidenceSpan]
  public var output: Partial
  public var tokenUsage: LLMTokenUsage?

  public init(
    chunk: Chunk,
    output: Partial,
    evidence: [EvidenceSpan] = [],
    tokenUsage: LLMTokenUsage? = nil
  ) {
    self.chunk = chunk
    self.evidence = evidence
    self.output = output
    self.tokenUsage = tokenUsage
  }
}

extension ChunkProcessingResult: Equatable where Chunk: Equatable, Partial: Equatable {}

public struct MapReducePipeline<Chunk: Sendable, Partial: Sendable, Final: Sendable>: Sendable {
  public var map:
    @Sendable (Chunk) async throws -> ChunkProcessingResult<Chunk, Partial>
  public var reduce:
    @Sendable ([ChunkProcessingResult<Chunk, Partial>]) async throws -> Final

  public init(
    map: @escaping @Sendable (Chunk) async throws -> ChunkProcessingResult<Chunk, Partial>,
    reduce: @escaping @Sendable ([ChunkProcessingResult<Chunk, Partial>]) async throws -> Final
  ) {
    self.map = map
    self.reduce = reduce
  }

  public func run(
    chunks: [Chunk]
  ) async throws -> MapReduceResult<Chunk, Partial, Final> {
    var partials: [ChunkProcessingResult<Chunk, Partial>] = []
    partials.reserveCapacity(chunks.count)

    for chunk in chunks {
      partials.append(try await map(chunk))
    }

    return MapReduceResult(
      partials: partials,
      output: try await reduce(partials)
    )
  }
}

public struct MapReduceResult<Chunk: Sendable, Partial: Sendable, Final: Sendable>: Sendable {
  public var output: Final
  public var partials: [ChunkProcessingResult<Chunk, Partial>]

  public init(
    partials: [ChunkProcessingResult<Chunk, Partial>],
    output: Final
  ) {
    self.output = output
    self.partials = partials
  }
}

extension MapReduceResult: Equatable where Chunk: Equatable, Partial: Equatable, Final: Equatable {}

public struct MergePolicy<Item: Sendable>: Sendable {
  public var key: @Sendable (Item) -> String
  public var merge: @Sendable (Item, Item) -> Item

  public init(
    key: @escaping @Sendable (Item) -> String,
    merge: @escaping @Sendable (Item, Item) -> Item
  ) {
    self.key = key
    self.merge = merge
  }

  public func merged(_ items: [Item]) -> [Item] {
    var orderedKeys: [String] = []
    var values: [String: Item] = [:]

    for item in items {
      let key = normalizedMergeKey(self.key(item))
      if let existing = values[key] {
        values[key] = merge(existing, item)
      } else {
        orderedKeys.append(key)
        values[key] = item
      }
    }

    return orderedKeys.compactMap { values[$0] }
  }
}

extension MergePolicy where Item == String {
  public static let normalizedText = Self(
    key: { $0 },
    merge: { existing, _ in existing }
  )
}

private func normalizedMergeKey(_ text: String) -> String {
  text
    .lowercased()
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }
    .joined(separator: " ")
}

extension String {
  fileprivate var normalizedWhitespace: String {
    split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  fileprivate func units(
    splitBy boundary: TextChunkBoundary
  ) -> [(text: String, range: Range<String.Index>)] {
    switch boundary {
    case .word:
      return split(whereSeparator: \.isWhitespace).map {
        (String($0), $0.startIndex..<$0.endIndex)
      }
    case .paragraph:
      return units(separatedBy: "\n\n")
    case .sentence:
      return sentenceUnits()
    }
  }

  private func units(
    separatedBy separator: String
  ) -> [(text: String, range: Range<String.Index>)] {
    var units: [(String, Range<String.Index>)] = []
    var cursor = startIndex

    while cursor < endIndex {
      let nextRange = self[cursor...].range(of: separator)
      let upperBound = nextRange?.lowerBound ?? endIndex
      let text = String(self[cursor..<upperBound]).normalizedWhitespace
      if !text.isEmpty {
        units.append((text, cursor..<upperBound))
      }
      guard let nextRange else { break }
      cursor = nextRange.upperBound
    }

    return units
  }

  private func sentenceUnits() -> [(text: String, range: Range<String.Index>)] {
    var units: [(String, Range<String.Index>)] = []
    var sentenceStart = startIndex
    var cursor = startIndex

    while cursor < endIndex {
      let character = self[cursor]
      let next = index(after: cursor)
      if character == "." || character == "!" || character == "?" {
        let text = String(self[sentenceStart..<next]).normalizedWhitespace
        if !text.isEmpty {
          units.append((text, sentenceStart..<next))
        }
        sentenceStart = next
      }
      cursor = next
    }

    if sentenceStart < endIndex {
      let text = String(self[sentenceStart..<endIndex]).normalizedWhitespace
      if !text.isEmpty {
        units.append((text, sentenceStart..<endIndex))
      }
    }

    return units
  }
}
