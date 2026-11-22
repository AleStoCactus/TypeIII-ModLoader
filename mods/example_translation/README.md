# Example: Translation — template to translate Type III

This mod is a **template**. It does nothing until you set a language.
It contains every text of the game with an empty translation, ready to fill in.

## Make your own translation

1. Copy this folder inside `mods/` and rename it, e.g. `french_translation`.
2. In the new folder, edit `manifest.json`:
   ```json
   "id": "french_translation",
   "name": "Traduction française",
   "language": "fr",
   ```
   - `id` must be unique (letters, numbers and `_`).
   - `language` is a language code: `fr`, `de`, `es`, `pt_BR`, `ja`…
     While it is empty the mod stays off.
3. Translate `translation.po` (see below), then restart the game.
4. Make sure only one translation mod is **On** in Settings → Mod.

## Files

| File | What it is |
|---|---|
| `translation.po` | **All the texts of the game.** Translate here. |
| `mod_main.gd` | Loads `translation.po` and applies the translation. |
| `tooltip_ext.gd` | Shows translated item names in the item tooltip. |
| `manifest.json` | Mod info and `language`. |

## How to translate

Open `translation.po` with [Poedit](https://poedit.net) (recommended) or any
text editor. For every text, write your translation in `msgstr ""`:
```
msgid "Singleplayer"
msgstr "Un joueur"
```
An empty `msgstr` keeps the English text, so you can translate a bit at a time.

Rules:
- Never change the `msgid` lines. They must match the game's English text exactly.
- Keep `\n` (new line) and BBCode tags like `[b]...[/b]` where they are.
- Spaces at the start/end of a `msgid` (like `"   Create   "`) are added back
  automatically.
- The `#.` lines say where each text appears.
- Check that the game's fonts have your alphabet's letters.
  Latin accents (àéüñç…) are known to work.

## The kinds of entries

- **No `msgctxt`**: interface texts (menus, buttons, tabs, settings, popups,
  item descriptions, the Mod tab). Godot replaces every text that matches exactly.
- **`msgctxt "item name"`**: item names. They are translated only on screen (in
  the tooltip). They are never written into the worlds, so turning the mod off
  brings the English names back.
- **`msgctxt "stat name"` / `"stat description"`**: item stats in the tooltip.
  The game shows stat names With Every Word Capitalized.

## New texts are added automatically

When `language` is set, texts that are not in `translation.po` yet are written
at the end of the file when the game closes, with an empty `msgstr`. This covers
popups and menus you open, and items added by other mods. These entries have the
note `Found while playing` (some may be names, like a world name: leave those
empty).

If the file is open in Poedit while you play, reload it after closing the game.

## What cannot be translated by this mod

Texts that the game builds while running are not complete sentences in the code.
They cannot be matched, so they stay in English unless the game's scripts are
changed. Examples: `"Reason: " + reason`, `"%s joined"`, the world-version warning.
