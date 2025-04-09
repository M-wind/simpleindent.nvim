local INDENT_SNAPSHOT = {}
local SCOPE_SNAPSHOT = {}

local M = {}
M.current_scope = {}
M.current_marks = {}
M.ns_id = vim.api.nvim_create_namespace("SimpleIndent")
M.conf = {}
M.leftcol = 0

local default_conf = {
  char = "│",
  priority = 2,
  exclude = {
    filetype = { "checkhealth", "help" },
    buftype = { "nofile", "quickfix", "terminal", "prompt" },
  },
}

local validata_list_string = function(data)
  return vim.iter(data):all(function(v)
    return type(v) == "string"
  end)
end

local init_conf = function(conf)
  vim.validate({ conf = { conf, "table", true } })
  if conf.exclude ~= nil then
    vim.list_extend(conf.exclude.filetype or {}, default_conf.exclude.filetype)
    vim.list_extend(conf.exclude.buftype or {}, default_conf.exclude.buftype)
  end
  conf = vim.tbl_deep_extend("force", default_conf, conf or {})
  vim.validate({
    priority = { conf.priority, "number" },
    char = { conf.char, "string" },
    filetype = {
      conf.exclude.filetype,
      function()
        return validata_list_string(conf.exclude.filetype)
      end,
      "exclude[filetype] should be a list string",
    },
    buftype = {
      conf.exclude.buftype,
      function()
        return validata_list_string(conf.exclude.buftype)
      end,
      "exclude[buftype] should be a list string",
    },
  })
  M.conf = conf
end

local stop_draw = function(bufnr, exclude)
  return bufnr ~= vim.api.nvim_get_current_buf()
    or vim.list_contains(exclude.filetype, vim.bo[bufnr].ft)
    or vim.list_contains(exclude.buftype, vim.bo[bufnr].buftype)
end

local contains = function(a, b)
  local contains = a.indent == b.indent and a.top <= b.top and b.top <= a.bottom
  if contains then
    if a.bottom == b.top then
      contains = false
    end
  end
  return contains
end

local get_line_indent = function(row)
  local indent = INDENT_SNAPSHOT[row]
  if indent == nil then
    indent = vim.fn.indent(vim.fn.nextnonblank(row))
    INDENT_SNAPSHOT[row] = indent
  end
  return indent
end

local find_scope = function(row, indent, side, direction)
  local final_row, final_indent = side + direction, get_line_indent(side)
  for i = row + direction, side, direction do
    local new_indent = get_line_indent(i)
    if new_indent < indent then
      final_row = i
      final_indent = new_indent
      break
    end
  end
  return final_row, final_indent
end

local extmark_opts = {
  virt_text_pos = "overlay",
  hl_mode = "combine",
  priority = M.conf.priority,
}

local get_current_scope = function(row, indent, toprow, botrow)
  local top, final_up_indent = find_scope(row, indent, toprow, -1)
  local bottom, final_down_indent = find_scope(row, indent, botrow, 1)
  local final_indent = math.min(final_up_indent, final_down_indent)
  if top == toprow - 1 and bottom == botrow + 1 then
    final_indent = indent - M.shiftwidth
  end
  return {
    top = top,
    bottom = bottom,
    indent = final_indent,
  }
end

-- local on_draw = function(bufnr, row, indent)
--   for j = 0, indent - 1, M.shiftwidth do
--     extmark_opts.virt_text = { { M.conf.char, "IndentLine" } }
--     extmark_opts.virt_text_win_col = j
--     vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, row, 0, extmark_opts)
--   end
-- end

local on_draw_new = function(bufnr, scope)
  extmark_opts.virt_text = { { M.conf.char, "IndentLine" } }
  local col = scope.indent - M.leftcol
  -- extmark_opts.virt_text_win_col = scope.indent
  extmark_opts.virt_text_win_col = col
  if col < 0 then
    return
  end
  for i = scope.top, scope.bottom - 2 do
    vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, i, 0, extmark_opts)
  end
end

local find_current_scope = function(row)
  return vim
    .iter(SCOPE_SNAPSHOT)
    :filter(function(v)
      return v.top <= row and row <= v.bottom
    end)
    :fold({ indent = -1 }, function(acc, v)
      if v.indent >= acc.indent then
        acc = v
      end
      return acc
    end)
end

local update_marks = function(bufnr, hl_group)
  for _, v in pairs(M.current_marks) do
    local col = M.current_scope.indent - M.leftcol
    if v[4].virt_text_win_col == col then
      vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, v[2], 0, {
        id = v[1],
        virt_text_win_col = col,
        virt_text = { { M.conf.char, hl_group } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
        priority = M.conf.priority,
      })
    end
  end
end

local highlight_current = function(bufnr, row)
  local scope = find_current_scope(row)
  if scope.indent == -1 then
    return
  end
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    M.ns_id,
    { scope.top, 0 },
    { scope.bottom - 2, 0 },
    { details = true, type = "virt_text" }
  )
  M.current_scope = scope
  M.current_marks = marks
  update_marks(bufnr, "IndentLineCurrent")
end

local refresh_all = function(bufnr, toprow, botrow)
  INDENT_SNAPSHOT = {}
  SCOPE_SNAPSHOT = {}
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1)
  for i = toprow, botrow do
    local indent = get_line_indent(i)
    if indent <= 0 then
      goto continue
    end
    -- on_draw(bufnr, i - 1, indent)
    local scope = get_current_scope(i, indent, toprow, botrow)
    local is_contains = false
    for j = #SCOPE_SNAPSHOT, 1, -1 do
      if contains(SCOPE_SNAPSHOT[j], scope) then
        is_contains = true
        break
      end
    end
    if is_contains then
      goto continue
    end
    table.insert(SCOPE_SNAPSHOT, scope)
    pcall(on_draw_new, bufnr, scope)
    ::continue::
  end
  local minIndent = vim.iter(SCOPE_SNAPSHOT):fold(10000, function(acc, v)
    if v.indent < acc then
      acc = v.indent
    end
    return acc
  end)
  if minIndent == 0 or minIndent == 10000 then
    return
  end
  for i = 0, minIndent - M.shiftwidth, M.shiftwidth do
    pcall(on_draw_new, bufnr, { top = toprow - 1, bottom = botrow + 1, indent = i })
  end
end

local cmd_event = function(bufnr, event)
  local view = vim.fn.winsaveview()
  local height = vim.api.nvim_win_get_height(0)
  local toprow, botrow = view.topline, view.topline + height - 1
  local shiftwidth = vim.api.nvim_get_option_value("shiftwidth", { buf = bufnr })
  M.shiftwidth = shiftwidth
  M.leftcol = view.leftcol
  -- if view.lnum == M.currow and (event == "CursorMoved" or event == "CursorMovedI") then
  --   return
  -- end
  vim.schedule(function()
    refresh_all(bufnr, toprow, botrow)
    highlight_current(bufnr, view.lnum)
  end)
  -- M.currow = view.lnum
end

return {
  setup = function(conf)
    init_conf(conf)
    vim.api.nvim_create_autocmd(
      { "BufWinEnter", "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "FileType", "WinScrolled" },
      {
        group = vim.api.nvim_create_augroup("SimpleIndent", { clear = true }),
        pattern = "*",
        callback = function(opts)
          if stop_draw(opts.buf, M.conf.exclude) then
            return
          end
          cmd_event(opts.buf, opts.event)
        end,
        desc = "SimpleIndent",
      }
    )
  end,
}

