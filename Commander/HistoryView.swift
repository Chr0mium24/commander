//
//  HistoryView.swift
//  Commander
//
//  Created by Chr0mium on 11/21/25.
//


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
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(item.type) \(item.query)")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                            Text(item.result.prefix(50) + "...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        
                        // 复制按钮
                        Button(action: {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(item.result, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        
                        // 删除按钮
                        Button(action: {
                            appState.deleteHistoryItem(id: item.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 点击条目恢复状态
                        appState.restoreHistoryItem(item)
                    }
                }
            }
            .scrollContentBackground(.hidden) // 透明背景
        }
        .background(.ultraThinMaterial)
    }
}