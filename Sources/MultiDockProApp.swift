import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var launchAtLoginMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        // Ensure Launch at Login is enabled by default on first run
        if !UserDefaults.standard.bool(forKey: "didConfigureDefaultLaunchAtLogin") {
            LaunchAtLoginManager.shared.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didConfigureDefaultLaunchAtLogin")
        }
        
        setupMenuBar()
        
        DockWindowManager.shared.onOpenSettingsRequested = { [weak self] dockID in
            if let dockID = dockID {
                DockStore.shared.selectedDockID = dockID
            }
            self?.openSettingsWindow()
        }
        
        DockWindowManager.shared.syncAllPanels()
        
        // Only open Settings window automatically when launched manually (not silently at macOS login)
        let launchedAtLogin = CommandLine.arguments.contains("--launched-at-login")
        if !launchedAtLogin {
            openSettingsWindow()
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "MultiDock Pro")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Abrir Configurações do MultiDock...", action: #selector(openSettingsWindow), keyEquivalent: ","))
        
        let loginItem = NSMenuItem(title: "Iniciar Automaticamente ao Ligar o Mac", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(loginItem)
        self.launchAtLoginMenuItem = loginItem
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Criar Novo Dock Ao Lado", action: #selector(quickCreateSideBySideDock), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Recarregar Monitores", action: #selector(reloadScreens), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Sair do MultiDock Pro", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc private func toggleLaunchAtLogin() {
        let newState = !LaunchAtLoginManager.shared.isEnabled
        LaunchAtLoginManager.shared.setEnabled(newState)
        launchAtLoginMenuItem?.state = newState ? .on : .off
    }
    
    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            let vc = NSHostingController(rootView: SettingsView())
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "MultiDock Pro — Gerenciador de Docks Flutuantes, Pastas & Monitores"
            win.contentViewController = vc
            win.center()
            win.isReleasedWhenClosed = false
            self.settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quickCreateSideBySideDock() {
        let store = DockStore.shared
        let count = store.docks.count + 1
        let newDock = DockInstance(
            name: "Dock Lateral #\(count)",
            isEnabled: true,
            targetScreenName: NSScreen.screens.first?.localizedName,
            showOnAllScreens: false,
            snapEdge: .bottom,
            edgeOffsetPages: Double(count * 150),
            freePositionX: 350,
            freePositionY: 120,
            iconSize: 44,
            opacity: 0.90,
            elements: [
                .folder(AppFolder(name: "Nova Pasta", iconSymbol: "folder.fill", colorHex: "#007AFF", apps: []))
            ]
        )
        store.docks.append(newDock)
        store.selectedDockID = newDock.id
        openSettingsWindow()
    }
    
    @objc private func reloadScreens() {
        DockWindowManager.shared.syncAllPanels()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct MultiDockProApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
