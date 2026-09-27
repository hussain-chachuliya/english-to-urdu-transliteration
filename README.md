# urdu-translit

Write English the way you normally would. Press one key. It turns into Urdu.

```
aap kaise hen theek ho?
آپ کیسے ہیں ٹھیک ہو؟
```

It works in whatever you're typing in — a message, a document, a search box.
No browser, no app to switch to.

---

## Try it right now

Copy this and run it in a terminal:

```bash
echo "salaam aap kaise hen" | ./urdu-translit
```

To try it on text you already have on screen: select it, `Ctrl+C`, then run
the same command, then `Ctrl+V` back.

---

## Install

Four steps, about a minute.

### 1. Install the two helpers

```bash
sudo pacman -S wl-clipboard wtype
```

### 2. Run the installer

From this folder:

```bash
./install.sh
```

That's it. It puts the tool where your system looks for programs, creates your
corrections file, and tells you if anything is missing. Re-run it any time —
it won't undo your corrections.

> If you plan to keep this folder and edit it in place, run `./install.sh --link`
> instead. Your edits then apply immediately.

### 3. Add the keyboard shortcut

Open your Hyprland keybinds file and add:

```lua
hl.bind("SUPER + U",         hl.dsp.exec_cmd("urdu-translit --clip"),        { description = "Urdu: convert selection" })
hl.bind("SUPER + SHIFT + U", hl.dsp.exec_cmd("urdu-translit --clip --pick 2"), { description = "Urdu: other spelling" })
```

Then reload so it takes effect without a restart:

```bash
hyprctl reload
```

Two things worth knowing:

- **Keep `release = true` on both.** Without it, `SUPER + SHIFT + U` doesn't
  work — the app receives a different key combo and reports "nothing was
  selected". Add `{ description = "...", release = true }` if you left it out.
- **If the shortcut ever does nothing**, spell out the full path instead of
  `urdu-translit`, for example
  `hl.dsp.exec_cmd("/home/you/.local/bin/urdu-translit --clip")`.

### 4. Check it works

```bash
urdu-translit --selftest
```

Then type `aap kaise hen` anywhere, select it, and press **SUPER + U**.

---

## Using it

1. Type your English text.
2. Select it — highlight it with the mouse, or hold `Ctrl` and tap the arrow
   keys to select word by word.
3. Press **SUPER + U**.

The text turns into Urdu where it was, ready to keep typing.

| Key | What it does |
|---|---|
| **SUPER + U** | convert the selection to Urdu |
| **SUPER + SHIFT + U** | show a different spelling of the same word |

**SUPER + SHIFT + U is your fix button.** Many words have more than one correct
spelling, and the tool can't always guess which one you meant. `bhai` could be
بھائے (brother) or بھی (also). Press it and it swaps. Press it again to keep
cycling.

Once you pick the spelling you want, it sticks — **SUPER + U** will give you
that same spelling from then on, everywhere. So you fix a word once, not once
per sentence.

**In the terminal**, without selecting anything:

```bash
urdu-translit "aap kaise hen"
echo "salaam" | urdu-translit
```

---

## Fixing a word for good

Some words it will never guess right — your name, your street, your company.
Tell it once and it's sorted.

```bash
nano ~/.config/urdu-translit/overrides.json
```

```json
{
  "hussain": ["حسین"],
  "ayesha":  ["عائشہ"],
  "bhai":    ["بھائی", "بھی"]
}
```

Left side is what you type, right side is what you want. List a second option
and **SUPER + SHIFT + U** can switch between them.

Save, and it applies immediately — no restart. Check the file is still valid
after editing, because a stray comma makes the whole file get skipped:

```bash
python3 -m json.tool ~/.config/urdu-translit/overrides.json
```

---

## If something goes wrong

**A popup says "nothing was selected"** — you hadn't highlighted anything.
Select the text first, then press the key.

**Nothing happens at all, no popup** — the shortcut isn't reaching the tool.
Check it's registered with `hyprctl binds | grep -i urdu`, and check the path in
the shortcut is spelled right.

**A word keeps coming out wrong** — press **SUPER + SHIFT + U**. Still wrong?
Add it to `overrides.json`.

**Your corrections stopped applying** — the file has a typo in it. Run the
`json.tool` command above; it will point straight at the problem.

**It ran but pasted the wrong text** — press `Ctrl+Z` in that app to undo, then
highlight your text and try again. Highlighting is more reliable than copying.

---

## What it can't do

- **It spells out English; it doesn't translate.** `hello` becomes ہیلو. To
  actually say hello, type `salaam`. That's how Urdu is normally typed anyway.
- **It replaces your clipboard** each time it runs.
- **Big blocks are slow the first time.** Every new word needs a one-off
  lookup. Convert a sentence at a time, and it'll be instant from then on. It
  still works with no internet once a word has been seen.
- **Typing as you go isn't supported yet.** A version that converts words live
  while you type is planned, but it isn't ready. This one converts text you've
  already typed.

---

## How it works, in one line

The same engine that powers engurdu.com, run locally on your machine.

It needs an internet connection the first time it sees a word, and never again
for that word.
