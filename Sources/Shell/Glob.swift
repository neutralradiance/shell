/// https://github.com/devongovett/glob-match/blob/main/src/lib.rs
private struct State {
 internal init(
  glob: String,
  str: String,
  pathIndex: String.Index,
  globIndex: String.Index,
  captureIndex: UInt32 = .zero, wildcard: Wildcard, globstar: Wildcard
 ) {
  self.glob = glob
  self.str = str
  self.pathIndex = pathIndex
  self.globIndex = globIndex
  self.captureIndex = captureIndex
  self.wildcard = wildcard
  self.globstar = globstar
 }

 var glob: String
 var str: String
 // These store character indices into the glob and path strings.
 var pathIndex: String.Index, globIndex: String.Index,
     // The current index into the captures list.
     captureIndex: UInt32 = .zero,
     // When we hit a * or **, we store the state for backtracking.
     wildcard: Wildcard,
     globstar: Wildcard
 init(_ glob: String, with string: String) {
  self.glob = glob
  self.str = string
  self.pathIndex = string.startIndex
  self.globIndex = glob.startIndex
  self.wildcard = Wildcard(globIndex: glob.startIndex, pathIndex: string.startIndex)
  self.globstar = Wildcard(globIndex: glob.startIndex, pathIndex: string.startIndex)
 }
}

private struct Wildcard {
 // Using UInt8 rather than String.Index for these results in 10% faster performance. (???)
 var globIndex: String.Index,
     pathIndex: String.Index, captureIndex: UInt32 = .zero
}

@inline(__always)
private func contains(_ glob: String, in str: String) -> Bool {
 var results: [ClosedRange<String.Index>]?
 return match(glob, in: str, &results)
}

@inline(__always)
private func matches(
 _ glob: String, in str: String, matches: inout [ClosedRange<String.Index>]?
) -> [ClosedRange<String.Index>]? {
 if match(glob, in: str, &matches) {
//   if str.isEmpty { matches = [0 ... 0] }
//   else if str.count == 1 { matches = [0 ... 1] }
//   else if let last = matches!.last, last.upperBound > path.count - 1 {
//    matches![matches!.indices.last!] = last.lowerBound ... String.Index(path.count - 1)
//   }
  return matches
 }
 return nil
}

@inline(__always)
private func match(
 _ glob: String,
 in str: String, _ captures: inout [ClosedRange<String.Index>]?
) -> Bool {
 // This algorithm is based on https://research.swtch.com/glob
 // Store the state when we see an opening '{' brace in a stack.
 // Up to 10 nested braces are supported.
 var state = State(glob, with: str)
 var braceStack = BraceStack(glob, with: str)

 // First, check if the pattern is negated with a leading '!' character.
 // Multiple negations can occur.
 var negated = false
 while state.globIndex < glob.endIndex, glob[state.globIndex] == .exclamationMark {
  negated = !negated
  state.globIndex = glob.index(after: state.globIndex)
 }

 while state.globIndex < glob.endIndex, state.pathIndex < str.endIndex {
  if state.globIndex < glob.endIndex {
   switch glob[state.globIndex] {
   case .asterik:
    let isGlobstar =
     glob.index(after: state.globIndex) < glob.endIndex
      && glob[glob.index(after: state.globIndex)] == .asterik

    if isGlobstar {
     // Coalesce multiple ** segments into one.
     state.globIndex =
      glob.index(
       skipGlobstars(glob, glob.index(state.globIndex, offsetBy: 2)), offsetBy: -2
      )
    }
    // If we are on a different glob index than before, start a new capture.
    // Otherwise, extend the active one.
    if captures != nil,
       captures!.isEmpty || state.globIndex != state.wildcard.globIndex {
     state.wildcard.captureIndex = state.captureIndex
     state.beginCapture(
      &captures, state.pathIndex ... str.index(after: state.pathIndex)
     )
    } else {
     state.extendCapture(&captures)
    }

    state.wildcard.globIndex = state.globIndex
    state.wildcard.pathIndex = str.index(after: state.pathIndex)

    // ** allows path separators, whereas * does not.
    // However, ** must be a full path component, i.e. a/**/b not a**b.
    if isGlobstar {
     state.globIndex = glob.index(state.globIndex, offsetBy: 2)

     if glob.endIndex == state.globIndex {
      // A trailing ** segment without a following separator.
      state.globstar = state.wildcard
     } else if state.globIndex.utf16Offset(in: glob) < 3 ||
      glob[glob.index(state.globIndex, offsetBy: -3)] == .forwardslash,
      glob[state.globIndex] == .forwardslash {
      // Matched a full /**/ segment. If the last character in the path was a separator,
      // skip the separator in the glob so we search for the next character.
      // In effect, this makes the whole segment optional so that a/**/b matches a/b.
      if state.pathIndex == str.startIndex || (
       state.pathIndex < str.endIndex &&
        str[str.index(before: state.pathIndex)] == .forwardslash
      ) {
       state.endCapture(&captures)
       state.globIndex = glob.index(after: state.globIndex)
      }

      // The allows_sep flag allows separator characters in ** matches.
      // one is a '/', which prevents a/**/b from matching a/bb.
      state.globstar = state.wildcard
     }
    } else {
     state.globIndex = glob.index(after: state.globIndex)
    }

    // If we are in a * segment and hit a separator,
    // either jump back to a previous ** or end the wildcard.
    if state.globstar.pathIndex != state.wildcard.pathIndex,
       state.pathIndex < str.endIndex,
       str[state.pathIndex] == .forwardslash {
     // Special case: don't jump back for a / at the end of the glob.
     if state.globstar.pathIndex > glob.startIndex,
        str.index(after: state.pathIndex) < str.endIndex {
      state.globIndex = state.globstar.globIndex
      state.captureIndex = state.globstar.captureIndex
      state.wildcard.globIndex = state.globstar.globIndex
      state.wildcard.captureIndex = state.globstar.captureIndex
     } else {
      state.wildcard.pathIndex = glob.startIndex
     }
    }

    // If the next char is a special brace separator,
    // skip to the end of the braces so we don't try to match it.
    if braceStack.length > 0,
       state.globIndex < glob.endIndex,
       [.comma, .endBrace].contains(glob[state.globIndex]) {
     if state.skipBraces(glob, &captures, false) == .invalid {
      // invalid pattern!
      return false
     }
    }
    continue
   case .questionMark where state.pathIndex < str.endIndex:
    if str[state.pathIndex] != .forwardslash {
     state.addCharCapture(&captures)
     state.globIndex = glob.index(after: state.globIndex)
     state.pathIndex = str.index(after: state.pathIndex)
     continue
    }
   case .startBracket where state.pathIndex < str.endIndex:
    state.globIndex = glob.index(after: state.globIndex)
    let c = str[state.pathIndex]

    // Check if the character class is negated.
    var negated = false
    if state.globIndex < glob.endIndex,
       [.exclamationMark, .caret].contains(glob[state.globIndex]) {
     negated = true
     state.globIndex = glob.index(after: state.globIndex)
    }

    // Try each range.
    var first = true
    var isMatch = false
    while state.globIndex < glob.endIndex,
          first || glob[state.globIndex] != .endBracket {
     var low = glob[state.globIndex]
     if !unescape(&low, glob, &state.globIndex) {
      // Invalid pattern!
      return false
     }
     state.globIndex = glob.index(after: state.globIndex)

     // If there is a - and the following character is not ], read the range end character.
     var high: Character = low /// - NOTE: Altered from source
     if glob.index(after: state.globIndex) < glob.endIndex,
        glob[state.globIndex] == .hyphen,
        glob[glob.index(after: state.globIndex)] != .endBracket {
      state.globIndex = glob.index(after: state.globIndex)
      var char = glob[state.globIndex]
      if !unescape(&char, glob, &state.globIndex) {
       // Invalid pattern!
       return false
      }
      state.globIndex = glob.index(after: state.globIndex)
      high = char
     }

     if low <= c, c <= high { isMatch = true }
     first = false
    }
    if state.globIndex >= glob.endIndex {
     // invalid pattern!
     return false
    }
    state.globIndex = glob.index(after: state.globIndex)
    if isMatch != negated {
     state.addCharCapture(&captures)
     state.pathIndex = str.index(after: state.pathIndex)
     continue
    }
   case .startBrace where state.pathIndex < str.endIndex:
    if braceStack.length >= braceStack.stack.endIndex {
     // Invalid pattern! Too many nested braces.
     return false
    }

    state.endCapture(&captures)
    state.beginCapture(&captures, state.pathIndex ... str.index(after: state.pathIndex))

    // Push old state to the stack, and reset current state.
    state = braceStack.push(state)
    continue
   case .endBrace where braceStack.length > 0:
    // If we hit the end of the braces, we matched the last option.
    braceStack.longestBraceMatch =
     max(state.pathIndex, braceStack.longestBraceMatch)
    state.globIndex = glob.index(after: state.globIndex)
    state = braceStack.pop(state, &captures)
    continue
   case .comma where braceStack.length > 0:
    // If we hit a comma, we matched one of the options!
    // But we still need to check the others in case there is a longer match.
    braceStack.longestBraceMatch =
     max(state.pathIndex, braceStack.longestBraceMatch)
    state.pathIndex = braceStack.last().pathIndex
    state.globIndex = glob.index(after: state.globIndex)
    state.wildcard = .init(globIndex: glob.startIndex, pathIndex: str.startIndex)
    state.globstar = .init(globIndex: glob.startIndex, pathIndex: str.startIndex)
    continue
   case var c where state.pathIndex < str.endIndex:
    // Match escaped characters as literals.
    if !unescape(&c, glob, &state.globIndex) {
     // Invalid pattern!
     return false
    }

    if str[state.pathIndex] == c {
     state.endCapture(&captures)
     if braceStack.length > 0,
        state.globIndex > glob.startIndex,
        glob[glob.index(before: state.globIndex)] == .endBrace {
      braceStack.longestBraceMatch = state.pathIndex
      state = braceStack.pop(state, &captures)
     }
     state.globIndex = glob.index(after: state.globIndex)
     state.pathIndex = str.index(after: state.pathIndex)
     // If this is not a separator, lock in the previous globstar.
     if c != .forwardslash { state.globstar.pathIndex = glob.startIndex }
     continue
    }
   default:
    break
   }
   // If we didn't match, restore state to the previous star pattern.
   if state.wildcard.pathIndex > str.startIndex,
      state.wildcard.pathIndex <= str.endIndex {
    state.backtrack()
    continue
   }

   if braceStack.length > 0 {
    // If in braces, find next option and reset str to index where we saw the '{'
    switch state.skipBraces(glob, &captures, true) {
    case .invalid: return false
    case .comma:
     state.pathIndex = braceStack.last().pathIndex
     continue
    case .endbrace: break
    }
   }

   // Hit the end. Pop the stack.
   // If we matched a previous option, use that.
   if braceStack.longestBraceMatch > str.startIndex {
    state = braceStack.pop(state, &captures)
    continue
   } else {
    // Didn't match. Restore state, and check if we need to jump back to a star pattern.
    state = braceStack.last()
    braceStack.length &-= 1
    if captures != nil {
     captures!.removeSubrange(0 ..< Int(state.captureIndex))
    }
    if state.wildcard.pathIndex > str.startIndex,
       state.wildcard.pathIndex <= str.endIndex {
     state.backtrack()
     continue
    }
   }
  }

  return negated
 }

 if braceStack.length > 0,
    state.globIndex > glob.startIndex,
    glob[glob.index(before: state.globIndex)] == .endBrace {
  braceStack.longestBraceMatch = state.pathIndex
  braceStack.pop(state, &captures)
 }

 return !negated
}

@inline(__always)
private func unescape(_ c: inout Character, _ glob: String, _ globIndex: inout String.Index) -> Bool {
 if c == .backslash {
  globIndex = glob.index(after: globIndex)
  if globIndex >= glob.endIndex {
   // Invalid pattern!
   return false
  }
  // TODO: Try switching before setting c
  switch glob[globIndex] {
//      b'a' => b'\x61',
//      b'b' => b'\x08',
//      b'n' => b'\n',
//      b'r' => b'\r',
//      b't' => b'\t',
//      c => c,
  case "a": c = Character("a")
  case "b": c = Character("b")
  case "n": c = "\n"
  case "r": c = "\r"
  case "t": c = "\t"
  default: break
  }
 }
 return true
}

@inline(__always)
private func skipGlobstars(_ glob: String, _ globIndex: String.Index) -> String.Index {
 var lastIndex: String.Index = globIndex
 // Coalesce multiple ** segments into one.
 while let projectedIndex = glob.index(lastIndex, offsetBy: 3, limitedBy: glob.endIndex), glob[globIndex ..< projectedIndex] == "/**" {
  lastIndex = projectedIndex // glob.index(globIndex, offsetBy: 3)
 }
 return lastIndex
}

private enum BraceState {
 case invalid, comma, endbrace
}

private struct BraceStack {
 var glob: String
 var stack: [State],
     length: UInt = .zero,
     longestBraceMatch: String.Index
 init(_ glob: String, with string: String) {
  self.glob = glob
  self.stack = [State](repeating: State(glob, with: string), count: 10)
  self.longestBraceMatch = string.startIndex
 }
}

private extension State {
 @inline(__always)
 mutating func backtrack() {
  globIndex = wildcard.globIndex
  pathIndex = wildcard.pathIndex
  captureIndex = wildcard.captureIndex
 }

 @inline(__always)
 mutating func beginCapture(_ captures: inout [ClosedRange<String.Index>]?, _ capture: ClosedRange<String.Index>) {
  if captures != nil {
   if captureIndex < captures!.endIndex {
    captures![Int(captureIndex)] = capture
   } else {
    captures!.append(capture)
   }
  }
 }

 @inline(__always)
 mutating func extendCapture(_ captures: inout [ClosedRange<String.Index>]?) {
  if captures != nil {
   if captureIndex < captures!.endIndex {
    // extend range
    let currentCapture = captures![Int(captureIndex)]
    captures![Int(captureIndex)] =
     currentCapture.lowerBound ... pathIndex
   }
  }
 }

 @inline(__always)
 mutating func endCapture(_ captures: inout [ClosedRange<String.Index>]?) {
  if captures != nil {
   if captureIndex < captures!.endIndex {
    captureIndex &+= 1
   }
  }
 }

 @inline(__always)
 mutating func addCharCapture(_ captures: inout [ClosedRange<String.Index>]?) {
  endCapture(&captures)
  beginCapture(&captures, pathIndex ... pathIndex)
  captureIndex &+= 1
 }

 mutating func skipBraces(
  _ glob: String,
  _ captures: inout [ClosedRange<String.Index>]?,
  _ stopOnComma: Bool
 ) -> BraceState {
  var braces = 1
  var inBrackets = false
  var captureIndex = captureIndex + 1

  while globIndex < glob.endIndex, braces > 0 {
   switch glob[globIndex] {
   // Skip nested braces.
   case .startBrace where !inBrackets: braces &+= 1
   case .endBrace where !inBrackets: braces &-= 1
   case .comma:
    if stopOnComma, braces == 1, !inBrackets {
     globIndex = glob.index(after: globIndex)
     return .comma
    }
   case let c where [.asterik, .questionMark, .startBracket].contains(c) && !inBrackets:
    if c == .startBracket {
     inBrackets = true
    }
    if captures != nil {
     if captureIndex < captures!.endIndex {
      captures![Int(captureIndex)] = pathIndex ... pathIndex
     } else {
      captures!.append(pathIndex ... pathIndex)
     }
     captureIndex &+= 1
    }
    if c == .asterik {
     let nextIndex = glob.index(after: globIndex)
     if nextIndex < glob.endIndex, glob[nextIndex] == .asterik {
      globIndex =
       glob.index(
        skipGlobstars(glob, glob.index(globIndex, offsetBy: 2)), offsetBy: -2
       )
      globIndex = nextIndex
     }
    }
   case .endBracket: inBrackets = false
   case .backslash: globIndex = glob.index(after: globIndex)
   default: break
   }
   globIndex = glob.index(after: globIndex)
  }
  if braces != 0 { return .invalid }
  return .endbrace
 }
}

private extension BraceStack {
 @inline(__always)
 mutating func push(_ state: State) -> State {
  // Push old state to the stack, and reset current state.
  stack[Int(length)] = state
  length &+= 1
  return State(
   glob: glob,
   str: state.str, pathIndex: state.pathIndex,
   globIndex: glob.index(after: state.globIndex),
   captureIndex: state.captureIndex + 1,
   wildcard: Wildcard(globIndex: glob.startIndex, pathIndex: state.str.startIndex),
   globstar: Wildcard(globIndex: glob.startIndex, pathIndex: state.str.startIndex)
  )
 }

 @inline(__always) @discardableResult
 mutating func pop(_ state: State, _ captures: inout [ClosedRange<String.Index>]?) -> State {
  length &-= 1
  var modified = State(
   glob: state.glob, str: state.str,
   pathIndex: longestBraceMatch,
   globIndex: state.globIndex,
   // But restore star state if needed later.
   captureIndex: stack[Int(length)].captureIndex,
   wildcard: stack[Int(length)].wildcard,
   globstar: stack[Int(length)].globstar
  )
  if length == 0 { longestBraceMatch = state.str.startIndex }
  modified.extendCapture(&captures)
  if captures != nil { modified.captureIndex = UInt32(captures!.endIndex) }
  return state
 }

 func last() -> State {
  stack[length > 0 ? Int(length &- 1) : stack.endIndex - 1]
 }
}

public extension String {
 @inline(__always)
 func contains(glob pattern: String) -> Bool { Shell.contains(pattern, in: self) }
 @inline(__always)
 func matches(glob pattern: String, matches: inout [ClosedRange<String.Index>]?) -> [ClosedRange<String.Index>]? {
  Shell.matches(pattern, in: self, matches: &matches)
 }

 @inline(__always)
 func matches(glob pattern: String) -> [ClosedRange<String.Index>]? {
  var matches: [ClosedRange<String.Index>]? = []
  return Shell.matches(pattern, in: self, matches: &matches)
 }
}

// - MARK: StringProcessing
// import _StringProcessing
// public extension String {
// // @inline(__always)
//// func _contains(glob pattern: String) -> Bool {
////  return false
//// }
//
// // @inline(__always)
// func _matches(glob pattern: String) -> [ClosedRange<String.Index>]? {
//  nil
// }
// }

// - MARK: Regex
extension String {
// #if os(Windows)
//  static let sep = #"\\\\+"#
//  static let sepEsc = #"\\\\"#
// #else
//  static let sep = #"\\/"#
//  static let sepEsc = "/"
// #endif
// static let globstar = "((?:[^/]*(?:/|$))*)"
// static let wildcard = "([^/]*)"
// static let globstarSegment = "((?:[^${\(sepEsc)}]*(?:${\(sepEsc)}|$))*)"
// static let wildcardSegment = "([^${\(sepEsc)}]*)"
//
// func globToRegex(_ options: String.CompareOptions = []) -> String {
//  processNode("to-regex", with: self)
// }

// public func range(glob pattern: String) -> Range<String.Index>? {
//  let regex = pattern.globToRegex()
//  print(regex)
//  return self.range(of: regex)
// }
}

// var globToRegExp = require('glob-to-regexp');
