local here = debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]')
local J = dofile(here .. '/json.lua')
local Windows = dofile(here .. '/windows_paths.lua')
local M = {}

local function norm(path)
  return (path:gsub('/', '\\'):gsub('\\+$', ''))
end

local function relative(path, base)
  if path:lower() == base:lower() then return '' end
  if path:sub(1, #base + 1):lower() == base:lower() .. '\\' then return path:sub(#base + 2) end
end

local function valid(path)
  return type(path) == 'string' and path:match('^%a:\\.+') and not path:find('[%z\1-\31<>|?*"]')
    and not path:sub(3):find(':', 1, true) and not path:match('\\%.%.?\\') and not path:match('\\%.%.?$')
end

local function unpack_path(path, root, profile)
  if type(path) ~= 'string' then return nil end
  local base, tail
  if path:sub(1, 6) == '@data/' then base, tail = root, path:sub(7)
  elseif path:sub(1, 8) == '@reaper/' then base, tail = profile, path:sub(9)
  else return valid(norm(path)) and norm(path) or nil end
  local full = norm(base .. '\\' .. tail)
  return valid(full) and full or nil
end

local function pack_path(path, root, profile)
  local tail = root and relative(norm(path), root)
  if tail then return '@data/' .. tail:gsub('\\', '/') end
  tail = relative(norm(path), profile)
  if tail then return '@reaper/' .. tail:gsub('\\', '/') end
  return path
end

local function expand(value, root, profile)
  if type(value) == 'string' and value:match('^@[%a]+/') then
    return unpack_path(value, root, profile)
  end
  if type(value) ~= 'table' then return value end
  local fields = {}
  for key, entry in pairs(value) do fields[key] = expand(entry, root, profile) end
  return fields
end

function M.new(r, section)
  local profile = norm(r.GetResourcePath())
  local local_data, problem = Windows.local_app_data(r, J, section)
  assert(local_data, problem)
  local system = norm(local_data .. '\\Aiwist\\Ai ReaStems')
  local portable = profile .. '\\Data\\Ai ReaStems'
  local old_system = norm(local_data .. '\\Aiwist\\Ai Stems')
  local old_portable = profile .. '\\Data\\Ai Stems'
  local is_portable = r.file_exists(profile .. '\\reaper.exe') and r.file_exists(profile .. '\\reaper.ini')
  local selected = r.GetExtState(section, 'storage_mode')
  local mode = selected ~= '' and selected or (is_portable and 'portable' or 'system')
  local root = (mode == 'custom' and unpack_path(r.GetExtState(section, 'storage_path'), system, profile))
    or (mode == 'portable' and portable) or system
  local old_root = (mode == 'system' and old_system) or (mode == 'portable' and old_portable)
  if old_root and not r.file_exists(root .. '/.stems_storage_context.json')
      and r.file_exists(old_root .. '/.stems_storage_context.json') then
    root = old_root
  end
  local default_models = (mode == 'system' and norm(local_data .. '\\Ai ReaStems') or root) .. '\\models'
  local old_model_folders = {norm(local_data .. '\\Ai Stems\\models'), old_portable .. '\\models'}
  local model_folder = unpack_path(r.GetExtState(section, 'models_path'), root, profile) or default_models
  local storage = {
    root = root, mode = mode, system = system, portable = portable, model_folder = model_folder,
    default_models = default_models, profile = profile,
  }
  local function require_folder(folder)
    assert(type(folder) == 'string', 'Укажите путь к папке.')
    folder = folder:match('^%s*(.-)%s*$')
    folder = norm(folder:match('^"(.*)"$') or folder)
    assert(valid(folder) and folder:lower() ~= profile:lower(), 'Выберите отдельную папку на локальном диске.')
    return folder
  end
  function storage:open_folder(folder, probe_only)
    folder = require_folder(folder)
    local powershell = (os.getenv('SystemRoot') or 'C:\\Windows') .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
    local command = '"' .. powershell .. '" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' ..
      here .. '/../setup/open_folder.ps1" -Folder "' .. folder .. '"' .. (probe_only and ' -ProbeOnly' or '')
    local result = r.ExecProcess(command, 10000) or ''
    local code = tostring(result):match('^(%-?%d+)')
    assert(code == '0' and result:find('AISTEMS_FOLDER_OK', 1, true),
      'Не удалось открыть папку: ' .. folder .. '\n' .. tostring(result))
  end
  function storage:set_models(folder)
    folder = require_folder(folder or default_models)
    if folder:lower() == self.model_folder:lower() then return end
    local previous = J.load_json(root .. '/model_folders.json', {})
    if type(previous) ~= 'table' then previous = {} end
    r.RecursiveCreateDirectory(root, 0)
    local history = {pack_path(self.model_folder, root, profile)}
    for _, value in ipairs(previous) do
      if #history >= 32 then break end
      if value ~= history[1] then history[#history + 1] = value end
    end
    assert(J.save_json(root .. '/model_folders.json', J.array(history)), 'Не удалось сохранить прежнюю папку моделей.')
    r.SetExtState(section, 'models_path', folder ~= default_models and pack_path(folder, root, profile) or '', true)
    self.model_folder = folder
  end
  function storage:set_data(new_mode, folder)
    local target = require_folder(new_mode == 'system' and system or new_mode == 'portable' and portable or folder)
    if self.mode == new_mode and target:lower() == root:lower() then return end
    r.RecursiveCreateDirectory(target, 0)
    local probe = target .. '/.write-test-' .. r.genGuid():gsub('[^%x]', '')
    assert(J.write(probe, 'Ai ReaStems'), 'Не удалось записать в выбранную папку.')
    os.remove(probe)
    if r.GetExtState(section, 'models_path') ~= '' then
      r.SetExtState(section, 'models_path', pack_path(self.model_folder, nil, profile), true)
    end
    local paths, seen = {}, {}
    local function remember(path)
      if path and not seen[path:lower()] and #paths < 32 then
        paths[#paths + 1] = pack_path(path, target, profile)
        seen[path:lower()] = true
      end
    end
    remember(self.model_folder)
    for _, path in ipairs(self:other_model_folders()) do remember(path) end
    local target_paths = J.load_json(target .. '/model_folders.json', {})
    if type(target_paths) == 'table' then
      for _, entry in ipairs(target_paths) do remember(unpack_path(entry, target, profile)) end
    end
    assert(J.save_json(target .. '/model_folders.json', J.array(paths)), 'Не удалось сохранить пути к моделям.')
    local engine = self:read(root .. '/stems_active.json')
    if type(engine) == 'table' and not r.file_exists(target .. '/stems_active.json') then
      assert(J.save_json(target .. '/stems_active.json', engine), 'Не удалось сохранить выбранный движок.')
    end
    r.SetExtState(section, 'storage_path', new_mode == 'custom' and pack_path(target, nil, profile) or '', true)
    r.SetExtState(section, 'storage_mode', new_mode, true)
    self.restart_required = true
  end
  function storage:prepare()
    r.RecursiveCreateDirectory(root, 0)
    local marker = root .. '/.stems_storage_context.json'
    local current = J.load_json(marker, {})
    if type(current) == 'table' and current.schema == 1 and current.mode == mode and
        current.data_root == root and current.resource_root == profile then return end
    assert(J.save_json(marker, {
      schema = 1, mode = mode, data_root = root, resource_root = profile,
    }), 'Не удалось использовать папку данных Ai ReaStems.')
  end
  function storage:read(path, fallback)
    local data = J.load_json(path)
    if data == nil then return fallback end
    return expand(data, root, profile)
  end
  function storage:other_model_folders()
    local result = {}
    local list = J.load_json(root .. '/model_folders.json', {})
    if type(list) == 'table' then
      for index, saved in ipairs(list) do
        if index > 32 then break end
        local path = unpack_path(saved, root, profile)
        if path then result[#result + 1] = path end
      end
    end
    for _, path in ipairs(old_model_folders) do
      if path:lower() ~= self.model_folder:lower() then result[#result + 1] = path end
    end
    return result
  end
  function storage:legacy_model(id)
    local old_system = norm(local_data .. '\\Aiwist\\Ai Transcriber')
    local old_root = is_portable and profile .. '\\Data\\Ai Transcriber' or old_system
    local ok, old = pcall(J.decode, r.GetExtState('AiwistTranscriber2', 'data_storage_v1'))
    if ok and type(old) == 'table' then
      if old.mode == 'system' then old_root = old_system
      elseif old.mode == 'portable' then old_root = profile .. '\\Data\\Ai Transcriber'
      elseif old.mode == 'custom' and type(old.path) == 'string' then
        old_root = norm(old.relative and profile .. '\\' .. old.path or old.path)
      end
    end
    if not valid(old_root) then return nil end
    local registry = J.load_json(old_root .. '/native_active.json', {})
    if type(registry) ~= 'table' then return nil end
    local entry = registry[id == 'mdx23c_drumsep' and 'drumsep' or id]
    if type(entry) == 'table' then return unpack_path(entry.model, old_root, profile) end
  end
  return storage
end

return M
