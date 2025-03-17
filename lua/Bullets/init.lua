-- bullets.nvim
-- Author: Keith Miyake
-- Rewritten from https://github.com/dkarter/bullets.vim
-- License: GPLv3, MIT
-- Copyright (c) 2024 Keith Miyake
-- See LICENSE

local Bullets = {}
local H = {}

-- ## Setup
Bullets.setup = function(config)
  _G.Bullets = Bullets
  config = H.setup_config(config)
  H.apply_config(config)
end

Bullets.config = {
  colon_indent = true,
  delete_last_bullet = true,
  empty_buffers = true,
  file_types = { 'markdown', 'text', 'gitcommit' },
  line_spacing = 1,
  mappings = true,
  outline_levels = { 'ROM', 'ABC', 'num', 'abc', 'rom', 'std*', 'std-', 'std+' },
  renumber = true,
  alpha = { len = 2 },
  checkbox = {
    nest = true,
    markers = ' .oOx',
    toggle_partials = true,
  },
}
H.default_config = Bullets.config

H.setup_config = function(config)
  config = vim.tbl_deep_extend('force', H.default_config, config or {})
  return config
end

H.apply_config = function(config)
  local power = config.alpha.len
  config.abc_max = -1
  while power >= 0 do
    config.abc_max = config.abc_max + 26 ^ power
    power = power - 1
  end
  Bullets.config = config

  -- User commands
  vim.api.nvim_create_user_command('BulletDemote', function() Bullets.change_bullet_level(-1, 0) end, {})
  vim.api.nvim_create_user_command('BulletDemoteVisual', function() Bullets.change_bullet_level(-1, 1) end, { range = true })
  vim.api.nvim_create_user_command('BulletPromote', function() Bullets.change_bullet_level(1, 0) end, {})
  vim.api.nvim_create_user_command('BulletPromoteVisual', function() Bullets.change_bullet_level(1, 1) end, { range = true })
  vim.api.nvim_create_user_command('InsertNewBulletCR', function() Bullets.insert_new_bullet("cr") end, {})
  vim.api.nvim_create_user_command('InsertNewBulletO', function() Bullets.insert_new_bullet("o") end, {})
  vim.api.nvim_create_user_command('RenumberList', function() Bullets.renumber_whole_list() end, {})
  vim.api.nvim_create_user_command('RenumberSelection', function() Bullets.renumber_selection() end, { range = true })
  vim.api.nvim_create_user_command('SelectCheckbox', function() Bullets.select_checkbox(false) end, {})
  vim.api.nvim_create_user_command('SelectCheckboxInside', function() Bullets.select_checkbox(true) end, {})
  vim.api.nvim_create_user_command('ToggleCheckbox', function() Bullets.toggle_checkboxes_nested() end, {})

  -- Key mappings
  vim.api.nvim_set_keymap('i', '<Plug>(bullets-newline-cr)', '<C-O>:InsertNewBulletCR<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<Plug>(bullets-newline-o)', ':InsertNewBulletO<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('v', '<Plug>(bullets-renumber)', ':RenumberSelection<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<Plug>(bullets-renumber)', ':RenumberList<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<Plug>(bullets-toggle-checkbox)', ':ToggleCheckbox<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('i', '<Plug>(bullets-demote)', '<C-O>:BulletDemote<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<Plug>(bullets-demote)', ':BulletDemote<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('v', '<Plug>(bullets-demote)', ':BulletDemoteVisual<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('i', '<Plug>(bullets-promote)', '<C-O>:BulletPromote<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<Plug>(bullets-promote)', ':BulletPromote<cr>', { noremap = true, silent = true })
  vim.api.nvim_set_keymap('v', '<Plug>(bullets-promote)', ':BulletPromoteVisual<cr>', { noremap = true, silent = true })

  if config.mappings then
    vim.api.nvim_create_augroup('BulletMaps', { clear = true })
    H.buf_map('imap', '<cr>', '<Plug>(bullets-newline-cr)')
    H.buf_map('nmap', 'o', '<Plug>(bullets-newline-o)')
    H.buf_map('vmap', 'gN', '<Plug>(bullets-renumber)')
    H.buf_map('nmap', 'gN', '<Plug>(bullets-renumber)')
    H.buf_map('nmap', '<leader>x', '<Plug>(bullets-toggle-checkbox)')
    H.buf_map('imap', '<C-t>', '<Plug>(bullets-demote)')
    H.buf_map('nmap', '>>', '<Plug>(bullets-demote)')
    H.buf_map('vmap', '>', '<Plug>(bullets-demote)')
    H.buf_map('imap', '<C-d>', '<Plug>(bullets-promote)')
    H.buf_map('nmap', '<<', '<Plug>(bullets-promote)')
    H.buf_map('vmap', '<', '<Plug>(bullets-promote)')
  end
end

H.buf_map = function(mode, lhs, rhs)
  local fts = table.concat(Bullets.config.file_types, ',')
  vim.api.nvim_create_autocmd('Filetype', {
    pattern = fts,
    group = 'BulletMaps',
    command = mode .. ' <silent> <buffer> ' .. lhs .. ' ' .. rhs
  })
  if Bullets.config.empty_buffers then
    vim.api.nvim_create_autocmd('BufEnter', {
      group = 'BulletMaps',
      command = 'if bufname("") == ""|' .. mode .. ' <silent> <buffer> ' .. lhs .. ' ' .. rhs .. '| endif'
    })
  end
end

-- ## Helper Functions

-- **Optimized**: Line and indent caching utilities
local function get_lines_cache(start_ln, end_ln)
  local lines = {}
  for nr = start_ln, end_ln do
    lines[nr] = vim.fn.getline(nr)
  end
  return lines
end

H.define_bullet = function(match, btype, line_num)
  if not match or not next(match) then return {} end
  return {
    type = btype,
    bullet_length = #match[3],
    leading_space = match[4],
    bullet = match[5],
    checkbox_marker = type(match[6]) ~= "number" and match[6] or "",
    closure = type(match[7]) ~= "number" and match[7] or "",
    trailing_space = match[8],
    text_after_bullet = match[9],
    starting_at_line_num = line_num
  }
end

-- **Optimized**: Regex pre-check and simplified pattern construction
H.parse_bullet = function(line_num, input_text)
  if not input_text:match("^%s*[-%*%+%.%d]") then return {} end

  local std_pattern = '^((%s*)([%+%-%*%.])()()(%s+))(.*)'
  local chk_pattern = '^((%s*)([%-%*%+]) %[([' .. Bullets.config.checkbox.markers .. ' xX])%]()(%s+))(.*)'
  local num_pattern = '^((%s*)(%d+)()([%.%)])(%s+))(.*)'
  local rom_pattern = '\\v\\C^((\\s*)(M{0,4}%(CM|CD|D?C{0,3})%(XC|XL|L?X{0,3})%(IX|IV|V?I{0,3})|m{0,4}%(cm|cd|d?c{0,3})%(xc|xl|l?x{0,3})%(ix|iv|v?i{0,3}))()(\\.|\\))(\\s+))(.*)'
  local abc_pattern = '^((%s*)([a-zA-Z]+)()([%.%)])(%s+))(.*)'

  local matches = { input_text:find(chk_pattern) }
  if next(matches) then return H.define_bullet(matches, 'chk', line_num) end

  matches = { input_text:find(std_pattern) }
  if next(matches) then return H.define_bullet(matches, 'std', line_num) end

  matches = { input_text:find(num_pattern) }
  if next(matches) then return H.define_bullet(matches, 'num', line_num) end

  matches = vim.fn.matchlist(input_text, rom_pattern)
  if next(matches) then
    table.insert(matches, 1, 0)
    return H.define_bullet(matches, 'rom', line_num)
  end

  matches = { input_text:find(abc_pattern) }
  if next(matches) then return H.define_bullet(matches, 'abc', line_num) end

  return {}
end

-- **Optimized**: Memoization for closest bullet types
local closest_bullet_cache = {}
H.closest_bullet_types = function(from_line_num, max_indent, lines)
  local cache_key = from_line_num .. ":" .. max_indent
  if closest_bullet_cache[cache_key] then return closest_bullet_cache[cache_key] end

  local lnum = from_line_num
  local ltxt = lines and lines[lnum] or vim.fn.getline(lnum)
  local curr_indent = vim.fn.indent(lnum)
  local bullet_kinds = H.parse_bullet(lnum, ltxt)

  if max_indent < 0 then return {} end

  while lnum > 1 and (max_indent < curr_indent or not next(bullet_kinds)) and
        (curr_indent ~= 0 or next(bullet_kinds)) and not ltxt:match("^%s*$") do
    lnum = next(bullet_kinds) and lnum - Bullets.config.line_spacing or lnum - 1
    ltxt = lines and lines[lnum] or vim.fn.getline(lnum)
    bullet_kinds = H.parse_bullet(lnum, ltxt)
    curr_indent = vim.fn.indent(lnum)
  end

  closest_bullet_cache[cache_key] = bullet_kinds
  return bullet_kinds
end

H.contains_type = function(bullet_types, type)
  for _, t in ipairs(bullet_types) do
    if t.type == type then return true end
  end
  return false
end

H.find_by_type = function(bullet_types, type)
  for _, bullet in ipairs(bullet_types) do
    if bullet.type == type then return bullet end
  end
  return {}
end

H.has_rom_or_abc = function(bullet_types)
  return H.contains_type(bullet_types, 'rom') or H.contains_type(bullet_types, 'abc')
end

H.has_chk_or_std = function(bullet_types)
  return H.contains_type(bullet_types, 'chk') or H.contains_type(bullet_types, 'std')
end

-- **Optimized**: Memoization for conversions
local dec2abc_cache = {}
H.dec2abc = function(dec, islower)
  local key = dec .. ":" .. tostring(islower)
  if dec2abc_cache[key] then return dec2abc_cache[key] end

  local a = islower and 'a' or 'A'
  local rem = (dec - 1) % 26
  local abc = string.char(rem + a:byte())
  local result = dec <= 26 and abc or H.dec2abc(math.floor((dec - 1) / 26), islower) .. abc
  dec2abc_cache[key] = result
  return result
end

local abc2dec_cache = {}
H.abc2dec = function(abc)
  local cba = abc:lower()
  if abc2dec_cache[cba] then return abc2dec_cache[cba] end

  local a = 'a'
  local dec = cba:byte(1) - a:byte() + 1
  local result = #cba == 1 and dec or math.floor(26 ^ (#cba - 1)) * dec + H.abc2dec(cba:sub(2))
  abc2dec_cache[cba] = result
  return result
end

H.resolve_rom_or_abc = function(bullet_types)
  local first_type = bullet_types
  local prev_line = first_type.starting_at_line_num - Bullets.config.line_spacing
  local bullet_indent = vim.fn.indent(first_type.starting_at_line_num)
  local prev_bullet_types = H.closest_bullet_types(prev_line, bullet_indent)

  while next(prev_bullet_types) and bullet_indent <= vim.fn.indent(prev_line) do
    prev_line = prev_line - Bullets.config.line_spacing
    prev_bullet_types = H.closest_bullet_types(prev_line, bullet_indent)
  end

  if not next(prev_bullet_types) or bullet_indent > vim.fn.indent(prev_line) then
    return H.find_by_type(bullet_types, 'rom')
  elseif #prev_bullet_types == 1 and H.has_rom_or_abc(prev_bullet_types) then
    if H.abc2dec(prev_bullet_types.bullet) - H.abc2dec(first_type.bullet) == 0 then
      return H.find_by_type(bullet_types, prev_bullet_types[1].type)
    end
  end
  if H.has_rom_or_abc(prev_bullet_types) then
    local prev_bullet = H.resolve_rom_or_abc(prev_bullet_types)
    return H.find_by_type(bullet_types, prev_bullet.type)
  else
    return H.find_by_type(bullet_types, 'rom')
  end
end

H.resolve_chk_or_std = function(bullet_types)
  return H.find_by_type(bullet_types, 'chk')
end

H.resolve_bullet_type = function(bullet_types)
  if not next(bullet_types) then return {} end
  if H.has_rom_or_abc(bullet_types) then return H.resolve_rom_or_abc(bullet_types) end
  if H.has_chk_or_std(bullet_types) then return H.resolve_chk_or_std(bullet_types) end
  return bullet_types
end

-- **Optimized**: Simplified Roman numeral conversion
H.num_to_rom = function(s, islower)
  local numbers = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }
  local chars = { "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" }
  s = math.floor(s)
  if s <= 0 then return tostring(s) end
  local ret = ""
  for i, num in ipairs(numbers) do
    while s >= num do
      ret = ret .. chars[i]
      s = s - num
    end
  end
  return islower and ret or ret:upper()
end

H.rom_to_num = function(s)
  local map = { i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000 }
  s = s:lower()
  local ret = 0
  for i = 1, #s do
    local m = map[s:sub(i, i)]
    if i < #s and map[s:sub(i + 1, i + 1)] > m then
      ret = ret + (map[s:sub(i + 1, i + 1)] - m)
      i = i + 1
    else
      ret = ret + m
    end
  end
  return ret
end

H.next_rom_bullet = function(bullet)
  return H.num_to_rom(H.rom_to_num(bullet.bullet) + 1, bullet.bullet == bullet.bullet:lower())
end

H.next_abc_bullet = function(bullet)
  return H.dec2abc(H.abc2dec(bullet.bullet) + 1, bullet.bullet == bullet.bullet:lower())
end

H.next_num_bullet = function(bullet)
  return tostring(tonumber(bullet.bullet) + 1)
end

H.next_chk_bullet = function(bullet)
  return bullet.bullet:sub(1, 1) .. " [" .. Bullets.config.checkbox.markers:sub(1, 1) .. "]"
end

H.next_bullet_str = function(bullet)
  local next_bullet_marker = bullet.type == "rom" and H.next_rom_bullet(bullet) or
                            bullet.type == "abc" and H.next_abc_bullet(bullet) or
                            bullet.type == "num" and H.next_num_bullet(bullet) or
                            bullet.type == "chk" and H.next_chk_bullet(bullet) or
                            bullet.bullet
  return bullet.leading_space .. next_bullet_marker .. bullet.closure .. bullet.trailing_space
end

H.line_ends_in_colon = function(lnum)
  local line = vim.fn.getline(lnum)
  return line:sub(-1) == ":"
end

H.change_line_bullet_level = function(direction, lnum)
  local curr_line = H.parse_bullet(lnum, vim.fn.getline(lnum))
  local indent = vim.fn.indent(lnum)

  if direction == 1 then
    if next(curr_line) and indent == 0 then
      vim.fn.setline(lnum, curr_line.text_after_bullet)
      return
    else
      vim.cmd(lnum .. "normal! <<")
    end
  else
    vim.cmd(lnum .. "normal! >>")
  end

  if not next(curr_line) then
    if vim.fn.mode() == 'i' then vim.cmd("startinsert!") end
    local keys = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
    vim.api.nvim_feedkeys(keys, 'n', true)
    return
  end

  local curr_indent = vim.fn.indent(lnum)
  local curr_bullet = H.resolve_bullet_type(H.closest_bullet_types(lnum, curr_indent))
  local closest_bullet = H.resolve_bullet_type(H.closest_bullet_types(curr_bullet.starting_at_line_num - Bullets.config.line_spacing, curr_indent))

  if not next(closest_bullet) then return end

  local islower = closest_bullet.bullet == closest_bullet.bullet:lower()
  local closest_indent = vim.fn.indent(closest_bullet.starting_at_line_num)
  local closest_type = islower and closest_bullet.type or closest_bullet.type:upper()
  if closest_bullet.type == 'std' then closest_type = closest_type .. closest_bullet.bullet end

  local outline_levels = Bullets.config.outline_levels
  local closest_index = -1
  for i, j in ipairs(outline_levels) do
    if closest_type == j then
      closest_index = i
      break
    end
  end
  if closest_index == -1 then return end

  local bullet_str
  if curr_indent == closest_indent then
    bullet_str = H.next_bullet_str(closest_bullet) .. curr_bullet.text_after_bullet
  elseif closest_index + 1 > #outline_levels and curr_indent > closest_indent then
    return
  elseif closest_index + 1 <= #outline_levels or curr_indent < closest_indent then
    local next_type = outline_levels[closest_index + 1]
    local next_islower = next_type == next_type:lower()
    curr_bullet.closure = closest_bullet.closure
    local next_num = (next_type == 'rom' or next_type == 'ROM') and H.num_to_rom(1, next_islower) or
                     (next_type == 'abc' or next_type == 'ABC') and H.dec2abc(1, next_islower) or
                     next_type == 'num' and '1' or next_type:sub(-1)
    curr_bullet.closure = next_type:match('std') and '' or curr_bullet.closure
    bullet_str = curr_bullet.leading_space .. next_num .. curr_bullet.closure .. curr_bullet.trailing_space .. curr_bullet.text_after_bullet
  else
    bullet_str = curr_bullet.leading_space .. curr_bullet.text_after_bullet
  end

  vim.fn.setline(lnum, bullet_str)
end

Bullets.change_bullet_level = function(direction, is_visual)
  local sel = H.get_selection(is_visual)
  for lnum = sel.start_line, sel.end_line do
    H.change_line_bullet_level(direction, lnum)
  end
  if Bullets.config.renumber then Bullets.renumber_whole_list() end
  H.set_selection(sel)
end

H.first_bullet_line = function(line_num, min_indent)
  local indent = min_indent or 0
  if indent < 0 then return -1 end
  local first_line = line_num
  local lnum = line_num - Bullets.config.line_spacing
  local curr_indent = vim.fn.indent(lnum)
  local bullet_kinds = H.closest_bullet_types(lnum, curr_indent)

  while lnum >= 1 and curr_indent >= indent and next(bullet_kinds) do
    first_line = lnum
    lnum = lnum - Bullets.config.line_spacing
    curr_indent = vim.fn.indent(lnum)
    bullet_kinds = H.closest_bullet_types(lnum, curr_indent)
  end
  return first_line
end

H.last_bullet_line = function(line_num, min_indent)
  local indent = min_indent or 0
  if indent < 0 then return -1 end
  local lnum = line_num
  local buf_end = vim.fn.line('$')
  local last_line = -1
  local curr_indent = vim.fn.indent(lnum)
  local bullet_kinds = H.closest_bullet_types(lnum, curr_indent)
  local blank_lines = 0

  while lnum <= buf_end and blank_lines < Bullets.config.line_spacing and curr_indent >= indent do
    if next(bullet_kinds) then
      last_line = lnum
      blank_lines = 0
    else
      blank_lines = blank_lines + 1
    end
    lnum = lnum + 1
    curr_indent = vim.fn.indent(lnum)
    bullet_kinds = H.closest_bullet_types(lnum, curr_indent)
  end
  return last_line
end

H.get_selection = function(is_visual)
  local sel = {}
  local mode = is_visual ~= 0 and vim.fn.visualmode() or ""
  if mode == "v" or mode == "V" or mode == "\22" then
    local start = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    sel.start_line = start[2]
    sel.start_offset = #vim.fn.getline(sel.start_line) - start[3]
    sel.end_line = end_pos[2]
    sel.end_offset = #vim.fn.getline(sel.end_line) - end_pos[3]
    sel.visual_mode = mode
  else
    sel.start_line = vim.fn.line(".")
    sel.start_offset = #vim.fn.getline(sel.start_line) - vim.fn.col(".")
    sel.end_line = sel.start_line
    sel.end_offset = sel.start_offset
    sel.visual_mode = ""
  end
  return sel
end

H.set_selection = function(sel)
  local start_col = #vim.fn.getline(sel.start_line) - sel.start_offset
  local end_col = #vim.fn.getline(sel.end_line) - sel.end_offset
  vim.fn.cursor(sel.start_line, start_col)
  if sel.start_line ~= sel.end_line or start_col ~= end_col then
    if sel.visual_mode == "V" or sel.visual_mode == "v" then vim.cmd("normal! v") end
    vim.fn.cursor(sel.end_line, end_col)
  end
end

-- ## Checkboxes
H.find_checkbox_position = function(lnum)
  return vim.fn.matchend(vim.fn.getline(lnum), "\\v\\s*(\\*|-) \\[") + 1
end

Bullets.select_checkbox = function(inner)
  local lnum = vim.fn.line('.')
  local checkbox_col = H.find_checkbox_position(lnum)
  if checkbox_col > 0 then
    vim.fn.setpos('.', {0, lnum, checkbox_col})
    vim.cmd("normal! " .. (inner and "vi[" or "va["))
  end
end

H.set_checkbox = function(lnum, marker)
  local curline = vim.fn.getline(lnum)
  local initpos = vim.fn.getpos('.')
  local pos = H.find_checkbox_position(lnum)
  if pos >= 0 then
    vim.fn.setline(lnum, curline:sub(1, pos - 1) .. marker .. curline:sub(pos + 1))
    vim.fn.setpos('.', initpos)
  end
end

H.toggle_checkbox = function(lnum)
  local bullet = H.resolve_bullet_type(H.closest_bullet_types(lnum, vim.fn.indent(lnum)))
  if not next(bullet) or not bullet.checkbox_marker then return -1 end

  local markers = Bullets.config.checkbox.markers
  local partial = markers:sub(2, -2)
  local marker = markers:sub(1, 1)
  local content = bullet.checkbox_marker
  if Bullets.config.checkbox.toggle_partials and partial:find(content) then
    marker = markers:sub(-1)
  elseif content == markers:sub(1, 1) then
    marker = markers:sub(-1)
  elseif content:match('[xX]') or content == markers:sub(-1) then
    marker = markers:sub(1, 1)
  else
    return -1
  end

  H.set_checkbox(lnum, marker)
  return marker == markers:sub(-1) and 1 or 0
end

H.get_sibling_line_numbers = function(lnum)
  local indent = vim.fn.indent(lnum)
  local first = H.first_bullet_line(lnum, indent)
  local last = H.last_bullet_line(lnum, indent)
  local siblings = {}
  for l = first, last do
    if vim.fn.indent(l) == indent and next(H.parse_bullet(l, vim.fn.getline(l))) then
      table.insert(siblings, l)
    end
  end
  return siblings
end

H.get_children_line_numbers = function(line_num)
  if line_num < 1 then return {} end
  local lnum = line_num + 1
  local buf_end = vim.fn.line('$')
  local indent = vim.fn.indent(line_num)
  local curr_indent = vim.fn.indent(lnum)
  local bullet_kinds = H.closest_bullet_types(lnum, curr_indent)
  local child_lnum = 0
  local blank_lines = 0

  while lnum <= buf_end and child_lnum == 0 do
    if next(bullet_kinds) and curr_indent > indent then
      child_lnum = lnum
    else
      blank_lines = blank_lines + 1
      child_lnum = blank_lines >= Bullets.config.line_spacing and -1 or 0
    end
    lnum = lnum + 1
    curr_indent = vim.fn.indent(lnum)
    bullet_kinds = H.closest_bullet_types(lnum, curr_indent)
  end

  return child_lnum > 0 and H.get_sibling_line_numbers(child_lnum) or {}
end

H.sibling_checkbox_status = function(lnum)
  local siblings = H.get_sibling_line_numbers(lnum)
  local num_siblings = #siblings
  local checked = 0
  local markers = Bullets.config.checkbox.markers
  for _, l in ipairs(siblings) do
    local bullet = H.resolve_bullet_type(H.closest_bullet_types(l, vim.fn.indent(l)))
    if next(bullet) and bullet.checkbox_marker ~= "" and markers:sub(2):find(bullet.checkbox_marker) then
      checked = checked + 1
    end
  end
  local divisions = #markers - 1
  return markers:sub(1 + math.floor(divisions * checked / num_siblings), 1)
end

H.get_parent = function(lnum)
  local indent = vim.fn.indent(lnum)
  if indent < 0 then return {} end
  return H.resolve_bullet_type(H.closest_bullet_types(lnum, indent - 1))
end

H.set_parent_checkboxes = function(lnum, marker)
  if not Bullets.config.checkbox.nest then return end
  local parent = H.get_parent(lnum)
  if next(parent) and parent.type == 'chk' then
    local pnum = parent.starting_at_line_num
    H.set_checkbox(pnum, marker)
    H.set_parent_checkboxes(pnum, H.sibling_checkbox_status(pnum))
  end
end

H.set_child_checkboxes = function(lnum, checked)
  if not Bullets.config.checkbox.nest or not (checked == 0 or checked == 1) then return end
  local children = H.get_children_line_numbers(lnum)
  if next(children) then
    local markers = Bullets.config.checkbox.markers
    local marker = checked == 1 and markers:sub(-1) or markers:sub(1, 1)
    for _, child in ipairs(children) do
      H.set_checkbox(child, marker)
      H.set_child_checkboxes(child, checked)
    end
  end
end

Bullets.toggle_checkboxes_nested = function()
  local lnum = vim.fn.line('.')
  local bullet = H.resolve_bullet_type(H.closest_bullet_types(lnum, vim.fn.indent(lnum)))
  if not next(bullet) or bullet.type ~= 'chk' then return end

  local checked = H.toggle_checkbox(lnum)
  if Bullets.config.checkbox.nest then
    H.set_parent_checkboxes(lnum, H.sibling_checkbox_status(lnum))
    if checked then H.set_child_checkboxes(lnum, checked) end
  end
end

-- ## Renumbering
H.get_level = function(bullet)
  return next(bullet) and bullet.type == 'std' and #bullet.bullet or 0
end

Bullets.renumber_selection = function()
  local sel = H.get_selection(1)
  Bullets.renumber_lines(sel.start_line, sel.end_line)
  H.set_selection(sel)
end

-- **Optimized**: Batch updates with line caching
Bullets.renumber_lines = function(start_ln, end_ln)
  local lines = get_lines_cache(start_ln, end_ln)
  local new_lines = {}
  local prev_indent = -1
  local list = {}

  for nr = start_ln, end_ln do
    local indent = vim.fn.indent(nr)
    local bullet = H.resolve_bullet_type(H.closest_bullet_types(nr, indent, lines))
    if H.get_level(bullet) > 1 then break end

    if next(bullet) and bullet.starting_at_line_num == nr then
      if indent > prev_indent or not list[indent] then
        if bullet.type ~= 'chk' and bullet.type ~= 'std' then
          list[indent] = {
            index = bullet.type == 'num' and bullet.bullet or
                    bullet.type == 'rom' and H.rom_to_num(bullet.bullet) or
                    bullet.type == 'abc' and H.abc2dec(bullet.bullet) or 1,
            islower = bullet.bullet == bullet.bullet:lower(),
            type = bullet.type,
            closure = bullet.closure,
            trailing_space = bullet.trailing_space
          }
        end
      else
        if bullet.type ~= 'chk' and bullet.type ~= 'std' then
          list[indent].index = list[indent].index + 1
        end
        if indent < prev_indent then
          for key in pairs(list) do if key > indent then list[key] = nil end end
        end
      end
      prev_indent = indent
      if list[indent] then
        local bullet_num = list[indent].index
        if bullet.type == 'rom' then
          bullet_num = H.num_to_rom(bullet_num, list[indent].islower)
        elseif bullet.type == 'abc' then
          bullet_num = H.dec2abc(bullet_num, list[indent].islower)
        end
        new_lines[nr - start_ln + 1] = bullet.leading_space .. bullet_num .. list[indent].closure .. list[indent].trailing_space .. bullet.text_after_bullet
      elseif bullet.type == 'chk' then
        new_lines[nr - start_ln + 1] = lines[nr]
        H.set_checkbox(nr, bullet.checkbox_marker or ' ')
      end
    end
    if not new_lines[nr - start_ln + 1] then
      new_lines[nr - start_ln + 1] = lines[nr]
    end
  end

  vim.api.nvim_buf_set_lines(0, start_ln - 1, end_ln, false, new_lines)
end

Bullets.renumber_whole_list = function()
  local first_line = H.first_bullet_line(vim.fn.line('.'))
  local last_line = H.last_bullet_line(vim.fn.line('.'))
  if first_line > 0 and last_line > 0 then Bullets.renumber_lines(first_line, last_line) end
end

Bullets.insert_new_bullet = function(trigger)
  local curr_line_num = vim.fn.line('.')
  local cursor_pos = vim.fn.getcurpos('.')
  local line_text = vim.fn.getline('.')
  local next_line_num = curr_line_num + Bullets.config.line_spacing
  local curr_indent = vim.fn.indent(curr_line_num)
  local bullet_types = H.closest_bullet_types(curr_line_num, curr_indent)
  local send_return = true
  local normal_mode = vim.fn.mode() == 'n'
  local indent_next = H.line_ends_in_colon(curr_line_num) and Bullets.config.colon_indent
  local next_bullet_list = {}

  if next(bullet_types) then
    local bullet = H.resolve_bullet_type(bullet_types)
    local is_at_eol = #line_text + 1 == vim.fn.col('.')
    if next(bullet) and (normal_mode or is_at_eol) then
      if bullet.text_after_bullet == '' then
        if Bullets.config.delete_last_bullet then
          vim.fn.setline(curr_line_num, '')
          send_return = false
        end
      elseif not (bullet.type == 'abc' and H.abc2dec(bullet.bullet) + 1 > Bullets.config.abc_max) then
        local text_after_cursor = trigger == 'cr' and line_text:sub(cursor_pos[3]) or ''
        if text_after_cursor ~= '' then vim.fn.setline('.', line_text:sub(1, cursor_pos[3] - 1)) end
        local next_bullet = H.next_bullet_str(bullet) .. text_after_cursor
        next_bullet_list = { next_bullet }
        if Bullets.config.line_spacing > 1 then
          for i = 1, Bullets.config.line_spacing - 1 do table.insert(next_bullet_list, 1, '') end
        end
        vim.fn.append(curr_line_num, next_bullet_list)
        local col = #vim.fn.getline(next_line_num) + 1
        vim.fn.setpos('.', {0, next_line_num, col})
        if indent_next then
          H.change_line_bullet_level(-1, next_line_num)
          col = #vim.fn.getline(next_line_num) + 1
          vim.fn.setpos('.', {0, next_line_num, col})
        elseif Bullets.config.renumber then
          Bullets.renumber_whole_list()
        end
      end
      send_return = false
    end
  end

  if send_return then
    if trigger == "cr" and normal_mode then vim.cmd('startinsert')
    elseif trigger == 'o' then vim.cmd('startinsert!') end
    local keys = vim.api.nvim_replace_termcodes('<CR>', true, false, true)
    vim.api.nvim_feedkeys(keys, 'n', true)
  elseif trigger == 'o' then vim.cmd('startinsert!') end

  return ''
end

return Bullets
