import SwiftUI

struct StorageView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingCleanup: StorageRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.storageError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let notice = model.storageNotice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if model.storageRecords.isEmpty && model.isScanningStorage {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在计算本机 Codex 占用…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if model.storageRecords.isEmpty, let error = model.storageError {
                    ContentUnavailableView {
                        Label("存储信息读取失败", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新扫描") { Task { await model.scanStorage() } }
                    }
                } else if model.storageRecords.isEmpty {
                    ContentUnavailableView(
                        "Codex Home 暂无可统计内容",
                        systemImage: "internaldrive",
                        description: Text("没有发现可计入占用的文件；这不代表读取失败。")
                    )
                } else {
                    summary
                    permissionGuide
                    VStack(spacing: 0) {
                        ForEach(model.storageRecords) { record in
                            StorageRow(record: record) {
                                pendingCleanup = record
                            }
                            if record.id != model.storageRecords.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
        .navigationTitle("Codex 存储")
        .background(WorkbenchTheme.canvas)
        .task { await model.scanStorage() }
        .toolbar {
            Button { Task { await model.scanStorage() } } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanningStorage || model.isClearingStorage)
        }
        .confirmationDialog(cleanupTitle, isPresented: cleanupPresented, presenting: pendingCleanup) { record in
            Button(cleanupButtonTitle(record), role: .destructive) {
                Task {
                    await model.clearStorage(record)
                    pendingCleanup = nil
                }
            }
            Button("先在 Finder 中查看") {
                model.revealInFinder(path: record.path)
                pendingCleanup = nil
            }
            Button("取消", role: .cancel) { pendingCleanup = nil }
        } message: { record in
            Text(cleanupMessage(record))
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("本机 Codex Home").font(.largeTitle.bold())
                Text("只读取文件元数据计算占用，不读取文件内容，也不需要完全磁盘访问。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isScanningStorage || model.isClearingStorage { ProgressView() }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            MetricCard(title: "总占用", value: byteText(totalBytes), subtitle: "\(model.storageRecords.count) 类数据", symbol: "internaldrive", tint: .blue)
            MetricCard(title: "安全可释放", value: byteText(safeReclaimableBytes), subtitle: "缓存、过期临时与日志", symbol: "sparkles", tint: .green)
            MetricCard(title: "谨慎可释放", value: byteText(cautiousReclaimableBytes), subtitle: "归档会话，进入废纸篓", symbol: "exclamationmark.shield", tint: .orange)
        }
    }

    private var permissionGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("清理权限").font(.title3.bold())
            permissionRow(.safe, "缓存可重新生成；临时文件超过 24 小时、日志超过 7 天后才允许清理。")
            permissionRow(.cautious, "归档会话需要单独确认，并移到 macOS 废纸篓，不直接永久删除。")
            permissionRow(.protected, "当前会话、Memory、Skills、插件、软件包、数据库和未知数据只能查看。")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func permissionRow(_ level: StorageCleanupLevel, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: level.symbol).foregroundStyle(level.color).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var cleanupPresented: Binding<Bool> {
        Binding(get: { pendingCleanup != nil }, set: { if !$0 { pendingCleanup = nil } })
    }
    private var cleanupTitle: String {
        guard let pendingCleanup else { return "确认清理？" }
        return pendingCleanup.kind == .archivedSessions ? "将归档会话移到废纸篓？" : "清理\(pendingCleanup.kind.title)？"
    }
    private func cleanupButtonTitle(_ record: StorageRecord) -> String {
        let size = byteText(record.reclaimableSizeBytes)
        return record.kind == .cache ? "清理 \(size)" : "移到废纸篓 \(size)"
    }
    private func cleanupMessage(_ record: StorageRecord) -> String {
        let common = "Workbench 会先断开自己的 Codex 连接，并再次核对文件元数据；扫描后有变化就会取消操作。"
        switch record.kind {
        case .cache:
            return "仅永久删除 cache 目录中可重新生成的缓存。\(common)"
        case .temporary:
            return "只把超过 24 小时的临时文件移到 macOS 废纸篓，较新的临时文件保持不动。\(common)"
        case .logs:
            return "只把超过 7 天的诊断日志移到 macOS 废纸篓，近期日志保持不动。\(common)"
        case .archivedSessions:
            return "这会移除全部已归档 Codex 会话，任务历史将不再显示。文件会进入 macOS 废纸篓，在清空废纸篓前可以恢复。建议先在 Finder 中确认。\(common)"
        default:
            return "这类数据受到保护，不能由 Workbench 清理。"
        }
    }
    private var totalBytes: Int64 { model.storageRecords.reduce(0) { $0 + $1.sizeBytes } }
    private var safeReclaimableBytes: Int64 {
        model.storageRecords.filter { $0.kind.cleanupLevel == .safe }.reduce(0) { $0 + $1.reclaimableSizeBytes }
    }
    private var cautiousReclaimableBytes: Int64 {
        model.storageRecords.filter { $0.kind.cleanupLevel == .cautious }.reduce(0) { $0 + $1.reclaimableSizeBytes }
    }
}

private struct StorageRow: View {
    @Environment(AppModel.self) private var model
    let record: StorageRecord
    let clean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.kind.title).font(.headline)
                    Text(record.kind.cleanupLevel.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(record.kind.cleanupLevel.color)
                    if record.kind != .other {
                        Text(URL(fileURLWithPath: record.path).lastPathComponent)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Text(record.kind.cleanupImpact).font(.caption).foregroundStyle(.secondary)
                Text("\(record.itemCount.formatted()) 个文件")
                    .font(.caption2).foregroundStyle(.tertiary)
                if record.kind.cleanable {
                    Text(
                        record.hasReclaimableContent
                            ? "可释放 \(byteText(record.reclaimableSizeBytes)) · \(record.reclaimableItemCount.formatted()) 个文件 · \(record.kind.reclaimableDescription)"
                            : "目前没有符合“\(record.kind.reclaimableDescription)”规则的文件"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(record.hasReclaimableContent ? record.kind.cleanupLevel.color : Color.secondary.opacity(0.65))
                }
            }
            Spacer()
            Text(byteText(record.sizeBytes))
                .font(.headline.monospacedDigit())
                .frame(width: 104, alignment: .trailing)
            Group {
                if record.kind != .other {
                    Button { model.revealInFinder(path: record.path) } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("在 Finder 中显示 \(record.kind.title)")
                } else {
                    Color.clear
                        .frame(width: 20, height: 20)
                }
            }
            .frame(width: 34)
            Group {
                if record.kind.cleanable {
                    if record.hasReclaimableContent {
                        Button(record.kind == .archivedSessions ? "移到废纸篓" : "清理", role: .destructive, action: clean)
                            .disabled(model.isClearingStorage)
                    } else {
                        Text("无需清理")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("受保护，不可清理")
                }
            }
            .frame(width: 112, alignment: .center)
        }
        .padding(.vertical, 12)
    }

    private var color: Color { record.kind.cleanupLevel.color }
}

private extension StorageCleanupLevel {
    var color: Color {
        switch self {
        case .safe: .green
        case .cautious: .orange
        case .protected: .blue
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.shield"
        case .cautious: "exclamationmark.shield"
        case .protected: "lock.shield"
        }
    }
}

private func byteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
