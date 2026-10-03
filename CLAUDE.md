# CLAUDE.md — Trisplit

Gestor de ventanas en rejilla para macOS, nativo en Swift (rejilla por monitor, configuraciones con nombre, panel y atajos globales). Ver ARCHITECTURE.md.

## Regla de versión (obligatoria en cada release)

Cuando subas de versión (bump de `VERSION` + tag + GitHub release), SIEMPRE, en el mismo turno:

1. **CHANGELOG.md**: añade la entrada de la nueva versión arriba (formato Keep a Changelog, en español): qué hay nuevo, qué se arregló, qué cambia para el usuario. Sin entradas vacías: cada bullet, un cambio real del diff.
2. **Release de GitHub**: `gh release create vX.Y.Z --generate-notes` y luego reescribir las notas con el texto del changelog (las notas generadas solas no valen).
3. **Noticia en la web**: abrir PR en `pocharlies-org/k8s-web-pocharlies` que actualice la página del producto `src/pages/apps/trisplit` (ES y EN) con una noticia de la nueva versión: título, 2-3 bullets de lo nuevo y enlace de descarga (`brew install --cask pocharlies-org/tap/trisplit`). Si la página no existe todavía, es que la épica SC-1695 aún no se implementó: omite el paso sin bloquear el release.

Nunca taggear sin changelog. Nunca release sin noticia en la web (salvo el caso del punto 3).

## Distribución

- Homebrew tap: `pocharlies-org/homebrew-tap` (cask `trisplit`).
- La web pública es www.e-dani.com (repo k8s-web-pocharlies, GitOps con ArgoCD; nunca push directo al tronco).
