import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store = DockStore.shared
    @State private var selectedFolderID: UUID?
    @State private var showingNewFolderSheet = false
    @State private var newFolderName = ""
    @State private var newFolderSymbol = "folder.fill"
    @State private var newFolderColor = "#007AFF"
    @State private var axPermissionGranted = DockWindowManager.shared.isAccessibilityGranted
    @State private var launchAtLogin = LaunchAtLoginManager.shared.isEnabled
    
    private let presetSymbols = [
        "folder.fill", "paintbrush.pointed.fill", "film.stack.fill",
        "doc.richtext.fill", "globe.americas.fill", "hammer.fill",
        "music.note.list", "gamecontroller.fill", "terminal.fill",
        "camera.aperture", "cpu.fill", "sparkles"
    ]
    
    private let presetColors = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#00C7BE", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55"
    ]
    
    var body: some View {
        NavigationSplitView {
            // LEFT SIDEBAR: List of Docks
            VStack(spacing: 0) {
                List(selection: $store.selectedDockID) {
                    Section("Meus Docks Flutuantes") {
                        ForEach(store.docks) { dock in
                            HStack {
                                Circle()
                                    .fill(dock.isEnabled ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dock.name)
                                        .font(.body.weight(.medium))
                                    Text(dock.snapEdge.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tag(dock.id)
                        }
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Button {
                        addNewDock(sideBySide: false)
                    } label: {
                        Label("Novo Dock", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button {
                        addNewDock(sideBySide: true)
                    } label: {
                        Label("Ao Lado", systemImage: "rectangle.split.2x1")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Cria outro Dock conectado magneticamente ao lado do Dock atual")
                    
                    Spacer()
                    
                    if store.docks.count > 1, let selID = store.selectedDockID {
                        Button(role: .destructive) {
                            store.docks.removeAll { $0.id == selID }
                            store.selectedDockID = store.docks.first?.id
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 280)
        } detail: {
            if let selID = store.selectedDockID,
               let dockIdx = store.docks.firstIndex(where: { $0.id == selID }) {
                dockDetailEditor(dock: $store.docks[dockIdx])
            } else {
                Text("Selecione ou crie um Dock na barra lateral.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 880, minHeight: 610)
        .onAppear {
            axPermissionGranted = DockWindowManager.shared.isAccessibilityGranted
        }
    }
    
    // MARK: - Detail Editor for Selected Dock
    
    @ViewBuilder
    private func dockDetailEditor(dock: Binding<DockInstance>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header & Status
                HStack {
                    TextField("Nome do Dock", text: dock.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.bold())
                        .frame(maxWidth: 320)
                    
                    Toggle("Ativo", isOn: dock.isEnabled)
                        .toggleStyle(.switch)
                    
                    Divider().frame(height: 22)
                    
                    Toggle("Iniciar com o Mac", isOn: Binding(
                        get: { launchAtLogin },
                        set: { val in
                            launchAtLogin = val
                            LaunchAtLoginManager.shared.setEnabled(val)
                        }
                    ))
                    .toggleStyle(.switch)
                    .help("Abre o MultiDock Pro automaticamente sempre que você ligar ou fizer login no Mac")
                    
                    Spacer()
                    
                    Button {
                        hideOrShowNativeMacDock()
                    } label: {
                        Label("Alternar Auto-Hide do Dock da Apple", systemImage: "menubar.dock.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .help("Ativa/Desativa ocultar automaticamente o Dock original do macOS")
                }
                
                // Position, Magnetic Snap & Screen Protection Card
                GroupBox(label: Label("Telas (Monitores), Snap Magnético e Área de Proteção", systemImage: "display.2")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            Toggle("Mostrar em TODOS os monitores simultaneamente", isOn: dock.showOnAllScreens)
                            
                            if !dock.wrappedValue.showOnAllScreens {
                                Picker("Monitor Específico:", selection: Binding(
                                    get: { dock.wrappedValue.targetScreenName ?? NSScreen.screens.first?.localizedName ?? "Principal" },
                                    set: { dock.wrappedValue.targetScreenName = $0 }
                                )) {
                                    ForEach(NSScreen.screens, id: \.localizedName) { screen in
                                        Text(screen.localizedName).tag(screen.localizedName)
                                    }
                                }
                                .frame(maxWidth: 280)
                            }
                        }
                        
                        Divider()
                        
                        HStack(spacing: 20) {
                            Picker("Modo de Ancoragem (Snap):", selection: dock.snapEdge) {
                                ForEach(SnapEdge.allCases) { edge in
                                    Text(edge.rawValue).tag(edge)
                                }
                            }
                            .frame(maxWidth: 290)
                            
                            Toggle("Snap Magnético entre Docks (Evitar sobreposição)", isOn: dock.snapToOtherDocks)
                            Toggle("Bloquear Posição", isOn: dock.isLocked)
                            Toggle("Auto-Ocultar", isOn: dock.autoHide)
                        }
                        
                        // Screen Protection Zone Controls
                        HStack(spacing: 14) {
                            Toggle("Área de Proteção (Impedir que janelas maximizadas fiquem sobre o Dock)", isOn: dock.reserveScreenSpace)
                            
                            Spacer()
                            
                            if dock.wrappedValue.reserveScreenSpace {
                                if axPermissionGranted {
                                    Label("Proteção Ativa", systemImage: "checkmark.shield.fill")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                } else {
                                    Button {
                                        let granted = DockWindowManager.shared.requestAccessibilityPermissionForProtectionZone()
                                        axPermissionGranted = granted
                                    } label: {
                                        Label("Autorizar Permissão de Janelas (Acessibilidade)", systemImage: "lock.shield")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        if dock.wrappedValue.snapEdge != .free {
                            HStack {
                                Text("Deslocamento Lateral (ou simplesmente clique e arraste o Dock com o mouse):")
                                    .font(.caption)
                                Slider(value: dock.edgeOffsetPages, in: -650...650, step: 8)
                                Text("\(Int(dock.wrappedValue.edgeOffsetPages)) px")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 55)
                                Button("Centralizar") {
                                    dock.wrappedValue.edgeOffsetPages = 0
                                }
                                .controlSize(.small)
                            }
                        } else {
                            Text("Modo Flutuante Livre — Clique e arraste em qualquer parte do fundo do Dock para movê-lo ou encostá-lo em uma borda/outro Dock!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        HStack(spacing: 24) {
                            HStack {
                                Text("Tamanho dos Ícones (16pt a 84pt):")
                                Slider(value: dock.iconSize, in: 16...84, step: 2)
                                Text("\(Int(dock.wrappedValue.iconSize)) pt")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 42)
                            }
                            
                            HStack {
                                Text("Opacidade do Fundo:")
                                Slider(value: dock.opacity, in: 0.2...1.0, step: 0.05)
                                Text("\(Int(dock.wrappedValue.opacity * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 42)
                            }
                        }
                    }
                    .padding(10)
                }
                
                // Elements & Smart Folders Editor
                GroupBox(label: Label("Pastas Inteligentes e Aplicativos (Suporta Drag & Drop Direto no Dock!)", systemImage: "square.grid.2x2.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button {
                                newFolderName = "Nova Pasta (ex: Adobe / Vídeo)"
                                showingNewFolderSheet = true
                            } label: {
                                Label("Criar Pasta de Categoria", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                pickApplicationFromFinder { app in
                                    dock.wrappedValue.elements.append(.app(app))
                                }
                            } label: {
                                Label("Adicionar App Direto ao Dock", systemImage: "app.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Text("Você também pode arrastar apps (.app) do Finder direto para o Dock, reordenar arrastando ou puxar para fora para remover!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        HStack(alignment: .top, spacing: 16) {
                            // Left list: Elements in this Dock
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Itens no Dock (\(dock.wrappedValue.elements.count)) — Arraste para reordenar")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                
                                List {
                                    ForEach(Array(dock.wrappedValue.elements.enumerated()), id: \.element.id) { index, element in
                                        HStack {
                                            switch element {
                                            case .app(let a):
                                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.bundlePath))
                                                    .resizable()
                                                    .frame(width: 24, height: 24)
                                                Text(a.name)
                                                Spacer()
                                                Text("App")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                            case .folder(let f):
                                                Image(systemName: f.iconSymbol)
                                                    .foregroundColor(Color(hex: f.colorHex))
                                                    .frame(width: 24, height: 24)
                                                VStack(alignment: .leading) {
                                                    Text(f.name).fontWeight(.semibold)
                                                    Text("\(f.apps.count) softwares")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Button("Editar Pasta") {
                                                    selectedFolderID = f.id
                                                }
                                                .controlSize(.small)
                                            }
                                            
                                            Button(role: .destructive) {
                                                dock.wrappedValue.elements.remove(at: index)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .onMove { indices, newOffset in
                                        dock.wrappedValue.elements.move(fromOffsets: indices, toOffset: newOffset)
                                    }
                                }
                                .frame(minHeight: 230)
                            }
                            .frame(width: 330)
                            
                            // Right pane: Folder Contents Editor
                            VStack(alignment: .leading, spacing: 8) {
                                if let fID = selectedFolderID,
                                   let elemIdx = dock.wrappedValue.elements.firstIndex(where: { $0.id == fID }),
                                   case .folder(let folder) = dock.wrappedValue.elements[elemIdx] {
                                    
                                    folderEditorView(folder: folder) { updatedFolder in
                                        dock.wrappedValue.elements[elemIdx] = .folder(updatedFolder)
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "folder.fill.badge.gearshape")
                                            .font(.system(size: 34))
                                            .foregroundColor(.secondary)
                                        Text("Clique em \"Editar Pasta\" ao lado de qualquer pasta para adicionar seus softwares, ou simplesmente arraste aplicativos (.app) do Finder para cima do ícone da pasta no próprio Dock!")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 20)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 230)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(10)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingNewFolderSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Criar Nova Pasta de Softwares")
                    .font(.headline)
                
                TextField("Nome da Pasta (ex: Adobe, Edição de Vídeo, Microsoft)", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                
                Text("Ícone da Pasta:")
                    .font(.caption.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38))], spacing: 8) {
                    ForEach(presetSymbols, id: \.self) { sym in
                        Button {
                            newFolderSymbol = sym
                        } label: {
                            Image(systemName: sym)
                                .font(.title3)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(newFolderSymbol == sym ? Color.accentColor.opacity(0.25) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text("Cor da Pasta:")
                    .font(.caption.bold())
                HStack(spacing: 10) {
                    ForEach(presetColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: newFolderColor == hex ? 3 : 0)
                            )
                            .onTapGesture {
                                newFolderColor = hex
                            }
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Cancelar") {
                        showingNewFolderSheet = false
                    }
                    Button("Criar Pasta") {
                        let folder = AppFolder(
                            name: newFolderName.isEmpty ? "Pasta" : newFolderName,
                            iconSymbol: newFolderSymbol,
                            colorHex: newFolderColor,
                            apps: []
                        )
                        dock.wrappedValue.elements.append(.folder(folder))
                        selectedFolderID = folder.id
                        showingNewFolderSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
    
    // MARK: - Folder Apps Editor
    
    @ViewBuilder
    private func folderEditorView(folder: AppFolder, onUpdate: @escaping (AppFolder) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: folder.iconSymbol)
                    .foregroundColor(Color(hex: folder.colorHex))
                TextField("Nome da Pasta", text: Binding(
                    get: { folder.name },
                    set: { newName in
                        var copy = folder
                        copy.name = newName
                        onUpdate(copy)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                
                Spacer()
                
                Button {
                    pickMultipleApplicationsFromFinder { apps in
                        var copy = folder
                        for app in apps where !copy.apps.contains(where: { $0.bundlePath == app.bundlePath }) {
                            copy.apps.append(app)
                        }
                        onUpdate(copy)
                    }
                } label: {
                    Label("Adicionar Softwares (.app)", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            List {
                ForEach(Array(folder.apps.enumerated()), id: \.element.id) { idx, app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading) {
                            Text(app.name)
                                .fontWeight(.medium)
                            Text(app.bundlePath)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            var copy = folder
                            copy.apps.remove(at: idx)
                            onUpdate(copy)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { indices, newOffset in
                    var copy = folder
                    copy.apps.move(fromOffsets: indices, toOffset: newOffset)
                    onUpdate(copy)
                }
            }
            .frame(minHeight: 190)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
    }
    
    // MARK: - Helpers
    
    private func addNewDock(sideBySide: Bool) {
        let count = store.docks.count + 1
        var newDock = DockInstance(
            name: sideBySide ? "Dock Lateral #\(count)" : "Dock #\(count)",
            isEnabled: true,
            targetScreenName: NSScreen.screens.first?.localizedName,
            showOnAllScreens: false,
            snapEdge: .bottom,
            edgeOffsetPages: sideBySide ? Double(count * 160) : 0,
            freePositionX: 300,
            freePositionY: 120,
            iconSize: 44,
            opacity: 0.90,
            elements: [
                .folder(AppFolder(name: "Nova Categoria", iconSymbol: "folder.fill", colorHex: "#007AFF", apps: []))
            ]
        )
        if sideBySide, let currentID = store.selectedDockID, let current = store.docks.first(where: { $0.id == currentID }) {
            newDock.snapEdge = current.snapEdge
            newDock.targetScreenName = current.targetScreenName
            newDock.edgeOffsetPages = current.edgeOffsetPages + 220
        }
        store.docks.append(newDock)
        store.selectedDockID = newDock.id
    }
    
    private func pickApplicationFromFinder(completion: @escaping (AppEntry) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Escolher Aplicativo (.app)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.deletingPathExtension().lastPathComponent
            let bundle = Bundle(url: url)
            completion(AppEntry(name: name, bundlePath: url.path, bundleIdentifier: bundle?.bundleIdentifier))
        }
    }
    
    private func pickMultipleApplicationsFromFinder(completion: @escaping ([AppEntry]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Selecione um ou vários Aplicativos (.app)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            let entries = panel.urls.map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let bundle = Bundle(url: url)
                return AppEntry(name: name, bundlePath: url.path, bundleIdentifier: bundle?.bundleIdentifier)
            }
            completion(entries)
        }
    }
    
    private func hideOrShowNativeMacDock() {
        let script = """
        tell application "System Events"
            tell dock preferences
                set autohide to not autohide
            end tell
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var errorDict: NSDictionary? = nil
            appleScript.executeAndReturnError(&errorDict)
        }
    }
}
