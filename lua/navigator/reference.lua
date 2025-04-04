local util = require('navigator.util')
local mk_handler = util.mk_handler
local log = util.log
local lsphelper = require('navigator.lspwrapper')
local gui = require('navigator.gui')
local lsp = require('navigator.lspwrapper')
local trace = require('navigator.util').trace
ListViewCtrl = ListViewCtrl or require('guihua.listviewctrl').ListViewCtrl
-- local partial = util.partial
-- local cwd = vim.loop.cwd()
-- local lsphelper = require "navigator.lspwrapper"
local locations_to_items = lsphelper.locations_to_items

local M = {}
local ref_view = function(err, locations, ctx, cfg)
  local truncate = cfg and cfg.truncate or 20
  local opts = {}
  trace('arg1', err, ctx, locations)
  trace(locations)
  if ctx.combine then
    -- wait for both request
    if ctx.results == nil then
      return
    end
    if #ctx.results.definitions.result == nil or ctx.results.references.result == nil then
      log('not all requests returned')
      return
    end
    local definitions = ctx.results.definitions
    local references = ctx.results.references
    if definitions.error and references.error then
      vim.notify('lsp ref callback error', vim.inspect(ctx.result), vim.lsp.log_levels.WARN)
    end
    locations = {}
    if definitions.result then
      for i, _ in ipairs(definitions.result) do
        definitions.result[i].definition = true
      end
      vim.list_extend(locations, definitions.result)
    end
    if references.result then
      vim.list_extend(locations, references.result)
    end
    ctx = references.ctx or definitions.ctx
    err = nil
    cfg = references.config or definitions.config
    trace(ctx, locations)
  end
  -- log("num", num)
  -- log("bfnr", bufnr)
  if err ~= nil then
    vim.notify('lsp ref callback error', err, ctx, vim.inspect(locations), vim.lsp.log_levels.WARN)
    log('ref callback error, lsp may not ready', err, ctx, vim.inspect(locations))
    return
  end
  if type(locations) ~= 'table' then
    log(locations)
    log('ctx', ctx)
    vim.notify('incorrect setup', locations, vim.lsp.log_levels.WARN)
    return
  end
  if locations == nil or vim.tbl_isempty(locations) then
    vim.notify('References not found', vim.lsp.log_levels.WARN)
    return
  end

  local items, width, second_part = locations_to_items(locations, truncate)
  local thread_items = vim.deepcopy(items)
  log('splits: ', #items, #second_part)

  local ft = vim.api.nvim_buf_get_option(ctx.bufnr, 'ft')

  local wwidth = vim.api.nvim_get_option('columns')
  local mwidth = _NgConfigValues.width
  width = math.min(width + 30, 120, math.floor(wwidth * mwidth))
  -- log(items)
  -- log(width)
  opts = {
    total = #locations,
    items = items,
    rawdata = false,
    ft = ft,
    width = width,
    api = 'Reference',
    enable_preview_edit = true
  }
  local listview = gui.new_list_view(opts)

  if listview == nil then
    vim.notify('failed to create preview windows', vim.lsp.log_levels.WARN)
    return
  end
  -- trace("update items", listview.ctrl.class)
  local nv_ref_async
  nv_ref_async = vim.loop.new_async(vim.schedule_wrap(function()
    log('$$$$$$$$ seperate thread... $$$$$$$$')
    if vim.tbl_isempty(second_part) then
      return
    end
    local items2 = locations_to_items(second_part)

    vim.list_extend(thread_items, items2)

    local data = require('navigator.render').prepare_for_render(thread_items, opts)
    listview.ctrl:on_data_update(data)
    if nv_ref_async then
      vim.loop.close(nv_ref_async)
    else
      log('invalid asy', nv_ref_async)
    end
  end))

  vim.defer_fn(function()
    vim.loop.new_thread(function(asy)
      asy:send()
    end, nv_ref_async)
  end, 100)

  return listview, items, width
end

local ref_hdlr = mk_handler(function(err, locations, ctx, cfg)
  _NgConfigValues.closer = nil
  trace(err, locations, ctx, cfg)
  M.async_hdlr = vim.loop.new_async(vim.schedule_wrap(function()
    ref_view(err, locations, ctx, cfg)
    M.async_hdlr:close()
  end))
  M.async_hdlr:send()
end)

local async_ref = function()
  local ref_params = vim.lsp.util.make_position_params()
  local results = {definitions = {}, references = {}}
  ref_params.context = {includeDeclaration = false}
  lsp.call_async('textDocument/definition', ref_params, function(err, result, ctx, config)
    trace(err, result, ctx, config)
    results.definitions = {error = err, result = result, ctx = ctx, config = config}
    ctx = ctx or {}
    ctx.results = results
    ctx.combine = true
    ref_view(err, result, ctx, config)
  end) -- return asyncresult, canceller
  lsp.call_async('textDocument/references', ref_params, function(err, result, ctx, config)
    trace(err, result, ctx, config)
    results.references = {error = err, result = result, ctx = ctx, config = config}
    ctx = ctx or {}
    ctx.results = results
    ctx.combine = true
    ref_view(err, result, ctx, config)
  end) -- return asyncresult, canceller
end

local ref_req = function()
  if _NgConfigValues.closer ~= nil then
    -- do not call it twice
    _NgConfigValues.closer()
  end
  local ref_params = vim.lsp.util.make_position_params()
  ref_params.context = {includeDeclaration = true}
  -- lsp.call_async("textDocument/references", ref_params, ref_hdlr) -- return asyncresult, canceller
  local bufnr = vim.api.nvim_get_current_buf()
  log('bufnr', bufnr)
  local ids, closer = vim.lsp.buf_request(bufnr, 'textDocument/references', ref_params, ref_hdlr)
  log(ids)

  _NgConfigValues.closer = closer
  return ids, closer
end

local ref = function()
  local bufnr = vim.api.nvim_get_current_buf()

  local ref_params = vim.lsp.util.make_position_params()
  vim.lsp.for_each_buffer_client(bufnr, function(client, client_id, bufnr)
    if client.resolved_capabilities.find_references then
      client.request('textDocument/references', ref_params, ref_hdlr, bufnr)
    end
  end)
end


return {

  reference_handler = ref_hdlr,

  reference = ref_req,

  ref_view = ref_view,

  async_ref = async_ref

}
