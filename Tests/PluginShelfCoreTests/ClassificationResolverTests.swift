import Foundation
import Testing
@testable import PluginShelfCore

private func identified(_ f: Fixture, name: String, ext: String, id: String, version: String = "1.2.3",
                        auTypes: [String] = [], vstType: String? = nil) throws -> URL {
    let url = try f.plugin(name, ext: ext)
    var info: [String: Any] = ["CFBundleName": name, "CFBundleIdentifier": id, "CFBundleShortVersionString": version]
    if !auTypes.isEmpty {
        info["AudioComponents"] = auTypes.map { ["name": name, "type": $0] }
    }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: url.appendingPathComponent("Contents/Info.plist"))
    if let vstType {
        let file = url.appendingPathComponent("Contents/Resources/moduleinfo.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["Classes": [["Category": "Audio Module Class", "Name": name, "Sub Categories": [vstType]]]])
            .write(to: file)
    }
    return url
}

@Test func curatedAAXCatalogNeedsExactProductAndSupportedVersion() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try identified(f, name: "BF-76", ext: "aaxplugin", id: "com.AVID.plugin.BF-76", version: "25.12.1.133")
    let item = try #require(f.scan().first)
    #expect(item.categories == [.effect])
    #expect(item.classification?.basis == .catalog)
    #expect(item.classification?.components.isEmpty == true) // No invented bundle components.
    #expect(item.classification?.evidence?.first?.referenceURL?.hasPrefix("https://") == true)
    for (name, id, version) in [("Impostor", "com.AVID.plugin.BF-76", "25.12"),
                                ("BF-76", "com.someoneelse.BF-76", "25.12"),
                                ("BF-76", "com.AVID.plugin.BF-76", "99.0"),
                                ("BF-76", "com.AVID.plugin.BF-76", "25.bad"),
                                ("BF-76", "com.AVID.plugin.BF-76", "—")] {
        var plugin = item
        plugin.classification = nil
        let candidate = Plugin(path: plugin.path, name: name, format: .aax, vendor: "Avid", version: version,
            bundleID: id, root: f.root, addedAt: Date(), firstSeenAt: Date(), bytes: 1, restriction: nil)
        #expect(ClassificationResolver.enrich([candidate]).first?.categories == [.unknown])
    }
}

@Test func catalogSeparatesMIDIEffectsMetersAndSoundGenerators() throws {
    let f = try Fixture(); defer { f.cleanup() }
    for name in ["NoteStack", "PitchControl", "VelocityControl", "InTune", "MasterMeter", "SignalGenerator", "ClickII"] {
        _ = try identified(f, name: name, ext: "aaxplugin", id: "com.AVID.plugin." + name, version: "25.12.1.133 Release")
    }
    let items = f.scan()
    #expect(items.filter { $0.categories == [.effect] }.count == 3)
    #expect(items.filter { $0.categories == [.other] }.count == 3)
    #expect(items.first { $0.name == "ClickII" }?.categories == [.instrument])
}

@Test func exactIdentityInheritsAUAndVST3WithoutChangingFiles() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let au = try identified(f, name: "Original", ext: "component", id: "org.maker.original", auTypes: ["aumu"])
    let aax = try identified(f, name: "Original", ext: "aaxplugin", id: "org.maker.original")
    let before = try FileSafety.digest(aax)
    var items = f.scan()
    let inferred = try #require(items.first { $0.path == aax.path })
    #expect(inferred.categories == [.instrument])
    #expect(inferred.classification?.basis == .relatedFormat)
    #expect(inferred.classification?.evidence?.first?.pluginPath == au.path)
    #expect(inferred.classification?.components.isEmpty == true)
    #expect(try FileSafety.digest(aax) == before)
    try FileManager.default.removeItem(at: au)
    #expect(f.scan().first?.categories == [.unknown]) // No persisted inferred result.
    _ = try identified(f, name: "Original", ext: "vst3", id: "org.maker.original", vstType: "Instrument")
    items = f.scan()
    #expect(items.first { $0.path == aax.path }?.categories == [.instrument])
    #expect(items.first { $0.path == aax.path }?.classificationSource == "关联其他格式 · VST3")
}

@Test func explicitFormatAliasesLinkMelodyneAndCatalogWorksWithoutDonor() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let au = try identified(f, name: "Melodyne", ext: "component", id: "com.celemony.melodyne.au", version: "5.4.2", auTypes: ["aufx"])
    let aax = try identified(f, name: "Melodyne", ext: "aaxplugin", id: "com.celemony.melodyne.aax", version: "5.4.2")
    var item = try #require(f.scan().first { $0.path == aax.path })
    #expect(item.categories == [.effect])
    #expect(item.classification?.basis == .relatedFormat)
    try FileManager.default.removeItem(at: au)
    item = try #require(f.scan().first)
    #expect(item.categories == [.effect] && item.classification?.basis == .catalog)
}

@Test func associationRejectsNamesAloneSuffixGuessingAndMismatchedVersions() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try identified(f, name: "Piano", ext: "component", id: "org.maker.piano.au", auTypes: ["aumu"])
    _ = try identified(f, name: "Piano", ext: "aaxplugin", id: "org.maker.piano.aax")
    _ = try identified(f, name: "Piano", ext: "clap", id: "org.maker.piano.au", version: "2.0")
    _ = try identified(f, name: "Piano Lite", ext: "vst", id: "org.maker.piano.au")
    #expect(f.scan().filter { $0.format != .au }.allSatisfy { $0.categories == [.unknown] })
}

@Test func conflictingDonorsAndConflictingCatalogStayUnknown() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try identified(f, name: "Conflict", ext: "component", id: "org.maker.conflict", auTypes: ["aumu"])
    _ = try identified(f, name: "Conflict", ext: "vst3", id: "org.maker.conflict", vstType: "Fx")
    let aax = try identified(f, name: "Conflict", ext: "aaxplugin", id: "org.maker.conflict")
    let item = try #require(f.scan().first { $0.path == aax.path })
    #expect(item.categories == [.unknown])
    #expect(item.classificationSource.contains("冲突"))
    #expect(item.classification?.evidence?.count == 2)
    _ = try identified(f, name: "Melodyne", ext: "component", id: "com.celemony.melodyne.au", version: "5.4.2", auTypes: ["aumu"])
    let other = try identified(f, name: "Melodyne", ext: "aaxplugin", id: "com.celemony.melodyne.aax", version: "5.4.2")
    #expect(f.scan().first { $0.path == other.path }?.categories == [.unknown])
}

@Test func multiComponentOrHybridDeclarationCannotLabelAnotherFormat() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try identified(f, name: "Suite", ext: "component", id: "org.maker.suite", auTypes: ["aumu", "aufx"])
    _ = try identified(f, name: "Suite", ext: "aaxplugin", id: "org.maker.suite")
    _ = try identified(f, name: "Hybrid", ext: "vst3", id: "org.maker.hybrid", vstType: "Fx|Instrument")
    _ = try identified(f, name: "Hybrid", ext: "aaxplugin", id: "org.maker.hybrid")
    #expect(f.scan().filter { $0.format == .aax }.allSatisfy { $0.categories == [.unknown] })
}

@Test func directDeclarationsWinAndInferredResultsNeverBecomeDonors() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try identified(f, name: "TDR Nova", ext: "component", id: "com.TokyoDawnLabs.TDRNova", version: "2.2.2", auTypes: ["aumu"])
    let item = try #require(f.scan().first)
    #expect(item.categories == [.instrument] && item.classification?.basis == nil)
    var source = item
    source.classification = PluginClassification(components: [], source: "已核实资料", basis: .catalog, supplementalCategories: [.instrument])
    let target = Plugin(path: "/fixture/Other.aaxplugin", name: item.name, format: .aax, vendor: item.vendor, version: item.version,
        bundleID: item.bundleID, root: item.root, addedAt: item.addedAt, firstSeenAt: item.firstSeenAt, bytes: 0, restriction: nil)
    // It may use its own catalog entry, but never the fabricated donor's category.
    #expect(ClassificationResolver.enrich([source, target])[1].categories == [.effect])
}

@Test func manualClassificationSurvivesRescansAndDoesNotPropagate() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let au = try identified(f, name: "Original", ext: "component", id: "org.maker.original", auTypes: ["aumu"])
    let aax = try identified(f, name: "Original", ext: "aaxplugin", id: "org.maker.original")
    let items = f.scan()
    try await f.engine.setCategories([.effect], for: items.filter { $0.path == aax.path })
    var report = try await f.engine.scan(roots: [f.root], applications: [])
    let selected = try #require(report.plugins.first { $0.path == aax.path })
    #expect(selected.categories == [.effect] && selected.classification?.categories == [.instrument])
    try await f.engine.setCategories(nil, for: [selected])
    try await f.engine.setCategories([.effect], for: items.filter { $0.path == au.path })
    report = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(report.plugins.first { $0.path == aax.path }?.categories == [.instrument])
    // Manual source edits cannot supply a previously absent declaration.
    _ = try identified(f, name: "No Declaration", ext: "component", id: "org.maker.undeclared")
    let target = try identified(f, name: "No Declaration", ext: "aaxplugin", id: "org.maker.undeclared")
    try await f.engine.setCategories([.instrument], for: f.scan().filter { $0.name == "No Declaration" && $0.format == .au })
    report = try await f.engine.scan(roots: [f.root], applications: [])
    #expect(report.plugins.first { $0.path == target.path }?.categories == [.unknown])
}

@Test func classificationEvidenceRoundTripsAndOldDeclarationsDecode() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try identified(f, name: "BF-76", ext: "aaxplugin", id: "com.AVID.plugin.BF-76", version: "25.12.1.133")
    let item = try #require(f.scan().first)
    let restored = try JSONDecoder().decode(Plugin.self, from: JSONEncoder().encode(item))
    #expect(restored == item)
    let old = Data(#"{"components":[{"identifier":"x","name":"Piano","categories":["虚拟乐器"],"declaration":"aumu"}],"source":"插件声明 · AudioComponents"}"#.utf8)
    let declaration = try JSONDecoder().decode(PluginClassification.self, from: old)
    #expect(declaration.categories == [.instrument] && declaration.evidence == nil && declaration.basis == nil)
}
