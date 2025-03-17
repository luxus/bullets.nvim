-- bullets.nvim
-- Optimized for performance and functionality
-- License: GPLv3, MIT
-- Based on Keith Miyake's work

-- Cache frequently used Vim API functions for performance
local api = vim.api
local fn = vim.fn
local tbl_deep_extend = vim.tbl_deep_extend

local Bullets = {}
local H = {
  regex_cache = {},  -- Cache for compiled regex patterns
  bullet_cache = {}  -- Global memoization cache for bullets
}

-- Roman numeral conversion tables
local ROMAN_VALS = {
  I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000,
  i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000
}

local ROMAN_NUMERALS = {
  {1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"},
  {100, "C"}, {90, "XC"}, {50, "L"}, {40, "XL"},
  {10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}
}

-- Setup function to initialize the plugin with user configuration
Bullets.setup = function(config)
  _G.Bullets = Bullets
  config = H.setup_config(config)
  H.apply_config(config)
  H.compile_regex_patterns()  -- Compile regex patterns once on setup
end

-- Default configuration
Bullets.config = {
  colon_indent = true,
  delete_last_bullet = true,
  empty_buffers = true,
  file_types = { 'markdown', 'text', 'gitcommit' },
  line_spacing = 1,
  mappings = true,
  outline_levels = {'ROM','ABC', 'num', 'abc', 'rom', 'std*', 'std-', 'std+'},
  renumber = true,
  alpha = {
    len = 2,
  },
  checkbox = {
    nest = true,
    markers = ' .oOx',
    toggle_partials = true,
  },
}
H.default_config = Bullets.config

-- Compile regex patterns based on configuration (done once for performance)
H.compile_regex_patterns = function()
  local checkbox_markers = Bullets.config.checkbox.markers:gsub('[%[%]%(%)%.%+%-%*%?%^%$]', '%%%1')
  
  -- Pre-compile all regex patterns
  H.regex_cache = {
    -- Check for any bullet-like characters (fast pre-check)
    bullet_precheck = "^%s*[-%*%+%.%d%a]",
    
    -- Pattern tables for string.match
    std_bullet = {'^((%s*)([%+%-%*%.])()()(%s+))(.*)'},
    checkbox_bullet = {'^((%s*)([%-%*%+]) %[([' .. checkbox_markers .. ' xX])%]()(%s+))(.*)'},
    num_bullet = {'^((%s*)(%d+)()([%.%)])(%s+))(.*)'},
    
    -- Roman numeral regex (for vim.fn.matchlist)
    rom_bullet = '\\v\\C^((\\s*)(M{0,4}%(CM|CD|D?C{0,3})%(XC|XL|L?X{0,3})%(IX|IV|V?I{0,3})|m{0,4}%(cm|cd|d?c{0,3})%(xc|xl|l?x{0,3})%(ix|iv|v?i{0,3}))()(\\.|\\))(\\s+))(.*)',
  }
  
  -- Build alphabet regex based on config
  local max = Bullets.config.alpha.len
  local az = "[%a]"
  local abc = ""
  for _ = 1, max do
    abc = abc .. az .. "?"
  end
  H.regex_cache.abc_bullet = {'^((%s*)(' .. abc .. ')()([%.%)])(%s+))(.*)'}
end

-- Merge user config with defaults
H.setup_config = function(config)
  return tbl_deep_extend('force', H.default_config, config or {})
end

-- Apply configuration and compute derived values
H.apply_config = function(config)
  -- Calculate maximum value for alphabetic bullets
  local abc_max = -1
  local power = config.alpha.len
  
  while power >= 0 do
    abc_max = abc_max + 26 ^ power
    power = power - 1
  end
  
  config.abc_max = abc_max
  Bullets.config = config
end

-- Efficient line caching with pre-allocation
local function get_lines_cache(start_ln, end_ln)
  local count = end_ln - start_ln + 1
  local lines = {}
  
  -- Pre-allocate table size for better performance
  for i = 1, count do
    lines[start_ln + i - 1] = nil
  end
  
  for nr = start_ln, end_ln do
    lines[nr] = fn.getline(nr)
  end
  
  return lines
end

-- Define bullet properties from regex match (optimized)
H.define_bullet = function(match, btype, line_num)
  if not match or #match == 0 then
    return {}
  end
  
  return {
    type = btype,
    bullet_length = #match[3],
    leading_space = match[2],
    bullet = match[3],
    checkbox_marker = type(match[4]) ~= "number" and match[4] or "",
    closure = type(match[5]) ~= "number" and match[5] or "",
    trailing_space = match[6],
    text_after_bullet = match[7],
    starting_at_line_num = line_num
  }
end

-- Parse a line to identify bullet type with efficient pre-check
H.parse_bullet = function(line_num, input_text)
  -- Quick pre-check with cached pattern (avoid expensive regex for non-bullets)
  if not input_text:match(H.regex_cache.bullet_precheck) then
    return {}
  end

  -- Cache key for memoization
  local cache_key = line_num .. ":" .. input_text
  if H.bullet_cache[cache_key] then
    return H.bullet_cache[cache_key]
  end

  local result = {}
  local matches

  -- Try patterns in order of specificity and likelihood for early return
  if input_text:find("%[") then -- Only check checkbox if it has a bracket
    matches = {string.match(input_text, table.unpack(H.regex_cache.checkbox_bullet))}
    if #matches > 0 then
      result = H.define_bullet(matches, 'chk', line_num)
      H.bullet_cache[cache_key] = result
      return result
    end
  end
  
  -- Only check standard bullets if it starts with a standard bullet character
  if input_text:match("^%s*[%+%-%*%.]") then
    matches = {string.match(input_text, table.unpack(H.regex_cache.std_bullet))}
    if #matches > 0 then
      result = H.define_bullet(matches, 'std', line_num)
      H.bullet_cache[cache_key] = result
      return result
    end
  end
  
  -- Check numeric bullets
  if input_text:match("^%s*%d") then
    matches = {string.match(input_text, table.unpack(H.regex_cache.num_bullet))}
    if #matches > 0 then
      result = H.define_bullet(matches, 'num', line_num)
      H.bullet_cache[cache_key] = result
      return result
    end
  end
  
  -- Try roman numerals (only if it looks like it might be one)
  if input_text:match("^%s*[IVXivx]") then
    matches = fn.matchlist(input_text, H.regex_cache.rom_bullet)
    if #matches > 0 then
      table.insert(matches, 1, 0)  -- Add a dummy element to match other formats
      result = H.define_bullet(matches, 'rom', line_num)
      H.bullet_cache[cache_key] = result
      return result
    end
  end
  
  -- Try alphabetic bullets (only if it starts with a letter)
  if input_text:match("^%s*%a") then
    matches = {string.match(input_text, table.unpack(H.regex_cache.abc_bullet))}
    if #matches > 0 then
      result = H.define_bullet(matches, 'abc', line_num)
      H.bullet_cache[cache_key] = result
      return result
    end
  end

  H.bullet_cache[cache_key] = {}
  return {}
end

-- Find closest bullet type with enhanced memoization
H.closest_bullet_types = function(from_line_num, max_indent, lines, cache)
  local cache_key = from_line_num .. ":" .. max_indent
  if cache[cache_key] then
    return cache[cache_key]
  end
  
  local lnum = from_line_num
  local line_spacing = Bullets.config.line_spacing
  local ltxt = lines and lines[lnum] or fn.getline(lnum)
  local curr_indent = fn.indent(lnum)
  local bullet_kinds = H.parse_bullet(lnum, ltxt)
  
  if max_indent < 0 then 
    return {} 
  end
  
  -- Optimized search backwards for a valid bullet point
  while lnum > 1 and 
        (max_indent < curr_indent or next(bullet_kinds) == nil) and 
        (curr_indent ~= 0 or next(bullet_kinds) ~= nil) and 
        not ltxt:match("^%s*$") do
    
    -- Jump back by line_spacing if we found a bullet
    lnum = lnum - (next(bullet_kinds) ~= nil and line_spacing or 1)
    
    ltxt = lines and lines[lnum] or fn.getline(lnum)
    bullet_kinds = H.parse_bullet(lnum, ltxt)
    curr_indent = fn.indent(lnum)
  end
  
  cache[cache_key] = bullet_kinds
  return bullet_kinds
end

-- Resolve bullet type (pass-through for now)
H.resolve_bullet_type = function(bullet)
  return bullet
end

-- Fast Roman numeral conversion using lookup tables
H.rom_to_num = function(rom)
  if not rom or rom == "" then return 1 end
  
  local sum = 0
  local i = 1
  local len = #rom
  
  while i <= len do
    local current = ROMAN_VALS[rom:sub(i, i)] or 0
    local next_val = (i < len) and (ROMAN_VALS[rom:sub(i+1, i+1)] or 0) or 0
    
    if current < next_val then
      sum = sum + (next_val - current)
      i = i + 2
    else
      sum = sum + current
      i = i + 1
    end
  end
  
  return sum
end

-- Optimized number to roman numeral conversion
H.num_to_rom = function(num, islower)
  if not num or num < 1 or num > 3999 then return islower and "i" or "I" end
  
  local result = ""
  
  for _, pair in ipairs(ROMAN_NUMERALS) do
    local val, rom = pair[1], pair[2]
    
    -- Use integer division and multiplication for efficiency
    if num >= val then
      local count = math.floor(num / val)
      result = result .. string.rep(rom, count)
      num = num - (val * count)
    end
  end
  
  return islower and result:lower() or result
end

-- Optimized alphabet to decimal conversion
H.abc2dec = function(abc)
  if not abc or abc == "" then return 1 end
  
  abc = abc:lower()
  local result = 0
  local base = 26
  
  for i = 1, #abc do
    local char = abc:sub(i, i)
    local val = string.byte(char) - 96  -- 'a' is 97, so 'a' becomes 1
    if val >= 1 and val <= 26 then
      result = result * base + val
    end
  end
  
  return result > 0 and result or 1
end

-- Optimized decimal to alphabet conversion
H.dec2abc = function(dec, islower)
  if not dec or dec < 1 then return islower and "a" or "A" end
  
  local result = ""
  local base = 26
  
  -- Faster algorithm with table allocation and concatenation
  local chars = {}
  while dec > 0 do
    local remainder = (dec - 1) % base + 1
    table.insert(chars, 1, string.char(96 + remainder))  -- 96 + 1 = 'a'
    dec = math.floor((dec - remainder) / base)
  end
  
  result = table.concat(chars)
  return islower and result or result:upper()
end

-- Optimized checkbox setting with direct line replacement
H.set_checkbox = function(line_num, marker)
  local line = fn.getline(line_num)
  local new_line = line:gsub('%[.%]', '[' .. marker .. ']', 1)
  if new_line ~= line then
    api.nvim_buf_set_lines(0, line_num - 1, line_num, false, {new_line})
  end
end

-- Fully optimized line renumbering with batch operations
Bullets.renumber_lines = function(start_ln, end_ln)
  if start_ln > end_ln then return end
  
  local lines = get_lines_cache(start_ln, end_ln)
  local bullet_cache = {}
  local new_lines = {}
  local prev_indent = -1
  local list = {}
  local line_count = end_ln - start_ln + 1
  
  -- Pre-allocate the new_lines table for better performance
  for i = 1, line_count do
    new_lines[i] = lines[start_ln + i - 1]
  end
  
  -- Process all lines in a single pass
  for nr = start_ln, end_ln do
    local idx = nr - start_ln + 1
    local indent = fn.indent(nr)
    local bullet = H.closest_bullet_types(nr, indent, lines, bullet_cache)
    bullet = H.resolve_bullet_type(bullet)
    
    if next(bullet) ~= nil and bullet.starting_at_line_num == nr then
      local bullet_type = bullet.type
      local is_numberable = bullet_type ~= 'chk' and bullet_type ~= 'std'
      
      -- Efficient list level handling
      if indent > prev_indent or not list[indent] then
        if is_numberable then
          if not list[indent] then
            local index = bullet.bullet
            
            -- Type-specific conversion
            if bullet_type == 'num' then
              index = tonumber(index) or 1
            elseif bullet_type == 'rom' then
              index = H.rom_to_num(index)
            elseif bullet_type == 'abc' then
              index = H.abc2dec(index)
            end
            
            list[indent] = {index = index}
          end
          
          -- Store bullet properties
          list[indent].islower = bullet.bullet == string.lower(bullet.bullet)
          list[indent].type = bullet_type
          list[indent].closure = bullet.closure
          list[indent].trailing_space = bullet.trailing_space
        end
      else
        -- Increment bullet number for continuing lists
        if is_numberable then
          list[indent].index = list[indent].index + 1
        end
        
        -- Clean up deeper indentation levels when going back
        if indent < prev_indent then
          for key, _ in pairs(list) do
            if key > indent then list[key] = nil end
          end
        end
      end
      
      prev_indent = indent
      
      -- Create the new bullet text efficiently
      if list[indent] and is_numberable then
        local bullet_num = list[indent].index
        
        -- Convert number to appropriate format
        if list[indent].type == 'rom' then
          bullet_num = H.num_to_rom(bullet_num, list[indent].islower)
        elseif list[indent].type == 'abc' then
          bullet_num = H.dec2abc(bullet_num, list[indent].islower)
        end
        
        -- Build new line in a single concatenation
        new_lines[idx] = bullet.leading_space .. 
                         bullet_num .. 
                         list[indent].closure .. 
                         list[indent].trailing_space .. 
                         bullet.text_after_bullet
      elseif bullet_type == 'chk' then
        -- Don't modify the line text, just update the checkbox state
        H.set_checkbox(nr, bullet.checkbox_marker or ' ')
      end
    end
  end

  -- Batch update all lines at once for maximum efficiency
  api.nvim_buf_set_lines(0, start_ln - 1, end_ln, false, new_lines)
  
  -- Clear caches to prevent memory bloat on large files
  if line_count > 1000 then
    H.bullet_cache = {}
  end
end

return Bullets
