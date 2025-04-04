local gui = require('navigator.gui')
local M = {}
local log = require('navigator.util').log
local trace = require('navigator.util').trace
local mk_handler = require('navigator.util').mk_handler
local lsphelper = require('navigator.lspwrapper')
local locations_to_items = lsphelper.locations_to_items
local clone = require('guihua.util').clone
local symbol_kind = require('navigator.lspclient.lspkind').symbol_kind
local symbols_to_items = lsphelper.symbols_to_items

function M.workspace_symbols(query)
  opts = opts or {}
  local lspopts = {
    loc = 'top_center',
    prompt = true,
    -- rawdata = true,
    api = ' '
  }

  query = query or pcall(vim.fn.input, 'Query: ')
  local bufnr = vim.api.nvim_get_current_buf()
  vim.list_extend(lspopts, opts)
  local params = {query = query}
  vim.lsp.for_each_buffer_client(bufnr, function(client, client_id, _bufnr)
    if client.resolved_capabilities.workspace_symbol then
      client.request('workspace/symbol', params, M.workspace_symbol_handler, _bufnr)
    end
  end)
end

function M.document_symbols(opts)
  opts = opts or {}
  local lspopts = {
    loc = 'top_center',
    prompt = true,
    -- rawdata = true,
    api = ' '
  }

  local bufnr = vim.api.nvim_get_current_buf()
  vim.list_extend(lspopts, opts)
  local params = vim.lsp.util.make_position_params()
  params.context = {includeDeclaration = true}
  params.query = opts.prompt or ''
  vim.lsp.for_each_buffer_client(bufnr, function(client, client_id, _bufnr)
    if client.resolved_capabilities.document_symbol then
      client.request('textDocument/documentSymbol', params, M.document_symbol_handler, _bufnr)
    end
  end)
end

M.document_symbol_handler = mk_handler(function(err, result, ctx)
  if err then
    vim.notify('failed to get document symbol', ctx, vim.lsp.log_levels.WARN)
  end
  local bufnr = ctx.bufnr or 0

  if not result or vim.tbl_isempty(result) then
    vim.notify('symbol not found for buf', ctx, vim.lsp.log_levels.WARN)
    return
  end
  local locations = {}
  local fname = vim.fn.expand('%:p:f')
  local uri = vim.uri_from_fname(fname)
  -- vim.list_extend(locations, vim.lsp.util.symbols_to_items(result) or {})
  log(result[1])
  for i = 1, #result do
    local item = {}
    item.kind = result[i].kind
    local kind = symbol_kind(item.kind)
    item.name = result[i].name
    item.range = result[i].range or result[i].location.range
    item.uri = uri
    item.selectionRange = result[i].selectionRange
    item.detail = result[i].detail or ''
    if item.detail == '()' then
      item.detail = 'func'
    end

    item.lnum = result[i].range.start.line + 1
    item.text = '[' .. kind .. ']' .. item.name .. ' ' .. item.detail

    item.filename = fname

    table.insert(locations, item)
    if result[i].children ~= nil then
      for _, c in pairs(result[i].children) do
        local child = {}
        child.kind = c.kind
        child.name = c.name
        child.range = c.range
        local ckind = symbol_kind(child.kind)
        child.selectionRange = c.selectionRange
        child.filename = fname
        child.uri = uri
        child.lnum = c.range.start.line + 1
        child.detail = c.detail or ''
        child.text = '   ' .. ckind .. '' .. child.name .. ' ' .. child.detail
        table.insert(locations, child)
      end
    end
  end

  local ft = vim.api.nvim_buf_get_option(bufnr, 'ft')
  gui.new_list_view({items = locations, prompt = true, rawdata = true, ft = ft, api = ' '})
end)

M.workspace_symbol_handler = mk_handler(function(err, result, ctx, cfg)
  trace(err, result, ctx, cfg)
  if err then
    vim.notify('failed to get workspace symbol', ctx, vim.lsp.log_levels.WARN)
  end
  if not result or vim.tbl_isempty(result) then
    vim.notify('symbol not found for buf', ctx, vim.lsp.log_levels.WARN)
    return
  end
  log(result[1])
  local items = symbols_to_items(result)
  log(items[1])

  local ft = vim.api.nvim_buf_get_option(ctx.bufnr, 'ft')
  gui.new_list_view({items = items, prompt = true, ft = ft, rowdata = true, api = " "})

end)

return M
