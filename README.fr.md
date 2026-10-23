# vgui

[English](README.md) | [Русский](README.ru.md) | [Deutsch](README.de.md) | **Français** | [Español](README.es.md) | [Italiano](README.it.md) | [Nederlands](README.nl.md) | [Português](README.pt.md) | [Polski](README.pl.md)

Une bibliothèque d'interface graphique pour le langage
[V](https://vlang.io), basée sur [SDL3](https://libsdl.org). vgui dessine
toute l'interface elle-même (sans widgets natifs du système), prend en
charge le HiDPI, les thèmes, les animations et les traductions, et ne
redessine que les parties de la fenêtre qui ont changé.

![Vitrine vgui, thème sombre](screenshots/showcase-dark.png)

## Fonctionnalités

- **Contrôles** — Label, Button, CheckBox, RadioButton, ToggleSwitch,
  Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner, ProgressBar,
  Badge, DatePicker, ColorPicker, CurveEditor, ShortcutInput.
- **Widgets complexes** — CodeEditor avec coloration syntaxique,
  MarkdownView, ListBox, TableView (mode virtuel pour des millions de
  lignes), TreeView, PropertyGrid, PlotView, Canvas (dessin avec accès
  direct aux pixels), ImageView.
- **Conteneurs** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Mise en page sans pixels : un widget
  reçoit sa taille naturelle ou une part de l'espace libre (`flex`),
  avec `min`, `max` et alignement.
- **Menus et superpositions** — MenuBar avec raccourcis clavier,
  MenuButton, ContextMenu, infobulles sur tout widget, notifications,
  boîtes de dialogue modales.
- **Intégration au système** — dialogues natifs de fichiers et de
  dossiers, zone de notification, glisser-déposer depuis d'autres
  applications, fenêtres sans bordure.
- **Apparence** — 15 thèmes intégrés (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — variantes claires et sombres), feuilles de style
  de type CSS, animations, mise à l'échelle de l'interface.
- **Tout inclus** — icônes Lucide et polices Roboto intégrées au
  binaire, traduction de l'interface (`vgui.i18n`), annuler/rétablir,
  description compacte d'interface `.vui`.
- **Tests** — `testkit.v` : saisie synthétique et instantanés du rendu ;
  les tests tournent sans écran.

## Captures d'écran

La même fenêtre ([`examples/59_showcase.v`](examples/59_showcase.v))
avec les thèmes Light et Monokai ; le thème se change à la volée.

![Thème clair](screenshots/showcase-light.png)

![Thème Monokai](screenshots/showcase-monokai.png)

Une vraie application construite avec vgui :
[vraw](https://github.com/Mintormo/vraw), un développeur de photos RAW :

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Démarrage rapide

```v
module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Hello')!

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)

	mut counter := vgui.label('Clicks: 0')
	mut clicks := 0
	mut btn := vgui.button('Click me')
	btn.on_click = fn [mut counter, mut clicks] () {
		clicks++
		counter.text = 'Clicks: ${clicks}'
	}
	root.add(counter)
	root.add(btn)

	win.add_widget(root)
	app.add_window(win)
	app.run()
}
```

```bash
~/soft/v/v -cc gcc run hello.v
```

`box.add(w)` donne au widget sa taille naturelle, `box.add(w, flex: 1)`
une part de l'espace libre ; il existe aussi `min:`, `max:` et `align:`.
Une fenêtre sans taille explicite s'adapte à son contenu.

## Compilation et dépendances

vgui est un module source : rien à compiler séparément, la bibliothèque
est compilée avec votre programme. La plateforme principale est Linux
(testé sous Ubuntu 24.04). Les programmes Windows sont compilés de façon
croisée sous Linux (c'est ainsi qu'est produite la version Windows de
vraw) ; la compilation directement sous Windows dans MSYS2 devrait
fonctionner, mais n'a pas encore été testée. Une branche macOS est
prévue, mais pas testée.

| Composant | Version | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| Compilateur V | 0.5.2 (a1c9e93) ou plus récent | depuis les sources (étape 3) | depuis les sources |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | depuis les sources (étape 2), pas encore dans les dépôts | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | depuis les sources (étape 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | depuis les sources (étape 2) | `mingw-w64-x86_64-sdl3-image` |

vgui se compile uniquement avec gcc (`-cc gcc`).

### Linux

**1. Paquets système** — compilateur et bibliothèques avec lesquelles
SDL3 est compilée :

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

Sous Fedora, Arch et les autres distributions, installez les mêmes
bibliothèques avec leur gestionnaire de paquets. S'il fournit déjà SDL3,
SDL3_ttf et SDL3_image 3.4 ou plus récents (avec les paquets
`-devel`/`-dev`), passez l'étape 2.

**2. SDL3, SDL3_ttf, SDL3_image** — compilées depuis les sources et
installées dans `/usr/local` :

```bash
mkdir -p ~/src && cd ~/src
for repo in SDL SDL_ttf SDL_image; do
  git clone --depth 1 https://github.com/libsdl-org/$repo
  cmake -S $repo -B $repo/build -DCMAKE_BUILD_TYPE=Release
  cmake --build $repo/build -j"$(nproc)"
  sudo cmake --install $repo/build
done
sudo ldconfig
```

**3. Compilateur V :**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** La racine du dépôt est le module `vgui` lui-même ; V le
trouve via `~/.vmodules` :

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Compilation croisée sous Linux.** Installez MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) et placez les versions
Windows de SDL3, SDL3_ttf et SDL3_image (en-têtes, bibliothèques
d'import et DLL des paquets MSYS2 `mingw64`) dans un préfixe, par
exemple `~/soft/mingw64`. Ensuite :

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Placez à côté de l'exe les DLL de `$pfx/bin` dont il dépend. Un exemple
complet qui fonctionne — téléchargement des paquets MSYS2
(`tools/win_deps.py`) et collecte des DLL (`tools/windows.sh`) — se
trouve dans le dépôt [vraw](https://github.com/Mintormo/vraw).

**Directement dans MSYS2 (pas encore testé).** Installez
[MSYS2](https://www.msys2.org), ouvrez le terminal **MSYS2 MINGW64** et
lancez :

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Exemples

[`examples/`](examples) contient 58 petits programmes, un par widget ou
fonctionnalité, ainsi que
[`59_showcase.v`](examples/59_showcase.v) avec tout dans une seule
fenêtre.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # un exemple
PATH=~/soft/v:$PATH examples/build.sh          # tout compiler dans examples/bin/
```

## Tests

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Aucun écran n'est nécessaire : SDL tourne avec le pilote `dummy`.

## Documentation

Le code est commenté en détail : chaque fichier commence par un
en-tête qui le décrit. Les notes de conception sont en russe :
[PROJECT.md](PROJECT.md) — fonctionnement de chaque sous-système (mise
en page, invalidation, rendu, focus, superpositions, threads, thèmes,
i18n) et raisons des choix, [ROADMAP.md](ROADMAP.md) — plan de
développement, [docs/](docs) — audits et revues.

## Fait avec Claude Code

vgui a été créée en vibe coding : écrite avec
[Claude Code](https://claude.com/claude-code), l'assistant de
programmation IA d'Anthropic.

## Licence

[MIT](LICENSE). Les ressources tierces dans `assets/` relèvent de leurs
propres licences : polices Roboto — Apache License 2.0, polices
DejaVu — licence Bitstream Vera, icônes Lucide — ISC.
