local util = require "navigator.util"
local log = util.log
local trace = util.trace
local code_action = {}
local gui = require "navigator.gui"
local config = require("navigator").config_values()
local api = vim.api
trace = log

local sign_name = "NavigatorLightBulb"

--- `codeAction/resolve`
-- from neovim buf.lua, change vim.ui.select to gui

local diagnostic = vim.diagnostic or vim.lsp.diagnostic

-- https://github.com/glepnir/lspsaga.nvim/blob/main/lua/lspsaga/codeaction.lua
-- lspsaga has a clever design to inject code action indicator
local sign_group = "nvcodeaction"
local get_namespace = function()
  return api.nvim_create_namespace(sign_group)
end

local get_current_winid = function()
  return api.nvim_get_current_win()
end

local function _update_virtual_text(line, actions)
  local namespace = get_namespace()
  pcall(api.nvim_buf_clear_namespace, 0, namespace, 0, -1)

  if line then
    trace(line, actions)
    local icon_with_indent = "  " .. config.icons.code_action_icon

    local title = actions[1].title
    pcall(api.nvim_buf_set_extmark, 0, namespace, line, -1, {
      virt_text = {{icon_with_indent .. title, "LspDiagnosticsSignHint"}},
      virt_text_pos = "overlay",
      hl_mode = "combine"
    })
  end
end

local function _update_sign(line)

  if vim.tbl_isempty(vim.fn.sign_getdefined(sign_name)) then
    vim.fn.sign_define(sign_name, {
      text = config.icons.code_action_icon,
      texthl = "LspDiagnosticsSignHint"
    })
  end
  local winid = get_current_winid()
  if code_action[winid] == nil then
    code_action[winid] = {}
  end
  if code_action[winid].lightbulb_line ~= 0 then
    vim.fn.sign_unplace(sign_group, {id = code_action[winid].lightbulb_line, buffer = "%"})
  end

  if line then
    -- log("updatasign", line, sign_group, sign_name)
    vim.fn.sign_place(line, sign_group, sign_name, "%",
                      {lnum = line + 1, priority = config.lsp.code_action.sign_priority})
    code_action[winid].lightbulb_line = line
  end
end

-- local need_check_diagnostic = {["go"] = true, ["python"] = true}
local need_check_diagnostic = {['python'] = true}

function code_action:render_action_virtual_text(line, diagnostics)
  return function(err, actions, context)
    if actions == nil or type(actions) ~= "table" or vim.tbl_isempty(actions) then
      -- no actions cleanup
      if config.lsp.code_action.virtual_text then
        _update_virtual_text(nil)
      end
      if config.lsp.code_action.sign then
        _update_sign(nil)
      end
    else
      trace(err, line, diagnostics, actions, context)
      if config.lsp.code_action.sign then
        if need_check_diagnostic[vim.bo.filetype] then
          if next(diagnostics) == nil then
            _update_sign(nil)
          else
            -- no diagnostic, no code action sign..
            _update_sign(line)
          end
        else
          _update_sign(line)
        end
      end

      if config.lsp.code_action.virtual_text then
        if need_check_diagnostic[vim.bo.filetype] then
          if next(diagnostics) == nil then
            _update_virtual_text(nil)
          else
            _update_virtual_text(line, actions)
          end
        else
          _update_virtual_text(line, actions)
        end
      end
    end
  end
end

local special_buffers = {
  ["lspsagafinder"] = true,
  ["NvimTree"] = true,
  ["vista"] = true,
  ["guihua"] = true,
  ["lspinfo"] = true,
  ["markdown"] = true,
  ["text"] = true
}
-- local action_call_back = function (_,_)
--   return Action:action_callback()
-- end

local action_virtual_call_back = function(line, diagnostics)
  return code_action:render_action_virtual_text(line, diagnostics)
end

local code_action_req = function(_call_back_fn, diagnostics)
  local context = {diagnostics = diagnostics}
  local params = vim.lsp.util.make_range_params()
  params.context = context
  local line = params.range.start.line
  local callback = _call_back_fn(line, diagnostics)
  vim.lsp.buf_request(0, "textDocument/codeAction", params, callback)
end


code_action.code_action = function()

  local original_select = vim.ui.select
  vim.ui.select = require("guihua.gui").select

  log('codeaction')

  vim.lsp.buf.code_action()
  vim.defer_fn(
    function ()
        vim.ui.select = original_select
    end, 1000
  )

end

code_action.range_code_action = function(startpos, endpos)
  local context = {}
  context.diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  local params = util.make_given_range_params(startpos, endpos)
  params.context = context


  local original_select = vim.ui.select
  vim.ui.select = require("guihua.gui").select

  vim.lsp.buf.range_code_action(context, startpos, endpos)
  vim.defer_fn(
    function ()
        vim.ui.select = original_select
    end, 1000
  )
end

code_action.code_action_prompt = function()
  if special_buffers[vim.bo.filetype] then
    log('skip buffer', vim.bo.filetype)
    return
  end

  local diagnostics
  if diagnostic.get_line_diagnostics then
    -- old version
    diagnostics = diagnostic.get_line_diagnostics()
  else
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    diagnostics = diagnostic.get(vim.api.nvim_get_current_buf(), {lnum = lnum})
  end

  local winid = get_current_winid()
  code_action[winid] = code_action[winid] or {}
  code_action[winid].lightbulb_line = code_action[winid].lightbulb_line or 0
  code_action_req(action_virtual_call_back, diagnostics)
end

return code_action
