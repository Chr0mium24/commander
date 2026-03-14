import SwiftUI

struct HistoryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let type: String
    let query: String
    let result: String
    let timestamp: Date
}

enum AppStorageKey {
    static let launchAtLogin = "launchAtLogin"
    static let historyLimit = "historyLimit"
    static let autoCopy = "autoCopy"
    static let multilineInput = "multilineInput"
    
    static let geminiKey = "geminiApiKey"
    static let geminiModel = "geminiModel"
    static let geminiProxy = "geminiProxy" // [新增] 代理地址 Key

    static let aiProvider = "aiProvider"
    static let aiBaseURL = "aiBaseURL"
    static let aiApiKey = "aiApiKey"
    static let aiModel = "aiModel"

    static let pythonPath = "pythonPath"
    static let scriptDirectory = "scriptDirectory"
    static let pluginDirectory = "pluginDirectory"
    
    static let aliasDef = "aliasDef"
    static let aliasAsk = "aliasAsk"
    static let aliasSer = "aliasSer"
    static let aliasPy = "aliasPy"
}
