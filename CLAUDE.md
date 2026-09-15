# BMP Native — Brotherhood Marketing Prompts (SwiftUI)

Port nativo (Swift 5 / SwiftUI, macOS 14+) de la app Electron en `../Brotherhood Prompt`. **Solo modo Image** (Video removido 2026-09-15 por decisión de producto). Misma lógica de CLIs, UI rediseñada: controles nativos de macOS, dos columnas, una paleta, un acento.

**Proyecto:** generado con XcodeGen desde `project.yml` → `xcodegen generate` produce `BMP.xcodeproj` (no se commitea; regenerar tras tocar `project.yml` o agregar archivos fuera de `BMP/`).
**Build:** `xcodebuild -project BMP.xcodeproj -scheme BMP -configuration Release build` · o abrir `BMP.xcodeproj` en Xcode y ⌘R.
**Requisitos de runtime:** `claude` CLI (`~/.local/bin`) y `higgsfield` CLI (`npm i -g @higgsfield/cli`) — se resuelven contra `Shell.searchPath`, no contra el PATH del shell.

## Estructura
```
BMP/App/        BMPApp (entry, window chrome), AppModel (@Observable, todo el estado), Types
BMP/Core/       Shell (subprocesos), Prefs, MemoryStore, Staging, Lock (PBKDF2), Downloader
BMP/Services/   HiggsfieldService (generate/poll/upload/auth), ClaudeService (prompt), Prompts (SYSTEM_PROMPT)
BMP/UI/         Theme (paleta/tipografía), Components (Controls, DropZone, Panels), Screens (MainView = inputs+output+fire bar, Sheets = Settings/History/Login, Lock)
```

## Compatibilidad con la app Electron
- Lee/escribe los MISMOS archivos en `~/Library/Application Support/BMP/`: `bmp-memory.json` (historial de prompts, mismo shape, timestamps en ms) y `bmp-prefs.json` (outputPath, authFailCount, authLockUntil). El historial y la carpeta de salida se comparten.
- `Prompts.system` debe mantenerse byte-idéntico al `SYSTEM_PROMPT` de `../Brotherhood Prompt/electron/main.ts` — si cambia uno, cambiar el otro.
- Bundle id distinto (`com.brotherhood.bmp.native`) para convivir con la .app Electron.
- Lock: PBKDF2-SHA512 (200k iter) en vez de scrypt (Swift no lo trae). Misma passphrase; hash/salt en `Lock.swift`, regenerar con el comando del comentario.

## Decisiones de diseño (skills minimalist-ui / redesign, adaptadas a macOS nativo)
- **Nativo primero**: titlebar estándar con título/subtítulo y toolbar unificada (History · Reset · Settings), `HSplitView` redimensionable, `Picker(.segmented)` para engine/ratio/resolución/variaciones, botones `.borderedProminent` con tint de acento, `Settings` scene (⌘,) con `Form(.grouped)`, sheet de historial con `List` + preview, menú **Prompt** con atajos (⌘↩ generar, ⌘⇧↩ disparar, ⌘Y historial, ⌘R reset, ⌘⇧O carpeta de salida, ⌘⇧C copiar prompt).
- **Esencia que se conserva**: paleta cálida-oscura (`Theme`: bg `#0B0B0A`, surface `#111110`, hairlines white 7%), logo Brotherhood (`Logo.imageset` SVG template, `BrandMark`) en splash de arranque (`SplashView`, ~1.1 s), lock screen y empty state, acento naranja Brotherhood `#F54F1B` solo en acción principal/loading/★ (era oro, cambiado 2026-09-15), eyebrows en small caps con tracking, SF Mono para metadata/log/footer, cards con hairline, sin sombras ni gradientes. `titlebarAppearsTransparent` + `backgroundColor` = Theme.bg para que la ventana sea una sola superficie.
- Motion: una sola curva (`Theme.ease`, cubic-bezier 0.32/0.72/0/1, 220ms); pulso solo en el dot de tarea activa.

## Lo que NO está (vs Electron)
- Modo Video (Seedance) — removido a propósito.
- Auto-update (electron-updater) y selector de ícono del Dock.

## Rendimiento (v2.0.1)
- **Nada de `repeatForever` en SwiftUI**: una sola animación infinita mantiene todo el view graph re-renderizando a 60–120 Hz (~45 % CPU medido). El dot de tarea activa es `PulseDot` (`Controls.swift`), un `NSView` con `CABasicAnimation` de opacidad — el render server hace el fade, el main thread no trabaja.
- `LockScreen` solo corre su tick de 250 ms mientras hay lockout (`.task(id: lockUntil)`); en reposo no hay timer.
- `Shell.run` lee stdout/stderr con `readabilityHandler` (sin hilos GCD bloqueados en `readDataToEndOfFile`); `process.qualityOfService = .userInitiated`.
- Polling de Higgsfield: 2 s → 3 s los primeros 45 s → 5 s después (cada poll es un proceso + TLS).
- `Thumbs` (DropZone): `NSCache` con `totalCostLimit` (48 MB) y decodificación en función `nonisolated async` (cooperative pool, nunca main); respeta cancelación de `.task`.
- `AppModel.push` hace append in-place con recorte a `logCap` (antes copiaba el array por línea).
- `DEAD_CODE_STRIPPING: YES`; Release ya compila `-O` wholemodule.
- Para medir: `ps -o rss=,time=,%cpu= -p <pid>` a intervalos (el `time` acumulado debe quedarse plano en reposo) y `sample <pid> 3` si sube — buscar `NSAnimationContext runAnimationGroup` / `ViewGraphRootValueUpdater.render` en el stack.
