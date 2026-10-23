# vgui

[English](README.md) | [Русский](README.ru.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Nederlands](README.nl.md) | **Português** | [Polski](README.pl.md)

Uma biblioteca gráfica para a linguagem [V](https://vlang.io) sobre o
[SDL3](https://libsdl.org). A vgui desenha toda a interface sozinha (sem
widgets nativos do sistema), suporta HiDPI, temas, animações e
traduções, e só redesenha as partes da janela que mudaram.

![Montra da vgui, tema escuro](screenshots/showcase-dark.png)

## Funcionalidades

- **Controlos** — Label, Button, CheckBox, RadioButton, ToggleSwitch,
  Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner, ProgressBar,
  Badge, DatePicker, ColorPicker, CurveEditor, ShortcutInput.
- **Widgets complexos** — CodeEditor com realce de sintaxe,
  MarkdownView, ListBox, TableView (modo virtual para milhões de
  linhas), TreeView, PropertyGrid, PlotView, Canvas (desenho com acesso
  direto aos píxeis), ImageView.
- **Contentores** — VBox/HBox, Panel, Grid, Stack, Centered,
  ScrollBox, TabBox, Accordion, Splitter. Disposição sem píxeis: um
  widget recebe o seu tamanho natural ou uma parte do espaço livre
  (`flex`), com `min`, `max` e alinhamento.
- **Menus e sobreposições** — MenuBar com atalhos de teclado,
  MenuButton, ContextMenu, dicas em qualquer widget, notificações,
  diálogos modais.
- **Integração com o sistema** — diálogos nativos de ficheiros e
  pastas, área de notificação, arrastar e largar a partir de outras
  aplicações, janelas sem moldura.
- **Aspeto** — 15 temas incorporados (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — variantes claras e escuras), folhas de estilo ao
  estilo CSS, animações, escala da interface.
- **Tudo incluído** — ícones Lucide e tipos de letra Roboto embutidos
  no binário, tradução da interface (`vgui.i18n`), desfazer/refazer,
  descrição compacta de interfaces `.vui`.
- **Testes** — `testkit.v`: entrada sintética e instantâneos da
  renderização; os testes correm sem ecrã.

## Capturas de ecrã

A mesma janela ([`examples/59_showcase.v`](examples/59_showcase.v)) com
os temas Light e Monokai; o tema muda-se em tempo real.

![Tema claro](screenshots/showcase-light.png)

![Tema Monokai](screenshots/showcase-monokai.png)

Uma aplicação real feita com a vgui é o
[vraw](https://github.com/Mintormo/vraw), um revelador de fotografias
RAW:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Início rápido

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

`box.add(w)` dá ao widget o seu tamanho natural; `box.add(w, flex: 1)`,
uma parte do espaço livre; existem também `min:`, `max:` e `align:`.
Uma janela sem tamanho explícito ajusta-se ao conteúdo.

## Compilação e dependências

A vgui é um módulo em código-fonte: não há nada para compilar à parte,
a biblioteca é compilada juntamente com o seu programa. A plataforma
principal é o Linux (testado no Ubuntu 24.04). Os programas para
Windows são compilados de forma cruzada no Linux (é assim que é feita a
versão Windows do vraw); compilar diretamente no Windows com o MSYS2
deverá funcionar, mas ainda não foi testado. Existe um ramo para macOS,
não testado.

| Componente | Versão | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| Compilador V | 0.5.2 (a1c9e93) ou mais recente | a partir do código-fonte (passo 3) | a partir do código-fonte |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | a partir do código-fonte (passo 2), ainda não está nos repositórios | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | a partir do código-fonte (passo 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | a partir do código-fonte (passo 2) | `mingw-w64-x86_64-sdl3-image` |

A vgui só compila com o gcc (`-cc gcc`).

### Linux

**1. Pacotes do sistema** — compilador e bibliotecas com que o SDL3 é
compilado:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

No Fedora, Arch e noutras distribuições instale as mesmas bibliotecas
com o respetivo gestor de pacotes. Se ele já tiver SDL3, SDL3_ttf e
SDL3_image 3.4 ou mais recentes (com pacotes `-devel`/`-dev`), salte o
passo 2.

**2. SDL3, SDL3_ttf, SDL3_image** — compiladas a partir do código-fonte
e instaladas em `/usr/local`:

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

**3. Compilador V:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** A raiz do repositório é o próprio módulo `vgui`; o V
encontra-o através de `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Compilação cruzada no Linux.** Instale o MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) e coloque as versões para
Windows do SDL3, SDL3_ttf e SDL3_image (cabeçalhos, bibliotecas de
importação e DLL dos pacotes MSYS2 `mingw64`) num prefixo, por exemplo
`~/soft/mingw64`. Depois:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Coloque ao lado do exe as DLL de `$pfx/bin` de que ele precisa. Um
exemplo completo e funcional — descarregar os pacotes MSYS2
(`tools/win_deps.py`) e reunir as DLL (`tools/windows.sh`) — está no
repositório [vraw](https://github.com/Mintormo/vraw).

**Diretamente no MSYS2 (ainda não testado).** Instale o
[MSYS2](https://www.msys2.org), abra o terminal **MSYS2 MINGW64** e
execute:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Exemplos

[`examples/`](examples) contém 58 pequenos programas, um por widget ou
funcionalidade (a interface deles está em russo), e ainda
[`59_showcase.v`](examples/59_showcase.v) com tudo numa só janela.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # um exemplo
PATH=~/soft/v:$PATH examples/build.sh          # compilar todos em examples/bin/
```

## Testes

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Não é preciso ecrã: o SDL funciona com o controlador `dummy`.

## Documentação

O código está comentado em pormenor: cada ficheiro começa com um
cabeçalho que o descreve. As notas de conceção estão em russo:
[PROJECT.md](PROJECT.md) — como funciona cada subsistema (disposição,
invalidação, renderização, foco, sobreposições, threads, temas, i18n) e
porquê, [ROADMAP.md](ROADMAP.md) — o plano de desenvolvimento,
[docs/](docs) — auditorias e revisões.

## Feito com Claude Code

A vgui foi criada com vibe coding: escrita em conjunto com o
[Claude Code](https://claude.com/claude-code), o assistente de
programação com IA da Anthropic.

## Licença

[MIT](LICENSE). Os recursos de terceiros em `assets/` estão sob as suas
próprias licenças: tipos de letra Roboto — Apache License 2.0, tipos de
letra DejaVu — licença Bitstream Vera, ícones Lucide — ISC.
