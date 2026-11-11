# 🧲 MultiDock Pro for macOS

**MultiDock Pro** é um gerenciador nativo de Docks flutuantes e multi-monitores para macOS, desenvolvido em **Swift**, **SwiftUI** e **AppKit (`NSPanel`)**. Ele permite criar múltiplos Docks independentes ou lado a lado, agrupar softwares por categorias inteligentes (Adobe Suite, Microsoft Office, Google Workspace, Edição de Vídeo, etc.) e controlar exatamente o que aparece em cada monitor conectado.

---

## ✨ Principais Funcionalidades

1. **Pastas Inteligentes de Softwares (App Stacks / Categorias):**
   - Agrupe softwares semelhantes (ex: *Photoshop, Illustrator, Premiere, Final Cut, Word, Excel*) dentro de pastas com ícone em mini-grade 2×2 e cor personalizada.
   - **Botão "Abrir Todos":** Inicie todo um fluxo de trabalho (todos os apps de uma pasta) com apenas um clique.
   - Indicador luminoso (`●`) tanto para apps individuais abertos quanto para pastas que possuem algum aplicativo em execução.

2. **Múltiplos Monitores (Espelhado ou Independente por Tela):**
   - Exiba um Dock em **todos os monitores simultaneamente** ou atribua cada Dock a um **monitor específico** (ex: ferramentas de vídeo apenas no monitor secundário).
   - Reconhecimento automático ao conectar ou desconectar monitores externos (`NSApplication.didChangeScreenParametersNotification`).

3. **Múltiplos Docks Lado a Lado & Snap Magnético (`Snap to Next Dock`):**
   - Crie quantos Docks quiser na mesma tela ou na mesma borda.
   - **Ímã entre Docks:** Ao aproximar um Dock de outro, ele se conecta magneticamente mantendo uma margem de `6 px` e evitando sobreposição.

4. **Posicionamento Livre ou Ancorado (`Edge Snap` nas 4 Bordas):**
   - Clique e arraste em **qualquer lugar do fundo do Dock** (ou na alça pontilhada) para posicioná-lo livremente em qualquer ponto do desktop.
   - Encoste em qualquer uma das 4 bordas da tela (*Inferior, Superior, Esquerda, Direita*) para ancorar automaticamente (alternando entre layout horizontal e vertical).

5. **Drag & Drop Total (Finder ↔ Dock):**
   - **Adicionar:** Arraste qualquer aplicativo (`.app`) ou pasta do Finder diretamente para a barra do Dock ou para cima do ícone de uma pasta no Dock.
   - **Reorganizar:** Clique e arraste ícones dentro do próprio Dock para alterar a ordem em tempo real.
   - **Remover:** Puxe qualquer ícone para fora do Dock e solte para eliminá-lo.

6. **Miniaturização Extrema (`16pt` a `84pt`):**
   - Reduza o tamanho dos ícones até `16 pt` para criar barras ultra-compactas ou aumente até `84 pt`.

7. **Área de Proteção de Tela (Dock Protection Zone):**
   - Impede que janelas maximizadas de outros aplicativos cubram a região ancorada do seu Dock (utilizando a API de Acessibilidade do macOS `AXUIElement`) e mantém o Dock visível sobre aplicativos em tela cheia (`.fullScreenAuxiliary`).

8. **Inicialização Automática no Login (`Launch at Login`):**
   - Configura automaticamente um `LaunchAgent` em `~/Library/LaunchAgents/com.dansorrel.MultiDockPro.plist` para iniciar silenciosamente em segundo plano sempre que você ligar o Mac.

---

## 🏗️ Arquitetura do Projeto

```text
MultiDockPro/
├── Package.swift                      # Manifesto Swift Package Manager (macOS 13+)
├── Info.plist                         # Metadados do Bundle macOS e permissões AppleEvents
├── AppIcon.icns                       # Ícone oficial Retina (dois ímãs conectados)
└── Sources/
    ├── MultiDockProApp.swift          # Ciclo de vida do app, Menu Bar item e inicialização
    ├── Models.swift                   # Modelos de dados (DockInstance, AppFolder, AppEntry) e persistência JSON
    ├── DockWindowManager.swift        # Coordenador NSPanel multi-tela, Snap magnético e Área de Proteção AX
    ├── DockBarView.swift              # Interface SwiftUI do Dock, Popover de pastas e Drag & Drop
    ├── SettingsView.swift             # Janela completa de configurações e editor de pastas
    └── LaunchAtLoginManager.swift     # Gerenciador de inicialização automática via LaunchAgent
```

### Onde as configurações ficam salvas?
Todas as suas customizações de Docks, posições, tamanhos e pastas são salvas automaticamente em formato JSON em:
```text
~/Library/Application Support/MultiDockPro/docks_config.json
```

---

## 🚀 Como Compilar e Instalar

### Pré-requisitos
- macOS 13.0 (Ventura) ou superior
- Swift 5.9+ / Xcode Command Line Tools

### Compilando via Terminal

```bash
cd MultiDockPro
swift build -c release
```

### Gerando o Aplicativo `.app` e Instalando em `/Applications`

```bash
mkdir -p "/Applications/MultiDock Pro.app/Contents/MacOS"
mkdir -p "/Applications/MultiDock Pro.app/Contents/Resources"
cp .build/release/MultiDockPro "/Applications/MultiDock Pro.app/Contents/MacOS/MultiDockPro"
cp Info.plist "/Applications/MultiDock Pro.app/Contents/Info.plist"
cp AppIcon.icns "/Applications/MultiDock Pro.app/Contents/Resources/AppIcon.icns"
xattr -cr "/Applications/MultiDock Pro.app"
codesign --force --deep --sign - "/Applications/MultiDock Pro.app"
open "/Applications/MultiDock Pro.app"
```

---

## 🎮 Guia Rápido de Uso

- **Mover um Dock:** Clique e arraste pelo fundo translúcido do Dock ou pela alça lateral (`⠿`).
- **Fazer Snap na Borda:** Solte o Dock próximo ao topo, base, esquerda ou direita do monitor.
- **Grudar Dois Docks Lado a Lado:** Arraste um Dock para perto da extremidade de outro Dock.
- **Adicionar Apps via Finder:** Arraste qualquer `.app` da pasta `/Applications` para cima da barra do Dock ou solte sobre uma pasta do Dock.
- **Reorganizar ou Excluir Ícones:** Arraste o ícone para os lados dentro do Dock para reordenar, ou puxe-o para fora do Dock até aparecer o ícone vermelho de lixeira e solte.
- **Menu Rápido:** Clique com o **botão direito** sobre qualquer Dock ou ícone, ou use o ícone do MultiDock Pro na **Barra de Menus (Menu Bar)** no topo da tela ao lado do relógio.

---

## 📄 Licença

Desenvolvido por **Daniel Sorrentino (@dansorrel)**. Uso livre sob licença MIT.
