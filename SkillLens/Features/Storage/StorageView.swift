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
                if model.storageRecords.isEmpty && model.isScanningStorage {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在计算本机 Codex 占用…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if model.storageRecords.isEmpty {
                    ContentUnavailableView("无法读取存储信息", systemImage: "internaldrive")
                } else {
                    summary
                    VStack(spacing: 0) {
                        ForEach(model.storageRecords) { record in
                            StorageRow(record: record) {
                                pendingCleanup = record
                            }
                            if record.id != model.storageRecords.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
        .navigationTitle("Codex 存储")
        .task { await model.scanStorage() }
        .toolbar {
            Button { Task { await model.scanStorage() } } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanningStorage || model.isClearingStorage)
        }
        .confirmationDialog("清理 Codex 缓存？", isPresented: cleanupPresented, presenting: pendingCleanup) { record in
            Button("清理 \(byteText(record.sizeBytes))", role: .destructive) {
                Task {
                    await model.clearStorage(record)
                    pendingCleanup = nil
                }
            }
            Button("取消", role: .cancel) { pendingCleanup = nil }
        } message: { record in
            Text("仅删除 \(record.path) 中可重新生成的缓存。本应用会先断开 Codex，若内容在扫描后变化则取消清理。会话、配置、凭据、Skills、插件和数据库不会被删除。")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("本机 Codex Home").font(.largeTitle.bold())
                Text("只读取文件元数据计算占用，不读取文件内容。未知数据默认受保护。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isScanningStorage || model.isClearingStorage { ProgressView() }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            MetricCard(title: "总占用", value: byteText(totalBytes), subtitle: "\(model.storageRecords.count) 类数据", symbol: "internaldrive", tint: .blue)
            MetricCard(title: "可安全清理", value: byteText(cleanableBytes), subtitle: "当前只包含固定 cache 白名单", symbol: "sparkles", tint: .green)
            MetricCard(title: "受保护", value: byteText(totalBytes - cleanableBytes), subtitle: "会话、能力、配置与未知数据", symbol: "lock.shield", tint: .purple)
        }
    }

    private var cleanupPresented: Binding<Bool> {
        Binding(get: { pendingCleanup != nil }, set: { if !$0 { pendingCleanup = nil } })
    }
    private var totalBytes: Int64 { model.storageRecords.reduce(0) { $0 + $1.sizeBytes } }
    private var cleanableBytes: Int64 { model.storageRecords.filter(\.kind.cleanable).reduce(0) { $0 + $1.sizeBytes } }
}

private struct StorageRow: View {
    @Environment(AppModel.self) private var model
    let record: StorageRecord
    let clean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.kind.title).font(.headline)
                    if record.kind != .other {
                        Text(URL(fileURLWithPath: record.path).lastPathComponent)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Text(record.kind.cleanupImpact).font(.caption).foregroundStyle(.secondary)
                Text("\(record.itemCount.formatted()) 个文件")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(byteText(record.sizeBytes)).font(.headline.monospacedDigit())
            if record.kind != .other {
                Button { model.revealInFinder(path: record.path) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }
            if record.kind.cleanable {
                Button("清理", role: .destructive, action: clean)
                    .disabled(model.isClearingStorage)
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(width: 44)
            }
        }
        .padding(.vertical, 12)
    }

    private var color: Color { record.kind.cleanable ? .green : .blue }
}

private func byteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
