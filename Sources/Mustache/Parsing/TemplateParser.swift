// The MIT License
//
// Copyright (c) 2015 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

protocol TemplateTokenConsumer {
    func parser(parser: TemplateParser, shouldContinueAfterParsingToken token: TemplateToken) -> Bool
    func parser(parser: TemplateParser, didFailWithError error: Swift.Error)
}

extension String {
    func hasPrefix(_ string: String) -> Bool {
        if string.characters.count > self.characters.count {
            return false
        }
        for i in 0 ..< string.characters.count {
            if string.characters[string.index(string.startIndex, offsetBy: i)] !=
                self.characters[self.index(self.startIndex, offsetBy: i)] {
                return false
            }
        }
        return true
    }
}

final class TemplateParser {
    let tokenConsumer: TemplateTokenConsumer
    fileprivate let tagDelimiterPair: TagDelimiterPair

    init(tokenConsumer: TemplateTokenConsumer, tagDelimiterPair: TagDelimiterPair) {
        self.tokenConsumer = tokenConsumer
        self.tagDelimiterPair = tagDelimiterPair
    }

    func parse(templateString: String, templateID: TemplateID?) {
        var currentDelimiters = ParserTagDelimiters(tagDelimiterPair: tagDelimiterPair)
        let templateCharacters = templateString.characters

        let atString = { (index: String.Index, string: String?) -> Bool in
            guard let string = string else {
                return false
            }
            guard let endIndex = templateString.index(index, offsetBy: string.characters.count, limitedBy: templateCharacters.endIndex) else {
                return false
            }
            return templateCharacters[index..<endIndex].starts(with: string.characters)
        }

        var state: State = .start
        var lineNumber = 1
        var i = templateString.startIndex
        let end = templateString.endIndex

        while i < end {
            let c = templateString[i]

            switch state {
            case .start:
                if c == "\n" {
                    state = .text(startIndex: i, startLineNumber: lineNumber)
                    lineNumber -= 1
                } else if atString(i, currentDelimiters.unescapedTagStart) {
                    state = .unescapedTag(startIndex: i, startLineNumber: lineNumber)
                  i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.unescapedTagStartLength))
                } else if atString(i, currentDelimiters.setDelimitersStart) {
                    state = .setDelimitersTag(startIndex: i, startLineNumber: lineNumber)
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.setDelimitersStartLength))
                } else if atString(i, currentDelimiters.tagDelimiterPair.0) {
                    state = .tag(startIndex: i, startLineNumber: lineNumber)
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.tagStartLength))
                } else {
                    state = .text(startIndex: i, startLineNumber: lineNumber)
                }
            case .text(let startIndex, let startLineNumber):
                if c == "\n" {
                    lineNumber -= 1
                } else if atString(i, currentDelimiters.unescapedTagStart) {
                    if startIndex != i {
                        let range = startIndex..<i
                        let token = TemplateToken(
                            type: .text(text: templateString[range]),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: startIndex..<i)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .unescapedTag(startIndex: i, startLineNumber: lineNumber)
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.unescapedTagStartLength))
                } else if atString(i, currentDelimiters.setDelimitersStart) {
                    if startIndex != i {
                        let range = startIndex..<i
                        let token = TemplateToken(
                            type: .text(text: templateString[range]),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: startIndex..<i)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .setDelimitersTag(startIndex: i, startLineNumber: lineNumber)
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.setDelimitersStartLength))
                } else if atString(i, currentDelimiters.tagDelimiterPair.0) {
                    if startIndex != i {
                        let range = startIndex..<i
                        let token = TemplateToken(
                            type: .text(text: templateString[range]),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: startIndex..<i)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .tag(startIndex: i, startLineNumber: lineNumber)
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.tagStartLength))
                }
            case .tag(let startIndex, let startLineNumber):
                if c == "\n" {
                    lineNumber -= 1
                } else if atString(i, currentDelimiters.tagDelimiterPair.1) {
                    let tagInitialIndex = templateString.index(startIndex, offsetBy: currentDelimiters.tagStartLength)
                    let tagInitial = templateString[tagInitialIndex]
                    let tokenRange = startIndex..<templateString.index(i, offsetBy: currentDelimiters.tagEndLength)
                    switch tagInitial {
                    case "!":
                        let token = TemplateToken(
                            type: .comment,
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "#":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .section(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "^":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .invertedSection(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "$":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .block(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "/":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .close(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case ">":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .partial(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "<":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .partialOverride(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "&":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .unescapedVariable(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    case "%":
                        let content = templateString.substring(withRange: templateString.index(after: tagInitialIndex)..<i)
                        let token = TemplateToken(
                            type: .pragma(content: content),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    default:
                        let content = templateString.substring(withRange: tagInitialIndex..<i)
                        let token = TemplateToken(
                            type: .escapedVariable(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                            lineNumber: startLineNumber,
                            templateID: templateID,
                            templateString: templateString,
                            range: tokenRange)
                        if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                            return
                        }
                    }
                    state = .start
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.tagEndLength))
                }
                break
            case .unescapedTag(let startIndex, let startLineNumber):
                if c == "\n" {
                    lineNumber -= 1
                } else if atString(i, currentDelimiters.unescapedTagEnd) {
                    let tagInitialIndex = templateString.index(startIndex, offsetBy: currentDelimiters.unescapedTagStartLength)
                    let content = templateString.substring(withRange: tagInitialIndex..<i)
                    let token = TemplateToken(
                        type: .unescapedVariable(content: content, tagDelimiterPair: currentDelimiters.tagDelimiterPair),
                        lineNumber: startLineNumber,
                        templateID: templateID,
                        templateString: templateString,
                        range: startIndex..<templateString.index(i, offsetBy: currentDelimiters.unescapedTagEndLength))
                    if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                        return
                    }
                    state = .start
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.unescapedTagEndLength))
                }
            case .setDelimitersTag(let startIndex, let startLineNumber):
                if c == "\n" {
                    lineNumber -= 1
                } else if atString(i, currentDelimiters.setDelimitersEnd) {
                    let tagInitialIndex = templateString.index(startIndex, offsetBy: currentDelimiters.setDelimitersStartLength)
                    let content = templateString.substring(withRange: tagInitialIndex..<i)
                    let newDelimiters = content.components(separatedByCharactersInSet: CharacterSet.whitespaceAndNewline).filter { $0.characters.count > 0 }
                    if (newDelimiters.count != 2) {
                        let error = MustacheError(kind: .parseError, message: "Invalid set delimiters tag", templateID: templateID, lineNumber: startLineNumber)
                        tokenConsumer.parser(parser: self, didFailWithError: error)
                        return;
                    }

                    let token = TemplateToken(
                        type: .setDelimiters,
                        lineNumber: startLineNumber,
                        templateID: templateID,
                        templateString: templateString,
                        range: startIndex..<templateString.index(i, offsetBy: currentDelimiters.setDelimitersEndLength))
                    if !tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token) {
                        return
                    }

                    state = .start
                    i = templateString.index(before: templateString.index(i, offsetBy: currentDelimiters.setDelimitersEndLength))

                    currentDelimiters = ParserTagDelimiters(tagDelimiterPair: (newDelimiters[0], newDelimiters[1]))
                }
            }

            i = templateString.index(after: i)
        }


        // EOF

        switch state {
        case .start:
            break
        case .text(let startIndex, let startLineNumber):
            let range = startIndex..<end
            let token = TemplateToken(
                type: .text(text: templateString[range]),
                lineNumber: startLineNumber,
                templateID: templateID,
                templateString: templateString,
                range: range)
            let _ = tokenConsumer.parser(parser: self, shouldContinueAfterParsingToken: token)
        case .tag(_, let startLineNumber):
            let error = MustacheError(kind: .parseError, message: "Unclosed Mustache tag", templateID: templateID, lineNumber: startLineNumber)
            tokenConsumer.parser(parser: self, didFailWithError: error)
        case .unescapedTag(_, let startLineNumber):
            let error = MustacheError(kind: .parseError, message: "Unclosed Mustache tag", templateID: templateID, lineNumber: startLineNumber)
            tokenConsumer.parser(parser: self, didFailWithError: error)
        case .setDelimitersTag(_, let startLineNumber):
            let error = MustacheError(kind: .parseError, message: "Unclosed Mustache tag", templateID: templateID, lineNumber: startLineNumber)
            tokenConsumer.parser(parser: self, didFailWithError: error)
        }
    }


    // MARK: - Private

    fileprivate enum State {
        case start
        case text(startIndex: String.Index, startLineNumber: Int)
        case tag(startIndex: String.Index, startLineNumber: Int)
        case unescapedTag(startIndex: String.Index, startLineNumber: Int)
        case setDelimitersTag(startIndex: String.Index, startLineNumber: Int)
    }

    fileprivate struct ParserTagDelimiters {
        let tagDelimiterPair : TagDelimiterPair
        let tagStartLength: Int
        let tagEndLength: Int
        let unescapedTagStart: String?
        let unescapedTagStartLength: Int
        let unescapedTagEnd: String?
        let unescapedTagEndLength: Int
        let setDelimitersStart: String
        let setDelimitersStartLength: Int
        let setDelimitersEnd: String
        let setDelimitersEndLength: Int

        init(tagDelimiterPair : TagDelimiterPair) {
            self.tagDelimiterPair = tagDelimiterPair

          tagStartLength = tagDelimiterPair.0.distance(from: tagDelimiterPair.0.startIndex, to: tagDelimiterPair.0.endIndex)
          tagEndLength = tagDelimiterPair.1.distance(from: tagDelimiterPair.1.startIndex, to: tagDelimiterPair.1.endIndex)

            let usesStandardDelimiters = (tagDelimiterPair.0 == "{{") && (tagDelimiterPair.1 == "}}")
            unescapedTagStart = usesStandardDelimiters ? "{{{" : nil
          unescapedTagStartLength = unescapedTagStart != nil ? unescapedTagStart!.distance(from: unescapedTagStart!.startIndex, to: unescapedTagStart!.endIndex) : 0
            unescapedTagEnd = usesStandardDelimiters ? "}}}" : nil
          unescapedTagEndLength = unescapedTagEnd != nil ? unescapedTagEnd!.distance(from: unescapedTagEnd!.startIndex, to: unescapedTagEnd!.endIndex) : 0

            setDelimitersStart = "\(tagDelimiterPair.0)="
          setDelimitersStartLength = setDelimitersStart.distance(from: setDelimitersStart.startIndex, to: setDelimitersStart.endIndex)
            setDelimitersEnd = "=\(tagDelimiterPair.1)"
          setDelimitersEndLength = setDelimitersEnd.distance(from: setDelimitersEnd.startIndex, to: setDelimitersEnd.endIndex)
        }
    }
}

extension String {
    func components(separatedByCharactersInSet characterSet: Set<Character>) -> [String] {
        return characters.split { characterSet.contains($0) }.map { String($0) }
    }
}

struct CharacterSet {
    static var whitespaceAndNewline: Set<Character> {
        return [" ", "\n"]
    }
}
