import OSLog

enum AppLogger {
    static let general = Logger(subsystem: AppConfig.bundleID, category: "general")
    static let spotify = Logger(subsystem: AppConfig.bundleID, category: "spotify")
    static let routing = Logger(subsystem: AppConfig.bundleID, category: "routing")
}
