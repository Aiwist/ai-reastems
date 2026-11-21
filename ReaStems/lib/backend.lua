local here = debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]')
local J = dofile(here .. '/json.lua')
local Support = dofile(here .. '/support_zip.lua')
local Storage = dofile(here .. '/storage.lua')
local Audio = dofile(here .. '/drumsep_audio.lua')
local Identity = dofile(here .. '/drum_source.lua')
local Gate = dofile(here .. '/drumsep_gate.lua')
local Hidden = dofile(here .. '/hidden_runner.lua')
local Runtime = dofile(here .. '/stems_runtime.lua')
local rate, chunk_size, tail = 44100, 4096, 11025
local function payload_header(frames)
  return 'RIFF' .. string.pack('<I4', 36 + frames * 8) .. 'WAVEfmt ' ..
    string.pack('<I4I2I2I4I4I2I2', 16, 3, 2, rate, rate * 8, 8, 32) ..
    'data' .. string.pack('<I4', frames * 8)
end

local function describe(r, item)
  local take = r.GetActiveTake(item)
  assert(take and not r.TakeIsMIDI(take), 'Нужен аудиоайтем с активным тейком.')
  local _, item_id = r.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  local _, take_id = r.GetSetMediaItemTakeInfo_String(take, 'GUID', '', false)
  local track = r.GetMediaItem_Track(item)
  local _, name = r.GetTrackName(track, '')
  local readable, state = r.GetItemStateChunk(item, '', false)
  assert(readable and #state <= 4194304, 'Не удалось прочитать параметры аудио.')
  return { item_guid = item_id, take_guid = take_id, track_guid = r.GetTrackGUID(track),
    position = r.GetMediaItemInfo_Value(item, 'D_POSITION'), duration = r.GetMediaItemInfo_Value(item, 'D_LENGTH'),
    name = r.GetTakeName(take) or '', track_name = name or '', fingerprint = Identity.fingerprint(state) }
end

local function present(path, size)
  local file = path and io.open(path, 'rb')
  if not file then return false end
  local valid = file:read(4) == 'GGUF' and file:seek('end') == size
  file:close()
  return valid
end

return function(r, directory, section)
  local storage = Storage.new(r, section)
  local root = storage.root
  local manifest = J.load_json(directory .. '/manifest.json', {})
  local catalog = J.load_json(directory .. '/models_catalog.json')
  assert(catalog and catalog.schema == 1, 'Каталог моделей Ai ReaStems недоступен.')
  local owner = {r = r, dir = directory, root = root, native = {},
    json = {load_json = function(path, fallback) return storage:read(path, fallback) end}}
  local self = {phase = 'idle', storage = storage, models = catalog, audio = Audio, fonts = directory .. '/fonts/'}

  local registry = root .. '/stems_active.json'
  local function update_registry()
    owner.native = storage:read(registry, storage:read(registry .. '.bak', {}))
    if type(owner.native) ~= 'table' then owner.native = {} end
    owner.stems_runtime_health = nil
  end
  update_registry()

  local ready_files, last_scan = {}, -math.huge
  local function refresh_models(force)
    local now = r.time_precise()
    if not force and now - last_scan < 2 then return end
    last_scan = now
    ready_files = {}
    local prior = storage:other_model_folders()
    for _, id in ipairs(catalog.order) do
      local info = catalog.models[id]
      local path = storage.model_folder .. '/' .. info.file
      if not present(path, info.bytes) then
        path = nil
        for _, old in ipairs(prior) do
          local candidate = old .. '/' .. info.file
          if present(candidate, info.bytes) then path = candidate; break end
        end
        if not path then
          local legacy = storage:legacy_model(id)
          if present(legacy, info.bytes) then path = legacy end
        end
      end
      ready_files[id] = path
    end
  end
  function self:stem_registration(id)
    refresh_models(false)
    return ready_files[id]
  end
  function self:stem_names(id)
    return catalog.models[id].stems
  end

  local ok, prefs = pcall(J.decode, r.GetExtState(section, 'separation'))
  prefs = ok and type(prefs) == 'table' and prefs or {}
  self.split_model = prefs.mode == 'drums' and 'mdx23c_drumsep' or prefs.model
  if not catalog.models[self.split_model] then
    self.split_model = catalog.order[1]
    for _, id in ipairs(catalog.order) do
      if self:stem_registration(id) then self.split_model = id; break end
    end
  end
  self.split_outputs = type(prefs.outputs) == 'table' and prefs.outputs or {}
  if not self.split_outputs.mdx23c_drumsep then self.split_outputs.mdx23c_drumsep = self.split_outputs.drumsep end
  self.gate_settings = Gate.settings(prefs.gate)

  function self:save_settings()
    r.SetExtState(section, 'separation', J.encode({
      model = self.split_model, outputs = self.split_outputs, gate = self.gate_settings,
    }), true)
  end
  function self:busy()
    return self.phase ~= 'idle'
  end
  function self:device()
    return r.GetExtState(section, 'device') == 'cpu' and 'cpu' or 'auto'
  end
  function self:engine()
    return Runtime.get(owner)
  end
  function self:available_update()
    local update = owner.native.stems_update
    local running = self:engine()
    local latest = type(update) == 'table' and type(update.latest) == 'table' and update.latest.version
    if Runtime.newer(latest, running.version) then return latest end
  end
  function self:refresh_selection()
    local project = r.EnumProjects(-1, '')
    local items, signature = Audio.selected(r)
    local revision = r.GetProjectStateChangeCount(project)
    if self.project == project and self.selection_signature == signature and self.revision == revision then return end
    self.project, self.selection_signature, self.revision = project, signature, revision
    self.binding, self.selection_issue = nil, nil
    if #items == 0 then return end
    local valid, source, track = pcall(Audio.snapshot, r, J, items, describe)
    if valid then self.binding = {project_ptr = project, items = items, source = source, track = track}
    else self.selection_issue = tostring(source):gsub('^.-%.lua:%d+: ', '') end
  end
  local function guard()
    local binding = assert(self.binding, 'Выберите исходное аудио.')
    assert(binding.project_ptr == r.EnumProjects(-1, ''), 'Откройте исходный проект.')
    local revision = r.GetProjectStateChangeCount(binding.project_ptr)
    if revision ~= binding.checked_revision then
      local source = Audio.snapshot(r, J, binding.items, describe)
      assert(source.fingerprint == binding.source.fingerprint, 'Исходное аудио изменилось. Запустите разделение снова.')
      binding.checked_revision = revision
    end
    return binding
  end

  local function launch(mode)
    local job = self.job
    local ran, detail = pcall(Hidden.launch, r, directory, root, job.work, mode)
    if not ran then self.warning = tostring(detail) end
  end
  local function new_job(config)
    assert(not self:busy() and not storage.restart_required, 'Дождитесь завершения операции или перезапустите Ai ReaStems.')
    storage:prepare()
    local id = r.genGuid():gsub('[^%x]', '')
    local work = root .. '/stems_jobs/' .. id
    r.RecursiveCreateDirectory(work, 0)
    self.job = {id = id, work = work, action = config.action, model = config.model, started = r.time_precise()}
    self.error, self.warning, self.cancel_requested, self.progress = nil, nil, false, 0
    config.schema, config.id = 1, id
    assert(J.save_json(work .. '/config.json', config), 'Не удалось подготовить задание Ai ReaStems.')
  end
  local function start_component(config)
    new_job(config)
    self.phase, self.message = 'running', 'Запуск…'
    r.SetExtState(section, 'component_job', self.job.id, true)
    launch('Run')
  end
  function self:install(id)
    assert(catalog.models[id], 'Неизвестная модель.')
    start_component({action = 'install', model = id, folder = storage.model_folder})
  end
  function self:request_engine(operation, version)
    start_component({action = 'engine', operation = operation, runtime_version = version})
  end

  local function release_input()
    for _, part in ipairs(self.parts or {}) do r.DestroyAudioAccessor(part.accessor) end
    self.parts = nil
    if self.file then self.file:close(); self.file = nil end
  end
  function self:separate(id, marked)
    self.selection_signature = nil
    self:refresh_selection()
    local binding = guard()
    local choices = {}
    for _, stem in ipairs(self:stem_names(id)) do if marked[stem] ~= false then choices[stem] = true end end
    assert(next(choices), 'Выберите хотя бы один стем.')
    refresh_models(true)
    local weights = assert(self:stem_registration(id), 'Сначала установите выбранную модель.')
    local _, ready = self:engine()
    assert(ready, 'Восстановите движок из установщика Ai ReaStems.')
    new_job({action = 'separate', model = id, weights = weights, device = self:device(), duration = binding.source.duration})

    self.choices = choices
    self.gate = id == 'mdx23c_drumsep' and Gate.settings(self.gate_settings) or nil
    self.frames = math.floor(binding.source.duration * rate + .5)
    assert(self.frames > 0, 'Выберите более длинный фрагмент.')
    self.offset, self.parts = 0, {}
    for _, item in ipairs(binding.items) do
      local source = describe(r, item)
      local access = assert(r.CreateTakeAudioAccessor(r.GetActiveTake(item)), 'Не удалось прочитать исходное аудио.')
      local part = {accessor = access, position = source.position}
      self.parts[#self.parts + 1] = part
      part.origin = r.GetAudioAccessorStartTime(access)
      local available = math.max(0, r.GetAudioAccessorEndTime(access) - part.origin)
      part.duration = math.floor(math.min(source.duration, available) * rate) / rate
    end
    self.file = assert(io.open(self.job.work .. '/input.wav', 'wb'), 'Не удалось создать WAV.')
    assert(self.file:write(payload_header(self.frames + rate + tail), string.rep('\0', rate * 8)))
    self.phase, self.message = 'exporting', 'Подготовка аудио…'
  end

  local function export_chunk()
    local binding = guard()
    local count = math.min(chunk_size, self.frames - self.offset)
    local samples = {}
    for index = 1, count * 2 do samples[index] = 0 end
    local time = binding.source.position + self.offset / rate
    for _, part in ipairs(self.parts) do
      local first = math.max(0, math.ceil((part.position - time) * rate - 1e-7))
      local last = math.min(count, math.ceil((part.position + part.duration - time) * rate - 1e-7))
      if last > first then
        local size = last - first
        local buffer = r.new_array(size * 2)
        buffer.clear()
        local at = part.origin + time + first / rate - part.position
        local read = r.GetAudioAccessorSamples(part.accessor, rate, 2, at, size, buffer)
        assert(type(read) == 'number' and read >= 0, 'Не удалось прочитать исходное аудио.')
        local values = buffer.table()
        for index = 1, size * 2 do samples[first * 2 + index] = samples[first * 2 + index] + (values[index] or 0) end
      end
    end
    for first = 1, #samples, 512 do
      local last = math.min(#samples, first + 511)
      assert(self.file:write(string.pack('<' .. string.rep('f', last - first + 1), table.unpack(samples, first, last))))
    end
    self.offset = self.offset + count
    self.progress = .1 * self.offset / self.frames
    if self.offset == self.frames then
      assert(self.file:write(string.rep('\0', tail * 8)))
      local closed, detail = self.file:close()
      self.file = nil
      assert(closed, detail)
      release_input()
      self.phase = 'running'
      self.job.started = r.time_precise()
      launch('Run')
    end
  end

  local function clean_import()
    for _, path in ipairs(self.pending_wavs or {}) do
      os.remove(path)
      os.remove(path .. '.reapeaks')
    end
    self.pending_wavs = nil
  end

  local function begin_import(result)
    local binding = guard()
    local top = Audio.media_folder(r, binding.project_ptr, self.job.id, true)
    r.RecursiveCreateDirectory(top, 0)
    self.pending_wavs = {}
    self.phase, self.progress = 'importing', .94
    self.message = result.cached and 'Стемы взяты из кэша. Сохранение WAV…' or 'Сохранение WAV…'
    self.importer = coroutine.create(function()
      local files = {}
      local function checkpoint()
        coroutine.yield()
        assert(not self.cancel_requested, 'Операция отменена.')
      end
      for _, stem in ipairs(result.stems) do
        if self.choices[stem.name] then
          -- The worker returns names from the pinned catalogue; do not let
          -- an inconsistent on-disk result resolve to another file.
          local stem_id = assert(stem.name:match('^[a-z_]+$'))
          local wav = stem.wav:gsub('\\', '/')
          local prefix = root:gsub('\\', '/') .. '/stems_jobs/'
          local path_key = wav:sub(#prefix + 1)
          local cached_id, stem_file = path_key:match('^(%x+)/stems/([a-z_]+)%.wav$')
          assert(wav:sub(1, #prefix):lower() == prefix:lower() and cached_id and #cached_id == 32 and stem_file == stem_id,
            'Не удалось открыть подготовленный стем.')
          local path = top .. '/' .. Audio.title(stem_id) .. '.wav'
          self.pending_wavs[#self.pending_wavs + 1] = path
          Audio.trim(wav, path, 1, binding.source.duration, checkpoint, self.gate)
          Audio.build_peaks(r, path, checkpoint)
          files[#files + 1] = {name = stem_id, path = path}
        end
      end
      guard()
      assert(#files > 0, 'Движок не вернул выбранные стемы.')
      Audio.insert_stems(r, binding.project_ptr, binding.track, binding.source, files)
      self.pending_wavs = nil
      self.progress, self.message = 1, 'Создано аудиодорожек: ' .. #files
    end)
  end

  function self:fail(problem)
    if self.phase == 'running' and self.job then
      pcall(J.write, self.job.work .. '/cancel.request', 'cancel\n')
    end
    release_input()
    clean_import()
    self:record_error(problem)
    self.phase, self.importer, self.job = 'idle', nil, nil
    self.message = self.error:match('^[^\r\n]*'):gsub('^.-%.lua:%d+: ', '')
  end
  local function diagnostics(problem, job, phase)
    local engine = self:engine()
    return {
      app = 'Ai ReaStems', version = manifest.version, reaper = r.GetAppVersion(), os = r.GetOS(),
      engine = engine.version, storage_mode = storage.mode, phase = phase,
      model = job and job.model or self.split_model, action = job and job.action,
      job_id = job and job.id, error = tostring(problem or ''),
    }
  end
  function self:record_error(problem, phase)
    self.error = tostring(problem)
    self.report_message = nil
    self.last_diagnostics = diagnostics(problem, self.job, phase or self.phase)
    pcall(Support.record, r, J, root, self.last_diagnostics, Support.prefixes(r, storage))
  end
  function self:save_error_report()
    local summary = self.last_diagnostics or diagnostics(self.error, self.job, self.phase)
    return Support.create(r, J, root, summary, Support.prefixes(r, storage), summary.job_id)
  end
  function self:cancel()
    if self.phase == 'running' then
      assert(J.write(self.job.work .. '/cancel.request', 'cancel\n'))
    elseif self.phase == 'exporting' then
      release_input()
      self.phase, self.job = 'idle', nil
    end
    self.cancel_requested = true
    self.message = 'Операция отменяется…'
  end
  function self:shutdown()
    if self.job and self.job.action == 'separate' then
      if self.phase == 'importing' and self.importer then
        self.cancel_requested = true
        coroutine.resume(self.importer)
      else
        self:cancel()
      end
    end
    release_input()
    clean_import()
  end

  local pending = r.GetExtState(section, 'component_job')
  if #pending == 32 and pending:match('^%x+$') then
    local work = root .. '/stems_jobs/' .. pending
    local cfg = J.load_json(work .. '/config.json', {})
    if cfg.id == pending and (cfg.action == 'engine' or cfg.action == 'install') then
      self.job = {id = pending, work = work, action = cfg.action, model = cfg.model, started = r.time_precise()}
      self.phase = 'running'
    else
      r.DeleteExtState(section, 'component_job', true)
    end
  end
  function self:tick()
    if self.phase == 'idle' then self:refresh_selection(); return end
    local worked, problem = xpcall(function()
      if self.phase == 'exporting' then export_chunk(); return end
      if self.phase == 'importing' then
        local deadline = r.time_precise() + .008
        repeat
          local resumed, issue = coroutine.resume(self.importer)
          assert(resumed, issue)
          if coroutine.status(self.importer) == 'dead' then
            self.phase, self.importer, self.job = 'idle', nil, nil
            break
          end
        until r.time_precise() >= deadline
        return
      end
      local job = self.job
      local result = storage:read(job.work .. '/result.json')
      if result and result.job_id == job.id then
        if job.action ~= 'separate' then r.DeleteExtState(section, 'component_job', true) end
        if not result.ok and not result.cancelled then
          self:record_error(result.message)
          self.phase = 'idle'
          self.job = nil
          self.message = self.error:match('^[^\r\n]*')
          return
        end
        if result.ok and job.action == 'separate' and not self.cancel_requested then
          begin_import(result)
        else
          self.phase, self.job = 'idle', nil
          self.progress, self.message = 1, result.message or 'Операция отменена.'
          update_registry()
          refresh_models(true)
        end
        return
      end
      local now = r.time_precise()
      if not job.polled or now - job.polled >= .25 then
        job.polled = now
        local status = storage:read(job.work .. '/status.json')
        if status and status.job_id == job.id and not self.cancel_requested then
          self.message = status.message
          self.progress = status.total and status.total > 0 and math.max(0, math.min(1, status.bytes / status.total)) or
            (status.stage == 'separating' and .2 or self.progress)
        end
      end
      if now - job.started >= 30 and (not job.checked or now - job.checked >= 30) then
        job.checked = now
        launch('Check')
      end
    end, debug.traceback)
    if not worked then self:fail(problem) end
  end
  self:refresh_selection()
  return {module = self, models = catalog, audio = Audio, fonts = self.fonts}
end
