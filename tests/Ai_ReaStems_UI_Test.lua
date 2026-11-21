-- @description Ai ReaStems — проверка отрисовки ReaImGui
local r = reaper
local path = debug.getinfo(1, 'S').source:sub(2)
local root = path:match('^(.*)[/\\]tests[/\\][^/\\]+$')
local json = dofile(root .. '/lib/json.lua')

local function report(result)
  r.SetExtState('reaper_mcp_script_result', 'last_result', json.encode(result), false)
end

local ok, failure = xpcall(function()
  local backend = dofile(root .. '/lib/backend.lua')(r, root, 'AiwistStems')
  local source = assert(json.read(root .. '/Aiwist_ReaStems.lua'))
  local version = assert(source:match('@version ([%d.]+)'))
  local frames = 0
  local model_ids = {'htdemucs_ft', 'mdx23c_drumsep', 'uvr_denoise_lite'}
  local drawn, seen = {}, {}
  local installed, offered = {}, {}
  local preview, simulated_combo, empty_hint
  local saved_model
  for _, id in ipairs(model_ids) do installed[id] = true end
  local settings_frames = 0
  local install_checks, install_requests = 0, 0
  local disabled_stack = {}
  local copied, opened, applied = {}, {}, {}
  local storage = backend.module.storage
  storage:open_folder(root, true)
  local temporary = assert(os.getenv('TEMP')) .. '\\Ai-ReaStems-Test-' .. r.genGuid():gsub('[^%x]', '')
  assert(r.RecursiveCreateDirectory(temporary, 0) > 0, 'Не удалось создать папку проверки.')
  storage:open_folder(temporary, true)
  local diagnostic_api = setmetatable({
    GetExtState = function(section, key)
      if section ~= 'AiStemsDiagnosticsTest' then return r.GetExtState(section, key) end
      if key == 'storage_mode' then return 'custom' end
      if key == 'storage_path' then return temporary end
      return ''
    end,
  }, {__index = r})
  local diagnostic_module = dofile(root .. '/lib/backend.lua')(diagnostic_api, root, 'AiStemsDiagnosticsTest').module
  diagnostic_module:fail('Тестовая ошибка Ai ReaStems hf_TEST_REDACTED')
  local log = assert(json.read(temporary .. '/logs/errors.log'))
  assert(log:find('Тестовая ошибка Ai ReaStems', 1, true) and not log:find('hf_TEST_REDACTED', 1, true))
  local report_path
  function backend.module:save_error_report()
    report_path = diagnostic_module:save_error_report()
    return report_path
  end
  local sample_models_path = '"D:\\Ai ReaStems Test\\Models"'
  local sample_data_path = 'D:\\Ai ReaStems Test\\Data'
  local current_models_path, current_data_path = storage.model_folder, storage.root
  function storage:open_folder(path) opened[#opened + 1] = path end
  function storage:set_models(path) applied.models = path end
  function storage:set_data(mode, path)
    assert(mode == 'custom')
    applied.data = path
  end
  function backend.module:stem_registration(id)
    if frames ~= 6 and installed[id] then return 'D:/Ai ReaStems Test/' .. id .. '.gguf' end
  end
  function backend.module:save_settings()
    saved_model = self.split_model
  end
  function backend.module:install(id)
    assert(id == 'htdemucs', 'Кнопка отправила на установку другую модель.')
    install_requests = install_requests + 1
  end
  assert(#backend.models.order == 13, 'Неполный каталог моделей stems.cpp.')
  local engine, ready = backend.module:engine()
  assert(ready, 'Комплектный stems.cpp недоступен.')
  local api = setmetatable({
    ImGui_BeginCombo = function(ctx, label, current)
      local opened = r.ImGui_BeginCombo(ctx, label, current)
      if label ~= '##model' then return opened end
      assert(frames ~= 6, 'Пустой список моделей отрисован как выпадающий.')
      preview = current
      if frames == 0 then
        simulated_combo = not opened
        return true
      end
      return opened
    end,
    ImGui_EndCombo = function(ctx)
      if simulated_combo then simulated_combo = false else r.ImGui_EndCombo(ctx) end
    end,
    ImGui_Selectable = function(ctx, label, selected)
      if frames == 0 then
        offered[#offered + 1] = label
        if not simulated_combo then r.ImGui_Selectable(ctx, label, selected) end
        return label == backend.models.models.mdx23c_drumsep.label
      end
      return false
    end,
    ImGui_SetItemDefaultFocus = function(ctx)
      if not simulated_combo then r.ImGui_SetItemDefaultFocus(ctx) end
    end,
    ImGui_TextWrapped = function(ctx, label)
      if label == 'Установите модель в настройках.' then empty_hint = true end
      r.ImGui_TextWrapped(ctx, label)
    end,
    ImGui_BeginDisabled = function(ctx, disabled)
      disabled_stack[#disabled_stack + 1] = disabled ~= false
      r.ImGui_BeginDisabled(ctx, disabled)
    end,
    ImGui_EndDisabled = function(ctx)
      r.ImGui_EndDisabled(ctx)
      table.remove(disabled_stack)
    end,
    ImGui_SetClipboardText = function(_, path) copied[#copied + 1] = path end,
    ImGui_InputText = function(ctx, label, value, flags)
      r.ImGui_InputText(ctx, label, value, flags)
      if frames == 3 then
        if label == '##folder_path_models' then return true, sample_models_path end
        if label == '##folder_path_data' then return true, sample_data_path end
      end
      return false, value
    end,
    ImGui_Button = function(ctx, label, ...)
      if label == 'Разделить на стемы' then
        local model = backend.module.split_model or 'none'
        drawn[model] = (drawn[model] or 0) + 1
        if frames == 6 then assert(disabled_stack[#disabled_stack], 'Разделение доступно без модели.') end
      end
      seen[label] = true
      r.ImGui_Button(ctx, label, ...)
      assert(not label:find('^Установить HTDemucs'), 'Кнопка установки осталась в главном окне.')
      if frames >= 6 and label == 'Установить##model_htdemucs' then
        local disabled = false
        for _, state in ipairs(disabled_stack) do disabled = disabled or state end
        assert(disabled == (frames == 7 or frames == 8), 'Неверное состояние кнопки установки.')
        install_checks = install_checks + 1
        return not disabled
      end
      if frames == 2 then
        return label:find('##folder_copy_', 1, true) ~= nil or label:find('##folder_open_', 1, true) ~= nil
      end
      if frames == 3 and label:find('##folder_apply_', 1, true) then
        for _, state in ipairs(disabled_stack) do assert(not state, 'Применение введённого пути заблокировано.') end
        return true
      end
      if frames == 4 and label == 'Сохранить отчёт об ошибке##report_settings' then return true end
      return false
    end,
    ImGui_InvisibleButton = function(ctx, label, ...)
      r.ImGui_InvisibleButton(ctx, label, ...)
      return label == '##settings_gear' and frames == 1
    end,
    ImGui_BeginPopup = function(ctx, id)
      local visible = r.ImGui_BeginPopup(ctx, id)
      if visible then settings_frames = settings_frames + 1 end
      return visible
    end,
    ImGui_CollapsingHeader = function(ctx, label)
      r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_Always())
      return r.ImGui_CollapsingHeader(ctx, label)
    end,
  }, {__index = r})
  local gui = dofile(root .. '/lib/ui.lua')(api, backend, {
    language = 'ru', scale = 1, theme = 'cyan',
  }, 'Ai ReaStems — проверка', version, function() end)
  backend.module.binding = nil
  backend.module.selection_issue = nil
  local flags = r.ImGui_ConfigFlags_NoSavedSettings and r.ImGui_ConfigFlags_NoSavedSettings() or 0
  local context = r.ImGui_CreateContext('Ai ReaStems UI Test', flags)
  gui.attach_fonts(context)

  local function frame()
    local valid, issue = xpcall(function()
      backend.module.split_model = frames > 0 and frames < 6 and model_ids[(frames % #model_ids) + 1] or 'htdemucs'
      backend.module.phase = frames == 7 and 'running' or 'idle'
      backend.module.storage.restart_required = frames == 8 or nil
      assert(gui.draw(context), 'Тестовое окно было закрыто раньше времени.')
      if frames == 0 then
        assert(preview == backend.models.models.htdemucs_ft.label, 'Не выбрана первая установленная модель.')
        assert(#offered == #model_ids, 'Количество пунктов выпадающего списка неверно.')
        for i, id in ipairs(model_ids) do assert(offered[i] == backend.models.models[id].label) end
        assert(saved_model == 'mdx23c_drumsep' and backend.module.split_model == saved_model,
          'Не выбрана установленная модель из списка.')
      elseif frames == 6 then
        assert(backend.module.split_model == nil and empty_hint, 'Пустой список моделей отображается неверно.')
      end
      frames = frames + 1
      if frames == 9 then
        for _, id in ipairs(model_ids) do assert(drawn[id] and drawn[id] > 0, 'Не отрисована модель ' .. id) end
        assert(settings_frames > 0 and seen['Проверить обновления'], 'Не отрисованы настройки движка.')
        assert(#copied == 2 and copied[1] == current_data_path and copied[2] == current_models_path,
          'В буфер переданы неверные пути.')
        assert(#opened == 2 and opened[1] == current_data_path and opened[2] == current_models_path,
          'В Проводник переданы неверные пути.')
        assert(applied.models == sample_models_path and applied.data == sample_data_path,
          'Не переданы введённые пути к папкам.')
        local zip = assert(json.read(report_path))
        assert(zip:sub(1, 4) == 'PK\003\004' and zip:find('diagnostics.json', 1, true)
          and zip:find('errors.log', 1, true) and not zip:find('hf_TEST_REDACTED', 1, true))
        local model_count = 0
        for label in pairs(seen) do if label:find('##model_', 1, true) then model_count = model_count + 1 end end
        assert(model_count >= #backend.models.order, 'Не отрисована таблица моделей.')
        assert(install_checks == 3 and install_requests == 1, 'Не подтверждена установка из настроек.')
        assert(source:find('Ai ReaStems', 1, true) and version == json.load_json(root .. '/manifest.json').version, 'Название или версия скрипта не совпадает.')
        local registered = r.AddRemoveReaScript(true, 0, root .. '/Aiwist_ReaStems.lua', true)
        assert(registered and registered > 0, 'Не удалось зарегистрировать Ai ReaStems.')
        report({ok = true, version = version, engine = engine.version, frames = frames, settings_frames = settings_frames,
          models = #backend.models.order, modes = drawn, empty_selection = true,
          installed_choices = #offered, empty_models_hint = empty_hint, settings_install_requests = install_requests,
          paths_copied = #copied, folders_opened = #opened, custom_paths_applied = true,
          existing_folders_verified = true, error_logged = true, report_path = report_path,
          registered_action = r.ReverseNamedCommandLookup(registered)})
      else
        r.defer(frame)
      end
    end, debug.traceback)
    if not valid then report({ok = false, version = version, frames = frames, error = issue}) end
  end
  r.defer(frame)
end, debug.traceback)
if not ok then report({ok = false, error = failure}) end
