import Foundation
import AppKit

/// Manages automatic launch at macOS login using a LaunchAgent in ~/Library/LaunchAgents
/// and copies the app bundle to /Applications so it runs reliably from a fixed location.
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    
    private let label = "com.dansorrel.MultiDockPro"
    
    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    
    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    func setEnabled(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
            try? fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            
            // Prefer /Applications/MultiDock Pro.app if installed there, otherwise current bundle executable
            let installedExecPath = "/Applications/MultiDock Pro.app/Contents/MacOS/MultiDockPro"
            let execPath = fm.fileExists(atPath: installedExecPath)
                ? installedExecPath
                : (Bundle.main.executablePath ?? installedExecPath)
            
            let plistDict: [String: Any] = [
                "Label": label,
                "ProgramArguments": [execPath, "--launched-at-login"],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            
            if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) {
                try? data.write(to: launchAgentURL, options: .atomic)
            }
        } else {
            try? fm.removeItem(at: launchAgentURL)
        }
    }
}
