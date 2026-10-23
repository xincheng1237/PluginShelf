import SwiftUI
import PluginShelfCore
import AppKit

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section {
                Text("新删除的插件会进入系统废纸篓，不安装后台清理程序。")
                Text("如需自动清理，请在 Finder → 设置 → 高级中勾选“30 天后移除废纸篓中的项目”。此设置影响整个系统废纸篓；手动清空会提前永久删除。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("打开系统废纸篓", action: model.openSystemTrash)
            } header: { Label("废纸篓", systemImage: "arrow.counterclockwise") }
            Section {
                Toggle("自动刷新插件资料库", isOn: $model.autoRefresh)
                Text("启动时自动扫描；启用后每 5 分钟重新扫描。不会加载或运行插件代码。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.customRoots) { root in
                    HStack {
                        Text(root.path).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button { model.removeRoot(root) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("移除扫描目录，不删除插件")
                    }
                }
                Button("添加自定义插件目录…", action: model.addRoot)
                Text("自动扫描用户及共享资源库的 AU、VST2、VST3、AAX、CLAP、LV2、RTAS 目录，并查看应用内 AUv3。非标准目录可手动添加。宿主内置效果、部分脚本格式与云端插件不在首版管理范围。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("扫描", systemImage: "magnifyingglass") }
            Section {
                Text("备份以命名文件夹导出，并附 SHA-256 校验清单。移动到网盘前请等待导出完成。恢复前先完整下载到本机；若自行压缩，请先解压。")
                Text("备份仅包含选中的插件文件，不包含授权、外置音色库、独立预设或安装器依赖。跨电脑恢复可能仍需厂商安装器与重新授权。")
            } header: { Label("备份边界", systemImage: "archivebox") }.font(.caption).foregroundStyle(.secondary)
            Section {
                LabeledContent("版本", value: "1.1")
                Text("本版本不申请管理员权限。受保护目录中的项目可查看；写入、移动受系统权限约束，失败时保留源文件并显示结果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 570, height: 665)
    }
}
