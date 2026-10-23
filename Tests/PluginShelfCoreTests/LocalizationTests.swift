import Foundation
import Testing
@testable import PluginShelfCore

@Test func systemLanguageRulesCoverSimplifiedTraditionalAndOtherLanguages() {
    for language in ["zh", "zh-Hans-CN", "zh-Hant", "zh-Hant-TW", "zh-HK"] {
        #expect(AppLanguage.system.resolved(preferredLanguages: [language]) == "zh-Hans")
    }
    for languages in [["en-US"], ["ja-JP", "zh-Hans"], ["fr"], [String]()] {
        #expect(AppLanguage.system.resolved(preferredLanguages: languages) == "en")
    }
    #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-Hant"]) == "en")
    #expect(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en"]) == "zh-Hans")
}
@Test func translationResourceContainsEveryRequiredUIKeyAndValidPlaceholders() throws {
    #expect(L10n.english.count >= 320)
    let regex = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
    func slots(_ value: String) -> [String] {
        regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted()
    }
    for (zh, en) in L10n.english {
        #expect(!en.isEmpty)
        #expect(slots(zh) == slots(en), "Translation placeholders: \(zh)")
    }
}
@Test func dynamicTranslationsKeepUserNamesAndLiteralBracesIntact() {
    L10n.$overrideLanguage.withValue(.english) {
        #expect(L("删除 \(3) 项") == "Delete 3 items")
        #expect(L("删除 \(1) 项") == "Delete 1 item")
        #expect(L("已选 \(1) 项 · \(2) 条记录") == "1 selected · 2 records")
        #expect(L("请输入“\("Delete {0} items")”确认数量：") == "Type “Delete {0} items” to confirm the count:")
        #expect(L("\("我的声音/Voice.vst3") 在备份期间发生变化，备份已取消。") == "我的声音/Voice.vst3 changed during backup. The backup was canceled.")
        #expect(PluginCategory.instrument.displayName == "Virtual Instruments")
    }
    L10n.$overrideLanguage.withValue(.simplifiedChinese) {
        #expect(L("删除 \(3) 项") == "删除 3 项")
    }
}
@Test func switchingLanguageKeepsPersistedCategoryIdentitiesCompatible() throws {
    let before = try JSONEncoder().encode([PluginCategory.effect, .instrument])
    try L10n.$overrideLanguage.withValue(.english) {
        #expect(PluginCategory.effect.rawValue == "效果器")
        #expect(PluginCategory.effect.route == "category:效果器")
        let encoded = try JSONEncoder().encode([PluginCategory.effect, .instrument])
        let decoded = try JSONDecoder().decode([PluginCategory].self, from: before)
        #expect(encoded == before)
        #expect(decoded == [.effect, .instrument])
    }
}
@Test func cachedClassificationMetadataCanBeDisplayedInEitherLanguage() {
    L10n.$overrideLanguage.withValue(.english) {
        #expect(L10n.rendered("插件声明 · AudioComponents") == "Plug-in declaration · AudioComponents")
        #expect(L10n.rendered("已核实资料 · BF-76") == "Verified reference · BF-76")
        #expect(L10n.rendered("已更新 4 项插件的分类") == "Updated categories for 4 plug-ins")
        #expect(L10n.rendered("/音频/我的插件.vst3") == "/音频/我的插件.vst3")
    }
    L10n.$overrideLanguage.withValue(.simplifiedChinese) {
        #expect(L10n.rendered("Updated categories for 4 plug-ins") == "已更新 4 项插件的分类")
        #expect(L10n.rendered("Verified reference · BF-76") == "已核实资料 · BF-76")
    }
}
