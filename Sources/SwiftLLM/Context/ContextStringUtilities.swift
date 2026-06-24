import Foundation

func normalizedMergeKey(_ text: String) -> String {
  text
    .lowercased()
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }
    .joined(separator: " ")
}

extension String {
  var normalizedWhitespace: String {
    split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func units(
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
