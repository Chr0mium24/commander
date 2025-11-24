import SwiftUI

struct HistoryView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Command History")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 10)
            
            List {
                ForEach(appState.history) { item in
                    HStack(alignment: .top) { // 对齐方式改为 .top 以便多行时更美观
                        VStack(alignment: .leading, spacing: 4) {
                            // 第一行：类型 + 查询词 + 时间
                            HStack {
                                Text(item.type.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                                
                                Text(item.query)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                // 新增：显示时间
                                Text(item.timestamp, format: .dateTime.month(.defaultDigits).day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                            }
                            
                            // 第二行：结果预览
                            Text(item.result.prefix(80) + "...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        
                        // 右侧操作按钮区域
                        VStack(spacing: 10) {
                            Button(action: {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(item.result, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            
                            Button(action: {
                                appState.deleteHistoryItem(id: item.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.restoreHistoryItem(item)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(.ultraThinMaterial)
    }
}
