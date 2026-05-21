import Foundation

public struct TokenBudget: Equatable, Sendable {
  public var contextLimit: Int
  public var reservedResponseTokens: Int
  public var safetyMarginTokens: Int

  public init(
    contextLimit: Int = 4_096,
    reservedResponseTokens: Int = 512,
    safetyMarginTokens: Int = 256
  ) {
    self.contextLimit = contextLimit
    self.reservedResponseTokens = reservedResponseTokens
    self.safetyMarginTokens = safetyMarginTokens
  }

  public var availableInputTokens: Int {
    max(0, contextLimit - reservedResponseTokens - safetyMarginTokens)
  }
}

public struct TokenCounter: Sendable {
  public var count: @Sendable (String) -> Int

  public init(count: @escaping @Sendable (String) -> Int) {
    self.count = count
  }

  public static let latinHeuristic = Self { text in
    guard !text.isEmpty else { return 0 }

    let latinScalars = text.unicodeScalars.filter { $0.value < 0x3000 }.count
    let nonLatinScalars = text.unicodeScalars.count - latinScalars
    let latinTokens = Int(ceil(Double(latinScalars) / 4.0))
    return max(1, latinTokens + nonLatinScalars)
  }
}

public struct TextChunk: Equatable, Identifiable, Sendable {
  public var characterRange: Range<String.Index>
  public var id: Int
  public var text: String
  public var tokenCount: Int

  public init(
    id: Int,
    text: String,
    characterRange: Range<String.Index>,
    tokenCount: Int
  ) {
    self.id = id
    self.text = text
    self.characterRange = characterRange
    self.tokenCount = tokenCount
  }
}

public struct TextChunker: Sendable {
  public var counter: TokenCounter
  public var maxTokensPerChunk: Int
  public var overlapTokens: Int

  public init(
    maxTokensPerChunk: Int,
    overlapTokens: Int = 64,
    counter: TokenCounter = .latinHeuristic
  ) {
    self.counter = counter
    self.maxTokensPerChunk = max(1, maxTokensPerChunk)
    self.overlapTokens = max(0, overlapTokens)
  }

  public func chunks(for text: String) -> [TextChunk] {
    let words = text
      .split(whereSeparator: \.isWhitespace)
      .map { word in
        (
          text: String(word),
          range: word.startIndex..<word.endIndex
        )
      }

    guard !words.isEmpty else { return [] }

    var chunks: [TextChunk] = []
    var cursor = 0

    while cursor < words.count {
      var chunkWords: [String] = []
      var tokenCount = 0
      var index = cursor

      while index < words.count {
        let candidate = chunkWords + [words[index].text]
        let candidateText = candidate.joined(separator: " ")
        let candidateTokens = counter.count(candidateText)
        guard candidateTokens <= maxTokensPerChunk || chunkWords.isEmpty else { break }
        chunkWords = candidate
        tokenCount = candidateTokens
        index += 1
      }

      let chunkText = chunkWords.joined(separator: " ")
      let chunkRange = words[cursor].range.lowerBound..<words[index - 1].range.upperBound
      chunks.append(
        TextChunk(
          id: chunks.count,
          text: chunkText,
          characterRange: chunkRange,
          tokenCount: tokenCount
        )
      )

      guard index < words.count else { break }

      if overlapTokens == 0 {
        cursor = index
      } else {
        var overlapStart = index
        var overlapWords: [String] = []
        while overlapStart > cursor {
          let candidate = [words[overlapStart - 1].text] + overlapWords
          guard counter.count(candidate.joined(separator: " ")) <= overlapTokens else { break }
          overlapWords = candidate
          overlapStart -= 1
        }
        cursor = max(cursor + 1, overlapStart)
      }
    }

    return chunks
  }
}

public struct RetrievedSnippet: Equatable, Identifiable, Sendable {
  public var characterRange: Range<Int>?
  public var id: String
  public var isRequired: Bool
  public var sourceDisplayName: String?
  public var sourceID: String
  public var sourceKind: String?
  public var text: String
  public var tokenCount: Int
  public var score: Double

  public init(
    id: String,
    sourceID: String,
    text: String,
    tokenCount: Int,
    score: Double,
    sourceDisplayName: String? = nil,
    sourceKind: String? = nil,
    characterRange: Range<Int>? = nil,
    isRequired: Bool = false
  ) {
    self.characterRange = characterRange
    self.id = id
    self.isRequired = isRequired
    self.sourceDisplayName = sourceDisplayName
    self.sourceID = sourceID
    self.sourceKind = sourceKind
    self.text = text
    self.tokenCount = tokenCount
    self.score = score
  }

  public var sourceReference: SourceReference {
    SourceReference(
      id: sourceID,
      displayName: sourceDisplayName,
      kind: sourceKind
    )
  }

  public var evidenceSource: EvidenceSource {
    EvidenceSource(
      id: id,
      text: text,
      displayName: sourceDisplayName,
      kind: sourceKind
    )
  }
}

public struct ContextPacker: Sendable {
  public var budget: TokenBudget
  public var strategy: ContextPackingStrategy

  public init(
    budget: TokenBudget,
    strategy: ContextPackingStrategy = .scoreDescending
  ) {
    self.budget = budget
    self.strategy = strategy
  }

  public func pack(
    snippets: [RetrievedSnippet],
    reservedInputTokens: Int = 0
  ) -> [RetrievedSnippet] {
    var remaining = max(0, budget.availableInputTokens - reservedInputTokens)
    var packed: [RetrievedSnippet] = []
    var packedIDs = Set<RetrievedSnippet.ID>()

    let required = strategy.sort(snippets.filter(\.isRequired))
    let optional = strategy.sort(snippets.filter { !$0.isRequired })

    for snippet in required + optional {
      guard !packedIDs.contains(snippet.id) else { continue }
      guard snippet.tokenCount <= remaining else { continue }
      packed.append(snippet)
      packedIDs.insert(snippet.id)
      remaining -= snippet.tokenCount
    }

    return packed
  }
}

public enum ContextPackingStrategy: Equatable, Sendable {
  case scoreDescending
  case scoreDensity
  case sourceDiverse

  func sort(_ snippets: [RetrievedSnippet]) -> [RetrievedSnippet] {
    switch self {
    case .scoreDescending:
      return snippets.sorted { lhs, rhs in
        if lhs.score != rhs.score {
          return lhs.score > rhs.score
        }
        return lhs.tokenCount < rhs.tokenCount
      }
    case .scoreDensity:
      return snippets.sorted { lhs, rhs in
        let lhsDensity = lhs.score / Double(max(1, lhs.tokenCount))
        let rhsDensity = rhs.score / Double(max(1, rhs.tokenCount))
        if lhsDensity != rhsDensity {
          return lhsDensity > rhsDensity
        }
        return lhs.score > rhs.score
      }
    case .sourceDiverse:
      var groups = Dictionary(grouping: snippets, by: \.sourceID)
        .mapValues { snippets in
          snippets.sorted { lhs, rhs in
            if lhs.score != rhs.score {
              return lhs.score > rhs.score
            }
            return lhs.tokenCount < rhs.tokenCount
          }
        }
      var ordered: [RetrievedSnippet] = []

      while !groups.isEmpty {
        let sourceIDs = groups.keys.sorted { lhs, rhs in
          let lhsScore = groups[lhs]?.first?.score ?? -.infinity
          let rhsScore = groups[rhs]?.first?.score ?? -.infinity
          if lhsScore != rhsScore {
            return lhsScore > rhsScore
          }
          return lhs < rhs
        }

        for sourceID in sourceIDs {
          guard var snippets = groups[sourceID],
            !snippets.isEmpty
          else {
            groups[sourceID] = nil
            continue
          }
          ordered.append(snippets.removeFirst())
          groups[sourceID] = snippets.isEmpty ? nil : snippets
        }
      }

      return ordered
    }
  }
}
