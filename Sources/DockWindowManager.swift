import AppKit
import SwiftUI
import Combine
import ApplicationServices

// MARK: - Floating Non-Activating Dock Panel

final class FloatingDockPanel: NSPanel {
    let dockID: UUID
    let assignedScreen: NSScreen
    
    init(dockID: UUID, screen: NSScreen, contentRect: NSRect) {
        self.dockID = dockID
        self.assignedScreen = screen
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        // Use statusWindow + 1 level so it stays visible even above maximized windows
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Multi-Monitor, Snap-to-Next-Dock & Protection Area Coordinator

final class DockWindowManager: ObservableObject {
    static let shared = DockWindowManager()
    
    @Published var axAuthorized: Bool = AXIsProcessTrusted()
    
    private var panels: [String: FloatingDockPanel] = [:] // key: "\(dockID)_\(screenName)"
    private var dragStartFrames: [String: NSRect] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var windowProtectionTimer: Timer?
    private var axObservers: [pid_t: AXObserver] = [:]
    var onOpenSettingsRequested: ((UUID?) -> Void)?
    
    private let edgeSnapThreshold: CGFloat = 46.0
    private let dockToDockSnapThreshold: CGFloat = 28.0
    private let dockSpacingGap: CGFloat = 6.0
    
    init() {
        DockStore.shared.$docks
            .debounce(for: .milliseconds(25), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncAllPanels()
                self?.enforceScreenProtectionZone()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        setupScreenProtectionObserver()
    }
    
    @objc private func screensDidChange() {
        syncAllPanels()
        enforceScreenProtectionZone()
    }
    
    func syncAllPanels() {
        let docks = DockStore.shared.docks
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        var activeKeys = Set<String>()
        
        for dock in docks where dock.isEnabled {
            let targetScreens: [NSScreen]
            if dock.showOnAllScreens {
                targetScreens = screens
            } else if let targetName = dock.targetScreenName,
                      let matched = screens.first(where: { $0.localizedName == targetName }) {
                targetScreens = [matched]
            } else {
                targetScreens = [screens.first!]
            }
            
            for screen in targetScreens {
                let key = "\(dock.id.uuidString)_\(screen.localizedName)"
                activeKeys.insert(key)
                
                if let existingPanel = panels[key] {
                    updatePanelLayout(existingPanel, dock: dock, screen: screen)
                } else {
                    let newPanel = createPanel(for: dock, screen: screen, key: key)
                    panels[key] = newPanel
                    updatePanelLayout(newPanel, dock: dock, screen: screen)
                    newPanel.orderFrontRegardless()
                }
            }
        }
        
        for (key, panel) in panels where !activeKeys.contains(key) {
            panel.orderOut(nil)
            panel.close()
            panels.removeValue(forKey: key)
        }
        
        resolveSnappedOverlaps()
    }
    
    private func createPanel(for dock: DockInstance, screen: NSScreen, key: String) -> FloatingDockPanel {
        let initialRect = NSRect(x: screen.visibleFrame.midX - 150, y: screen.visibleFrame.minY + 12, width: 300, height: 80)
        let panel = FloatingDockPanel(dockID: dock.id, screen: screen, contentRect: initialRect)
        
        let rootView = DockBarView(
            dockID: dock.id,
            screen: screen,
            onDragDelta: { [weak self, weak panel] translation in
                guard let self = self, let panel = panel else { return }
                self.handleDragDelta(panel: panel, key: key, translation: translation)
            },
            onDragEnded: { [weak self, weak panel] mouseLocation in
                guard let self = self, let panel = panel else { return }
                self.handleDragEnded(panel: panel, key: key, mouseLocation: mouseLocation)
            },
            onOpenSettings: { [weak self] dockID in
                self?.onOpenSettingsRequested?(dockID)
            },
            onElementDragRemoved: { elementID, _ in
                NSSound.beep()
                DockStore.shared.removeElement(inDock: dock.id, elementID: elementID)
            }
        )
        
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        return panel
    }
    
    private func updatePanelLayout(_ panel: FloatingDockPanel, dock: DockInstance, screen: NSScreen) {
        guard let contentView = panel.contentView else { return }
        let fittingSize = contentView.fittingSize
        let width = max(fittingSize.width, 44)
        let height = max(fittingSize.height, 36)
        
        let vf = screen.visibleFrame
        var origin = CGPoint.zero
        
        switch dock.snapEdge {
        case .bottom:
            origin.x = vf.midX - (width / 2) + CGFloat(dock.edgeOffsetPages)
            origin.y = vf.minY + 6
        case .top:
            origin.x = vf.midX - (width / 2) + CGFloat(dock.edgeOffsetPages)
            origin.y = vf.maxY - height - 6
        case .left:
            origin.x = vf.minX + 6
            origin.y = vf.midY - (height / 2) + CGFloat(dock.edgeOffsetPages)
        case .right:
            origin.x = vf.maxX - width - 6
            origin.y = vf.midY - (height / 2) + CGFloat(dock.edgeOffsetPages)
        case .free:
            origin.x = vf.minX + CGFloat(dock.freePositionX)
            origin.y = vf.minY + CGFloat(dock.freePositionY)
        }
        
        origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - width - 4)
        origin.y = min(max(origin.y, vf.minY + 4), vf.maxY - height - 4)
        
        let targetFrame = NSRect(origin: origin, size: CGSize(width: width, height: height))
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: true, animate: false)
        }
    }
    
    // MARK: - Snap to Next Dock & Anti-Overlap Solver
    
    private func resolveSnappedOverlaps() {
        let screens = NSScreen.screens
        for screen in screens {
            for edge in [SnapEdge.bottom, .top, .left, .right] {
                let matchingPanels = panels.values.filter { panel in
                    guard panel.assignedScreen.localizedName == screen.localizedName,
                          let d = DockStore.shared.docks.first(where: { $0.id == panel.dockID }) else { return false }
                    return d.isEnabled && d.snapEdge == edge && d.snapToOtherDocks
                }.sorted { a, b in
                    edge.isVertical ? (a.frame.minY < b.frame.minY) : (a.frame.minX < b.frame.minX)
                }
                
                guard matchingPanels.count > 1 else { continue }
                
                let vf = screen.visibleFrame
                for i in 1..<matchingPanels.count {
                    let prev = matchingPanels[i - 1].frame
                    let currPanel = matchingPanels[i]
                    var curr = currPanel.frame
                    
                    if edge.isVertical {
                        if curr.minY < prev.maxY + dockSpacingGap {
                            curr.origin.y = min(prev.maxY + dockSpacingGap, vf.maxY - curr.height - 4)
                            currPanel.setFrame(curr, display: true, animate: false)
                        }
                    } else {
                        if curr.minX < prev.maxX + dockSpacingGap {
                            curr.origin.x = min(prev.maxX + dockSpacingGap, vf.maxX - curr.width - 4)
                            currPanel.setFrame(curr, display: true, animate: false)
                        }
                    }
                }
            }
        }
    }
    
    /// Computes magnetic snap against sibling docks on the same screen (both while dragging and on drop)
    private func applyMagneticDockSnap(proposedFrame: NSRect, movingPanel: FloatingDockPanel, screen: NSScreen, snapToOtherDocks: Bool) -> NSRect {
        guard snapToOtherDocks else { return proposedFrame }
        var result = proposedFrame
        
        let otherPanels = panels.values.filter {
            $0.dockID != movingPanel.dockID && $0.assignedScreen.localizedName == screen.localizedName
        }
        
        for other in otherPanels {
            let of = other.frame
            
            let verticalOverlap = min(result.maxY, of.maxY) - max(result.minY, of.minY)
            if verticalOverlap > -24 {
                if abs(result.minX - of.maxX) < dockToDockSnapThreshold {
                    result.origin.x = of.maxX + dockSpacingGap
                    if abs(result.midY - of.midY) < dockToDockSnapThreshold {
                        result.origin.y = of.midY - result.height / 2
                    }
                } else if abs(result.maxX - of.minX) < dockToDockSnapThreshold {
                    result.origin.x = of.minX - result.width - dockSpacingGap
                    if abs(result.midY - of.midY) < dockToDockSnapThreshold {
                        result.origin.y = of.midY - result.height / 2
                    }
                }
            }
            
            let horizontalOverlap = min(result.maxX, of.maxX) - max(result.minX, of.minX)
            if horizontalOverlap > -24 {
                if abs(result.minY - of.maxY) < dockToDockSnapThreshold {
                    result.origin.y = of.maxY + dockSpacingGap
                    if abs(result.midX - of.midX) < dockToDockSnapThreshold {
                        result.origin.x = of.midX - result.width / 2
                    }
                } else if abs(result.maxY - of.minY) < dockToDockSnapThreshold {
                    result.origin.y = of.minY - result.height - dockSpacingGap
                    if abs(result.midX - of.midX) < dockToDockSnapThreshold {
                        result.origin.x = of.midX - result.width / 2
                    }
                }
            }
            
            if result.intersects(of) {
                let pushRight = of.maxX + dockSpacingGap
                let pushLeft = of.minX - result.width - dockSpacingGap
                if abs(result.minX - pushRight) < abs(result.minX - pushLeft) {
                    result.origin.x = pushRight
                } else {
                    result.origin.x = pushLeft
                }
            }
        }
        
        return result
    }
    
    // MARK: - Interactive Free Drag & Edge/Dock Snap
    
    private func handleDragDelta(panel: FloatingDockPanel, key: String, translation: CGSize) {
        if dragStartFrames[key] == nil {
            dragStartFrames[key] = panel.frame
        }
        guard let startFrame = dragStartFrames[key] else { return }
        
        let rawOrigin = CGPoint(
            x: startFrame.origin.x + translation.width,
            y: startFrame.origin.y - translation.height
        )
        var candidateFrame = NSRect(origin: rawOrigin, size: panel.frame.size)
        
        let shouldSnapDocks = DockStore.shared.docks.first(where: { $0.id == panel.dockID })?.snapToOtherDocks ?? true
        candidateFrame = applyMagneticDockSnap(
            proposedFrame: candidateFrame,
            movingPanel: panel,
            screen: panel.assignedScreen,
            snapToOtherDocks: shouldSnapDocks
        )
        
        panel.setFrameOrigin(candidateFrame.origin)
    }
    
    private func handleDragEnded(panel: FloatingDockPanel, key: String, mouseLocation: CGPoint) {
        dragStartFrames.removeValue(forKey: key)
        
        let currentScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? panel.assignedScreen
        let vf = currentScreen.visibleFrame
        
        guard let idx = DockStore.shared.docks.firstIndex(where: { $0.id == panel.dockID }) else { return }
        var dock = DockStore.shared.docks[idx]
        
        if !dock.showOnAllScreens {
            dock.targetScreenName = currentScreen.localizedName
        }
        
        let snappedFrame = applyMagneticDockSnap(
            proposedFrame: panel.frame,
            movingPanel: panel,
            screen: currentScreen,
            snapToOtherDocks: dock.snapToOtherDocks
        )
        panel.setFrameOrigin(snappedFrame.origin)
        let frame = panel.frame
        
        let distBottom = abs(frame.minY - vf.minY)
        let distTop = abs(vf.maxY - frame.maxY)
        let distLeft = abs(frame.minX - vf.minX)
        let distRight = abs(vf.maxX - frame.maxX)
        
        let minDist = min(distBottom, distTop, distLeft, distRight)
        
        if minDist <= edgeSnapThreshold {
            if minDist == distBottom {
                dock.snapEdge = .bottom
                dock.edgeOffsetPages = Double(frame.midX - vf.midX)
            } else if minDist == distTop {
                dock.snapEdge = .top
                dock.edgeOffsetPages = Double(frame.midX - vf.midX)
            } else if minDist == distLeft {
                dock.snapEdge = .left
                dock.edgeOffsetPages = Double(frame.midY - vf.midY)
            } else {
                dock.snapEdge = .right
                dock.edgeOffsetPages = Double(frame.midY - vf.midY)
            }
        } else {
            dock.snapEdge = .free
            dock.freePositionX = Double(frame.minX - vf.minX)
            dock.freePositionY = Double(frame.minY - vf.minY)
        }
        
        DockStore.shared.docks[idx] = dock
        enforceScreenProtectionZone()
    }
    
    // MARK: - Real-Time Dock Protection Zone (Like macOS Native Dock!)
    // Prevents any window on any screen from entering the area occupied by our snapped Docks.
    
    private func setupScreenProtectionObserver() {
        // Check and prompt for Accessibility permission on launch if any dock has protection enabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            self.axAuthorized = AXIsProcessTrusted()
            let needsProtection = DockStore.shared.docks.contains { $0.isEnabled && $0.reserveScreenSpace }
            if needsProtection && !self.axAuthorized {
                _ = self.requestAccessibilityPermissionForProtectionZone()
            }
            self.registerAXObserversForAllRunningApps()
            self.enforceScreenProtectionZone()
        }
        
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.registerAXObserver(for: app.processIdentifier)
            }
            self?.enforceScreenProtectionZone()
        }
        wsnc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.registerAXObserver(for: app.processIdentifier)
            }
            self?.enforceScreenProtectionZone()
        }
        wsnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.removeAXObserver(for: app.processIdentifier)
            }
        }
        
        // Fast 0.35s heartbeat ensures continuous protection and updates AX status immediately after user grants permission
        windowProtectionTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.axAuthorized {
                self.axAuthorized = trusted
                if trusted {
                    self.registerAXObserversForAllRunningApps()
                }
            }
            if trusted {
                self.enforceScreenProtectionZone()
            }
        }
    }
    
    func requestAccessibilityPermissionForProtectionZone() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.axAuthorized = trusted
        return trusted
    }
    
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    
    private func registerAXObserversForAllRunningApps() {
        guard AXIsProcessTrusted() else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            registerAXObserver(for: app.processIdentifier)
        }
    }
    
    private func registerAXObserver(for pid: pid_t) {
        guard AXIsProcessTrusted(),
              pid != ProcessInfo.processInfo.processIdentifier,
              axObservers[pid] == nil else { return }
        
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in
            DispatchQueue.main.async {
                DockWindowManager.shared.enforceScreenProtectionZone()
            }
        }
        
        guard AXObserverCreate(pid, callback, &observer) == .success,
              let axObs = observer else { return }
        
        let appElem = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(axObs, appElem, kAXWindowMovedNotification as CFString, nil)
        AXObserverAddNotification(axObs, appElem, kAXWindowResizedNotification as CFString, nil)
        AXObserverAddNotification(axObs, appElem, kAXFocusedWindowChangedNotification as CFString, nil)
        AXObserverAddNotification(axObs, appElem, kAXWindowCreatedNotification as CFString, nil)
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObs), .defaultMode)
        axObservers[pid] = axObs
    }
    
    private func removeAXObserver(for pid: pid_t) {
        if let obs = axObservers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
    }
    
    /// Computes the protected safe area for a given screen by subtracting all snapped docks on that screen
    private func computeSafeRect(for screen: NSScreen, protectedDocks: [DockInstance]) -> NSRect {
        var safeRect = screen.visibleFrame
        let screenPanels = panels.values.filter { $0.assignedScreen.localizedName == screen.localizedName }
        
        for panel in screenPanels {
            guard let dock = protectedDocks.first(where: { $0.id == panel.dockID }) else { continue }
            let pf = panel.frame
            
            switch dock.snapEdge {
            case .bottom:
                let neededBottom = pf.maxY + 4
                if safeRect.minY < neededBottom {
                    let diff = neededBottom - safeRect.minY
                    safeRect.origin.y += diff
                    safeRect.size.height -= diff
                }
            case .top:
                let neededTop = pf.minY - 4
                if safeRect.maxY > neededTop {
                    let diff = safeRect.maxY - neededTop
                    safeRect.size.height -= diff
                }
            case .left:
                let neededLeft = pf.maxX + 4
                if safeRect.minX < neededLeft {
                    let diff = neededLeft - safeRect.minX
                    safeRect.origin.x += diff
                    safeRect.size.width -= diff
                }
            case .right:
                let neededRight = pf.minX - 4
                if safeRect.maxX > neededRight {
                    let diff = safeRect.maxX - neededRight
                    safeRect.size.width -= diff
                }
            case .free:
                break
            }
        }
        return safeRect
    }
    
    func enforceScreenProtectionZone() {
        let protectedDocks = DockStore.shared.docks.filter { $0.isEnabled && $0.reserveScreenSpace && !$0.autoHide && $0.snapEdge != .free }
        guard !protectedDocks.isEmpty, AXIsProcessTrusted() else { return }
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        
        // Check all visible regular applications (frontmost first so active app reacts immediately)
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            !$0.isHidden &&
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.bundleIdentifier != "com.apple.finder"
        }
        
        for app in runningApps {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            
            var windowsObj: CFTypeRef?
            var axWindows: [AXUIElement] = []
            if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsObj) == .success,
               let list = windowsObj as? [AXUIElement] {
                axWindows = list
            } else {
                var focusedObj: CFTypeRef?
                if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedObj) == .success,
                   let w = focusedObj {
                    axWindows = [w as! AXUIElement]
                }
            }
            
            for axWindow in axWindows {
                constrainWindowIfNeeded(axWindow, primaryHeight: primaryHeight, protectedDocks: protectedDocks)
            }
        }
    }
    
    private func constrainWindowIfNeeded(_ axWindow: AXUIElement, primaryHeight: CGFloat, protectedDocks: [DockInstance]) {
        // Skip minimized or native full-screen space windows
        var minObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minObj) == .success,
           let isMin = minObj as? Bool, isMin {
            return
        }
        var fsObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, "AXFullScreen" as CFString, &fsObj) == .success,
           let isFS = fsObj as? Bool, isFS {
            return
        }
        
        var posObj: CFTypeRef?
        var sizeObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posObj) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeObj) == .success else { return }
        
        var winPos = CGPoint.zero
        var winSize = CGSize.zero
        AXValueGetValue(posObj as! AXValue, .cgPoint, &winPos)
        AXValueGetValue(sizeObj as! AXValue, .cgSize, &winSize)
        
        // Ignore tiny utility popovers/tooltips
        guard winSize.width > 180, winSize.height > 140 else { return }
        
        // Convert Quartz/AX top-left origin to AppKit bottom-left origin
        let appKitWinY = primaryHeight - (winPos.y + winSize.height)
        var rect = NSRect(x: winPos.x, y: appKitWinY, width: winSize.width, height: winSize.height)
        
        // Find the screen with the largest intersection area with this window
        guard let winScreen = NSScreen.screens.max(by: { a, b in
            let ia = a.frame.intersection(rect)
            let ib = b.frame.intersection(rect)
            let areaA = ia.isNull ? 0 : ia.width * ia.height
            let areaB = ib.isNull ? 0 : ib.width * ib.height
            return areaA < areaB
        }) else { return }
        
        let intersection = winScreen.frame.intersection(rect)
        guard !intersection.isNull, intersection.width * intersection.height > 0 else { return }
        
        let safeRect = computeSafeRect(for: winScreen, protectedDocks: protectedDocks)
        guard safeRect != winScreen.visibleFrame else { return }
        
        var modified = false
        let tolerance: CGFloat = 1.5
        
        // 1. Protect BOTTOM Dock zone: no window's bottom edge (minY) may go below safeRect.minY
        if rect.minY < safeRect.minY - tolerance {
            let maxAllowedHeight = safeRect.maxY - safeRect.minY
            if rect.height > maxAllowedHeight {
                // Window is taller than the safe area (e.g. maximized) -> shrink height so it fits above the dock
                rect.origin.y = safeRect.minY
                rect.size.height = maxAllowedHeight
            } else {
                // Window fits in safe area -> push it up above the dock, clamping top to safeRect.maxY
                rect.origin.y = safeRect.minY
                if rect.maxY > safeRect.maxY {
                    rect.size.height = max(140, safeRect.maxY - safeRect.minY)
                }
            }
            modified = true
        }
        
        // 2. Protect TOP Dock zone: no window's top edge (maxY) may go above safeRect.maxY
        if rect.maxY > safeRect.maxY + tolerance {
            let overlap = rect.maxY - safeRect.maxY
            if rect.minY - overlap >= safeRect.minY {
                rect.origin.y -= overlap
            } else {
                rect.origin.y = safeRect.minY
                rect.size.height = max(140, safeRect.maxY - safeRect.minY)
            }
            modified = true
        }
        
        // 3. Protect LEFT Dock zone: no window's left edge (minX) may go left of safeRect.minX
        if rect.minX < safeRect.minX - tolerance {
            let maxAllowedWidth = safeRect.maxX - safeRect.minX
            if rect.width > maxAllowedWidth {
                rect.origin.x = safeRect.minX
                rect.size.width = maxAllowedWidth
            } else {
                rect.origin.x = safeRect.minX
                if rect.maxX > safeRect.maxX {
                    rect.size.width = max(200, safeRect.maxX - safeRect.minX)
                }
            }
            modified = true
        }
        
        // 4. Protect RIGHT Dock zone: no window's right edge (maxX) may go right of safeRect.maxX
        if rect.maxX > safeRect.maxX + tolerance {
            let overlap = rect.maxX - safeRect.maxX
            if rect.minX - overlap >= safeRect.minX {
                rect.origin.x -= overlap
            } else {
                rect.origin.x = safeRect.minX
                rect.size.width = max(200, safeRect.maxX - safeRect.minX)
            }
            modified = true
        }
        
        if modified {
            var newAXPos = CGPoint(
                x: rect.origin.x,
                y: primaryHeight - (rect.origin.y + rect.size.height)
            )
            var newAXSize = rect.size
            if let sizeVal = AXValueCreate(.cgSize, &newAXSize),
               let posVal = AXValueCreate(.cgPoint, &newAXPos) {
                // Set size first, then position, then size again (handles apps that clamp position based on current size)
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
            }
        }
    }
}
