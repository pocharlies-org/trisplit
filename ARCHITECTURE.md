# ARCHITECTURE.md — trisplit

Gestor de ventanas en rejilla para macOS, nativo en Swift (v2): cada monitor tiene su rejilla `cols × rows`, las apps se asignan a huecos y se recolocan con un atajo. **No es un componente de DGX ni de LLMs**: es una herramienta personal del Mac que quedó agrupada en la tanda de experimentos. Tronco: **`main`**. Licencia en `LICENSE`.

## Clientes y versiones
- Un único cliente: la app de barra de menú de macOS 13+ (`app/main.swift`; CLI `--selftest`, `--selftest-live`, `--login-item on|off|status`; URLs `trisplit://apply|next|panel`). Panel en `panel.html` (WKWebView).
- Capas: `app/Core/` (lógica pura y testeable: geometría, rejillas, estado/JSON, displayplacer, coexistencia), `app/Engine/` (motor de ventanas sobre Accessibility), `app/Shell/` (AppKit: menú, atajos, HUD, panel). `legacy/` es la v1 en Hammerspoon (Lua), solo para rollback (`docs/ROLLBACK.md`, tag `v1-hammerspoon`).

## Dependencias (ambos sentidos)
- **De**: Command Line Tools (`swiftc`), permiso de **Accesibilidad**, `displayplacer` (opcional, `brew`), `SMAppService` (login item). Estado en `~/Library/Application Support/trisplit/trisplit.json` (se importa una vez desde `~/.hammerspoon/trisplit.json`) y log en `~/Library/Logs/Trisplit/trisplit.log`.
- **Quién depende**: nadie. Sin relación con `dgx-infra`, LiteLLM ni los Sparks.

## Stack
Swift 5 compilado con `swiftc` (sin Xcode project ni paquetes de terceros), AppKit, WebKit, HTML/JS para el panel. No se usa: XCTest (el test del núcleo es un `swiftc` propio), Hammerspoon en v2 (si v1 está activo, v2 no registra sus atajos para no duplicarlos; `TRISPLIT_FORCE_HOTKEYS=1` lo fuerza).

## Componentes compartidos (canónicos)
Ninguno externo. La lógica de rejillas y estado vive solo en `app/Core/`; la UI no la reimplementa.

## Cómo se construye aquí
`make build` (`build.sh`), `make install` (copia a `~/Applications/Trisplit.app` y verifica la firma), `make cert` (identidad autofirmada `trisplit dev` en un llavero propio: con firma ad-hoc cada recompilación pierde el permiso de Accesibilidad). La lógica nueva va en `Core/` con test; AppKit en `Shell/`.

## Tests y validaciones
`make unit` (Core, sin XCTest), `make panel` (panel en WKWebView headless con `tests/panel_tests.js`), `make test` (ambos) y `make live` (selftest contra el escritorio real). Fixtures en `tests/fixtures/`.

## CI/CD y despliegue
No hay CI (no existe `.github/`) ni despliegue: se compila e instala a mano en el Mac. No pasa por ArgoCD ni por el runner `nexus-mac`.

## Decisiones y trampas
- Resultado vigente: v2 nativa en uso desde 23-09-2026; v1 Hammerspoon conservada para rollback.
- Fuera de alcance de las tandas DGX: propuesta (C5) para sacarlo de ellas; `legacy/` puede borrarse cuando acabe la ventana de rollback.
- No toca los Sparks: no aplica la regla de `gpu-arbiter-state`.
