-- rift-join: `J` and `gJ` like Neovim. rift doesn't have a join command.
--
-- This is a port of Neovim's do_join(), and gives the same text and cursor
-- as Neovim 0.11.
--
-- `J` pulls the next line up onto this one. Its leading whitespace becomes
-- a single space, unless the next line is empty or starts with `)`, or this
-- line is empty or already ends in a space or tab. `gJ` joins the lines as
-- they are, without touching any whitespace.
--
-- Like Neovim's default 'formatoptions', both also drop the comment leader
-- of the joined line when you're joining two comments, so `-- a` and `-- b`
-- become `-- a b`. The ` * ` at the start of /* */ middle lines goes too.
--
-- rift doesn't pass counts to plugins, so `3J` only joins two lines. Use
-- `:Join 3` or `:JoinRaw 3` instead.
local M = {}
local MODULE = ...

-- rift.replace_lines also eats the newline after the range, and it takes
-- two undos. So put that newline back, and in Normal mode do the edit
-- inside a quick trip to Insert mode so a single `u` undoes it.
local function set_lines(s, e, lines)
  local out = { table.unpack(lines) }
  if #out > 0 and e < rift.get_line_count() then out[#out + 1] = "" end
  local wrap = rift.get_mode() == "normal"
  if wrap then rift.exec_action("mode:insert") end
  rift.replace_lines(s, e, out)
  if wrap then rift.exec_action("mode:normal") end
end

-- rift's columns count characters, not bytes.
local function char_len(s) return utf8.len(s) or #s end

-- Maps go through `:lua` because rift updates the cursor and lines that
-- plugins see right before running it. Mapping `editor:run:Join` directly
-- would see the cursor from before the last motion. _rift_commands holds
-- the commands plugins have registered.
local function map(mode, keys, cmdline)
  local name, rest = cmdline:match("^(%S+)%s*(.*)$")
  local args = {}
  for a in rest:gmatch("%S+") do args[#args + 1] = string.format("%q", a) end
  rift.map(mode, keys, string.format("editor:run:lua _rift_commands[%q].fn({ %s })",
    name, table.concat(args, ", ")))
end

-- Comment leaders for each filetype, taken from Neovim's 'comments'. The
-- keys are rift filetype names and also file extensions, because a buffer
-- has no filetype until its syntax loads and plenty of extensions have no
-- rift grammar at all. `block` means /* */ comments with ` * ` middle lines.
local C_LIKE = { line = { "//" }, block = true }
local HASH = { line = { "#" } }
local LEADERS = {
  c = C_LIKE, h = C_LIKE, cpp = C_LIKE, cc = C_LIKE, cxx = C_LIKE, hpp = C_LIKE,
  c_sharp = C_LIKE, cs = C_LIKE, java = C_LIKE, go = C_LIKE, php = C_LIKE,
  javascript = C_LIKE, js = C_LIKE, jsx = C_LIKE, mjs = C_LIKE, cjs = C_LIKE,
  typescript = C_LIKE, ts = C_LIKE, tsx = C_LIKE, mts = C_LIKE, cts = C_LIKE,
  json = C_LIKE, jsonc = C_LIKE, kt = C_LIKE, kotlin = C_LIKE, swift = C_LIKE,
  dart = C_LIKE, scala = C_LIKE, scss = C_LIKE, less = C_LIKE, proto = C_LIKE,
  zig = { line = { "//" } },
  rust = { line = { "///", "//!", "//" }, block = true },
  css = { line = {}, block = true },
  lua = { line = { "---", "--" } },
  sql = { line = { "--" }, block = true },
  hs = { line = { "--" } }, elm = { line = { "--" } },
  python = HASH, py = HASH, ruby = HASH, rb = HASH, bash = HASH, sh = HASH,
  zsh = HASH, yaml = HASH, yml = HASH, toml = HASH, conf = HASH, cfg = HASH,
  fish = HASH, ps1 = HASH, psm1 = HASH, powershell = HASH, r = HASH, pl = HASH,
  nix = { line = { "#" }, block = true }, ex = HASH, exs = HASH, cmake = HASH,
  mk = HASH, make = HASH, makefile = HASH, dockerfile = HASH, gitignore = HASH,
  env = HASH,
  ini = { line = { ";" } },
  vim = { line = { '"' } },
  lisp = { line = { ";;" } }, clj = { line = { ";;" } }, el = { line = { ";;" } },
  erl = { line = { "%" } }, tex = { line = { "%" } },
}

-- The buffer's filetype, or else its extension. Files like Makefile and
-- .gitignore have no extension, so their whole name is used.
local function filetype()
  local ft = rift.get_filetype()
  if ft then return ft end
  local path = rift.get_filepath()
  if not path then return nil end
  local name = path:match("[^/\\]+$"):lower()
  return name:match("^.+%.([^.]+)$") or (name:gsub("^%.", ""))
end

local NONE = { line = {}, block = false }

local function leaders()
  local ft = filetype()
  return (ft and LEADERS[ft]) or NONE
end

local function starts_with(s, prefix) return s:sub(1, #prefix) == prefix end

-- Is there a comment still open at the end of `line`? Like Neovim, this
-- looks at the last comment leader on the line (at the start or after a
-- space). If the last thing is a `*/`, the comment was closed.
local function has_comment(line, L)
  local best, best_is_end = nil, false
  local function consider(pos, is_end)
    if pos > 1 and not line:sub(pos - 1, pos - 1):match("%s") then return end
    if not best or pos > best then best, best_is_end = pos, is_end end
  end
  for _, leader in ipairs(L.line) do
    local i = 1
    while true do
      local s = line:find(leader, i, true)
      if not s then break end
      consider(s, false)
      i = s + 1
    end
  end
  if L.block then
    local i = 1
    while true do
      local s = line:find("/*", i, true)
      if not s then break end
      consider(s, false)
      i = s + 1
    end
    i = 1
    while true do
      local s = line:find("*/", i, true)
      if not s then break end
      -- `*/` counts even right after text, like "text*/".
      if not best or s > best then best, best_is_end = s, true end
      i = s + 1
    end
    -- A middle line, like " * text".
    local ws = line:match("^%s*")
    if line:sub(#ws + 1, #ws + 1) == "*" and line:sub(#ws + 2, #ws + 2) ~= "/" then
      consider(#ws + 1, false)
    end
  end
  return best ~= nil and not best_is_end
end

-- How many bytes of comment leader `line` starts with, counting the indent
-- and, if `include_space`, the whitespace after it. 0 when there isn't one.
-- A closing `*/` is never removed.
local function leader_len(line, L, include_space)
  local ws = line:match("^%s*")
  local rest = line:sub(#ws + 1)
  local len
  for _, leader in ipairs(L.line) do
    if starts_with(rest, leader) then len = #ws + #leader break end
  end
  if not len and L.block and starts_with(rest, "*") and not starts_with(rest, "*/") then
    len = #ws + 1
  end
  if not len then return 0 end
  if include_space then len = len + #(line:sub(len + 1):match("^%s*")) end
  return len
end

-- Join `count` lines (at least 2) starting at the cursor line.
-- `insert_space` is true for J and false for gJ.
function M.join(count, insert_space)
  local kind = rift.buf_kind()
  if kind ~= "file" and kind ~= "scratch" then return end
  local row = rift.get_cursor()
  local all = rift.get_lines(1, -1)
  local total = #all
  -- rift counts the empty line after the file's last newline. Neovim doesn't.
  if total > 1 and all[total] == "" then total = total - 1 end

  count = math.max(2, count or 2)
  if row + count - 1 > total then
    if count <= 2 then return end -- already on the last line
    count = total - row + 1
  end

  local L = leaders()
  local result = all[row]
  local prev_was_comment = has_comment(result, L)
  local join_col = 0
  for t = 2, count do
    local curr = all[row + t - 1]
    local is_comment = has_comment(curr, L)
    if prev_was_comment and is_comment then
      curr = curr:sub(leader_len(curr, L, insert_space) + 1)
    end
    prev_was_comment = is_comment

    local space = ""
    if insert_space then
      curr = curr:gsub("^%s+", "")
      local last = result:sub(-1)
      if curr ~= "" and curr:sub(1, 1) ~= ")" and result ~= "" and last ~= "\t"
        and last ~= " " then
        space = " "
      end
    end
    join_col = char_len(result)
    result = result .. space .. curr
  end

  set_lines(row, row + count - 1, { result })
  rift.set_cursor(row, math.max(0, math.min(join_col, char_len(result) - 1)))
end

function M.setup()
  local function count_of(args) return tonumber(args[1] or "") or 2 end
  rift.register_command("Join", function(args) M.join(count_of(args), true) end,
    "Join [count] lines like J (default 2)")
  rift.register_command("JoinRaw", function(args) M.join(count_of(args), false) end,
    "Join [count] lines like gJ, keeping whitespace (default 2)")
  map("n", "J", "Join")
  map("n", "gJ", "JoinRaw")
end

M._has_comment = has_comment
M._leader_len = leader_len

-- If rift loaded this file straight from its plugins folder (rather than
-- a config require()ing it), set it up with the defaults.
if not MODULE then M.setup() end

return M
