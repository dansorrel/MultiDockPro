import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Dock Bar View (Rendered inside each Floating Panel)

struct DockBarView: View {
    let dockID: UUID
    let screen: NSScreen
    var onDragDelta: (CGSize) -> Void
    var onDragEnded: (CGPoint) -> Void
    var onOpenSettings: (UUID) -> Void
    var onElementDragRemoved: (UUID, CGPoint) -> Void
    
    @ObservedObject var store = DockStore.shared
    @State private var hoveredElementID: UUID?
    @State private var openFolderID: UUID?
    @State private var isHoveringDock: Bool = false
    @State private var isDropTargetedOnBar: Bool = false
    @State private var dropTargetedFolderID: UUID?
    @State private var draggingElementID: UUID?
    @State private var dragElementOffset: CGSize = .zero
    
    private var dock: DockInstance? {
        store.docks.first { $0.id == dockID }
    }
    
    var body: some View {
        if let dock = dock, dock.isEnabled {
            let isVertical = dock.snapEdge.isVertical
            let spacing = max(4.0, dock.iconSize * 0.18)
            let padH = isVertical ? max(6.0, dock.iconSize * 0.2) : max(8.0, dock.iconSize * 0.26)
            let padV = isVertical ? max(8.0, dock.iconSize * 0.26) : max(6.0, dock.iconSize * 0.2)
            let cornerRad = max(10.0, dock.iconSize * 0.34)
            
            ZStack {
                if dock.autoHide && !isHoveringDock && openFolderID == nil {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.38))
                        .frame(
                            width: isVertical ? 6 : 120,
                            height: isVertical ? 120 : 6
                        )
                        .padding(4)
                } else {
                    let layout = isVertical
                        ? AnyLayout(VStackLayout(spacing: spacing))
                        : AnyLayout(HStackLayout(spacing: spacing))
                    
                    layout {
                        // Drag Handle
                        dragHandleView(dock: dock, isVertical: isVertical)
                        
                        Divider()
                            .frame(
                                width: isVertical ? dock.iconSize * 0.65 : 1,
                                height: isVertical ? 1 : dock.iconSize * 0.65
                            )
                            .background(Color.white.opacity(0.22))
                        
                        // Apps and Folders
                        ForEach(dock.elements) { element in
                            elementView(element: element, dock: dock, isVertical: isVertical)
                        }
                        
                        // Quick Settings Button
                        Button {
                            onOpenSettings(dock.id)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: max(16, dock.iconSize * 0.65), height: max(16, dock.iconSize * 0.65))
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: max(9, dock.iconSize * 0.30), weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Configurar este Dock (\(dock.name))")
                    }
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
                    .background(
                        ZStack {
                            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                            RoundedRectangle(cornerRadius: cornerRad, style: .continuous)
                                .fill(Color.black.opacity(1.0 - dock.opacity))
                            RoundedRectangle(cornerRadius: cornerRad, style: .continuous)
                                .strokeBorder(
                                    isDropTargetedOnBar ? Color.cyan : Color.white.opacity(0.22),
                                    lineWidth: isDropTargetedOnBar ? 2.5 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRad, style: .continuous))
                        // Allow clicking & dragging ANYWHERE on the dock background!
                        .gesture(
                            dock.isLocked ? nil :
                            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                                .onChanged { value in
                                    onDragDelta(value.translation)
                                }
                                .onEnded { _ in
                                    onDragEnded(NSEvent.mouseLocation)
                                }
                        )
                    )
                    .shadow(color: .black.opacity(0.38), radius: 12, x: 0, y: 5)
                    // External Drag & Drop from Finder onto the Dock!
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargetedOnBar) { providers in
                        handleExternalFileDrop(providers: providers, dockID: dock.id, intoFolderID: nil)
                    }
                }
            }
            .padding(6)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.16)) {
                    isHoveringDock = hovering
                }
            }
            .contextMenu {
                Text(dock.name)
                Divider()
                Button("Configurar este Dock...") {
                    onOpenSettings(dock.id)
                }
                Divider()
                Menu("Ancorar (Snap) na Borda") {
                    ForEach(SnapEdge.allCases) { edge in
                        Button {
                            updateDock { $0.snapEdge = edge }
                        } label: {
                            HStack {
                                Text(edge.rawValue)
                                if dock.snapEdge == edge {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Button(dock.reserveScreenSpace ? "Desativar Área de Proteção de Tela" : "Ativar Área de Proteção (Empurrar Janelas)") {
                    updateDock { $0.reserveScreenSpace.toggle() }
                }
                Button(dock.snapToOtherDocks ? "Desativar Snap Magnético entre Docks" : "Ativar Snap Magnético entre Docks") {
                    updateDock { $0.snapToOtherDocks.toggle() }
                }
                Button(dock.isLocked ? "Desbloquear Posição" : "Bloquear Posição") {
                    updateDock { $0.isLocked.toggle() }
                }
                Button(dock.autoHide ? "Desativar Ocultação Automática" : "Ocultar Automaticamente") {
                    updateDock { $0.autoHide.toggle() }
                }
                Divider()
                Button("Duplicar Dock Ao Lado") {
                    duplicateDockSideBySide(dock)
                }
            }
        }
    }
    
    // MARK: - Drag Handle
    
    @ViewBuilder
    private func dragHandleView(dock: DockInstance, isVertical: Bool) -> some View {
        let grip = ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.09))
                .frame(
                    width: isVertical ? max(14, dock.iconSize * 0.7) : max(12, dock.iconSize * 0.35),
                    height: isVertical ? max(12, dock.iconSize * 0.35) : max(14, dock.iconSize * 0.7)
                )
            Image(systemName: dock.isLocked ? "lock.fill" : "circle.grid.2x3.fill")
                .font(.system(size: max(8, dock.iconSize * 0.22), weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .rotationEffect(isVertical ? .degrees(90) : .degrees(0))
        }
        .help(dock.isLocked ? "Posição Bloqueada (clique direito para desbloquear)" : "Arraste por aqui ou pelo fundo do Dock para mover, fazer Snap na borda ou grudar ao lado de outro Dock")
        
        if dock.isLocked {
            grip
        } else {
            grip.gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        onDragDelta(value.translation)
                    }
                    .onEnded { _ in
                        onDragEnded(NSEvent.mouseLocation)
                    }
            )
        }
    }
    
    // MARK: - Element View (App or Folder) with Reorder & Drag-Out-to-Remove
    
    @ViewBuilder
    private func elementView(element: DockElement, dock: DockInstance, isVertical: Bool) -> some View {
        let isHovered = hoveredElementID == element.id
        let isDraggingThis = draggingElementID == element.id
        let scale: CGFloat = isDraggingThis ? 1.22 : (isHovered ? 1.15 : 1.0)
        
        // Check if dragged far enough outside the dock to show "Trash / Poof" indicator
        let willRemoveIfDropped = isDraggingThis && (isVertical ? abs(dragElementOffset.width) > 65 : abs(dragElementOffset.height) > 65)
        
        ZStack(alignment: .topTrailing) {
            switch element {
            case .app(let app):
                VStack(spacing: max(2, dock.iconSize * 0.06)) {
                    Button {
                        store.launchApp(app)
                    } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: dock.iconSize, height: dock.iconSize)
                            .scaleEffect(scale)
                            .opacity(willRemoveIfDropped ? 0.45 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
                    }
                    .buttonStyle(.plain)
                    .help("\(app.name) — Arraste para reorganizar ou puxe para fora do Dock para remover")
                    
                    if dock.showRunningIndicator {
                        Circle()
                            .fill(store.isAppRunning(app) ? Color.white : Color.clear)
                            .frame(width: max(3, dock.iconSize * 0.09), height: max(3, dock.iconSize * 0.09))
                    }
                }
                
            case .folder(let folder):
                let isFolderDropTargeted = dropTargetedFolderID == folder.id
                VStack(spacing: max(2, dock.iconSize * 0.06)) {
                    Button {
                        if openFolderID == folder.id {
                            openFolderID = nil
                        } else {
                            openFolderID = folder.id
                        }
                    } label: {
                        folderIconView(folder: folder, size: dock.iconSize, isHighlighted: isFolderDropTargeted)
                            .scaleEffect(isFolderDropTargeted ? 1.22 : scale)
                            .opacity(willRemoveIfDropped ? 0.45 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
                    }
                    .buttonStyle(.plain)
                    .help("\(folder.name) (\(folder.apps.count) apps) — Solte apps aqui para adicionar à pasta")
                    .popover(isPresented: Binding(
                        get: { openFolderID == folder.id },
                        set: { if !$0 { openFolderID = nil } }
                    ), arrowEdge: popoverEdge(for: dock.snapEdge)) {
                        FolderPopoverView(folder: folder, dockID: dock.id) {
                            openFolderID = nil
                        } onOpenSettings: {
                            openFolderID = nil
                            onOpenSettings(dock.id)
                        }
                    }
                    // Allow dropping .app directly from Finder into this specific Folder!
                    .onDrop(of: [.fileURL], isTargeted: Binding(
                        get: { dropTargetedFolderID == folder.id },
                        set: { dropTargetedFolderID = $0 ? folder.id : nil }
                    )) { providers in
                        handleExternalFileDrop(providers: providers, dockID: dock.id, intoFolderID: folder.id)
                    }
                    
                    if dock.showRunningIndicator {
                        Circle()
                            .fill(store.isFolderRunning(folder) ? Color.cyan : Color.clear)
                            .frame(width: max(3, dock.iconSize * 0.1), height: max(3, dock.iconSize * 0.1))
                    }
                }
            }
            
            if willRemoveIfDropped {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: max(14, dock.iconSize * 0.42)))
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
                    .offset(x: 4, y: -4)
            }
        }
        .offset(isDraggingThis ? dragElementOffset : .zero)
        .zIndex(isDraggingThis ? 100 : 0)
        .onHover { hovering in
            hoveredElementID = hovering ? element.id : nil
        }
        // High-priority DragGesture on items to reorder inside the dock OR drag out to remove!
        .highPriorityGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { value in
                    draggingElementID = element.id
                    dragElementOffset = value.translation
                    
                    // Check if user is sliding along the dock axis to reorder items live!
                    let step = dock.iconSize + max(4.0, dock.iconSize * 0.18)
                    let primaryDelta = isVertical ? value.translation.height : value.translation.width
                    let perpDelta = isVertical ? abs(value.translation.width) : abs(value.translation.height)
                    
                    if perpDelta < 55 && abs(primaryDelta) > step * 0.65 {
                        if let currentIdx = dock.elements.firstIndex(where: { $0.id == element.id }) {
                            let direction = primaryDelta > 0 ? 1 : -1
                            let targetIdx = currentIdx + direction
                            if dock.elements.indices.contains(targetIdx) {
                                let targetID = dock.elements[targetIdx].id
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    store.moveElement(inDock: dock.id, fromID: element.id, toID: targetID)
                                }
                            }
                        }
                    }
                }
                .onEnded { value in
                    let removed = isVertical ? abs(value.translation.width) > 65 : abs(value.translation.height) > 65
                    draggingElementID = nil
                    dragElementOffset = .zero
                    if removed {
                        onElementDragRemoved(element.id, NSEvent.mouseLocation)
                    }
                }
        )
        .contextMenu {
            Text(element.displayName)
            Divider()
            if case .folder(let folder) = element {
                Button("Abrir Todos de \"\(folder.name)\"") {
                    store.launchAllInFolder(folder)
                }
            }
            Button("Mover para o Início") {
                if let firstID = dock.elements.first?.id {
                    store.moveElement(inDock: dock.id, fromID: element.id, toID: firstID)
                }
            }
            Button("Mover para o Fim") {
                if let lastID = dock.elements.last?.id {
                    store.moveElement(inDock: dock.id, fromID: element.id, toID: lastID)
                }
            }
            Divider()
            Button(role: .destructive) {
                store.removeElement(inDock: dock.id, elementID: element.id)
            } label: {
                Label("Remover do Dock", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Smart Folder Icon (Mini Grid + Badge)
    
    @ViewBuilder
    private func folderIconView(folder: AppFolder, size: Double, isHighlighted: Bool = false) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: folder.colorHex).opacity(0.92), Color(hex: folder.colorHex).opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(isHighlighted ? Color.cyan : Color.white.opacity(0.38), lineWidth: isHighlighted ? 2.5 : 1)
                )
            
            if folder.apps.isEmpty || size < 24 {
                Image(systemName: folder.iconSymbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                let previewApps = Array(folder.apps.prefix(4))
                let miniSize = size * 0.34
                VStack(spacing: max(1, size * 0.04)) {
                    HStack(spacing: max(1, size * 0.04)) {
                        if previewApps.indices.contains(0) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: previewApps[0].bundlePath))
                                .resizable()
                                .frame(width: miniSize, height: miniSize)
                        }
                        if previewApps.indices.contains(1) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: previewApps[1].bundlePath))
                                .resizable()
                                .frame(width: miniSize, height: miniSize)
                        }
                    }
                    HStack(spacing: max(1, size * 0.04)) {
                        if previewApps.indices.contains(2) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: previewApps[2].bundlePath))
                                .resizable()
                                .frame(width: miniSize, height: miniSize)
                        }
                        if previewApps.indices.contains(3) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: previewApps[3].bundlePath))
                                .resizable()
                                .frame(width: miniSize, height: miniSize)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
    
    // MARK: - Handle File Drop from Finder
    
    private func handleExternalFileDrop(providers: [NSItemProvider], dockID: UUID, intoFolderID: UUID?) -> Bool {
        var found = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                found = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let directURL = item as? URL {
                        url = directURL
                    }
                    if let validURL = url {
                        DispatchQueue.main.async {
                            DockStore.shared.addDroppedURLs([validURL], toDock: dockID, intoFolderID: intoFolderID)
                        }
                    }
                }
            }
        }
        return found
    }
    
    private func popoverEdge(for snap: SnapEdge) -> Edge {
        switch snap {
        case .bottom, .free: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }
    
    private func updateDock(_ transform: (inout DockInstance) -> Void) {
        guard let idx = store.docks.firstIndex(where: { $0.id == dockID }) else { return }
        transform(&store.docks[idx])
    }
    
    private func duplicateDockSideBySide(_ source: DockInstance) {
        var copy = source
        copy.id = UUID()
        copy.name = "\(source.name) (2)"
        copy.edgeOffsetPages = source.edgeOffsetPages + 240
        copy.freePositionX = source.freePositionX + 240
        store.docks.append(copy)
    }
}

// MARK: - Folder Popover View (Grid of Apps inside Category + Drag & Drop)

struct FolderPopoverView: View {
    let folder: AppFolder
    let dockID: UUID
    var onClose: () -> Void
    var onOpenSettings: () -> Void
    
    @ObservedObject var store = DockStore.shared
    @State private var isDropTargeted = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: folder.iconSymbol)
                    .foregroundColor(Color(hex: folder.colorHex))
                    .font(.title3.bold())
                Text(folder.name)
                    .font(.headline)
                
                Spacer()
                
                if !folder.apps.isEmpty {
                    Button {
                        store.launchAllInFolder(folder)
                        onClose()
                    } label: {
                        Label("Abrir Todos", systemImage: "play.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: folder.colorHex))
                    .controlSize(.small)
                }
                
                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Adicionar ou editar apps desta pasta")
            }
            .padding(.horizontal, 4)
            
            Divider()
            
            if folder.apps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.app.dashed")
                        .font(.system(size: 32))
                        .foregroundColor(isDropTargeted ? .cyan : .secondary)
                    Text("Arraste aplicativos (.app) do Finder para cá ou clique abaixo.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Escolher Aplicativos...") {
                        onOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(folder.apps) { app in
                            Button {
                                store.launchApp(app)
                                onClose()
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 50, height: 50)
                                        
                                        if store.isAppRunning(app) {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 10, height: 10)
                                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                                        }
                                    }
                                    
                                    Text(app.name)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 28, alignment: .top)
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.primary.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeAppFromFolder(appID: app.id)
                                } label: {
                                    Label("Remover da Pasta", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 290)
            }
            
            Text("Dica: Você pode arrastar apps do Finder para cima desta janela ou clicar com botão direito em um app para removê-lo.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 350)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTargeted ? Color.cyan : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let directURL = item as? URL {
                        url = directURL
                    }
                    if let validURL = url {
                        DispatchQueue.main.async {
                            DockStore.shared.addDroppedURLs([validURL], toDock: dockID, intoFolderID: folder.id)
                        }
                    }
                }
            }
            return true
        }
    }
    
    private func removeAppFromFolder(appID: UUID) {
        guard let dIdx = store.docks.firstIndex(where: { $0.id == dockID }),
              let eIdx = store.docks[dIdx].elements.firstIndex(where: { $0.id == folder.id }),
              case .folder(var updated) = store.docks[dIdx].elements[eIdx] else { return }
        updated.apps.removeAll { $0.id == appID }
        store.docks[dIdx].elements[eIdx] = .folder(updated)
    }
}

// MARK: - NSVisualEffectView Wrapper

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
