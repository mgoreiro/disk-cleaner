# Disk Cleaner

Aplicación nativa de macOS (SwiftUI) que dibuja un mapa del espacio ocupado en un disco, permite navegar por las carpetas, seleccionar elementos y borrarlos, y sugiere qué se puede eliminar.

Requiere macOS 14 o superior.

## Funciones

- **Selector de unidades**: desplegable con los volúmenes conectados (internos, externos y de red) más «Otra carpeta…» para analizar una carpeta concreta.
- **Escaneo**: recorre el disco en paralelo, mide el espacio realmente asignado, no sigue enlaces simbólicos, no cruza a otros volúmenes y cuenta una sola vez los hard links. Se puede cancelar.
- **Navegación** con dos vistas:
  - *Lista*: tabla ordenable (nombre, tamaño, % de la carpeta, nº de elementos, fecha).
  - *Mapa*: treemap donde el área de cada rectángulo es proporcional a su tamaño. Doble clic abre carpetas.
- **Selección múltiple** (⌘ o ⇧) y borrado con confirmación: a la papelera o definitivo. Tras borrar se actualizan árbol, listas, sugerencias y espacio libre sin reescanear.
- **Panel lateral**:
  - *Sugerencias*: candidatos a eliminar con etiqueta de riesgo (Seguro / Revisar / Precaución) y espacio recuperable.
  - *Carpetas*: las que más ocupan; por defecto oculta las «contenedoras» (las que solo contienen a otra mayor).
  - *Ficheros*: los 200 más grandes.
- Atajos: ⌘R analizar, ⌘↑ carpeta superior, Supr borrar la selección.

## Qué sugiere eliminar

Heurísticas en [`Analyzer.swift`](Sources/DiskCleaner/Analyzer.swift):

| Riesgo | Ejemplos |
|---|---|
| Seguro | Papelera, `~/Library/Caches/*` (≥ 50 MB), logs, Xcode DerivedData e iOS DeviceSupport, cachés de npm/Gradle/`~/.cache` |
| Revisar | `node_modules`, `.build`, `target`, `Pods`, `.venv` (con su proyecto detectado), Xcode Archives, simuladores, `.dmg`/`.pkg`/`.iso`, comprimidos > 200 MB, logs grandes, ficheros > 1 GB sin modificar en un año |
| Precaución | Copias de seguridad de iOS, datos de Docker Desktop |

Son sugerencias heurísticas: revisa cada elemento antes de borrarlo.

## Seguridad al borrar

- Por defecto se ofrece mover a la papelera (recuperable); el espacio no se libera hasta vaciarla.
- Se rechaza borrar `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, tu carpeta personal y las carpetas de primer nivel del volumen de arranque.
- Si se «elimina» la papelera, se vacía su contenido sin borrar la carpeta.

## Permisos

Para ver todo el espacio hay que conceder **Acceso total al disco** a Disk Cleaner (Ajustes del Sistema → Privacidad y seguridad). Sin él, las carpetas protegidas no se pueden leer; la app lo avisa y ofrece abrir los ajustes.

La app va firmada ad-hoc, así que macOS puede pedir de nuevo el permiso tras cada recompilación o actualización. Con un certificado propio se evita: `SIGN_ID="<identidad>" ./build.sh`.

Al abrir el DMG por primera vez (app sin notarizar): clic derecho → Abrir.

## Compilar

```bash
./build.sh          # genera build/DiskCleaner.app
./Scripts/make-dmg.sh   # genera build/DiskCleaner-<versión>.dmg
```

Requiere Xcode/Swift 5.10+. El icono se regenera con `swift Scripts/make-icon.swift`.

## Estructura

```
Package.swift
build.sh                     Compila y empaqueta el .app
Resources/                   Info.plist, AppIcon.icns
Scripts/                     make-icon.swift, make-dmg.sh
Sources/DiskCleaner/
  DiskCleanerApp.swift       Punto de entrada y menú «Disco»
  AppModel.swift             Estado: volúmenes, escaneo, navegación, borrado
  Scanner.swift              Escáner POSIX concurrente (opendir/fstatat)
  FileNode.swift             Árbol de ficheros y actualización de tamaños al borrar
  Analyzer.swift             Rankings de carpetas/ficheros y sugerencias
  NodeUI.swift               Formato, iconos/colores y algoritmo treemap (squarified)
  ContentView.swift          Ventana, barra de volumen, avisos, diálogo de borrado
  BrowserView.swift          Vista lista y vista mapa
  SidePanel.swift            Sugerencias, carpetas y ficheros
```

## Decisiones de diseño

- En el disco de arranque se escanea el volumen de datos (`/System/Volumes/Data`), donde vive el contenido del usuario; el volumen de sistema es de solo lectura.
- Tamaño = bloques asignados (`st_blocks × 512`), como Finder; por eso puede diferir del tamaño lógico.
- El árbol completo se mantiene en memoria (~1,2 M de nodos en un disco de 245 GB).
- Los borrados actualizan el árbol en sitio (resta tamaños a los ancestros) en lugar de reescanear.
