-- @version 0.2.5
-- @description Ai ReaStems
-- @author Aiwist

local r = reaper
local name, version = 'Ai ReaStems', '0.2.5'
local section = 'AiwistStems'
local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]')
local parent_section = 'AiwistTranscriber2'

local function preference(key)
  local value = r.GetExtState(section, key)
  if value == '' then return r.GetExtState(parent_section, key) end
  return value
end

local language = preference('language') == 'en' and 'en' or 'ru'
local function t(ru, en)
  return language == 'en' and en or ru
end

local function log_startup_error(problem)
  pcall(function()
    local json = dofile(directory .. '/lib/json.lua')
    local support = dofile(directory .. '/lib/support_zip.lua')
    support.record(r, json, r.GetResourcePath() .. '/Data/Ai ReaStems', {
      app = name, version = version, reaper = r.GetAppVersion(), os = r.GetOS(),
      phase = 'startup', error = tostring(problem),
    }, support.prefixes(r))
  end)
end

if not r.ImGui_CreateContext then
  r.MB(t('Установите ReaImGui через ReaPack и откройте Ai ReaStems снова.',
    'Install ReaImGui through ReaPack, then reopen Ai ReaStems.'), name, 0)
  return
end

local ok, backend = xpcall(function()
  return dofile(directory .. '/lib/backend.lua')(r, directory, section)
end, debug.traceback)
if not ok then
  log_startup_error(backend)
  r.MB(t('Не удалось открыть Ai ReaStems.', 'Could not open Ai ReaStems.') .. '\n\n' .. tostring(backend), name, 0)
  return
end

local selected_scale = tonumber(preference('ui_scale'))
local selected_theme = preference('theme')
local ui_settings = {
  language = language,
  scale = ({[0.75] = true, [1] = true, [1.25] = true, [1.5] = true})[selected_scale] and selected_scale or 1,
  theme = (selected_theme == 'cyan' or selected_theme == 'light') and selected_theme or 'dark',
}
local gui = dofile(directory .. '/lib/ui.lua')(r, backend, ui_settings, name, version, function(key, value)
  r.SetExtState(section, key, tostring(value), true)
end)
local context = dofile(directory .. '/lib/gui_context.lua').new(r, name, gui.attach_fonts)
local module = backend.module
local owner = r.genGuid()
local owner_key = 'window_owner'
local function own_window()
  local current = r.GetExtState(section, owner_key)
  local timestamp = tonumber(current:match(':(%d+)$'))
  if timestamp and timestamp > os.time() - 5 then return false end
  r.SetExtState(section, owner_key, owner .. ':' .. os.time(), false)
  return true
end
if not own_window() then return end

r.atexit(function()
  pcall(module.shutdown, module)
  if r.GetExtState(section, owner_key):sub(1, #owner) == owner then
    r.DeleteExtState(section, owner_key, false)
  end
end)

local closing, heartbeat = false, os.time()
local function loop()
  if os.time() ~= heartbeat then
    heartbeat = os.time()
    r.SetExtState(section, owner_key, owner .. ':' .. heartbeat, false)
  end
  local worked, problem = xpcall(function()
    module.language = ui_settings.language
    module:tick()
    if closing then return end
    local ctx, _, issue = context:ensure()
    assert(ctx, issue)
    if not gui.draw(ctx) then
      closing = true
      if module.job and module.job.action == 'separate' then module:cancel() end
    end
  end, debug.traceback)
  if not worked then
    pcall(module.record_error, module, problem, 'window')
    r.MB(t('Ошибка Ai ReaStems.', 'Ai ReaStems error.') .. '\n\n' .. tostring(problem), name, 0)
    return
  end
  if not closing or (module.job and module.job.action == 'separate') then r.defer(loop) end
end

loop()
