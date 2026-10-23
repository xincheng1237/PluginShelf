import SwiftUI
import AppKit
import PluginShelfCore

struct DeleteSheet: View {
    let plugins: [Plugin]
    let days: Int
    let hosts: [String]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 1
    @State private var acknowledged = false
    @State private var confirmation = ""
    private var phrase: String { "删除 \(plugins.count) 项" }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "trash.circle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text(stage == 1 ? "核对将要移除的插件" : "最后确认这次删除").font(.title2.weight(.semibold))
                    Text("第 \(stage) 步，共 2 步 · \(plugins.count) 项 · \(byteString(plugins.reduce(0) { $0 + $1.bytes }))").foregroundStyle(.secondary).font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                if stage == 1 {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(plugins) { plugin in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(plugin.name).fontWeight(.medium); Spacer(); Text(plugin.format.rawValue).foregroundStyle(.secondary) }
                                    Text(plugin.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    if let components = plugin.classification?.components, components.count > 1 {
                                        Text("整个文件包将一起移除，包含 \(components.count) 个组件：")
                                            .font(.caption.weight(.medium)).foregroundStyle(.orange)
                                        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                                            Text(component.name + " · " + component.categories.map(\.rawValue).joined(separator: "、"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }.padding(12)
                                Divider()
                            }
                        }
                    }.frame(height: 210).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Text("按整个插件文件包移除；包内所有组件都会一起移除，未识别的组件也包括在内。预设、授权、外置音色库与宿主工程保留。依赖这些插件的工程可能无法正常播放。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Label("移到废纸篓后，原目录中的插件将不可用。", systemImage: "exclamationmark.triangle").font(.headline)
                    Text("将保留 \(days) 天，预计于 \(Date().addingTimeInterval(Double(days) * 86400).formatted(date: .long, time: .shortened)) 永久删除。到期清理无需再次确认；App 退出期间暂停，下次启动时继续。")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("请输入“\(phrase)”确认数量：").font(.callout)
                    TextField(phrase, text: $confirmation).textFieldStyle(.roundedBorder).accessibilityLabel("删除确认文字")
                    Toggle("我已核对清单，并理解到期后无法从废纸篓找回", isOn: $acknowledged).toggleStyle(.checkbox)
                }
            }.id(stage).transition(.opacity)
            if !hosts.isEmpty { Label("检测到正在运行：\(hosts.joined(separator: "、"))。请先保存工程并退出宿主。", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if stage == 1 {
                    Button("继续核对") { advance() }.buttonStyle(.borderedProminent)
                } else {
                    Button("返回清单") { stage = 1; acknowledged = false; confirmation = "" }
                    Button("移到废纸篓", role: .destructive) { onConfirm() }
                        .disabled(confirmation != phrase || !acknowledged)
                }
            }
        }.padding(28).frame(width: 590)
    }
    private func advance() {
        let keyboard = NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp
        // Occasional state indication only. Keyboard transitions stay immediate.
        if keyboard { stage = 2 }
        else { withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.12 : 0.2)) { stage = 2 } }
    }
}

struct RestoreSheet: View {
    let manifest: BackupManifest
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("从备份恢复插件", systemImage: "archivebox").font(.title2.weight(.semibold))
            Text("已验证 \(manifest.entries.count) 项插件 · 备份于 \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(manifest.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name + " · " + entry.format.rawValue).fontWeight(.medium)
                            Text(entry.originalRoot + "/" + entry.relativePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(height: 230).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Text("将恢复到以上原始位置。同名插件会跳过；恢复不会覆盖现有文件。若目录无写入权限，结果中会列出具体项目。恢复完成后请重新启动宿主扫描插件。")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction); Button("恢复到原位置", action: onConfirm).buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 570)
    }
}

struct MessageSheet: View {
    let message: String
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("PluginShelf", systemImage: "info.circle").font(.title2.weight(.semibold))
            ScrollView { Text(message).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 330)
            HStack { Spacer(); Button("好", action: onDismiss).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 550)
    }
}

struct CustomDaysSheet: View {
    @Binding var value: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    private var validDays: Int? {
        guard let days = Int(draft), (1...36500).contains(days) else { return nil }
        return days
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("自定义添加时间").font(.title2.weight(.semibold))
            HStack {
                Text("最近")
                TextField("天数", text: $draft).textFieldStyle(.roundedBorder).frame(width: 85).accessibilityLabel("最近天数")
                Text("天内添加的插件")
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用") {
                    if let days = validDays { value = days; dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(validDays == nil)
            }
        }.padding(26).frame(width: 370)
        .onAppear { draft = String(value > 0 ? value : 30) }
    }
}

struct ClassificationSheet: View {
    let plugins: [Plugin]
    let onSave: ([PluginCategory]?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var categories = Set<PluginCategory>()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置分类").font(.title2.weight(.semibold))
            Text(plugins.count == 1 ? plugins[0].name : "所选 \(plugins.count) 项插件")
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Text("可以选择多个分类。设置作用于整个插件文件包，不修改插件文件。").font(.callout)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PluginCategory.allCases.filter { $0 != .unknown }) { category in
                    Toggle(category.rawValue, isOn: Binding(get: { categories.contains(category) }, set: { enabled in
                        if enabled { categories.insert(category) } else { categories.remove(category) }
                    })).toggleStyle(.checkbox)
                }
            }
            Divider()
            HStack {
                Button("恢复自动识别") { onSave(nil) }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { onSave(PluginCategory.normalized(Array(categories))) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(categories.isEmpty)
            }
        }.padding(26).frame(width: 460)
        .onAppear {
            let values = plugins.map { Set($0.categories.filter { $0 != .unknown }) }
            categories = values.first.map { first in values.allSatisfy { $0 == first } ? first : [] } ?? []
        }
    }
}
