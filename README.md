# urdu-translit

Type Roman English with your normal keyboard, get Urdu script — inside any
application, without opening a browser.

> **Status (checked 2026-09-27):** the tool that exists on this machine is
> `~/.local/bin/urdu-translit` (executable, no `.py` extension) — the
> **selection** tool driven by **SUPER + U**. The live IBus input method
> described further below is planned/documented but **not installed here**:
> `ibus` is not installed, and `~/.local/lib/urdu-translit/`,
> `~/.local/bin/urdu-engine`, `~/.local/bin/urdu-dict-build`,
> `~/.local/share/ibus/component/urdu.xml`,
> `~/.local/share/urdu-translit/dict.json` and the `ibus.service` unit do not
> exist. Only the `SUPER + U` parts of this README apply to the current system.

There are **two tools** described here, but only one is installed:

| | What it does | How you use it | Status here |
|---|---|---|---|
| **Live input method** | Transliterates as you type, like any keyboard layout | Turn it on with the IBus hotkey, then just type | **not installed** (planned) |
| **`SUPER + U`** | Transliterates text you already selected | Select text, press **SUPER + U** | **installed, working** |

When the live input method lands, both will resolve words the same way. For
now `SUPER + U` is the working method, and remains useful for pasting English
into an Urdu sentence even after live typing arrives.

Built for [this Hyprland config](../.config/hypr/) (CachyOS / Arch, Wayland).

---

## Table of contents

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Usage](#usage)
- [Files and where they live](#files-and-where-they-live)
- [How the engine is registered](#how-the-engine-is-registered)
- [Rebuilding the dictionary](#rebuilding-the-dictionary)
- [Running the tests](#running-the-tests)
- [Command-line options](#command-line-options)
- [Personal corrections](#personal-corrections)
- [Caching and offline use](#caching-and-offline-use)
- [Accuracy](#accuracy)
- [Troubleshooting](#troubleshooting)
- [Limitations and caveats](#limitations-and-caveats)
- [How it was built](#how-it-was-built)

---

## Why this exists

The goal was the typing experience on
[engurdu.com](https://engurdu.com/english-to-urdu-typing/) — type Urdu
phonetically in English letters, get proper Urdu script — but natively, with
the system keyboard.

The built-in Linux options were all measured against 25 common Urdu words:

| Option | Correct |
|---|---|
| XKB layout `pk(urd-phonetic)` | **1/25** |
| m17n input method `ur-phonetic` | **2/25** |
| `urdu-translit` (this) | **23/25** top-1, 24/25 top-5 |

Keyboard layouts cannot do this. They map one key to one fixed character, so
they cannot apply:

- **implicit alif** — `salaam` must become سلام, not سالاام
- **retroflex letters** — `theek` must start with ٹ, not ت
- **do-chashmi he** (ھ) vs **goal he** (ہ) — both are typed `h`
- **noon ghunna** (ں) at word endings
- **context** — `dekh` is دیکھ, but `dost` is دوست

Those need word-level logic, which is why this uses a transliteration engine
instead of a layout.

---

## How it works

### Live typing

A Python process holds a bus name that the IBus daemon spawns and addresses.
The daemon asks it, through a Factory, to create an engine; the engine receives
every keystroke in every application and decides what to do with it.

Per keystroke, the engine:

1. maps the key to a character, ignoring `Ctrl`/`Alt`/`Super` combinations so
   shortcuts still work
2. appends it to the current word
3. looks the word up in the dictionary — local file first, so **no network call
   ever happens while you type**
4. shows the top candidate as an inline preedit, replacing the Roman text
5. on space, commits the Urdu and clears the buffer

A word that is not in the dictionary commits as Roman and spawns a *detached*
background process to fetch it. The next time you type it, it is there. Typing
is never blocked on the network.

Only `Shift + Space` needs the candidate list, and it is read from the same local
file.

The dictionary is a plain JSON file, re-read if its modification time changes —
one `stat()` per keystroke, which is cheaper than it sounds and means you can
rebuild the dictionary without restarting anything.

### Selecting text

Pressing **SUPER + U** runs `~/.local/bin/urdu-translit --clip`, which
(current code, `do_clip()`):

1. fires on key **release** (`release = true` on the bind), so `SUPER`/`SHIFT`
   are already up by the time the script runs — a synthetic Ctrl+C sent
   while they are still held arrives with them attached (Super+Ctrl+C, or
   Ctrl+Shift+C for the `SUPER + SHIFT + U` chord) and the app ignores it
2. reads the **primary selection** (`wl-paste --primary`, i.e. whatever is
   currently highlighted) immediately — no key simulation in this path, so
   no waiting either
3. falls back to clipboard only if primary is empty. It tries two copy
   chords in order, each up to **3 times** with the clipboard cleared
   beforehand and **0.6 s** (plus 0.3 s per retry) of settle time after
   startup: **Ctrl+C** first, then **Ctrl+Shift+C**. The second one is not
   redundant — in a terminal `Ctrl+C` is `SIGINT`, not copy, so a terminal
   or TUI silently fails the first chord no matter how often it is retried.
   If every attempt is empty it restores the previous clipboard contents and
   fails with `nothing was selected`, naming both chords it tried
4. transliterates each word, using the local cache first and the network only
   for words it has not seen. **If the selection is already Urdu** (no Latin
   words in it) it does not transliterate — it looks the words up in the
   reverse index and steps each to the next spelling, which is what makes
   `SUPER + SHIFT + U` work on the output of `SUPER + U`
5. writes the Urdu to the clipboard (`wl-copy`), waits until **0.5 s** have
   passed since startup (a no-op after a slow network run) plus **0.12 s**
   for the clipboard to settle — a still-held `SHIFT` would otherwise turn
   the paste into Ctrl+Shift+V (Markdown preview in VS Code) — then sends a
   synthetic **Ctrl+V** to paste it back over the selection, and also prints
   the Urdu to stdout. If nothing changed it just logs `nothing changed` and
   exits 0

Any failure along the way raises a desktop notification, because a keybind's
stderr is thrown away and a silent failure looks identical to a broken key.

Note that `wtype` uses its own key syntax, not X-style `ctrl+c`. Modifiers go
through `-M`/`-m` and `-k` takes a bare key, so the correct call (as used in
`send_ctrl()`, with a 20 ms inter-key delay) is:

```bash
wtype -s 20 -M ctrl -k c -m ctrl      # correct
wtype -k ctrl+c                       # wrong: "Unknown key 'ctrl+c'", exit 1
```

The clipboard is the only portable way to move text in and out of an arbitrary
application on Wayland — there is no compositor API for reading a window's
selection.

The transliteration engine is Google's Input Tools, the same one engurdu.com
uses. It returns up to five ranked suggestions per word, so ambiguous words
have a sensible alternative available.

---

## Dependencies

| Package | Status (2026-09-27) | Purpose |
|---|---|---|
| `python3` | already installed | runs everything (needs 3.10+) |
| `wl-clipboard` | already installed | `wl-copy` / `wl-paste` (incl. `--primary`) |
| `wtype` | **installed** (0.4-2.2) | sends Ctrl+C / Ctrl+V to the focused window |
| `ibus` | **not installed** | the live input method only — not needed for `SUPER + U` |

`ibus` is needed **only** for the planned live typing. The
`SUPER + U` tool works without it and is unaffected by it.

```bash
sudo pacman -S ibus
```

No Python packages are needed. Everything uses only the standard library
(`urllib`, `json`, `re`, `concurrent.futures`). The live input method
additionally uses `python-gobject` (`gi`), which is already installed, and
needs no `python-dbus` — see [How the engine is registered](#how-the-engine-is-registered).

---

## Installation

### 1. Install `wtype`

```bash
sudo pacman -S wtype
```

Verify:

```bash
command -v wtype    # should print /usr/bin/wtype
```

### 2. Install `ibus` (live input method only — planned, not installed here)

> Skip this on the current machine. `ibus` is not installed and none of the
> engine files exist, so the steps below document the plan, not the present.

```bash
sudo pacman -S ibus
ibus version          # expect 1.5.34 or newer
```

### 3. Put the script on your PATH

```bash
install -Dm755 urdu-translit ~/.local/bin/urdu-translit
chmod +x ~/.local/bin/urdu-translit
```

Or run the installer, which does this plus the dependency checks and seeds
`overrides.json` on a fresh machine:

```bash
./install.sh
```

`install.sh` works in one of two modes, and **remembers which** in
`~/.config/urdu-translit/install-mode`, so a later plain `./install.sh` keeps
the same layout instead of quietly reverting it.

| Mode | `~/.local/bin/urdu-translit` | `~/.config/urdu-translit/overrides.json` |
|---|---|---|
| `copy` (default) | real file | real file, never overwritten |
| `link` (`--link`) | symlink to `./urdu-translit` | symlink to `./overrides.json` |

```bash
./install.sh              # uses the remembered mode
./install.sh --link       # make this project the single source of truth
./install.sh --copy       # go back to standalone files
```

In `copy` mode, `install.sh` **never overwrites an existing
`overrides.json`**, because that file is hand-edited and holds vocabulary that
exists nowhere else. To replace it deliberately:

```bash
./install.sh --force-overrides    # backs the old one up to overrides.json.bak
```

In `copy` mode the two files are independent, so they can drift: editing
`./overrides.json` in the project changes nothing, because the live file wins.
`install.sh` detects that and says so rather than letting you wonder.

In `link` mode you edit the project files and they apply immediately — no
re-running anything, and no way for the two copies to disagree. Converting
backs up whatever was there first (only if it actually differed), and
re-running is a no-op. This mode also makes `install.sh` ensure
`./urdu-translit` stays executable, since a symlink is executed with the
*target's* permissions.

**The trade-off:** in `link` mode the installed tool depends on this project
directory staying put. Move, rename, or delete it and the links break. Two
different failure modes, both handled:

- Broken **`overrides.json` link** — the tool itself is running, so it detects
  the dangling link and raises a notification. (It used to fail *silently*:
  opening a dangling symlink raises `FileNotFoundError`, indistinguishable
  from "no config file exists".)
- Broken **`~/.local/bin/urdu-translit` link** — nothing is running at all, so
  the tool cannot report it. This is why the keybindings carry a guard that
  tests the path with `-x` before running, and notifies otherwise.

If you would rather not depend on the path, use `--copy` and everything is
self-contained.

Confirm `~/.local/bin` is on your `PATH`:

```bash
command -v urdu-translit
```

On this system `~/.local/bin` is already first in `PATH`, so nothing else is
needed. If it is not on yours, either add it in `~/.config/uwsm/env` (this
config launches apps through UWSM):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

...or skip `PATH` entirely and call the script by absolute path in the
keybinding, which always works:

```lua
hl.bind(V.MOD_KEY .. " + U", hl.dsp.exec_cmd("/home/YOU/.local/bin/urdu-translit --clip"), { description = "Transliterate selection to Urdu" })
```

### 4. Add the keybindings

First define the command path once, in `~/.config/hypr/config/variables.lua`:

```lua
    -- Absolute path on purpose: keybinds discard stderr, so a bare command
    -- name that fails to resolve produces no visible error at all.
    -- Hardcoded because os.getenv is not available in Hyprland's Lua sandbox.
    URDU_TRANSLIT_CMD = "/home/YOU/.local/bin/urdu-translit",
```

Then bind it in `~/.config/hypr/config/binds/utilities.lua`:

```lua
local V = require("config.variables")

-- `release = true` matters: the command spawns after SUPER/SHIFT are up, so
-- the synthetic Ctrl+C / Ctrl+V the script sends arrive clean. Without it
-- the SUPER+SHIFT+U chord is typically still held and the app sees
-- Ctrl+Shift+C (devtools in browsers, a new terminal in VS Code) instead
-- of a copy, surfacing as "nothing was selected".
--
-- The -x guard exists because a keybind's stderr is discarded. With
-- `install.sh --link` the command is a symlink into the project directory; if
-- that directory is moved, exec fails *before* any of the tool runs, and
-- nothing running means nothing able to report it -- SUPER+U would just
-- appear to do nothing.
--
-- Deliberately `-x` and not `|| notify-send ...`: the tool exits 1 for ordinary
-- handled outcomes ("nothing was selected", "that text is already Urdu") and
-- reports those itself, so `||` would announce a broken install on every
-- normal no-op. Testing runnability cannot misfire, and also catches a target
-- that lost its executable bit, which an exit code would miss.
local function urdu_cmd(args)
    return "if [ -x " .. V.URDU_TRANSLIT_CMD .. " ]; then "
        .. V.URDU_TRANSLIT_CMD .. " " .. args
        .. "; else notify-send -u critical 'urdu-translit' 'Broken: "
        .. V.URDU_TRANSLIT_CMD .. " is missing, is a dangling symlink, or is not executable. "
        .. "Re-run ./install.sh from the project directory, or ./install.sh --copy to stop depending on it.'; fi"
end

hl.bind(V.MOD_KEY .. " + U",         hl.dsp.exec_cmd(urdu_cmd("--clip")),        { description = "Transliterate selection to Urdu", release = true })
hl.bind(V.MOD_KEY .. " + SHIFT + U", hl.dsp.exec_cmd(urdu_cmd("--clip --pick 2")), { description = "Transliterate selection (2nd suggestion)", release = true })
```

Update `URDU_TRANSLIT_CMD` if you move the script or change your username.
`exec_cmd` runs the string through a shell, which is what lets the guard's
`else` branch run at all.

`SUPER + U` and `SUPER + SHIFT + U` were free in this config. If you are
adding these to a different config, check for conflicts first:

```bash
grep -rn 'SHIFT + U\|+ U"' ~/.config/hypr/config/binds/
```

Ignore any hits that are your own `urdu-translit` lines.

### 5. Create the corrections file (optional)

`install.sh` creates `~/.config/urdu-translit/` and copies `overrides.json`
there if it is missing. To do it by hand:

```bash
mkdir -p ~/.config/urdu-translit
cp overrides.json ~/.config/urdu-translit/overrides.json
```

See [Personal corrections](#personal-corrections).

### 6. Reload and test

```bash
hyprctl reload
urdu-translit --selftest      # expect: 10/10 passed
```

Then type `aap kise hen` somewhere, select it, press **SUPER + U**.

### 7. Set up the live input method

Four files, no `sudo` required.

```bash
# a. the IBus component descriptor
mkdir -p ~/.local/share/ibus/component
#    → urdu.xml, shown below

# b. the systemd user unit
mkdir -p ~/.config/systemd/user
#    → ibus.service, shown below

# c. the session environment variables
cat >> ~/.config/uwsm/env <<'EOF'

# IBus - Urdu transliteration input method
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
EOF
```

`~/.local/share/ibus/component/urdu.xml` — replace `/home/hussain` with your
own home directory:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<component>
  <name>org.freedesktop.IBus.Urdu</name>
  <description>Urdu transliteration from Roman English</description>
  <exec>/home/hussain/.local/bin/urdu-engine</exec>
  <version>1.0</version>
  <textdomain>ibus</textdomain>
  <engines>
    <engine>
      <name>urdutranslit</name>
      <language>ur</language>
      <license>MIT</license>
      <author>hussain</author>
      <longname>Urdu (transliterated)</longname>
      <description>Urdu (transliterated from Roman English)</description>
      <symbol>ur</symbol>
      <icon>ibus-keyboard</icon>
      <rank>50</rank>
    </engine>
  </engines>
</component>
```

Four details are load-bearing and are not obvious:

- the component **must** have a `<name>` — it becomes the well-known bus name the
  spawned engine process claims, and it must match `BUS_NAME` in `engine.py`
- the engine **must** sit inside an `<engines>` wrapper, or it is not registered
- the engine **must** have a `<longname>` — `ibus write-cache` drops entries
  without one
- the directory is `~/.local/share/ibus/component`, **not** the older
  `~/.local/share/ibus-1.0/component`, which this ibus never reads

`~/.config/systemd/user/ibus.service`:

```ini
[Unit]
Description=IBus input method daemon (Urdu transliteration engine)
Documentation=man:ibus(1)
# Must exist before applications start, or the first keystrokes of the
# session bypass IBus entirely.
Before=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.IBus
Environment=IBUS_COMPONENT_PATH=/usr/share/ibus/component:/home/hussain/.local/share/ibus/component
ExecStartPre=-/usr/bin/ibus write-cache
ExecStart=/usr/bin/ibus-daemon --replace --panel disable --xim
Restart=on-failure
RestartSec=1
Slice=session.slice
TimeoutStopSec=5

[Install]
WantedBy=default.target
```

`IBUS_COMPONENT_PATH` is what `write-cache` reads to find your component;
without it the cache is built from the system directory alone and the engine
vanishes again.

Then start it and build the dictionary:

```bash
systemctl --user daemon-reload
systemctl --user enable --now ibus.service

~/.local/bin/urdu-dict-build     # first run: ~30s over the network

ibus list-engine | grep urdu     # expect: urdutranslit - Urdu (transliterated)
ibus engine urdutranslit
```

**Log out and back in.** The environment variables are only present in
applications started after they are set, and only a real login proves the
systemd unit starts the daemon.

---

## Usage

### Live typing

Turn on Urdu, then type. Nothing to select, nothing to paste.

1. Focus any application — a terminal, an editor, a browser form.
2. Press the IBus hotkey (see below) to switch from English to Urdu.
3. Type `salaam aap kaise hen` and press space.

The text on screen is already Urdu:

```
salaam aap kaise hen theek ho?
   ↓
سلام آپ کیسے ہیں ٹھीک ہو؟
```

The `ا` and `ی` characters appear as you type, replacing the Roman word
underneath — so if a word is not in the dictionary, you simply get the Roman
text back and nothing is lost.

**Switching between English and Urdu.** IBus owns the hotkey, not this config.
The default is `Super + Space`, but that is likely already taken by your window
manager. To change it:

```bash
# inspect what IBus currently has
gsettings get org.freedesktop.ibus.general.hotkey triggers

# set it to something free, e.g. Ctrl+Space
gsettings set org.freedesktop.ibus.general.hotkey triggers "['<Super>space']"
```

Run the live input method directly instead, without touching the hotkey:

```bash
ibus engine urdutranslit     # switch to Urdu now
ibus engine xkb:us::eng      # switch back to English
```

Set Urdu as the default for new windows:

```bash
gsettings set org.freedesktop.ibus.general preload-engines "['urdutranslit']"
```

#### Keys inside the live input method

| Key | Action |
|---|---|
| `Space` | commit the current word in Urdu |
| `Shift + Space` | **cycle to the next candidate** for the current word |
| `Escape` | abandon the current word, commit nothing |
| `BackSpace` | delete, as normal |
| `Ctrl`, `Alt`, `Super` + anything | pass through untouched — shortcuts still work |

`Shift + Space` is the important one. `salaam` has several valid spellings; type
it, then press `Shift + Space` to step through them:

```
salaam  →  سلام  →  صلعم  →  سالام  →  سلم
```

### Selecting text

The original tool, unchanged and independent of the input method.

1. Type Roman English in any application.
2. Select the text (mouse, or `CTRL + SHIFT + Left/Right` for words).
3. Press **SUPER + U**.

The selection is replaced with Urdu in place.

| Key | Action |
|---|---|
| `SUPER + U` | transliterate, using the top suggestion |
| `SUPER + SHIFT + U` | **step to another spelling** of the same word |

`SUPER + SHIFT + U` works on **Roman English** *and* on **Urdu that
urdu-translit produced**, and it always means the same thing: *show me a
different spelling of this word*.

- On Roman English (`thik`) it is the engine's 2nd suggestion.
- On Urdu output (`ٹھیک`) it looks the word up in the reverse index, finds the
  Roman word it came from, and moves to that word's next suggestion. Press it
  repeatedly to cycle, wrapping at the end.

Use it when a word comes out wrong — `bhai` is ambiguous between بھائی
("brother") and بھی ("also"), and `thik` ranks `ٹھیک` second.

**Accepted alternates stick.** Once you take an alternate, plain `SUPER + U`
keeps giving you that one for that word, with no further network call:

```
thik  --SUPER+U-->  تھک        (top-ranked, first ever use)
thik  --SHIFT+U-->  ٹھیک       (you accept the alternate)
thik  --SUPER+U-->  ٹھیک       (sticky - still the alternate, 0 requests)
```

This is the whole point of the alternates: correcting a word once fixes it
everywhere, for good, rather than making you re-pick it on every sentence.
The rank lives in `~/.cache/urdu-translit/picks.json` (capped at 1 000
entries), keyed per word, so `thik` sticking to `ٹھیک` does not affect `theek`.

Undo a sticky pick with:

```bash
urdu-translit --forget thik     # one word
urdu-translit --forget          # all of them
rm ~/.cache/urdu-translit/picks.json
```

`SUPER + SHIFT + U` on **Urdu** feeds the same memory, so cycling an Urdu word
also changes what `SUPER + U` gives you for the Roman word behind it.

The reverse index is what makes the second case possible at all. The
transliterator matches `[A-Za-z]+` only, so Urdu text is invisible to it:
without an index of "this Urdu came from that Roman word", `SUPER + SHIFT + U`
on the output of `SUPER + U` was a silent no-op. It lives in
`~/.cache/urdu-translit/reverse.json` (capped at 2 000 entries) and is written
as words are converted.

Two things it will *not* do:

- **Urdu it did not produce.** Text typed by hand has no entry in the index,
  so there is nothing to switch to. It says `no alternates known for that
  Urdu` and tells you to re-select the Roman original instead. Pin the word in
  `overrides.json` and it becomes known from then on.
- **Plain `SUPER + U` on Urdu.** That is already what you asked for, so it
  reports `that text is already Urdu` rather than silently doing nothing.

### From the terminal

```bash
$ urdu-translit "aap kise hen"
آپ کیسے ہیں

$ echo "salaam" | urdu-translit
سلام
```

### Without `wtype`

If you would rather not install anything, this works with no extra packages —
you just copy and paste yourself:

```bash
wl-paste --no-newline | urdu-translit | wl-copy
```

Select the text, `Ctrl+C`, run that, `Ctrl+V`.

---

## Files and where they live

**The live input method (planned — none of these exist on this machine as of 2026-09-27)**

| Path | Purpose |
|---|---|
| `~/.local/lib/urdu-translit/` | the source — its own git repository |
| `~/.local/lib/urdu-translit/engine.py` | the IBus engine (the only file importing `gi`) |
| `~/.local/lib/urdu-translit/core.py` | dictionary, overrides, resolution — no IBus |
| `~/.local/lib/urdu-translit/engine_state.py` | key-handling state machine — no IBus |
| `~/.local/lib/urdu-translit/builder.py` | offline dictionary builder |
| `~/.local/lib/urdu-translit/learn.py` | out-of-band learning |
| `~/.local/lib/urdu-translit/seed-words.txt` | 601 seed words |
| `~/.local/lib/urdu-translit/tests/` | 130 unit tests |
| `~/.local/bin/urdu-engine` | shim the daemon spawns |
| `~/.local/bin/urdu-dict-build` | rebuild the dictionary |
| `~/.local/share/ibus/component/urdu.xml` | the IBus component descriptor |
| `~/.local/share/urdu-translit/dict.json` | the built dictionary (517 words) |
| `~/.config/systemd/user/ibus.service` | starts the daemon at login |

**Both tools**

| Path | Purpose |
|---|---|
| `~/.local/bin/urdu-translit` | the selection script (executable) |
| `~/.config/urdu-translit/overrides.json` | your personal corrections (a symlink to `./overrides.json` if you ran `install.sh --link`) |
| `./overrides.json` | corrections in the project — the source of truth when symlinked |
| `~/.cache/urdu-translit/cache.json` | learned word cache, auto-created |
| `~/.cache/urdu-translit/reverse.json` | Urdu → Roman word, for `SUPER + SHIFT + U` alternates |
| `~/.cache/urdu-translit/picks.json` | Roman word → last accepted suggestion rank (sticky picks) |
| `~/.config/hypr/config/binds/utilities.lua` | the two keybindings |
| `~/.config/uwsm/env` | the IBus environment variables |

Delete the cache at any time to start fresh — it rebuilds automatically:

```bash
rm ~/.cache/urdu-translit/cache.json
```

---

## How the engine is registered

This is unusual, and the reason is worth writing down — it is the first thing to
suspect if the engine ever disappears after an `ibus` upgrade.

ibus 1.5.34 scans **only** `/usr/share/ibus/component`. It ignores
`IBUS_COMPONENT_PATH` and reads no cache path directly, so a component installed
in `~/.local/share/ibus/component/` is invisible to it. There is no
passwordless sudo on this machine, so writing to `/usr/share` was not an option.

The workaround is the registry cache. `ibus write-cache` regenerates
`~/.cache/ibus/bus/registry`, and the daemon loads *that* rather than rescanning.
So the component descriptor lives in the user directory, and the systemd unit
runs `write-cache` before the daemon starts:

```ini
[Service]
Type=dbus
BusName=org.freedesktop.IBus
ExecStartPre=-/usr/bin/ibus write-cache
ExecStart=/usr/bin/ibus-daemon --replace --panel disable --xim
Restart=on-failure
```

If the engine ever vanishes, run that command by hand and restart:

```bash
ibus write-cache
systemctl --user restart ibus.service
ibus list-engine | grep urdu
```

`--panel disable` is only cosmetic: without it `ibus-ui-gtk3` prints a
"should be called from the desktop session in wayland" tray-icon warning on every
start.

**No `python-dbus` required.** The engine uses `Gio` for all bus plumbing and
`IBus.get_address()` to find the daemon's *private* bus — which is a different
bus from the session bus, and is the single most likely thing to get wrong.

---

## Rebuilding the dictionary

The dictionary is built from `seed-words.txt`, one word per line. Growth means
appending lines and rebuilding:

```bash
# from the network, fetching any word not already cached
~/.local/bin/urdu-dict-build

# from cache only, no network
~/.local/bin/urdu-dict-build --offline
```

A full build takes about half a minute; an incremental rebuild fetches nothing
and finishes in well under a second. The engine reloads the dictionary
automatically — it stats the file on each keystroke, so you can rebuild while it
is running and the next word uses the new data.

---

## Running the tests

```bash
cd ~/.local/lib/urdu-translit
python3 -m unittest discover -s tests -t .
```

Expect `Ran 130 tests` … `OK`. No IBus daemon and no compositor are needed:
`core.py` and `engine_state.py` import no `gi` at all, and
`tests/fake_ibus.py` stands in for the bindings for the one file that does.

## Command-line options

```
usage: urdu-translit [-h] [--clip] [--pick N] [--offline] [--no-cache]
                     [--keep-punct] [--urdu-numbers] [--selftest]
                     [text ...]
```

| Option | Effect |
|---|---|
| `--clip` | transliterate the focused app's selection in place (primary selection first, clipboard fallback) |
| `--pick N` | use the Nth suggestion. `N > 1` is a deliberate choice: it overrides the remembered rank **and becomes the new default** for that word. Default `1` replays the last rank used, or the top suggestion for a word never seen before. On input that is already Urdu, steps each known word `N-1` places further through its suggestions |
| `--forget [WORD]` | forget the remembered suggestion for `WORD`, or for every word if given bare |
| `--offline` | cache only, never touch the network |
| `--no-cache` | ignore the cache for this run (and do not write it) |
| `--keep-punct` | leave `.` `,` `;` `?` `%` as-is instead of Urdu punctuation |
| `--urdu-numbers` | convert Latin digits to Urdu numerals |
| `--selftest` | run the built-in accuracy check |
| `--help` | show usage |

### Punctuation

By default Latin punctuation is converted to its Urdu equivalent:

| Typed | Output | |
|---|---|---|
| `.` | `۔` | Urdu full stop |
| `,` | `،` | Urdu comma |
| `;` | `؛` | Urdu semicolon |
| `?` | `؟` | Urdu question mark |
| `%` | `٪` | Urdu percent |

Use `--keep-punct` to leave them in Latin script.

### Protected tokens

These are detected and left completely untouched, so code, links and versions
survive transliteration:

- URLs — `https://example.com/urd`
- email addresses — `name@example.com`
- hex — `0xDEADBEEF`
- versions — `1.2.3`
- paths — `/usr/share/urdu`

```bash
$ urdu-translit 'see https://x.com/a and me@ex.com'
سی https://x.com/a اینڈ me@ex.com
```

---

## Personal corrections

`~/.config/urdu-translit/overrides.json` maps what you type to what you want.
These beat the engine's suggestions and are merged on top of the built-in
fixes, so you only list what you want to change.

```json
{
  "bhai":    ["بھائی", "بھی"],
  "hussain": ["حسین"],
  "ayesha":  ["عائشہ"]
}
```

Key = the Roman English you type. Value = your preferred Urdu, best first.
`SUPER + U` uses the first entry, `SUPER + SHIFT + U` the second, and so on —
and taking the second makes it the new first for next time. A plain string
works too:

```json
"ayesha": "عائشہ"
```

Names are the most common thing to add, since the engine transliterates them
phonetically rather than recognising them.

**The file must be valid JSON or none of it applies** — a single trailing
comma throws away every entry, silently. Keys beginning with `_` are treated
as comments and skipped, so you can annotate the file. Validate after editing:

```bash
python3 -m json.tool ~/.config/urdu-translit/overrides.json >/dev/null && echo ok
```

A single-entry list gives you no alternate to switch to: `--pick 2` clamps to
the end of the list and returns the same word. Add the second spelling if you
want one.

Built-in corrections already handled, so you rarely need them (exact
`BUILTIN_OVERRIDES` in the script): `wo` → وہ, `woh` → وہ, `hai` → ہے,
`hain` → ہیں, `hen` → ہیں, `main`/`mein` → میں.

---

## Caching and offline use

Every word the engine returns is cached with all five of its suggestions, so
repeats are instant and `--pick` still works offline.

The cache is **immutable per word**: the rank you end up preferring is stored
separately in `picks.json`, never written into the suggestion list. So the
first time you use a word it costs one request, and every pick and every
repeat after that is free — even with the network down.

Measured on a 17-word sentence:

| Run | Time |
|---|---|
| cold (network) | 1.17 s |
| warm (cache) | 0.05 s |
| `--offline` | 0.05 s |

Requests for uncached words are made in parallel (up to 8 workers:
`min(8, cpu_count)`), which is what
keeps a cold sentence near a second instead of half a second per word. Each
word retries twice on network failure with backoff before giving up, and
override words are never written to the cache.

To work with no network at all:

```bash
urdu-translit --offline "salaam"
```

Words that are not cached are passed through unchanged rather than mangled.

---

## Accuracy

Run the built-in check any time:

```bash
$ urdu-translit --selftest
  PASS  'aap kise hen' -> 'آپ کیسے ہیں'
  PASS  'aap ko dekh kar bahat acha laga' -> 'آپ کو دیکھ کر بہت اچھا لگا'
  PASS  'salaam' -> 'سلام'
  PASS  'theek' -> 'ٹھیک'
  ...
10/10 passed
```

The first two cases are the exact examples engurdu.com advertises.

Sample conversions:

| You type | You get |
|---|---|
| `aap kise hen` | آپ کیسے ہیں |
| `aap ko dekh kar bahat acha laga` | آپ کو دیکھ کر بہت اچھا لگا |
| `salaam` | سلام |
| `theek` | ٹھیک |
| `shukriya` | شکریہ |
| `zindagi` | زندگی |
| `khushi` | خوشی |
| `dost` | دوست |
| `ghar` | گھر |
| `ustad` | استاد |

---

## Troubleshooting

Start here, in order — these are the failures that actually occurred, ordered by
how often they are likely to bite you.

### Live input method

**Nothing is Urdu; the engine seems to be on but Latin text appears**

The engine receives the key, fails to turn it into a character, and hands the
key to the application. Turn on key logging to see which it is:

```bash
systemctl --user edit ibus.service     # add:
#   [Service]
#   Environment=URDU_ENGINE_DEBUG=/tmp/urdu-keys.log

systemctl --user daemon-reload
systemctl --user restart ibus.service
```

Then type in an application and:

```bash
cat /tmp/urdu-keys.log
```

- **The file does not exist** — the app is not routing keys through IBus at all.
  See "the app ignores the engine" below.
- **Lines appear but `char=''`** — the engine got the key but could not map it to
  a character.
- **Lines with real `char=` values** — the engine is working; the problem is
  downstream, in the dictionary.

Remove the override when done: `systemctl --user revert ibus.service`.

**The engine is missing from `ibus list-engine`**
Almost always the registry cache. See
[How the engine is registered](#how-the-engine-is-registered):

```bash
ibus write-cache
systemctl --user restart ibus.service
ibus list-engine | grep urdu
```

**`SetGlobalEngine` fails with `Timeout was reached`**
The daemon could not see the engine's bus name. The engine must be on the
daemon's private bus (`IBus.get_address()`), not the session bus, and it must
export a Factory. Both are handled in `main()`; if you have edited `engine.py`,
check that neither has been lost.

**The app ignores the engine entirely**
Hyprland does not implement `zwp_input_method_manager_v2`, and GTK4 apps use the
Wayland `text-input` protocol rather than `GTK_IM_MODULE`. **Neither can use any
IBus engine**, not just this one. This is a compositor limitation.

What works: **GTK3 apps** and **Qt apps** (kitty's Qt builds, qterminal). What
does not: **GTK4 apps** — including `gnome-text-editor` — and GLFW-based
terminals such as kitty's default build on this machine.

```bash
# check a running app has the variables
tr '\0' '\n' < /proc/PID/environ | grep IM_MODULE
```

Apps started before the variables were set do not have them. Log out and back in.

**The IBus hotkey conflicts with a window-manager binding**
Change it:

```bash
gsettings get org.freedesktop.ibus.general.hotkey triggers
gsettings set org.freedesktop.ibus.general.hotkey triggers "['<Super>space']"
```

…or skip the hotkey entirely and use `ibus engine urdutranslit`.

**Words keep coming out in the wrong script**
Add a correction. The live input method honours `overrides.json` on every
keystroke and overrides always win:

```bash
$EDITOR ~/.config/urdu-translit/overrides.json
```

```json
{ "bhai": ["بھائی", "بھی"] }
```

### Selection tool (`SUPER + U`)

**`wtype is not installed`**
Run `sudo pacman -S wtype`.

**Nothing happens, and no error appears**
This is what a keybind failure used to look like. Hyprland discards the
spawned process's stdout and stderr, so a crash was invisible. The script now
sends a desktop notification on every failure, so **if you get no popup, the
command is not running at all** — check the bind is registered and the path in
`URDU_TRANSLIT_CMD` is correct:

```bash
hyprctl binds -j | grep -A2 Transliterate      # is it registered?
ls -l /home/YOU/.local/bin/urdu-translit      # does the path exist?
```

With the text selected, also run it in a terminal to see the real error:

```bash
~/.local/bin/urdu-translit --clip
```

**`nothing was selected`**
The script found neither a primary selection nor clipboard text. Select
(highlight) text before pressing the key. If primary is empty it falls back
to synthetic `Ctrl+C`, so also make sure the app actually copies on `Ctrl+C`
— a few apps ignore synthetic key events from `wtype`. On this failure path
the script restores your previous clipboard contents instead of leaving the
cleared clipboard behind.

If it worked before with a manual `Ctrl+C` first: that workaround is no
longer needed. The old code sent `Ctrl+C` immediately while `SUPER` was still
held (arriving as Super+Ctrl+C, which apps ignore); the current code reads
the primary selection first (no keys involved) and settles/retries around
any synthetic key, so plain highlight + `SUPER + U` works.

**`SUPER + SHIFT + U` says `nothing was selected` (but `SUPER + U` works)**
The 3-key chord was still held when the script sent Ctrl+C, so the app
received Ctrl+Shift+C instead of a copy — devtools in browsers, a new
terminal in VS Code — and nothing landed on the clipboard. Two fixes cover
it, and both are in place if you installed after 2026-09-27: the binds fire
on key *release* (`release = true` in `binds/utilities.lua`), and the
script settles 0.6 s before the first Ctrl+C and retries it 3 times. If you
still see it, check both ends are current:

```bash
grep -c "release = true" ~/.config/hypr/config/binds/utilities.lua   # expect 2
grep -c "COPY_TRIES" ~/.local/bin/urdu-translit                       # expect 2+
```

If either is 0, re-copy the bind lines from
[Installation](#installation) and re-run `./install.sh` from the project
directory, then `hyprctl reload`.

**It pasted the wrong text**
The script overwrites your clipboard when it pastes back. If the app ignored
the synthetic `Ctrl+C` fallback, it read whatever was already on the
clipboard. Undo in the app (`Ctrl+Z`) and check whether that app handles
synthetic copy events. Highlighting the text (primary selection path) avoids
this entirely.

**It does not work in one specific app**
If highlighting works but the fallback does not, the method depends on the
app treating `Ctrl+C` as copy. Apps with custom or
disabled copy shortcuts will not respond. This is the main limitation of the
clipboard fallback; the primary-selection path needs no copy shortcut at all.

**A word in `overrides.json` is ignored**
One malformed byte discards **the whole file** — JSON has no partial credit,
so a single stray comma silently drops every correction in it, not just the
one you were looking at. The tool pops a notification naming the file and the
parse error; before 2026-09-27 it only wrote to stderr, which a keybind
discards, so the words just stopped working with no explanation.

Check it directly:

```bash
python3 -m json.tool ~/.config/urdu-translit/overrides.json >/dev/null && echo ok
```

The usual culprit is a trailing comma before a closing `]` or `}`. To confirm
a word is actually loaded:

```bash
urdu-translit --selftest   # unrelated, but proves the script runs
urdu-translit "me"         # must print your override, not the engine's pick
```

**`overrides.json is a broken symlink`**
Only happens with `install.sh --link`: the project directory moved or was
deleted, so the link points at nothing. Fix it from the project:

```bash
./install.sh --link        # re-points it
```

Before 2026-09-27 this failed *silently* — a dangling symlink raises
`FileNotFoundError`, which is indistinguishable from "no config file exists",
so all corrections just quietly stopped applying. Confirm the link resolves:

```bash
readlink -f ~/.config/urdu-translit/overrides.json   # must print a real path
```

**`SUPER + SHIFT + U` gives the same word as `SUPER + U` for an override**
Expected when the override has a single entry — the rank is clamped to the
list, so `--pick 2` on `["میں"]` returns `میں`. Add the alternate to the list:

```json
"me": ["میں", "مے"]
```

**A word comes out wrong**
Press `SUPER + SHIFT + U` instead — on the Urdu that is already there, it steps
to the next spelling of the same word. Or pin it in `overrides.json`. Undo
first.

**A notification says `Broken: .../urdu-translit is missing`**
Only possible in `link` mode: the symlink in `~/.local/bin` cannot be executed
— the project directory moved, or `./urdu-translit` lost its executable bit.
Nothing was transliterated. Fix it:

```bash
./install.sh --link     # re-point the links (also restores +x)
```

Or drop the dependency entirely:

```bash
./install.sh --copy     # back to standalone, self-contained files
```

Check the link by hand:

```bash
ls -l ~/.local/bin/urdu-translit
readlink -f ~/.local/bin/urdu-translit   # must print a real path
```

**`SUPER + SHIFT + U` says `no alternates known for that Urdu`**
The word was not produced by urdu-translit, so the reverse index has nothing
to work from. Re-select the original Roman English and press it again, or add
the word to `overrides.json`. Check the index is being written:

```bash
ls -l ~/.cache/urdu-translit/reverse.json
python3 -c "import json;d=json.load(open('$HOME/.cache/urdu-translit/reverse.json'));print('ٹھیک' in d, d.get('ٹھیک'))"
```

**`SUPER + SHIFT + U` does nothing, with no popup**
Old behaviour, fixed on 2026-09-27: selecting Urdu text matched no words
(`WORD_RE` is Latin-only), so the tool exited 0 having changed nothing. If you
still see it, the installed copy predates the reverse index:

```bash
grep -c "next_alternate" ~/.local/bin/urdu-translit    # expect 2+
```

**`command -v urdu-translit` finds nothing**
`~/.local/bin` is not on your `PATH`. See step 3 in
[Installation](#installation).

**Hyprland reports a Lua syntax error after editing the binds**
Run `luac -p ~/.config/hypr/config/binds/utilities.lua` to check the file
before reloading.

---

## Limitations and caveats

**It transliterates, it does not translate.** `Hello, how are you?` becomes
ہیلو، ہو ارے یو؟ — the English words spelled out phonetically. To write "hello"
in Urdu you type `salaam`. This is the correct behaviour for a transliterator
and the same as engurdu.com.

**It is selection-based, not a true input method.** You convert a selection
after the fact. A live IBus engine is planned (see the status note at the top
and the sections below), but it is not installed on this machine, so
selection-based conversion is currently the only method.

**It depends on an undocumented Google endpoint.**
`https://www.google.com/inputtools/request` with `ime=transliteration_en_ur`
is a public but unofficial API — it is what engurdu.com itself calls, so it is
as stable as they are, but it could change or rate-limit without notice. The
cache is what protects you day to day.

**It overwrites your clipboard** every time it runs.

**Selection-based means large selections are slow to convert.** Converting a
whole page sends a request per distinct word. Select sentence-sized chunks
rather than entire documents.

**The live input method does not work in GTK4 apps, or in any Wayland app that
uses the `text-input` protocol.** Hyprland does not implement
`zwp_input_method_manager_v2`, so there is no way for those apps to reach any
IBus engine. GTK3 and Qt apps are unaffected. This is a compositor limitation
and applies to Fcitx and every other input method too.

**The live input method is not installed system-wide.** It registers via the
user registry cache rather than `/usr/share/ibus/component`, because
`/usr/share` is not writable here. It works for this user and needs no `sudo`,
but it will not follow you to another account or another machine without
reinstalling — and an `ibus` upgrade that clears `~/.cache/ibus/bus/registry`
will hide it until `ibus write-cache` runs again. The systemd unit handles that
automatically; see [How the engine is registered](#how-the-engine-is-registered).

**The seed dictionary is 601 words, not the ~2 500 originally planned.** This is
enough for the common cases and background learning fills the rest, but a
longer tail will initially come out in Roman. Appending to
`seed-words.txt` and rebuilding is the fix.

---

## How it was built

The endpoint was not guessed. engurdu.com's own JavaScript bundle was read to
find the API it calls, which turned out to be Google Input Tools
transliteration with `dt=rm` romanization — not the `translate_a/t` translation
endpoint, which returns nonsense for this purpose (`hen` comes back as مرغی,
"chicken").

Alternatives were evaluated and rejected:

- **`fcitx5-laren`** (AUR) — the closest architecturally, with word-level
  suggestions, but its dictionary is 375k *Arabic* words with essentially no
  Urdu coverage, and it applies Arabic abjad rules where short vowels are
  optional. It outputs Arabic, not Urdu.
- **`arabizi-ibus-git`** (AUR) — Arabizi-to-Arabic, same problem.
- **`transliterate`** (PyPI) — no Urdu support.
- **ICU** — has no Urdu transliterator.
- **Google's `translate_a/t`** — conflates translation with transliteration.

The XKB `pk(urd-phonetic)` layout remains configured in
`~/.config/hypr/config/inputs.lua` on `Alt+Shift` as a fallback for one-shot
letter entry, where word-level logic is not needed.

### Licence

Yours to do what you like with. The transliteration service is Google's and
subject to their terms; this script sends only the individual words you
convert.
