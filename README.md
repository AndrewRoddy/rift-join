# rift-join

`J` and `gJ` for rift, joining lines exactly like Neovim. rift has no line join.

| Key / command | Effect |
|---|---|
| `J` | Join the next line onto this one with one space |
| `gJ` | Join without adding or removing whitespace |
| `:Join [n]` | `J` on `n` lines (default 2) |
| `:JoinRaw [n]` | `gJ` on `n` lines (default 2) |

Like Neovim:

- The joined line's leading whitespace becomes one space, except when it is
  empty or starts with `)`, or when this line is empty or ends in a space or
  tab. One space after `.` too (`nojoinspaces`).
- The comment leader of the joined line is removed when the line it joins
  onto has a comment in it: `-- a` + `-- b` gives `-- a b`, and
  `x = 1 -- a` + `-- b` gives `x = 1 -- a b`. The ` * ` of `/* */` middle
  lines goes too (`formatoptions` j, Neovim's default).
- The cursor lands on the join point. On the last line nothing happens.
- Undo takes one `u`.

Checked against Neovim 0.11 on 31 cases (text and cursor position), covering
Lua, Python, C and JavaScript comments.

No options. Comment leaders are known for about 60 filetypes and extensions
(`//`, `--`, `#`, `;`, `"`, `%`, `/* */`, ...).

## Limitations

- `3J` joins two lines: rift drops counts before mapped keys. Use `:Join 3`.
- No visual `J`: rift plugins can't map visual-mode keys.

## Install

rift-join installs through riftpm. Install riftpm first from
[Monster0506/riftpm](https://github.com/Monster0506/riftpm) (see its README),
then add rift-join to your `plugins.lua` spec:

```lua
{ "AndrewRoddy/rift-join" },
```

Run `:PluginSync` to clone it. It has no options and no dependencies.
It's small, so load it at startup: with riftpm's lazy `keys`, the first `J`
would only load the plugin and not join anything.

Tested with rift 0.7.7.
