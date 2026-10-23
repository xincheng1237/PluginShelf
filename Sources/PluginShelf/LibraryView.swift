import SwiftUI
import PluginShelfCore
import AppKit

struct BackupPreview: Identifiable {
    let id = UUID()
    let url: URL
    let manifest: BackupManifest
}
struct DeletionSnapshot: Identifiable {
    let id = UUID()
    let plugins: [Plugin]
}

struct RecoveryDeletionSnapshot: Identifiable {
    let id = UUID()
    let records: [RecoveryRecord]
}

struct ClassificationSnapshot: Identifiable {
    let id = UUID()
    let plugins: [Plugin]
}

struct LibraryView: View {
    @Environment(\.locale) private var interfaceLocale
    @ObservedObject var model: AppModel
    @ObservedObject var updater: SoftwareUpdater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCustomDays = false
    @State private var tableScrollRequest: TableScrollRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarAnimation = SidebarAnimationController()
    @State private var sidebarIsVisible = true
    @State private var deletion: DeletionSnapshot?
    @State private var permanentDeletion: RecoveryDeletionSnapshot?
    @State private var forgetting = Set<UUID>()
    @State private var showForgetConfirmation = false
    @State private var backup: BackupPreview?
    @State private var classification: ClassificationSnapshot?
    private var isRecovery: Bool { model.route == "recovery" }
    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 170, ideal: 215, max: 260)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                GeometryReader { detailGeometry in
                    let compact = detailGeometry.size.width < 600 || detailGeometry.size.height < 560
                    VStack(spacing: 0) {
                        UpdateBanner(updater: updater)
                        if isRecovery { recoveryHeader; recoveryTable(width: detailGeometry.size.width) }
                        else { libraryHeader(compact: compact); filters(width: detailGeometry.size.width); pluginTable(width: detailGeometry.size.width) }
                        statusBar(width: detailGeometry.size.width)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(SidebarAnimationBridge(controller: sidebarAnimation, visible: sidebarIsVisible,
                    onToggle: { visible in setSidebarVisible(visible) }))
                .navigationTitle(model.title)
                .toolbar { toolbar }
                .searchable(text: $model.search, placement: .toolbar, prompt: isRecovery ? L("搜索已删除插件") : L("搜索名称、厂商、路径"))
                .inspector(isPresented: $model.showInspector) {
                    inspector.inspectorColumnWidth(min: 220, ideal: 250, max: 340)
                }
            }
            .toolbar(removing: .sidebarToggle)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(isPresented: $showCustomDays) { CustomDaysSheet(value: $model.days) }
        .sheet(item: $deletion) { snapshot in
            DeleteSheet(plugins: snapshot.plugins, hosts: model.hostNames) {
                deletion = nil
                Task { await model.delete(snapshot.plugins) }
            }
        }
        .sheet(item: $permanentDeletion) { snapshot in
            PermanentDeleteSheet(records: snapshot.records) {
                permanentDeletion = nil
                Task { await model.permanentlyDelete(Set(snapshot.records.map(\.id))) }
            }
        }
        .confirmationDialog(L("移除所选删除记录？"), isPresented: $showForgetConfirmation, titleVisibility: .visible) {
            Button(L("移除记录"), role: .destructive) { let ids = forgetting; Task { await model.forgetUnavailable(ids) } }
            Button(L("取消"), role: .cancel) {}
        } message: { Text(L("仅移除应用内的记录，不删除任何文件。之后将无法通过这些记录追踪或还原插件。")) }
        .sheet(item: $backup) { item in
            RestoreSheet(manifest: item.manifest) { backup = nil; Task { await model.restoreBackup(item.url) } }
        }
        .sheet(item: $classification) { item in
            ClassificationSheet(plugins: item.plugins) { categories in
                classification = nil
                Task { await model.setCategories(categories, for: item.plugins) }
            }
        }
        .sheet(isPresented: Binding(get: { model.detailMessage != nil }, set: { if !$0 { model.detailMessage = nil } })) {
            MessageSheet(message: model.detailMessage ?? "") { model.detailMessage = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseShelfBackup)) { _ in chooseBackup() }
        .onOpenURL { url in
            Task {
                if let (folder, manifest) = await model.inspectBackup(url) { backup = BackupPreview(url: folder, manifest: manifest) }
            }
        }
        .onChange(of: columnVisibility) { _, visibility in
            if !sidebarAnimation.isAnimating { sidebarIsVisible = visibility != .detailOnly }
        }
        .onChange(of: model.route) { _, _ in model.selection.removeAll(); model.recoverySelection.removeAll() }
        .onChange(of: model.search) { _, _ in model.selection.removeAll(); model.recoverySelection.removeAll() }
        .onChange(of: model.days) { _, value in model.days = max(0, min(value, 36500)); model.selection.removeAll() }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.route) {
                Section(L("资料库")) {
                    Label { HStack { Text(L("所有插件")); Spacer(); Text("\(model.plugins.count)").foregroundStyle(.secondary).monospacedDigit() } } icon: { Image(systemName: "square.stack.3d.up") }.tag("all")
                    Label(L("最近添加"), systemImage: "clock").tag("recent")
                }
                Section(L("插件分类")) {
                    ForEach(PluginCategory.allCases) { category in
                        Label {
                            HStack {
                                Text(category.displayName); Spacer()
                                Text("\(model.plugins.filter { $0.categories.contains(category) }.count)")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: { Image(systemName: category.symbol) }.tag(category.route)
                    }
                }
                Section(L("插件格式")) {
                    ForEach(PluginFormat.allCases) { format in
                        Label { HStack { Text(format.rawValue); Spacer(); Text("\(model.plugins.filter { $0.format == format }.count)").foregroundStyle(.secondary).monospacedDigit() } } icon: { Image(systemName: "puzzlepiece.extension") }.tag(format.rawValue)
                    }
                }
                Section(L("安全管理")) {
                    Label { HStack { Text(L("废纸篓")); Spacer(); Text("\(model.recovery.count)").foregroundStyle(.secondary).monospacedDigit() } } icon: { Image(systemName: "trash") }.tag("recovery")
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Label(model.isDemo ? L("演示样本") : L("本机插件资料库"), systemImage: model.isDemo ? "testtube.2" : "internaldrive").font(.callout.weight(.medium))
                Text(model.isDemo ? L("样本不含可执行插件") : L("\(model.plugins.count) 项 · \(byteString(model.totalBytes))")).font(.caption).foregroundStyle(.secondary)
                SettingsLink { Label(L("设置"), systemImage: "gearshape") }.buttonStyle(.plain).font(.callout).padding(.top, 3)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
    }
    private func libraryHeader(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: compact ? 12 : 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.1)).frame(width: compact ? 36 : 56, height: compact ? 36 : 56)
                Image(systemName: model.route == "recent" ? "clock.badge.checkmark" : "square.stack.3d.up").font(.system(size: compact ? 19 : 25, weight: .light)).foregroundStyle(Color.accentColor)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.title).font(.system(size: compact ? 20 : 27, weight: .semibold)).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(model.filtered.count)").font(.system(size: compact ? 22 : 28, weight: .medium, design: .rounded)).monospacedDigit()
                Text(L("\(byteString(model.filtered.reduce(0) { $0 + $1.bytes })) · 插件文件")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 20).padding(.vertical, compact ? 12 : 23)
    }
    private func filters(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(LibrarySort.allCases) { order in
                    Button { model.sortOrder = order.comparators } label: {
                        if model.currentSort == order { Label(order.displayName, systemImage: "checkmark") }
                        else { Text(order.displayName) }
                    }
                }
            } label: {
                if width < 500 { Image(systemName: "arrow.up.arrow.down") }
                else { Text(model.currentSort?.displayName ?? L("自定义")) }
            }
            .fixedSize().accessibilityLabel(L("排序方式")).help(L("更改名称、添加时间或大小的排序方式"))
            Menu {
                Button(L("全部时间")) {
                    if model.route == "recent" { model.route = "all" }
                    model.days = 0
                }
                ForEach([7, 30, 90], id: \.self) { days in Button(L("近 \(days) 天")) { model.days = days } }
                Divider()
                Button(L("自定义…")) { showCustomDays = true }
            } label: {
                Text(model.days == 0 ? (model.route == "recent" ? L("近 30 天") : L("全部时间")) : L("近 \(model.days) 天"))
            }.fixedSize().accessibilityLabel(L("添加时间筛选")).help(L("按添加时间筛选，可选择常用范围或自定义天数"))
            Spacer(minLength: 8)
            if model.days != 0 || !model.search.isEmpty {
                Button { model.days = 0; model.search = "" } label: {
                    if width < 500 { Image(systemName: "xmark.circle") }
                    else { Text(L("清除筛选")) }
                }.buttonStyle(.plain).foregroundStyle(Color.accentColor).help(L("清除筛选"))
            }
        }.controlSize(.regular).padding(.horizontal, 25).padding(.bottom, 16)
    }
    private func pluginColumns(width: CGFloat) -> TableColumnCustomization<Plugin> {
        var columns = TableColumnCustomization<Plugin>()
        columns[visibility: "size"] = width >= 420 ? .visible : .hidden
        columns[visibility: "category"] = width >= 600 ? .visible : .hidden
        columns[visibility: "version"] = width >= 720 ? .visible : .hidden
        columns[visibility: "added"] = width >= 600 ? .visible : .hidden
        return columns
    }
    private func nameColumnMaximum(width: CGFloat) -> CGFloat {
        var otherColumns: CGFloat = 55 + 16 // Format and its cell spacing.
        if width >= 420 { otherColumns += 65 + 16 }
        if width >= 600 { otherColumns += 70 + 16 + 95 + 16 }
        if width >= 720 { otherColumns += 50 + 16 }
        return max(140, width - 29 - 16 - otherColumns)
    }
    private func pluginTable(width: CGFloat) -> some View {
        HStack(spacing: 0) {
        Table(model.filtered, selection: $model.selection, sortOrder: $model.sortOrder, columnCustomization: .constant(pluginColumns(width: width))) {
            TableColumn(L("插件名称"), value: \.alphabeticalName) { plugin in
                HStack(spacing: 10) {
                    Image(systemName: plugin.canManage ? "waveform" : "lock.shield").foregroundStyle(model.selection.contains(plugin.id) ? Color.primary : plugin.canManage ? Color.accentColor : .secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plugin.name).fontWeight(.medium).lineLimit(1)
                        Text(L10n.text(plugin.vendor)).font(.caption).foregroundStyle(model.selection.contains(plugin.id) ? .primary : .secondary).lineLimit(1)
                    }.padding(.vertical, 7)
                }.help(plugin.path)
            }.width(min: 140, ideal: 240, max: nameColumnMaximum(width: width))
            TableColumn(L("格式"), value: \.format.rawValue) { plugin in
                Text(plugin.format.rawValue).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(model.selection.contains(plugin.id) ? .primary : .secondary).padding(.horizontal, 7).padding(.vertical, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }.width(55)
            TableColumn(L("分类")) { plugin in
                Text(plugin.categoryText).font(.callout).lineLimit(1)
                    .foregroundStyle(model.selection.contains(plugin.id) ? .primary : .secondary)
                    .help(plugin.categoryText + " · " + plugin.classificationSource)
            }.width(min: 70, ideal: 100, max: 140).customizationID("category")
            TableColumn(L("版本"), value: \.version).width(min: 50, ideal: 65).customizationID("version")
            TableColumn(L("大小"), value: \.bytes) { plugin in Text(byteString(plugin.bytes)).foregroundStyle(model.selection.contains(plugin.id) ? .primary : .secondary).monospacedDigit() }.width(min: 65, ideal: 80).customizationID("size")
            TableColumn(L("添加时间"), value: \.addedAt) { plugin in Text(plugin.addedAt, format: .dateTime.year().month().day()).foregroundStyle(model.selection.contains(plugin.id) ? .primary : .secondary) }.width(min: 95, ideal: 110).customizationID("added")
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .background(TablePositionBridge(request: tableScrollRequest))
        .contextMenu(forSelectionType: String.self) { ids in
            Button(L("设置分类…")) {
                classification = ClassificationSnapshot(plugins: model.plugins.filter { ids.contains($0.id) })
            }.disabled(ids.isEmpty || model.busy)
            Divider()
            Button(L("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting(model.plugins.filter { ids.contains($0.id) }.map(\.url)) }.disabled(ids.isEmpty)
            Button(L("选择当前检索结果")) { model.selection = Set(model.filtered.map(\.id)) }
        }
        .overlay {
            if model.filtered.isEmpty && !model.busy {
                ContentUnavailableView(model.plugins.isEmpty ? L("未找到插件") : L("没有匹配的插件"), systemImage: model.plugins.isEmpty ? "puzzlepiece.extension" : "magnifyingglass", description: Text(model.plugins.isEmpty ? L("扫描标准目录，或在设置中添加自定义插件目录。") : L("试试其他名称或时间范围。")))
            }
        }
        Divider()
            alphabetIndex
        }
    }
    private var alphabetIndex: some View {
        let available = Set(model.filtered.map(\.initial))
        return VStack(spacing: 0) {
            ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"], id: \.self) { letter in
                Button {
                    model.sortOrder = LibrarySort.nameAscending.comparators
                    if let row = model.filtered.firstIndex(where: { $0.initial == letter }) {
                        let keyboard = NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp
                        tableScrollRequest = TableScrollRequest(row: row, animated: !reduceMotion && !keyboard)
                    }
                } label: {
                    Text(letter).font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(AlphabetIndexButtonStyle()).foregroundStyle(available.contains(letter) ? Color.accentColor : Color.secondary.opacity(0.35))
                .disabled(!available.contains(letter)).help(L("定位到 \(letter)"))
                .accessibilityLabel(L("定位到首字母 \(letter)"))
            }
        }.padding(.vertical, 5).frame(width: 28)
            .accessibilityElement(children: .contain).accessibilityLabel(L("首字母快速定位"))
    }
    private var recoveryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("废纸篓"), systemImage: "trash").font(.title2.weight(.semibold))
            Text(L("删除的插件会进入系统废纸篓，由系统设置控制一段时间之后彻底删除。清空废纸篓会提前彻底删除。"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("打开系统废纸篓"), action: model.openSystemTrash)
                if model.recovery.contains(where: { $0.systemTrash == nil }) {
                    Text(L("旧版项目仍可还原或手动永久删除，不再自动清理。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(25)
    }
    private var recoveryItems: [RecoveryRecord] {
        model.filteredRecovery
    }
    private func recoveryColumns(width: CGFloat) -> TableColumnCustomization<RecoveryRecord> {
        var columns = TableColumnCustomization<RecoveryRecord>()
        columns[visibility: "deleted"] = width >= 500 ? .visible : .hidden
        columns[visibility: "location"] = width >= 650 ? .visible : .hidden
        return columns
    }
    private func recoveryTable(width: CGFloat) -> some View {
        Table(recoveryItems, selection: $model.recoverySelection, columnCustomization: .constant(recoveryColumns(width: width))) {
            TableColumn(L("插件")) { record in VStack(alignment: .leading, spacing: 3) { Text(record.entry.name).fontWeight(.medium); Text(record.entry.format.rawValue).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 7) }.width(min: 150, ideal: 220)
            TableColumn(L("删除日期")) { record in Text(record.deletedAt, format: .dateTime.year().month().day()).foregroundStyle(.secondary) }.width(min: 90, ideal: 110).customizationID("deleted")
            TableColumn(L("位置")) { record in Text(record.locationText).foregroundStyle(.secondary) }.width(min: 100, ideal: 120).customizationID("location")
            TableColumn(L("状态")) { record in Text(record.statusText).font(.caption).foregroundStyle(.secondary) }.width(min: 80, ideal: 180)
        }.frame(minHeight: 0, maxHeight: .infinity).overlay {
            if recoveryItems.isEmpty { ContentUnavailableView(L("废纸篓是空的"), systemImage: "arrow.counterclockwise.circle", description: Text(L("删除的插件会显示在这里；仍在废纸篓中的项目可以还原。"))) }
        }
    }
    private func statusBar(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.mini); Text(L10n.rendered(model.activity)) }
                else if !model.notice.isEmpty {
                    Image(systemName: "info.circle").foregroundStyle(Color.accentColor)
                    Text(L10n.rendered(model.notice)).lineLimit(1)
                    Button { model.notice = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L("关闭提示"))
                } else { Text(isRecovery ? L("已选 \(model.selectedRecovery.count) 项 · \(model.recovery.count) 条记录") : L("已选 \(model.selected.count) 项 · \(byteString(model.selectedBytes))")).monospacedDigit() }
                Spacer()
                if !model.scanWarnings.isEmpty { Button(L("\(model.scanWarnings.count) 条扫描提示")) { model.detailMessage = model.scanWarnings.joined(separator: "\n\n") }.buttonStyle(.plain).foregroundStyle(.orange) }
                if width >= 500, let date = model.lastScan { Text(L("扫描于 \(date.formatted(.dateTime.locale(L10n.locale).hour().minute()))")) }
                if isRecovery {
                    Button(L("选择可还原项")) { model.recoverySelection = Set(recoveryItems.filter(\.canRecover).map(\.id)) }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(model.busy)
                }
                if !isRecovery { Button(L("选择结果")) { model.selection = Set(model.filtered.map(\.id)) }.buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(model.busy || model.filtered.isEmpty) }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 36)
        }.background(.bar)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { Task { await model.scan() } } label: { Label(L("扫描"), systemImage: "arrow.clockwise") }
                .help(L("重新扫描 ⌘R")).disabled(model.busy)
        }
        if isRecovery {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.restoreDeleted() } } label: { Label(L("还原所选"), systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canOperateRecovery)
                Button(role: .destructive) { permanentDeletion = RecoveryDeletionSnapshot(records: model.selectedRecovery) }
                    label: { Label(L("永久删除"), systemImage: "trash.slash") }
                    .help(L("永久删除所选插件")).disabled(!model.canOperateRecovery)
                if !model.selectedRecovery.isEmpty && model.selectedRecovery.allSatisfy({ $0.systemTrash != nil && !$0.canRecover }) {
                    Button(L("移除记录")) { forgetting = Set(model.selectedRecovery.map(\.id)); showForgetConfirmation = true }
                        .disabled(model.busy)
                }
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.exportSelection() } label: { Label(L("备份所选"), systemImage: "archivebox") }
                    .help(L("备份所选插件")).disabled(model.manageable.isEmpty || model.busy || model.manageable.count != model.selected.count)
                Button { chooseBackup() } label: { Label(L("从备份恢复"), systemImage: "square.and.arrow.down") }
                    .disabled(model.busy)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { deletion = DeletionSnapshot(plugins: model.manageable) } label: { Label(L("移到废纸篓"), systemImage: "trash") }
                    .help(L("将所选插件移到废纸篓")).disabled(model.manageable.isEmpty || model.busy || model.manageable.count != model.selected.count)
            }
        }
        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $model.showInspector) { Label(L("详细信息"), systemImage: "sidebar.right") }
                .toggleStyle(.button)
                .help(model.showInspector ? L("隐藏详细信息") : L("显示详细信息"))
                .accessibilityLabel(L("详细信息"))
                .accessibilityValue(model.showInspector ? L("已展开") : L("已收起"))
        }
    }
    private func setSidebarVisible(_ visible: Bool) {
        let keyboard = NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp
        sidebarIsVisible = visible
        if sidebarAnimation.setVisible(visible, animated: !reduceMotion && !keyboard, onSettled: { actual in
            sidebarIsVisible = actual
            // AppKit has already laid out the split view. Reassigning SwiftUI's
            // visibility here rebuilds the toolbar at the end of the animation.
        }) { return }
        columnVisibility = visible ? .all : .detailOnly
    }
    @ViewBuilder private var inspector: some View {
        if isRecovery, let record = model.selectedRecovery.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "arrow.uturn.backward.circle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Color.accentColor)
                    Text(record.entry.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Divider()
                    detail(L("原始目录"), record.entry.originalRoot + "/" + record.entry.relativePath)
                    detail(L("移入时间"), record.deletedAt.appFormatted())
                    detail(L("位置"), record.locationText)
                    detail(L("状态"), record.statusText)
                    Text(record.canRecover ? L("可还原到原位置；同名文件不会覆盖。系统废纸篓清空后无法还原。") : L("文件可能已被清理、移出废纸篓，或所在磁盘未连接。请先在 Finder 中检查。")).font(.caption).foregroundStyle(.secondary)
                    Button(L("还原所选插件")) { Task { await model.restoreDeleted() } }.disabled(!model.canOperateRecovery)
                    Button(L("永久删除所选插件"), role: .destructive) {
                        permanentDeletion = RecoveryDeletionSnapshot(records: model.selectedRecovery)
                    }.disabled(!model.canOperateRecovery)
                }.padding(22)
            }
        } else if !isRecovery, model.selected.count == 1, let plugin = model.selected.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack { RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.09)).frame(width: 72, height: 72); Image(systemName: "waveform").font(.system(size: 32, weight: .light)).foregroundStyle(Color.accentColor) }
                    Text(plugin.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Text(L10n.text(plugin.vendor)).foregroundStyle(.secondary).font(.callout)
                    Divider()
                    detail(L("分类"), plugin.categoryText)
                    detail(L("识别依据"), plugin.classificationSource)
                    if let evidence = plugin.classification?.evidence {
                        ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 6) {
                                if item.title == plugin.classificationSource {
                                    Text(L10n.rendered(item.detail)).font(.callout).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else { detail(L10n.rendered(item.title), L10n.rendered(item.detail)) }
                                if let path = item.pluginPath {
                                    Text(path).font(.caption).foregroundStyle(.secondary)
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                                if let reference = item.referenceURL, let url = URL(string: reference), url.scheme == "https" {
                                    Link(L("查看官方资料"), destination: url).font(.callout)
                                }
                            }
                        }
                    }
                    if plugin.categoryOverride != nil {
                        detail(L("自动识别"), (plugin.classification?.categories ?? [.unknown]).map(\.displayName).joined(separator: L10n.listSeparator))
                    }
                    Button(L("设置分类…")) { classification = ClassificationSnapshot(plugins: [plugin]) }.disabled(model.busy)
                    if let declared = plugin.classification, !declared.components.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("文件包内的组件（\(declared.components.count)）")).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(declared.components.enumerated()), id: \.offset) { _, component in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(component.name).font(.callout).textSelection(.enabled)
                                    Text(component.categories.map(\.displayName).joined(separator: L10n.listSeparator) + (component.declaration.isEmpty ? "" : " · " + L10n.rendered(component.declaration)))
                                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    Divider()
                    detail(L("插件格式"), plugin.format.rawValue)
                    detail(L("版本"), plugin.version)
                    detail(L("文件大小"), byteString(plugin.bytes))
                    detail(L("添加时间（文件系统）"), plugin.addedAt.formatted(.dateTime.locale(L10n.locale).year().month().day().hour().minute()))
                    detail(L("首次发现"), plugin.firstSeenAt.formatted(.dateTime.locale(L10n.locale).year().month().day()))
                    detail(L("安装位置"), plugin.path)
                    if !plugin.bundleID.isEmpty { detail(L("标识符"), plugin.bundleID) }
                    if let restriction = plugin.restriction { Label(L10n.rendered(restriction), systemImage: "lock.shield").font(.caption).foregroundStyle(.orange) }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([plugin.url]) } label: { Label(L("在 Finder 中显示"), systemImage: "folder") }
                    Divider()
                    Text(L("文件时间可能被安装器或迁移工具保留，仅用于辅助检索。插件文件不包含独立音色库与许可证。")).font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }
        } else {
            VStack(spacing: 15) {
                Image(systemName: !isRecovery && model.selected.count > 1 ? "square.stack.3d.up" : "slider.horizontal.3").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.tertiary)
                Text(!isRecovery && model.selected.count > 1 ? L("已选 \(model.selected.count) 项") : L("插件详细信息")).font(.headline)
                Text(!isRecovery && model.selected.count > 1 ? L("\(byteString(model.selectedBytes))\n使用工具栏批量备份或移到废纸篓。") : L("选择一项查看格式、版本和安装位置。\n按住 ⌘ 或 Shift 可多选。")).multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                if !isRecovery && model.selected.count > 1 { Text(L("\(model.manageable.count) 项可管理")).font(.caption).foregroundStyle(.secondary) }
                if !isRecovery && model.selected.count > 1 {
                    Button(L("设置分类…")) { classification = ClassificationSnapshot(plugins: model.selected) }.disabled(model.busy)
                }
            }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
    private func chooseBackup() { Task { if let (url, manifest) = await model.chooseBackup() { backup = BackupPreview(url: url, manifest: manifest) } } }
}
