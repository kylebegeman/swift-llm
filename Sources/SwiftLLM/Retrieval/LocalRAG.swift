import Foundation

public struct SourceReference: Equatable, Identifiable, Sendable {
  public var displayName: String?
  public var id: String
  public var kind: String?
  public var metadata: [String: String]
  public var updatedAt: Date?

  public init(
    id: String,
    displayName: String? = nil,
    kind: String? = nil,
    metadata: [String: String] = [:],
    updatedAt: Date? = nil
  ) {
    self.displayName = displayName
    self.id = id
    self.kind = kind
    self.metadata = metadata
    self.updatedAt = updatedAt
  }
}

public struct RetrievableDocument: Equatable, Identifiable, Sendable {
  public var id: String
  public var source: SourceReference
  public var text: String

  public init(
    id: String,
    text: String,
    displayName: String? = nil,
    kind: String? = nil,
    metadata: [String: String] = [:],
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.source = SourceReference(
      id: id,
      displayName: displayName,
      kind: kind,
      metadata: metadata,
      updatedAt: updatedAt
    )
    self.text = text
  }

  public init(
    id: String,
    source: SourceReference,
    text: String
  ) {
    self.id = id
    self.source = source
    self.text = text
  }
}

public struct LocalRetrievalQuery: Equatable, Sendable {
  public var allowedSourceIDs: Set<SourceReference.ID>?
  public var excludedSourceIDs: Set<SourceReference.ID>
  public var maxResults: Int
  public var metadata: [String: String]
  public var minimumScore: Double
  public var requiredSourceIDs: Set<SourceReference.ID>
  public var text: String

  public init(
    text: String,
    maxResults: Int = 8,
    minimumScore: Double = 0,
    allowedSourceIDs: Set<SourceReference.ID>? = nil,
    excludedSourceIDs: Set<SourceReference.ID> = [],
    requiredSourceIDs: Set<SourceReference.ID> = [],
    metadata: [String: String] = [:]
  ) {
    self.allowedSourceIDs = allowedSourceIDs
    self.excludedSourceIDs = excludedSourceIDs
    self.maxResults = max(0, maxResults)
    self.metadata = metadata
    self.minimumScore = minimumScore
    self.requiredSourceIDs = requiredSourceIDs
    self.text = text
  }
}

public struct LocalRetrievalResult: Equatable, Sendable {
  public var query: LocalRetrievalQuery
  public var snippets: [RetrievedSnippet]
  public var sources: [SourceReference]

  public init(
    query: LocalRetrievalQuery,
    snippets: [RetrievedSnippet],
    sources: [SourceReference]
  ) {
    self.query = query
    self.snippets = snippets
    self.sources = sources
  }
}

public protocol LocalRetriever: Sendable {
  func retrieve(_ query: LocalRetrievalQuery) async throws -> LocalRetrievalResult
}

public struct AnyLocalRetriever: LocalRetriever {
  private var retrieveHandler:
    @Sendable (LocalRetrievalQuery) async throws -> LocalRetrievalResult

  public init(
    retrieve: @escaping @Sendable (LocalRetrievalQuery) async throws -> LocalRetrievalResult
  ) {
    self.retrieveHandler = retrieve
  }

  public init<R: LocalRetriever>(_ retriever: R) {
    self.init { query in
      try await retriever.retrieve(query)
    }
  }

  public func retrieve(_ query: LocalRetrievalQuery) async throws -> LocalRetrievalResult {
    try await retrieveHandler(query)
  }
}

public struct KeywordLocalRetriever: LocalRetriever {
  public var boundary: TextChunkBoundary
  public var counter: TokenCounter
  public var documents: [RetrievableDocument]
  public var maxTokensPerSnippet: Int

  public init(
    documents: [RetrievableDocument],
    maxTokensPerSnippet: Int = 180,
    boundary: TextChunkBoundary = .paragraph,
    counter: TokenCounter = .latinHeuristic
  ) {
    self.boundary = boundary
    self.counter = counter
    self.documents = documents
    self.maxTokensPerSnippet = max(1, maxTokensPerSnippet)
  }

  public func retrieve(_ query: LocalRetrievalQuery) async throws -> LocalRetrievalResult {
    let queryTerms = LocalRetrievalScorer.terms(in: query.text)
    guard query.maxResults > 0,
          !queryTerms.isEmpty || !query.requiredSourceIDs.isEmpty
    else {
      return LocalRetrievalResult(query: query, snippets: [], sources: [])
    }

    let chunker = BoundaryAwareTextChunker(
      boundary: boundary,
      maxTokensPerChunk: maxTokensPerSnippet,
      overlapUnitCount: 0,
      counter: counter
    )
    var snippets: [RetrievedSnippet] = []
    var sourcesByID: [SourceReference.ID: SourceReference] = [:]

    for document in documents where query.allows(sourceID: document.source.id) {
      let chunks = chunker.chunks(for: document.text)
      let documentChunks = chunks.isEmpty
        ? [
          TextChunk(
            id: 0,
            text: document.text,
            characterRange: document.text.startIndex..<document.text.endIndex,
            tokenCount: counter.count(document.text)
          )
        ]
        : chunks

      for chunk in documentChunks {
        let score = LocalRetrievalScorer.score(text: chunk.text, query: query.text, terms: queryTerms)
        guard (score > 0 && score >= query.minimumScore)
          || query.requiredSourceIDs.contains(document.source.id)
        else { continue }

        sourcesByID[document.source.id] = document.source
        snippets.append(
          RetrievedSnippet(
            id: "\(document.id)#\(chunk.id)",
            sourceID: document.source.id,
            text: chunk.text,
            tokenCount: chunk.tokenCount,
            score: score,
            sourceDisplayName: document.source.displayName,
            sourceKind: document.source.kind,
            characterRange: document.text.intRange(for: chunk.characterRange),
            isRequired: query.requiredSourceIDs.contains(document.source.id)
          )
        )
      }
    }

    let ranked = snippets
      .sorted { lhs, rhs in
        if lhs.score != rhs.score {
          return lhs.score > rhs.score
        }
        if lhs.sourceID != rhs.sourceID {
          return lhs.sourceID < rhs.sourceID
        }
        return lhs.id < rhs.id
      }
      .prefix(query.maxResults)

    let resultSnippets = Array(ranked)
    let sources = resultSnippets
      .compactMap { sourcesByID[$0.sourceID] }
      .uniquedByID()

    return LocalRetrievalResult(
      query: query,
      snippets: resultSnippets,
      sources: sources
    )
  }
}

public struct SnippetCitation: Equatable, Identifiable, Sendable {
  public var characterRange: Range<Int>?
  public var id: String
  public var marker: String
  public var snippetID: RetrievedSnippet.ID
  public var sourceDisplayName: String?
  public var sourceID: SourceReference.ID
  public var sourceKind: String?

  public init(
    id: String,
    marker: String,
    snippetID: RetrievedSnippet.ID,
    sourceID: SourceReference.ID,
    sourceDisplayName: String? = nil,
    sourceKind: String? = nil,
    characterRange: Range<Int>? = nil
  ) {
    self.characterRange = characterRange
    self.id = id
    self.marker = marker
    self.snippetID = snippetID
    self.sourceDisplayName = sourceDisplayName
    self.sourceID = sourceID
    self.sourceKind = sourceKind
  }
}

public enum CitationMarkerStyle: Equatable, Sendable {
  case numeric
  case snippetID
}

public struct CitationContextRenderer: Sendable {
  public var markerStyle: CitationMarkerStyle

  public init(markerStyle: CitationMarkerStyle = .numeric) {
    self.markerStyle = markerStyle
  }

  public func citations(for snippets: [RetrievedSnippet]) -> [SnippetCitation] {
    snippets.enumerated().map { index, snippet in
      let marker = marker(for: snippet, index: index)
      return SnippetCitation(
        id: marker,
        marker: marker,
        snippetID: snippet.id,
        sourceID: snippet.sourceID,
        sourceDisplayName: snippet.sourceDisplayName,
        sourceKind: snippet.sourceKind,
        characterRange: snippet.characterRange
      )
    }
  }

  public func render(snippets: [RetrievedSnippet]) -> String {
    snippets.enumerated().map { index, snippet in
      let marker = marker(for: snippet, index: index)
      let sourceName = snippet.sourceDisplayName ?? snippet.sourceID
      let sourceKind = snippet.sourceKind.map { " (\($0))" } ?? ""
      return """
      [\(marker)] \(sourceName)\(sourceKind)
      \(snippet.text)
      """
    }
    .joined(separator: "\n\n")
  }

  private func marker(
    for snippet: RetrievedSnippet,
    index: Int
  ) -> String {
    switch markerStyle {
    case .numeric:
      return "\(index + 1)"
    case .snippetID:
      return snippet.id
    }
  }
}

public struct LocalRAGPipeline: Sendable {
  public var packer: ContextPacker
  public var renderer: CitationContextRenderer
  public var reservedInputTokens: Int
  public var retriever: AnyLocalRetriever

  public init<R: LocalRetriever>(
    retriever: R,
    packer: ContextPacker,
    reservedInputTokens: Int = 0,
    renderer: CitationContextRenderer = CitationContextRenderer()
  ) {
    self.packer = packer
    self.renderer = renderer
    self.reservedInputTokens = max(0, reservedInputTokens)
    self.retriever = AnyLocalRetriever(retriever)
  }

  public func run(
    query: LocalRetrievalQuery
  ) async throws -> LocalRAGResult {
    let retrieval = try await retriever.retrieve(query)
    let packed = packer.pack(
      snippets: retrieval.snippets,
      reservedInputTokens: reservedInputTokens
    )

    return LocalRAGResult(
      query: query,
      retrieval: retrieval,
      packedSnippets: packed,
      contextBlock: renderer.render(snippets: packed),
      citations: renderer.citations(for: packed)
    )
  }
}

public struct LocalRAGResult: Equatable, Sendable {
  public var citations: [SnippetCitation]
  public var contextBlock: String
  public var packedSnippets: [RetrievedSnippet]
  public var query: LocalRetrievalQuery
  public var retrieval: LocalRetrievalResult

  public init(
    query: LocalRetrievalQuery,
    retrieval: LocalRetrievalResult,
    packedSnippets: [RetrievedSnippet],
    contextBlock: String,
    citations: [SnippetCitation]
  ) {
    self.citations = citations
    self.contextBlock = contextBlock
    self.packedSnippets = packedSnippets
    self.query = query
    self.retrieval = retrieval
  }

  public var sourceContext: StructuredGenerationSourceContext {
    StructuredGenerationSourceContext(
      sources: packedSnippets.map(\.evidenceSource)
    )
  }
}

enum LocalRetrievalScorer {
  static func score(
    text: String,
    query: String,
    terms: [String]
  ) -> Double {
    let textTerms = self.terms(in: text)
    guard !textTerms.isEmpty else { return 0 }

    let querySet = Set(terms)
    let textSet = Set(textTerms)
    let matchedUnique = querySet.intersection(textSet).count
    let totalMatches = textTerms.filter { querySet.contains($0) }.count
    guard matchedUnique > 0 else { return 0 }

    let coverage = Double(matchedUnique) / Double(max(1, querySet.count))
    let frequency = log(Double(totalMatches) + 1)
    let phraseBonus = text.normalizedForRetrieval.contains(query.normalizedForRetrieval) ? 0.5 : 0
    return coverage + frequency + phraseBonus
  }

  static func terms(in text: String) -> [String] {
    text
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count > 1 }
  }
}

private extension LocalRetrievalQuery {
  func allows(sourceID: SourceReference.ID) -> Bool {
    guard !excludedSourceIDs.contains(sourceID) else { return false }
    if let allowedSourceIDs {
      return allowedSourceIDs.contains(sourceID)
    }
    return true
  }
}

private extension Array where Element == SourceReference {
  func uniquedByID() -> [SourceReference] {
    var seenIDs = Set<SourceReference.ID>()
    var result: [SourceReference] = []
    for source in self where !seenIDs.contains(source.id) {
      seenIDs.insert(source.id)
      result.append(source)
    }
    return result
  }
}

private extension String {
  var normalizedForRetrieval: String {
    LocalRetrievalScorer.terms(in: self).joined(separator: " ")
  }

  func intRange(for range: Range<String.Index>) -> Range<Int> {
    distance(from: startIndex, to: range.lowerBound)..<distance(from: startIndex, to: range.upperBound)
  }
}
