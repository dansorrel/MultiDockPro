import Foundation
import AppKit
import Combine

// MARK: - Data Models

enum SnapEdge: String, Codable, CaseIterable, Identifiable {
    case free = "Livre (Qualquer Lugar)"
    case bottom = "Inferior (Base)"
    case top = "Superior (Topo)"
    case left = "Esquerda"
    case right = "Direita"
    
    var id: String { rawValue }
    
    var isVertical: Bool {
        self == .left || self == .right
    }
}

struct AppEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundlePath: String
    var bundleIdentifier: String?
}

struct AppFolder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var iconSymbol: String
    var colorHex: String
    var apps: [AppEntry]
}

enum DockElement: Identifiable, Codable, Equatable {
    case app(AppEntry)
    case folder(AppFolder)
    
    var id: UUID {
        switch self {
        case .app(let a): return a.id
        case .folder(let f): return f.id
        }
    }
    
    var displayName: String {
        switch self {
        case .app(let a): return a.name
        case .folder(let f): return f.name
        }
    }
}

struct DockInstance: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var isEnabled: Bool = true
    var targetScreenName: String? = nil
    var showOnAllScreens: Bool = false
    var snapEdge: SnapEdge = .bottom
    /// Pixel offset along the snapped axis from screen center (allows side-by-side docks)
    var edgeOffsetPages: Double = 0.0
    var freePositionX: Double = 300
    var freePositionY: Double = 100
    var iconSize: Double = 44 // Can go all the way down to 16pt!
    var opacity: Double = 0.88
    var autoHide: Bool = false
    var isLocked: Bool = false
    var showRunningIndicator: Bool = true
    /// Reserves screen space (Dock Protection Zone) so maximized/zoomed windows don't cover the dock
    var reserveScreenSpace: Bool = true
    /// Magnetic snap to adjacent docks so they never overlap
    var snapToOtherDocks: Bool = true
    var elements: [DockElement] = []
    
    enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, targetScreenName, showOnAllScreens, snapEdge
        case edgeOffsetPages, freePositionX, freePositionY, iconSize, opacity
        case autoHide, isLocked, showRunningIndicator, reserveScreenSpace, snapToOtherDocks, elements
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        targetScreenName: String? = nil,
        showOnAllScreens: Bool = false,
        snapEdge: SnapEdge = .bottom,
        edgeOffsetPages: Double = 0.0,
        freePositionX: Double = 300,
        freePositionY: Double = 100,
        iconSize: Double = 44,
        opacity: Double = 0.88,
        autoHide: Bool = false,
        isLocked: Bool = false,
        showRunningIndicator: Bool = true,
        reserveScreenSpace: Bool = true,
        snapToOtherDocks: Bool = true,
        elements: [DockElement] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.targetScreenName = targetScreenName
        self.showOnAllScreens = showOnAllScreens
        self.snapEdge = snapEdge
        self.edgeOffsetPages = edgeOffsetPages
        self.freePositionX = freePositionX
        self.freePositionY = freePositionY
        self.iconSize = iconSize
        self.opacity = opacity
        self.autoHide = autoHide
        self.isLocked = isLocked
        self.showRunningIndicator = showRunningIndicator
        self.reserveScreenSpace = reserveScreenSpace
        self.snapToOtherDocks = snapToOtherDocks
        self.elements = elements
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        targetScreenName = try c.decodeIfPresent(String.self, forKey: .targetScreenName)
        showOnAllScreens = try c.decodeIfPresent(Bool.self, forKey: .showOnAllScreens) ?? false
        snapEdge = try c.decodeIfPresent(SnapEdge.self, forKey: .snapEdge) ?? .bottom
        edgeOffsetPages = try c.decodeIfPresent(Double.self, forKey: .edgeOffsetPages) ?? 0.0
        freePositionX = try c.decodeIfPresent(Double.self, forKey: .freePositionX) ?? 300
        freePositionY = try c.decodeIfPresent(Double.self, forKey: .freePositionY) ?? 100
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? 44
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.88
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        showRunningIndicator = try c.decodeIfPresent(Bool.self, forKey: .showRunningIndicator) ?? true
        reserveScreenSpace = try c.decodeIfPresent(Bool.self, forKey: .reserveScreenSpace) ?? true
        snapToOtherDocks = try c.decodeIfPresent(Bool.self, forKey: .snapToOtherDocks) ?? true
        elements = try c.decodeIfPresent([DockElement].self, forKey: .elements) ?? []
    }
}

// MARK: - Store & Persistence

class DockStore: ObservableObject {
    static let shared = DockStore()
    
    @Published var docks: [DockInstance] = [] {
        didSet {
            save()
        }
    }
    
    @Published var selectedDockID: UUID?
    @Published var runningBundlePaths: Set<String> = []
    
    private let saveURL: URL
    private var workspaceObservers: [NSObjectProtocol] = []
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MultiDockPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.saveURL = folder.appendingPathComponent("docks_config.json")
        
        load()
        if docks.isEmpty {
            createDefaultDocks()
        }
        selectedDockID = docks.first?.id
        setupRunningAppsObserver()
    }
    
    private func setupRunningAppsObserver() {
        updateRunningApps()
        let nc = NSWorkspace.shared.notificationCenter
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningApps()
        }
        let termObs = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningApps()
        }
        workspaceObservers = [launchObs, termObs]
    }
    
    func updateRunningApps() {
        let paths = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
        runningBundlePaths = Set(paths)
    }
    
    func isAppRunning(_ app: AppEntry) -> Bool {
        runningBundlePaths.contains(app.bundlePath)
    }
    
    func isFolderRunning(_ folder: AppFolder) -> Bool {
        folder.apps.contains { isAppRunning($0) }
    }
    
    func launchApp(_ app: AppEntry) {
        let url = URL(fileURLWithPath: app.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }
    
    func launchAllInFolder(_ folder: AppFolder) {
        for app in folder.apps {
            launchApp(app)
        }
    }
    
    // MARK: - Drag & Drop Helpers
    
    func addDroppedURLs(_ urls: [URL], toDock dockID: UUID, intoFolderID: UUID? = nil, atIndex: Int? = nil) {
        guard let dockIdx = docks.firstIndex(where: { $0.id == dockID }) else { return }
        
        for url in urls {
            let path = url.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            
            if path.hasSuffix(".app") {
                let name = url.deletingPathExtension().lastPathComponent
                let bundle = Bundle(url: url)
                let appEntry = AppEntry(name: name, bundlePath: path, bundleIdentifier: bundle?.bundleIdentifier)
                
                if let folderID = intoFolderID,
                   let elemIdx = docks[dockIdx].elements.firstIndex(where: { $0.id == folderID }),
                   case .folder(var folder) = docks[dockIdx].elements[elemIdx] {
                    if !folder.apps.contains(where: { $0.bundlePath == path }) {
                        folder.apps.append(appEntry)
                        docks[dockIdx].elements[elemIdx] = .folder(folder)
                    }
                } else {
                    let elem = DockElement.app(appEntry)
                    if let idx = atIndex, idx <= docks[dockIdx].elements.count {
                        docks[dockIdx].elements.insert(elem, at: idx)
                    } else {
                        docks[dockIdx].elements.append(elem)
                    }
                }
            } else if isDir.boolValue {
                // User dragged a regular folder from Finder -> scan for .app bundles inside it and create an AppFolder!
                let folderName = url.lastPathComponent
                var subApps: [AppEntry] = []
                if let items = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    for item in items where item.hasSuffix(".app") {
                        let subPath = (path as NSString).appendingPathComponent(item)
                        let appName = (item as NSString).deletingPathExtension
                        let bundle = Bundle(path: subPath)
                        subApps.append(AppEntry(name: appName, bundlePath: subPath, bundleIdentifier: bundle?.bundleIdentifier))
                    }
                }
                let newFolder = AppFolder(name: folderName, iconSymbol: "folder.fill", colorHex: "#007AFF", apps: subApps)
                if let idx = atIndex, idx <= docks[dockIdx].elements.count {
                    docks[dockIdx].elements.insert(.folder(newFolder), at: idx)
                } else {
                    docks[dockIdx].elements.append(.folder(newFolder))
                }
            }
        }
    }
    
    func moveElement(inDock dockID: UUID, fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let dockIdx = docks.firstIndex(where: { $0.id == dockID }),
              let fromIdx = docks[dockIdx].elements.firstIndex(where: { $0.id == fromID }),
              let toIdx = docks[dockIdx].elements.firstIndex(where: { $0.id == toID }) else { return }
        
        var elems = docks[dockIdx].elements
        let item = elems.remove(at: fromIdx)
        elems.insert(item, at: toIdx)
        docks[dockIdx].elements = elems
    }
    
    func removeElement(inDock dockID: UUID, elementID: UUID) {
        guard let dockIdx = docks.firstIndex(where: { $0.id == dockID }) else { return }
        docks[dockIdx].elements.removeAll { $0.id == elementID }
    }
    
    func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([DockInstance].self, from: data) else {
            return
        }
        self.docks = decoded
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(docks) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
    
    // MARK: - Default Starter Setup
    
    func createDefaultDocks() {
        let finder = AppEntry(name: "Finder", bundlePath: "/System/Library/CoreServices/Finder.app", bundleIdentifier: "com.apple.finder")
        let safari = AppEntry(name: "Safari", bundlePath: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")
        let sysSettings = AppEntry(name: "Ajustes", bundlePath: "/System/Applications/System Settings.app", bundleIdentifier: "com.apple.systempreferences")
        
        let installedApps = Self.scanApplicationsFolder()
        
        let adobeApps = installedApps.filter { $0.name.localizedCaseInsensitiveContains("Adobe") || $0.name.localizedCaseInsensitiveContains("Photoshop") || $0.name.localizedCaseInsensitiveContains("Lightroom") || $0.name.localizedCaseInsensitiveContains("Illustrator") || $0.name.localizedCaseInsensitiveContains("Premiere") || $0.name.localizedCaseInsensitiveContains("After Effects") }
        
        let microsoftApps = installedApps.filter { $0.name.localizedCaseInsensitiveContains("Microsoft") || $0.name.localizedCaseInsensitiveContains("Word") || $0.name.localizedCaseInsensitiveContains("Excel") || $0.name.localizedCaseInsensitiveContains("PowerPoint") || $0.name.localizedCaseInsensitiveContains("Outlook") || $0.name.localizedCaseInsensitiveContains("Teams") }
        
        let googleApps = installedApps.filter { $0.name.localizedCaseInsensitiveContains("Google") || $0.name.localizedCaseInsensitiveContains("Chrome") }
        
        let videoApps = installedApps.filter { $0.name.localizedCaseInsensitiveContains("Final Cut") || $0.name.localizedCaseInsensitiveContains("Premiere") || $0.name.localizedCaseInsensitiveContains("DaVinci") || $0.name.localizedCaseInsensitiveContains("QuickTime") || $0.name.localizedCaseInsensitiveContains("iMovie") || $0.name.localizedCaseInsensitiveContains("VLC") }
        
        let adobeFolder = AppFolder(
            name: "Adobe Suite",
            iconSymbol: "paintbrush.pointed.fill",
            colorHex: "#FF3B30",
            apps: adobeApps
        )
        
        let msFolder = AppFolder(
            name: "Microsoft Office",
            iconSymbol: "doc.richtext.fill",
            colorHex: "#007AFF",
            apps: microsoftApps
        )
        
        let googleFolder = AppFolder(
            name: "Google Workspace",
            iconSymbol: "globe.americas.fill",
            colorHex: "#34C759",
            apps: googleApps
        )
        
        let videoFolder = AppFolder(
            name: "Vídeo & Edição",
            iconSymbol: "film.stack.fill",
            colorHex: "#AF52DE",
            apps: videoApps.isEmpty ? [AppEntry(name: "QuickTime Player", bundlePath: "/System/Applications/QuickTime Player.app", bundleIdentifier: "com.apple.QuickTimePlayerX")] : videoApps
        )
        
        let mainDock = DockInstance(
            name: "Dock Principal (Pastas)",
            isEnabled: true,
            targetScreenName: nil,
            showOnAllScreens: false,
            snapEdge: .bottom,
            edgeOffsetPages: -140,
            freePositionX: 250,
            freePositionY: 80,
            iconSize: 44,
            opacity: 0.90,
            elements: [
                .app(finder),
                .folder(adobeFolder),
                .folder(msFolder),
                .folder(googleFolder),
                .folder(videoFolder)
            ]
        )
        
        let sideBySideDock = DockInstance(
            name: "Dock Auxiliar (Ao Lado)",
            isEnabled: true,
            targetScreenName: nil,
            showOnAllScreens: false,
            snapEdge: .bottom,
            edgeOffsetPages: 180,
            freePositionX: 650,
            freePositionY: 80,
            iconSize: 44,
            opacity: 0.90,
            elements: [
                .app(safari),
                .app(sysSettings)
            ]
        )
        
        self.docks = [mainDock, sideBySideDock]
    }
    
    static func scanApplicationsFolder() -> [AppEntry] {
        var results: [AppEntry] = []
        let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    let name = (item as NSString).deletingPathExtension
                    let bundle = Bundle(path: fullPath)
                    results.append(AppEntry(name: name, bundlePath: fullPath, bundleIdentifier: bundle?.bundleIdentifier))
                } else {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                        if let subItems = try? fm.contentsOfDirectory(atPath: fullPath) {
                            for sub in subItems where sub.hasSuffix(".app") {
                                let subPath = (fullPath as NSString).appendingPathComponent(sub)
                                let name = (sub as NSString).deletingPathExtension
                                let bundle = Bundle(path: subPath)
                                results.append(AppEntry(name: name, bundlePath: subPath, bundleIdentifier: bundle?.bundleIdentifier))
                            }
                        }
                    }
                }
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
