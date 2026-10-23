import Foundation

/// Conservative reader for ordinary Turtle declarations. Unsupported syntax stays
/// unclassified; no RDF inference, network access, or plug-in binary loading.
enum LV2Metadata {
    private static let core = "http://lv2plug.in/ns/lv2core#"
    private static let rdfType = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    private static let seeAlso = "http://www.w3.org/2000/01/rdf-schema#seeAlso"
    private static let name = "http://usefulinc.com/ns/doap#name"
    static func classify(_ root: URL) -> PluginClassification? {
        let manifest = root.appendingPathComponent("manifest.ttl")
        guard let data = PluginClassifier.metadata(manifest, in: root), let text = String(data: data, encoding: .utf8), let declarations = Turtle.read(text, base: manifest) else { return nil }
        let subjects = Array(Set(declarations.filter { $0.predicate == rdfType && $0.object == core + "Plugin" && !$0.literal }.map(\.subject))).sorted()
        guard !subjects.isEmpty else { return nil }
        var triples = declarations
        var visited = Set([manifest.standardizedFileURL.path])
        var queue = declarations.filter { $0.predicate == seeAlso && !$0.literal && subjects.contains($0.subject) }.map(\.object)
        var totalBytes = data.count
        while !queue.isEmpty && visited.count < 64 {
            let reference = queue.removeFirst()
            guard let file = URL(string: reference), file.isFileURL, file.pathExtension.lowercased() == "ttl", visited.insert(file.standardizedFileURL.path).inserted,
                  let bytes = PluginClassifier.metadata(file, in: root), totalBytes + bytes.count <= 4_000_000,
                  let text = String(data: bytes, encoding: .utf8), let more = Turtle.read(text, base: file) else { continue }
            totalBytes += bytes.count
            triples += more
            queue += more.filter { $0.predicate == seeAlso && !$0.literal && subjects.contains($0.subject) }.map(\.object)
        }
        let effects: Set<String> = ["DelayPlugin", "ReverbPlugin", "DistortionPlugin", "WaveshaperPlugin", "DynamicsPlugin", "CompressorPlugin", "LimiterPlugin", "ExpanderPlugin", "GatePlugin", "AmplifierPlugin", "FilterPlugin", "LowpassPlugin", "HighpassPlugin", "BandpassPlugin", "CombPlugin", "AllpassPlugin", "EQPlugin", "ParaEQPlugin", "MultiEQPlugin", "ModulatorPlugin", "ChorusPlugin", "FlangerPlugin", "PhaserPlugin", "SpectralPlugin", "PitchPlugin", "SpatialPlugin", "SimulatorPlugin"]
        let others: Set<String> = ["MIDIPlugin", "AnalyserPlugin", "UtilityPlugin", "ConverterPlugin", "FunctionPlugin", "MixerPlugin", "GeneratorPlugin", "ConstantPlugin", "OscillatorPlugin"]
        let components = subjects.map { subject in
            let properties = triples.filter { $0.subject == subject }
            let types = properties.filter { $0.predicate == rdfType && !$0.literal }.map(\.object).filter { $0.hasPrefix(core) }.map { String($0.dropFirst(core.count)) }
            var categories: [PluginCategory] = []
            if types.contains("InstrumentPlugin") { categories.append(.instrument) }
            if types.contains(where: effects.contains) { categories.append(.effect) }
            if categories.isEmpty && types.contains(where: others.contains) { categories.append(.other) }
            return PluginComponent(identifier: subject, name: properties.first(where: { $0.predicate == name && $0.literal })?.object ?? subject, categories: PluginCategory.normalized(categories), declaration: types.filter { $0 != "Plugin" }.joined(separator: ", "))
        }
        return PluginClassification(components: components, source: "插件声明 · LV2 Turtle")
    }
}

private struct Triple {
    let subject: String
    let predicate: String
    let object: String
    let literal: Bool
}

private struct Turtle {
    struct Token { let text: String; let kind: Kind }
    enum Kind { case iri, word, literal, punctuation }
    var tokens: [Token]
    var index = 0
    var base: URL
    var prefixes: [String: String] = [:]
    var triples: [Triple] = []
    static func read(_ text: String, base: URL) -> [Triple]? {
        guard let tokens = tokenize(text) else { return nil }
        var parser = Self(tokens: tokens, base: base)
        return parser.parse() ? parser.triples : nil
    }
    mutating func parse() -> Bool {
        while index < tokens.count {
            let start = take()
            if ["@prefix", "PREFIX"].contains(start.text) {
                guard index + 1 < tokens.count else { return false }
                let prefix = take(); let uri = take()
                guard prefix.text.hasSuffix(":"), uri.kind == .iri, let expanded = expand(uri) else { return false }
                prefixes[String(prefix.text.dropLast())] = expanded
                if start.text == "@prefix" && !consume(".") { return false }
                continue
            }
            if ["@base", "BASE"].contains(start.text) {
                guard index < tokens.count, let expanded = expand(take()), let url = URL(string: expanded) else { return false }
                base = url
                if start.text == "@base" && !consume(".") { return false }
                continue
            }
            guard let subject = expand(start) else { return false }
            while true {
                guard index < tokens.count else { return false }
                let token = take()
                guard let predicate = token.text == "a" ? "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" : expand(token) else { return false }
                repeat {
                    guard index < tokens.count else { return false }
                    let object = take()
                    if object.text == "[" || object.text == "(" {
                        // Nested blank nodes and collections do not declare this subject's type.
                        var stack = [object.text == "[" ? "]" : ")"]
                        while !stack.isEmpty {
                            guard index < tokens.count else { return false }
                            let next = take()
                            if next.kind == .punctuation {
                                if next.text == "[" { stack.append("]") }
                                else if next.text == "(" { stack.append(")") }
                                else if next.text == stack.last { stack.removeLast() }
                            }
                        }
                    } else if object.kind == .literal {
                        triples.append(Triple(subject: subject, predicate: predicate, object: object.text, literal: true))
                        if index < tokens.count && tokens[index].kind == .word && tokens[index].text.hasPrefix("@") { index += 1 }
                        if consume("^^") { guard index < tokens.count, expand(take()) != nil else { return false } }
                    } else if let value = expand(object) {
                        triples.append(Triple(subject: subject, predicate: predicate, object: value, literal: false))
                    } else if object.kind != .word { return false }
                } while consume(",")
                if consume(".") { break }
                guard consume(";") else { return false }
                while consume(";") {}
                if consume(".") { break }
            }
        }
        return true
    }
    mutating func take() -> Token { defer { index += 1 }; return tokens[index] }
    mutating func consume(_ value: String) -> Bool {
        guard index < tokens.count, tokens[index].kind == .punctuation, tokens[index].text == value else { return false }
        index += 1; return true
    }
    func expand(_ token: Token) -> String? {
        if token.kind == .iri { return URL(string: token.text, relativeTo: base)?.absoluteURL.absoluteString }
        guard token.kind == .word, let colon = token.text.firstIndex(of: ":"), let prefix = prefixes[String(token.text[..<colon])] else { return nil }
        return prefix + token.text[token.text.index(after: colon)...]
    }
    static func tokenize(_ text: String) -> [Token]? {
        let chars = Array(text)
        var i = 0; var result: [Token] = []
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "#" { while i < chars.count && chars[i] != "\n" { i += 1 }; continue }
            if c == "<" {
                i += 1; let start = i
                while i < chars.count && chars[i] != ">" { i += 1 }
                guard i < chars.count else { return nil }
                result.append(Token(text: String(chars[start..<i]), kind: .iri)); i += 1; continue
            }
            if c == "\"" || c == "'" {
                let quote = c
                let triple = i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote
                i += triple ? 3 : 1; var value = ""; var closed = false
                while i < chars.count {
                    if chars[i] == "\\" {
                        i += 1; guard i < chars.count else { return nil }
                        value.append(chars[i]); i += 1; continue
                    }
                    if chars[i] == quote && (!triple || (i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote)) { i += triple ? 3 : 1; closed = true; break }
                    value.append(chars[i]); i += 1
                }
                guard closed else { return nil }
                result.append(Token(text: value, kind: .literal)); continue
            }
            if ";,.[ ]()".contains(c) || c == "^" {
                if c == "^" { guard i + 1 < chars.count && chars[i + 1] == "^" else { return nil }; result.append(Token(text: "^^", kind: .punctuation)); i += 2 }
                else { result.append(Token(text: String(c), kind: .punctuation)); i += 1 }
                continue
            }
            let start = i
            while i < chars.count && !chars[i].isWhitespace && !";,[]()<>\"'".contains(chars[i]) && chars[i] != "#" && chars[i] != "^" {
                if chars[i] == "." && (i + 1 == chars.count || chars[i + 1].isWhitespace) { break }
                i += 1
            }
            guard i > start else { return nil }
            result.append(Token(text: String(chars[start..<i]), kind: .word))
        }
        return result
    }
}
