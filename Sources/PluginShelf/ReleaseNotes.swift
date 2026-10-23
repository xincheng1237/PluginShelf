import SwiftUI
import PluginShelfCore

struct ReleaseNotesView: View {
    @Environment(\.locale) private var interfaceLocale
    @Environment(\.dismissWindow) private var dismissWindow
    private var english: Bool { L10n.isEnglish }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(english ? "Release Notes" : "更新日志")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(english ? "Done" : "完成") { dismissWindow(id: "release-notes") }
                    .keyboardShortcut(.defaultAction)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(ReleaseNotes.versions, id: \.version) { release in
                        VStack(alignment: .leading, spacing: 10) {
                            Text((english ? "Version " : "版本 ") + release.version)
                                .font(.headline)
                            ForEach(release.sections, id: \.kind) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.kind.title(english: english))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                        Label(english ? item.en : item.zh, systemImage: section.kind.symbol)
                                            .foregroundStyle(.primary, section.kind.tint)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        if release.version != ReleaseNotes.versions.last?.version { Divider() }
                    }
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)
                .textSelection(.enabled)
            }
        }
        .padding(28)
        .frame(width: 650, height: 600)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

enum ReleaseNotes {
    enum Kind: String {
        case initial, added, improved, fixed
        func title(english: Bool) -> String {
            switch self {
            case .initial: english ? "Features" : "主要功能"
            case .added: english ? "New Features" : "新增功能"
            case .improved: english ? "Improvements" : "优化改进"
            case .fixed: english ? "Fixes" : "问题修复"
            }
        }
        var symbol: String {
            switch self {
            case .initial, .added: "checkmark.circle.fill"
            case .improved: "wand.and.stars"
            case .fixed: "wrench.and.screwdriver.fill"
            }
        }
        var tint: Color {
            switch self {
            case .initial, .added: .green
            case .improved: .blue
            case .fixed: .orange
            }
        }
    }
    struct Item { let zh: String; let en: String }
    struct Section { let kind: Kind; let items: [Item] }
    struct Version { let version: String; let sections: [Section] }
    static let versions = [
        Version(version: "1.1", sections: [
            Section(kind: .added, items: [
                Item(zh: "新增对系统废纸篓的支持，可在应用内批量还原或永久删除插件。", en: "Added system Trash support, with batch restore and permanent deletion in the app."),
                Item(zh: "新增检查更新功能，支持启动时自动检查和手动检查。", en: "Added update checks, both automatically at launch and on demand."),
                Item(zh: "新增中英文界面与语言切换功能，默认跟随系统。", en: "Added Chinese and English interfaces with a language selector that follows the system by default."),
                Item(zh: "新增更新日志功能，可查看各版本的更新内容。", en: "Added release notes to view changes in each version.")
            ]),
            Section(kind: .improved, items: [
                Item(zh: "调整了废纸篓的清理方式，新删除的插件由系统设置控制自动清理。", en: "Changed Trash cleanup so newly deleted plug-ins follow the system’s automatic removal setting."),
                Item(zh: "优化了废纸篓记录与批量操作体验，兼容旧版废纸篓项目。", en: "Improved Trash records and batch actions while retaining support for items deleted in the previous version.")
            ])
        ]),
        Version(version: "1.0", sections: [
            Section(kind: .initial, items: [
                Item(zh: "支持音频插件扫描与管理，涵盖 AU、VST2、VST3、AAX 等常见格式。", en: "Supports audio plug-in scanning and management for AU, VST2, VST3, AAX and other common formats."),
                Item(zh: "支持搜索、时间筛选、排序和首字母快速定位。", en: "Supports search, date filters, sorting and alphabet navigation."),
                Item(zh: "支持批量备份与恢复，可将插件还原到原安装位置。", en: "Supports batch backup and restore to the original installation locations."),
                Item(zh: "支持批量删除与废纸篓还原，删除前需完成两步确认。", en: "Supports batch deletion and Trash restore, with two-step confirmation before deletion."),
                Item(zh: "支持插件分类，可自动识别部分插件用途并手动调整分类。", en: "Supports plug-in categories, with automatic detection for supported plug-ins and manual categorization.")
            ])
        ])
    ]
}
