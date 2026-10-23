import Foundation
import Testing
@testable import PluginShelfCore

private func setInfo(_ url: URL, components: [[String: Any]], extensionInfo: Bool = false) throws {
    var info: [String: Any] = ["CFBundleName": "Test", "CFBundleIdentifier": "com.example.instrument"]
    if extensionInfo {
        info["NSExtension"] = ["NSExtensionAttributes": ["AudioComponents": components]]
    } else { info["AudioComponents"] = components }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
}
private func setModule(_ url: URL, text: String, legacy: Bool = false) throws {
    let file = url.appendingPathComponent(legacy ? "Contents/moduleinfo.json" : "Contents/Resources/moduleinfo.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
}
private func writeTTL(_ url: URL, _ text: String, file: String = "manifest.ttl") throws {
    try Data(text.utf8).write(to: url.appendingPathComponent(file))
}

@Test func auClassifiesAllComponentsWithoutConfusingMIDIEffects() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("Mixed", ext: "component")
    try setInfo(url, components: [["type": "aumu", "name": "Piano"], ["type": "aumf", "name": "MIDI Filter"], ["type": "aufx", "name": "Reverb"], ["type": "augn", "name": "Tone"], ["name": "Undeclared"]])
    let plugin = try #require(f.scan().first)
    #expect(plugin.categories == [.effect, .instrument, .other, .unknown])
    #expect(plugin.classification?.components.count == 5)
    #expect(plugin.classification?.components[1].categories == [.effect])
    var query = PluginQuery(); query.category = .instrument; #expect(query.matches(plugin))
    query.category = .effect; #expect(query.matches(plugin))
    query.format = .vst3; #expect(!query.matches(plugin))
}

@Test func auv3ReadsNestedExtensionAttributes() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("Nested", ext: "appex")
    try setInfo(url, components: [["type": "aumu", "name": "Nested Piano"]], extensionInfo: true)
    let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
    let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(PluginClassifier.classify(url: url, format: .auv3, info: info)?.categories == [.instrument])
}

@Test func vst3JSON5IgnoresControllersAndPreservesHybridClasses() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("Hybrid")
    try setModule(url, text: """
    { // Official module info permits JSON5 and trailing commas.
      "Classes": [
        {"CID":"one", "Category":"Audio Module Class", "Name":"Hybrid", "Sub Categories":["Fx|Instrument", "Synth"],},
        {"CID":"two", "Category":"Component Controller Class", "Name":"Editor", "Sub Categories":["Analyzer"]},
        {"CID":"three", "Category":"Audio Module Class", "Name":"Meter", "Sub Categories":["Analyzer"]},
      ],
    }
    """)
    let plugin = try #require(f.scan().first)
    #expect(plugin.categories == [.effect, .instrument, .other])
    #expect(plugin.classification?.components.count == 2)
    #expect(plugin.classification?.components.first?.categories == [.effect, .instrument])
}

@Test func legacyModuleInfoAndUnknownSubcategoryStayConservative() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("Legacy")
    try setModule(url, text: #"{"Classes":[{"Category":"Audio Module Class","Sub Categories":["VendorSynthMagic"]}]}"#, legacy: true)
    #expect(f.scan().first?.categories == [.unknown])
    #expect(f.scan().first?.classification?.components.count == 1)
    try setModule(url, text: #"{"Classes":[{"Category":"Audio Module Class","Sub Categories":["Instrument","Piano"]}]}"#, legacy: true)
    #expect(f.scan().first?.categories == [.instrument])
}

@Test func missingMalformedOrExternalMetadataDoesNotGuessFromName() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("Super Synth Piano Instrument")
    #expect(f.scan().first?.categories == [.unknown])
    try setModule(url, text: "bad json")
    #expect(f.scan().first?.categories == [.unknown])
    let file = url.appendingPathComponent("Contents/Resources/moduleinfo.json")
    try FileManager.default.removeItem(at: file)
    let external = f.directory.appendingPathComponent("outside.json")
    try Data(#"{"Classes":[{"Category":"Audio Module Class","Sub Categories":["Instrument"]}]}"#.utf8).write(to: external)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: external)
    #expect(f.scan().first?.categories == [.unknown])
}

@Test func lv2ResolvesLocalSeeAlsoAndClassifiesOnlyPluginSubjects() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("Mixed LV2", ext: "lv2")
    try writeTTL(url, """
    @prefix custom: <http://lv2plug.in/ns/lv2core#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    <urn:piano> a custom:Plugin ; rdfs:seeAlso <details.ttl> .
    <urn:echo> a custom:Plugin, custom:DelayPlugin .
    <urn:preset> a custom:InstrumentPlugin .
    """)
    try writeTTL(url, """
    @prefix l: <http://lv2plug.in/ns/lv2core#> .
    @prefix d: <http://usefulinc.com/ns/doap#> .
    <urn:piano> a l:InstrumentPlugin ; d:name "Paper Piano"@en ; l:port [ a l:InputPort ] .
    """, file: "details.ttl")
    let plugin = try #require(f.scan().first)
    #expect(plugin.categories == [.effect, .instrument])
    #expect(plugin.classification?.components.count == 2)
    #expect(plugin.classification?.components.contains(where: { $0.name == "Paper Piano" }) == true)
}

@Test func lv2CommentsLiteralsAndUnreferencedFilesCannotImpersonateTypes() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("LV2", ext: "lv2")
    try writeTTL(url, """
    @prefix lv2: <http://lv2plug.in/ns/lv2core#> .
    @prefix d: <http://usefulinc.com/ns/doap#> .
    # <urn:fake> a lv2:InstrumentPlugin .
    <urn:real> a lv2:Plugin ; d:name "contains lv2:InstrumentPlugin" .
    """)
    try writeTTL(url, "<urn:real> a <http://lv2plug.in/ns/lv2core#InstrumentPlugin> .", file: "unreferenced.ttl")
    #expect(f.scan().first?.categories == [.unknown])
    #expect(f.scan().first?.classification?.components.count == 1)
}

@Test func lv2OutsideReferencesAndMalformedDocumentsRemainUnknown() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin("LV2", ext: "lv2")
    try writeTTL(url, """
    @prefix l: <http://lv2plug.in/ns/lv2core#> .
    @prefix r: <http://www.w3.org/2000/01/rdf-schema#> .
    <urn:real> a l:Plugin ; r:seeAlso <../outside.ttl>, <https://example.invalid/plugin.ttl> .
    """)
    try Data("<urn:real> a <http://lv2plug.in/ns/lv2core#InstrumentPlugin> .".utf8).write(to: f.root.url.appendingPathComponent("outside.ttl"))
    #expect(f.scan().first?.categories == [.unknown])
    try writeTTL(url, "@prefix l: <http://lv2plug.in/ns/lv2core#> . <urn:real> a l:InstrumentPlugin ; broken")
    #expect(f.scan().first?.classification == nil)
}

@Test func manualCategoriesPersistAndResetWithoutChangingPluginBytes() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin()
    let before = try FileSafety.digest(url)
    let items = f.scan()
    try await f.engine.setCategories([.instrument, .effect, .instrument], for: items)
    let restarted = LibraryEngine(dataDirectory: f.directory.appendingPathComponent("Data"))
    var scanned = try await restarted.scan(roots: [f.root], applications: [])
    #expect(scanned.plugins.first?.categories == [.effect, .instrument])
    #expect(scanned.plugins.first?.classificationSource == L("手动设置"))
    #expect(scanned.plugins.first?.classification == nil)
    #expect(try FileSafety.digest(url) == before)
    try await restarted.setCategories(nil, for: scanned.plugins)
    scanned = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(scanned.plugins.first?.categoryOverride == nil)
    #expect(scanned.plugins.first?.categories == [.unknown])
}

@Test func manualOverrideDoesNotFollowADifferentBundleAtSamePath() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let url = try f.plugin()
    try await f.engine.setCategories([.instrument], for: f.scan())
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.other.replacement"], format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
    let result = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(result.plugins.first?.categories == [.unknown])
}

@Test func oldPluginSnapshotsStillDecodeWithoutClassification() throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    let data = try JSONEncoder().encode(try #require(f.scan().first))
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "classification"); json.removeValue(forKey: "categoryOverride")
    let old = try JSONDecoder().decode(Plugin.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.categories == [.unknown])
}

@Test func damagedManualClassificationDoesNotHideThePluginLibrary() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    let data = f.directory.appendingPathComponent("Data")
    try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    let file = data.appendingPathComponent("category-overrides.json")
    try Data("broken".utf8).write(to: file)
    let report = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(report.plugins.count == 1 && report.warnings.count == 1)
    #expect(report.plugins.first?.categories == [.unknown])
    await #expect(throws: (any Error).self) { try await f.engine.setCategories([.effect], for: report.plugins) }
    #expect(try String(contentsOf: file, encoding: .utf8) == "broken")
}

@Test func bulkClassificationResetPreservesDeclarationsAndUnselectedItems() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let instrument = try f.plugin("Piano", ext: "component")
    try setInfo(instrument, components: [["type": "aumu", "name": "Piano"]])
    _ = try f.plugin("Echo"); _ = try f.plugin("Untouched")
    let selected = f.scan().filter { $0.name != "Untouched" }
    try await f.engine.setCategories([.effect, .instrument], for: selected)
    var result = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(result.plugins.filter { $0.categories == [.effect, .instrument] }.count == 2)
    #expect(result.plugins.first { $0.name == "Untouched" }?.categories == [.unknown])
    let piano = try #require(result.plugins.first { $0.path == instrument.path })
    #expect(piano.classification?.categories == [.instrument])
    try await f.engine.setCategories(nil, for: [piano])
    result = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(result.plugins.first { $0.path == instrument.path }?.categories == [.instrument])
    #expect(result.plugins.first { $0.name == "Echo" }?.categories == [.effect, .instrument])
}
