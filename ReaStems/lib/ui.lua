-- Visual helpers adapted from Ai Transcriber Plus 2.16.8 (Aiwist, Apache-2.0).
return function(reaper, backend, settings, name, version, save)
local FONT = {}
local ICON = {SETTINGS = utf8.char(0xE154)}
local module = backend.module
local settings_anchor_x, settings_anchor_y
local folder_drafts = {}
local function ui_size(size)
  return math.max(1, math.floor(size * settings.scale + 0.5))
end

local TK_LIGHT = {
  bg = 0xE6EAF1FF, bg_elev = 0xF3F6FBFF, card = 0xFFFFFFFF,
  title_bg = 0xE6EAF1FF,
  card_hover = 0xF3F6FAFF, prompt_bg = 0xFFFFFFFF,
  border = 0x465F8C42, border_str = 0x465F8C5C,
  text = 0x0F1824FF, text_muted = 0x475467FF, text_faint = 0x5E6A7CFF,
  accent = 0x3F63A8FF, accent_ui = 0x89A4E4FF, accent_soft = 0xBDD1EEFF,
  accent_text = 0xFFFFFFFF, input_bg = 0xECEFF5FF,
  green = 0x217548FF, red = 0xC14747FF, amber = 0x8A5A12FF,
  footer_bg = 0x00000005,
}
local TK_DARK = {
  bg = 0x1C1F21FF, bg_elev = 0x202326FF, card = 0x292C2FFF,
  title_bg = 0x090A0BFF,
  card_hover = 0x35383BFF, prompt_bg = 0x24272AFF,
  border = 0xFFFFFF18, border_str = 0xFFFFFF2A,
  text = 0xE6E8EAFF, text_muted = 0xA0A4A8FF, text_faint = 0x7A7E82FF,
  accent = 0xF0B84FFF, accent_ui = 0x8C682DFF, accent_soft = 0x3B3020FF,
  accent_text = 0xFFFFFFFF, input_bg = 0x17191BFF,
  green = 0x66CC66FF, red = 0xD46F6FFF, amber = 0xF0B84FFF,
  footer_bg = 0x00000026,
}
local TK_CYAN = {
  bg = 0x1C1F21FF, bg_elev = 0x202326FF, card = 0x292C2FFF,
  title_bg = 0x090A0BFF,
  card_hover = 0x35383BFF, prompt_bg = 0x24272AFF,
  border = 0x7BA7AE28, border_str = 0x7BA7AE48,
  text = 0xE6E8EAFF, text_muted = 0xA0A4A8FF, text_faint = 0x7A7E82FF,
  accent = 0x6DC9DAFF, accent_ui = 0x2B778CFF, accent_soft = 0x1C343AFF,
  accent_text = 0xFFFFFFFF, input_bg = 0x17191BFF,
  green = 0x66CC66FF, red = 0xD46F6FFF, amber = 0x6DC9DAFF,
  footer_bg = 0x00000026,
}
local TK = TK_CYAN

local function ui_text(ru, en)
  return settings.language == "ru" and ru or en
end

local function push_font(c, font, size)
  if not font then return false end
  reaper.ImGui_PushFont(c, font, ui_size(size))
  return true
end

local function pop_font(c, pushed)
  if pushed then reaper.ImGui_PopFont(c) end
end

local function calc_text(c, font, size, text)
  local pushed = push_font(c, font, size)
  local w, h = reaper.ImGui_CalcTextSize(c, text)
  pop_font(c, pushed)
  return w or 0, h or size
end

local function dl_text(dl, font, size, x, y, color, text)
  if font then
    reaper.ImGui_DrawList_AddTextEx(dl, font, ui_size(size), x, y, color, text)
  else
    reaper.ImGui_DrawList_AddText(dl, x, y, color, text)
  end
end

local function lerp_u32(a, b, t)
  local ar, ag, ab, aa = (a >> 24) & 0xFF, (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
  local br, bg, bb, ba = (b >> 24) & 0xFF, (b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF
  local it = 1 - t
  return ((math.floor(ar * it + br * t) & 0xFF) << 24)
       | ((math.floor(ag * it + bg * t) & 0xFF) << 16)
       | ((math.floor(ab * it + bb * t) & 0xFF) << 8)
       |  (math.floor(aa * it + ba * t) & 0xFF)
end

local function select_palette()
  TK = settings.theme == "light" and TK_LIGHT
    or settings.theme == "cyan" and TK_CYAN
    or TK_DARK
end

local function push_theme(c)
  select_palette()
  local colors = {
    { reaper.ImGui_Col_WindowBg(), TK.bg },
    { reaper.ImGui_Col_ChildBg(), TK.bg },
    { reaper.ImGui_Col_PopupBg(), TK.bg_elev },
    { reaper.ImGui_Col_TitleBg(), TK.title_bg },
    { reaper.ImGui_Col_TitleBgActive(), TK.title_bg },
    { reaper.ImGui_Col_TitleBgCollapsed(), TK.title_bg },
    { reaper.ImGui_Col_Text(), TK.text },
    { reaper.ImGui_Col_TextDisabled(), TK.text_faint },
    { reaper.ImGui_Col_Border(), TK.border },
    { reaper.ImGui_Col_Separator(), TK.border },
    { reaper.ImGui_Col_FrameBg(), TK.input_bg },
    { reaper.ImGui_Col_FrameBgHovered(), TK.prompt_bg },
    { reaper.ImGui_Col_FrameBgActive(), TK.prompt_bg },
    { reaper.ImGui_Col_Button(), TK.card },
    { reaper.ImGui_Col_ButtonHovered(), TK.card_hover },
    { reaper.ImGui_Col_ButtonActive(), lerp_u32(TK.card_hover, TK.accent_ui, 0.35) },
    { reaper.ImGui_Col_Header(), TK.card },
    { reaper.ImGui_Col_HeaderHovered(), TK.card_hover },
    { reaper.ImGui_Col_HeaderActive(), lerp_u32(TK.card_hover, TK.accent_ui, 0.30) },
    { reaper.ImGui_Col_PlotHistogram(), TK.accent },
    { reaper.ImGui_Col_PlotHistogramHovered(), TK.accent },
    { reaper.ImGui_Col_TableHeaderBg(), TK.card },
    { reaper.ImGui_Col_TableBorderStrong(), TK.border_str },
    { reaper.ImGui_Col_TableBorderLight(), TK.border },
    { reaper.ImGui_Col_TableRowBg(), 0x00000000 },
    { reaper.ImGui_Col_TableRowBgAlt(), TK.footer_bg },
    { reaper.ImGui_Col_CheckMark(), TK.accent },
    { reaper.ImGui_Col_ScrollbarBg(), 0x00000000 },
    { reaper.ImGui_Col_ScrollbarGrab(), TK.border_str },
    { reaper.ImGui_Col_ScrollbarGrabHovered(), TK.accent_ui },
    { reaper.ImGui_Col_ScrollbarGrabActive(), TK.accent },
  }
  for _, pair in ipairs(colors) do
    reaper.ImGui_PushStyleColor(c, pair[1], pair[2])
  end
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_WindowBorderSize(), 0)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_FramePadding(), 8, 5)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_ItemSpacing(), 7, 4)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_FrameRounding(), 5)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_GrabRounding(), 5)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_ChildRounding(), 6)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_PopupRounding(), 7)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_ScrollbarSize(), 10)
  return #colors, 9
end

local function section_label(c, label)
  local base_x = reaper.ImGui_GetCursorPosX(c)
  local inset = 7
  reaper.ImGui_SetCursorPosX(c, base_x + inset)

  local pushed = push_font(c, FONT.mono_med, 10)
  reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Text(), TK.text_faint)
  reaper.ImGui_Text(c, label)
  reaper.ImGui_PopStyleColor(c)
  pop_font(c, pushed)
  local x2, y2 = reaper.ImGui_GetItemRectMax(c)
  local _, y1 = reaper.ImGui_GetItemRectMin(c)
  local cursor_x = reaper.ImGui_GetCursorScreenPos(c)
  local avail_w = reaper.ImGui_GetContentRegionAvail(c)
  local line_y = math.floor((y1 + y2) * 0.5)
  local line_end = cursor_x + avail_w
  if line_end > x2 + 8 then
    reaper.ImGui_DrawList_AddLine(reaper.ImGui_GetWindowDrawList(c),
      x2 + 8, line_y, line_end, line_y, TK.border, 1)
  end
  reaper.ImGui_SetCursorPosX(c, base_x)
  reaper.ImGui_Dummy(c, 1, 1)
end

local card_inset = 7

local function begin_card(c, id)
  local avail_w = reaper.ImGui_GetContentRegionAvail(c)
  reaper.ImGui_Indent(c, card_inset)
  reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_ChildBg(), TK.card)
  reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Border(), TK.border)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_ChildBorderSize(), 1)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_ChildRounding(), 6)
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_WindowPadding(), 14, 10)
  return reaper.ImGui_BeginChild(c, id,
    math.max(1, avail_w - card_inset * 2), 0,
    reaper.ImGui_ChildFlags_AutoResizeY() | reaper.ImGui_ChildFlags_Borders())
end

local function end_card(c, child_open)
  reaper.ImGui_PopStyleVar(c, 3)
  reaper.ImGui_PopStyleColor(c, 2)
  if child_open then reaper.ImGui_EndChild(c) end
  reaper.ImGui_Unindent(c, card_inset)
end

local function card_title(c, title, dot_color, wrap_x)
  local pushed = push_font(c, FONT.inter_semi, 12)
  reaper.ImGui_AlignTextToFramePadding(c)
  local dl = reaper.ImGui_GetWindowDrawList(c)
  local sx, sy = reaper.ImGui_GetCursorScreenPos(c)
  local dot_y = sy + math.floor(reaper.ImGui_GetFrameHeight(c) / 2)
  reaper.ImGui_DrawList_AddRectFilled(dl, sx, dot_y - 2, sx + 4, dot_y + 2, dot_color)
  reaper.ImGui_SetCursorPosX(c, reaper.ImGui_GetCursorPosX(c) + 10)
  reaper.ImGui_PushTextWrapPos(c, wrap_x)
  reaper.ImGui_TextColored(c, TK.text, title)
  reaper.ImGui_PopTextWrapPos(c)
  pop_font(c, pushed)
end

local function muted_text(c, text, wrap)
  local pushed = push_font(c, FONT.inter_reg, 11)
  reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Text(), TK.text_muted)
  if wrap then reaper.ImGui_TextWrapped(c, text) else reaper.ImGui_Text(c, text) end
  reaper.ImGui_PopStyleColor(c)
  pop_font(c, pushed)
end

local function mono_text(c, color, text)
  local pushed = push_font(c, FONT.mono_reg, 10)
  reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Text(), color)
  reaper.ImGui_Text(c, text)
  reaper.ImGui_PopStyleColor(c)
  pop_font(c, pushed)
end

local function draw_hero(c)
  local dl = reaper.ImGui_GetWindowDrawList(c)
  local base_x = reaper.ImGui_GetCursorPosX(c)
  local base_y = reaper.ImGui_GetCursorPosY(c)
  local sx, sy = reaper.ImGui_GetCursorScreenPos(c)
  local win_x = reaper.ImGui_GetWindowPos(c)
  local win_w = reaper.ImGui_GetWindowWidth(c)
  local hero_h = 72
  reaper.ImGui_DrawList_AddRectFilledMultiColor(dl,
    win_x, sy, win_x + win_w, sy + hero_h,
    TK.accent_soft, TK.accent_soft, TK.bg, TK.bg)
  reaper.ImGui_DrawList_AddLine(dl, win_x, sy + hero_h - 1,
    win_x + win_w, sy + hero_h - 1, TK.border, 1)

  local pad_x = 20
  local title_y = sy + 10
  local brand_w = calc_text(c, FONT.inter_light or FONT.inter_reg, 24, "Ai ")
  dl_text(dl, FONT.inter_light or FONT.inter_reg, 24, sx + pad_x, title_y,
    lerp_u32(TK.accent, 0x18264FFF, 0.25), "Ai ")
  dl_text(dl, FONT.inter_bold or FONT.inter_semi, 24, sx + pad_x + brand_w - 1,
    title_y, TK.accent, "ReaStems")
  dl_text(dl, FONT.mono_med, 9, sx + pad_x, sy + 43, TK.text_muted,
    ui_text("РАЗДЕЛЕНИЕ АУДИО", "STEM SEPARATION"))

  local icon_size = 14
  local icon_font = FONT.lucide
  local icon_text = icon_font and ICON.SETTINGS or "..."
  local iw = calc_text(c, icon_font, icon_size, icon_text)
  local version_label = "v" .. version
  local version_font = FONT.mono_reg or FONT.inter_reg
  local version_w = calc_text(c, version_font, 9, version_label)
  local tap_w, tap_h = math.max(iw + 10, version_w, 24), 24
  local x1 = sx + win_w - 20 - tap_w
  local y1 = sy + math.floor((hero_h - tap_h) * 0.5)
  reaper.ImGui_SetCursorScreenPos(c, x1, y1)
  local clicked = reaper.ImGui_InvisibleButton(c, "##settings_gear", tap_w, tap_h)
  local hovered = reaper.ImGui_IsItemHovered(c)
  if hovered then reaper.ImGui_SetMouseCursor(c, reaper.ImGui_MouseCursor_Hand()) end
  if hovered then reaper.ImGui_SetTooltip(c, ui_text("Настройки", "Settings")) end
  dl_text(dl, icon_font, icon_size,
    x1 + math.floor((tap_w - iw) * 0.5), y1 + math.floor((tap_h - icon_size) * 0.5),
    hovered and TK.text or TK.text_muted, icon_text)
  dl_text(dl, version_font, 9, x1 + (tap_w - version_w) * 0.5,
    y1 + tap_h + 1, TK.text_muted, version_label)
  settings_anchor_x = x1 + tap_w
  settings_anchor_y = y1 + tap_h
  if clicked then reaper.ImGui_OpenPopup(c, "settings_popup") end

  reaper.ImGui_SetCursorPos(c, base_x, base_y)
  reaper.ImGui_Dummy(c, 1, hero_h)
end

local function draw_source_card(c)
  local binding = module.binding
  local source = binding and binding.source
  local count = binding and #binding.items or 0
  local title = ui_text("(объект не выбран)", "(no item selected)")
  if count > 1 then
    title = ui_text("Выбрано айтемов: ", "Selected items: ") .. count
  elseif source then
    title = source.name ~= "" and source.name or ui_text("Аудиофрагмент", "Audio item")
  end
  local position, duration = source and source.position or 0, source and source.duration or 0
  local bpm = reaper.TimeMap_GetDividedBpmAtTime(0, source and position or reaper.GetCursorPosition())

  section_label(c, ui_text("ИСТОЧНИК АУДИО", "AUDIO SOURCE"))
  local visible = begin_card(c, "##source_card")
  if visible then
    card_title(c, title, source and TK.accent_ui or TK.amber, 0)
    if module.selection_issue then
      muted_text(c, module.selection_issue, true)
    elseif source then
      local track_name = source.track_name
      if binding.project_ptr == reaper.EnumProjects(-1, "") and
          reaper.ValidatePtr2(binding.project_ptr, binding.track, "MediaTrack*") then
        local index = reaper.GetMediaTrackInfo_Value(binding.track, "IP_TRACKNUMBER")
        if track_name == "" then track_name = ui_text("Дорожка ", "Track ") .. math.floor(index) end
        track_name = string.format("%s  ·  #%d", track_name, index)
      end
      muted_text(c, track_name, true)
    else
      muted_text(c, ui_text("Сначала выберите аудиообъект.", "Select an audio item first."), true)
    end
    local function fmt(seconds)
      seconds = math.max(0, seconds)
      return string.format("%d:%05.2f", math.floor(seconds / 60), seconds % 60)
    end
    local details = string.format("%s  %s     %s  %s     %s  %.2f",
      ui_text("ПОЗИЦИЯ", "POSITION"), fmt(position), ui_text("ДЛИТЕЛЬНОСТЬ", "DURATION"), fmt(duration),
      ui_text("ТЕМП ПРОЕКТА", "PROJECT BPM"), bpm)
    mono_text(c, TK.text_muted, details)
    if module:busy() then
      muted_text(c, ui_text("Источник закреплён на время обработки.", "Source locked while processing."), true)
    end
  end
  end_card(c, visible)
end

local function model_label(model)
  return backend.models.models[model].label
end

local function action(fn)
  local ok, problem = xpcall(fn, debug.traceback)
  if not ok then module:fail(problem) end
end

local function draw_support(c, id)
  if reaper.ImGui_Button(c, ui_text("Сохранить отчёт об ошибке", "Save error report") .. "##report_" .. id) then
    local ok, result = pcall(module.save_error_report, module)
    module.report_message = ok and (ui_text("Отчёт сохранён", "Report saved") .. "\n" .. result) or tostring(result)
  end
  if module.report_message then muted_text(c, module.report_message, true) end
end

local function draw_model(c)
  local installed = {}
  local current = module.split_model
  local selected
  for _, id in ipairs(backend.models.order) do
    if module:stem_registration(id) then
      installed[#installed + 1] = id
      if id == current then selected = id end
    end
  end
  module.split_model = selected or installed[1]
  section_label(c, ui_text("МОДЕЛЬ РАЗДЕЛЕНИЯ", "SEPARATION MODEL"))
  local visible = begin_card(c, "##model_card")
  if visible then
    if module.split_model then
      reaper.ImGui_BeginDisabled(c, module:busy())
      reaper.ImGui_SetNextItemWidth(c, -1)
      if reaper.ImGui_BeginCombo(c, "##model", model_label(module.split_model)) then
        for _, id in ipairs(installed) do
          local active = module.split_model == id
          if reaper.ImGui_Selectable(c, model_label(id), active) then
            module.split_model = id
            module:save_settings()
          end
          if active then reaper.ImGui_SetItemDefaultFocus(c) end
        end
        reaper.ImGui_EndCombo(c)
      end
      reaper.ImGui_EndDisabled(c)
    else
      muted_text(c, ui_text("Установите модель в настройках.", "Install a model in Settings."), true)
    end
  end
  end_card(c, visible)
  return module.split_model
end

local function draw_outputs(c, model, marked)
  section_label(c, ui_text("ДОРОЖКИ ДЛЯ ВСТАВКИ", "TRACKS TO IMPORT"))
  local visible = begin_card(c, "##outputs_card")
  local count = 0
  if visible then
    reaper.ImGui_BeginDisabled(c, module:busy())
    if reaper.ImGui_BeginTable(c, "##outputs", 2) then
      for _, stem in ipairs(module:stem_names(model)) do
        reaper.ImGui_TableNextColumn(c)
        local changed, checked = reaper.ImGui_Checkbox(c, ui_text(table.unpack(backend.audio.names[stem] or backend.audio.composition_names[stem])) .. "##stem_" .. stem,
          marked[stem] ~= false)
        if changed then
          marked[stem] = checked
          module.split_outputs[model] = marked
          module:save_settings()
        end
        if marked[stem] ~= false then count = count + 1 end
      end
      reaper.ImGui_EndTable(c)
    end
    reaper.ImGui_EndDisabled(c)
  end
  end_card(c, visible)
  return count
end

local function draw_actions(c, model, marked, count)
  local busy = module:busy()
  local blocked = busy or module.storage.restart_required == true
  local _, engine_ready = module:engine()
  local visible = begin_card(c, "##actions_card")
  if visible then
    reaper.ImGui_BeginDisabled(c, blocked or not engine_ready or not model or not module.binding or module.selection_issue ~= nil or count == 0)
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_Button(), TK.accent_ui)
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_ButtonHovered(), lerp_u32(TK.accent_ui, TK.accent, .2))
    reaper.ImGui_PushStyleColor(c, reaper.ImGui_Col_ButtonActive(), lerp_u32(TK.accent_ui, TK.accent, .3))
    local start = reaper.ImGui_Button(c, ui_text("Разделить на стемы", "Separate stems"), -1, ui_size(36))
    reaper.ImGui_PopStyleColor(c, 3)
    reaper.ImGui_EndDisabled(c)
    if start and model then action(function() module:separate(model, marked) end) end
    if module:busy() then
      local progress = math.max(0, math.min(1, module.progress or 0))
      reaper.ImGui_ProgressBar(c, progress, -1, 0, string.format("%d%%", math.floor(progress * 100)))
      reaper.ImGui_BeginDisabled(c, module.cancel_requested)
      if reaper.ImGui_Button(c, ui_text("Остановить", "Stop")) then action(function() module:cancel() end) end
      reaper.ImGui_EndDisabled(c)
    end
    if module.storage.restart_required then
      muted_text(c, ui_text("Папка данных изменена. Откройте Ai ReaStems заново.", "Reopen Ai ReaStems to use the new data folder."), true)
    end
    if module.message then muted_text(c, module.message, true) end
    if module.warning then muted_text(c, module.warning, true) end
    if module.error then
      if reaper.ImGui_CollapsingHeader(c, ui_text("Подробности ошибки", "Error details")) then
        reaper.ImGui_TextWrapped(c, module.error)
      end
      draw_support(c, "main")
    end
  end
  end_card(c, visible)
end

local function draw_settings_models(c)
  reaper.ImGui_Text(c, ui_text("Модели", "Models"))
  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() |
    reaper.ImGui_TableFlags_ScrollY()
  if not reaper.ImGui_BeginTable(c, "##models", 4, flags, 0, ui_size(288)) then return end
  reaper.ImGui_TableSetupColumn(c, ui_text("Модель", "Model"), reaper.ImGui_TableColumnFlags_WidthStretch(), 1.65)
  reaper.ImGui_TableSetupColumn(c, ui_text("Размер", "Size"), reaper.ImGui_TableColumnFlags_WidthFixed(), ui_size(72))
  reaper.ImGui_TableSetupColumn(c, ui_text("Состояние", "Status"), reaper.ImGui_TableColumnFlags_WidthStretch())
  reaper.ImGui_TableSetupColumn(c, "", reaper.ImGui_TableColumnFlags_WidthFixed(), ui_size(88))
  reaper.ImGui_TableSetupScrollFreeze(c, 0, 1)
  reaper.ImGui_TableHeadersRow(c)
  local titles = {
    mix = ui_text("Композиция", "Full mix"), vocals = ui_text("Вокал", "Vocals"),
    drums = ui_text("Барабаны", "Drums"), cleanup = ui_text("Очистка аудио", "Audio cleanup"),
  }
  local category
  for _, id in ipairs(backend.models.order) do
    local model = backend.models.models[id]
    if category ~= model.category then
      category = model.category
      reaper.ImGui_TableNextRow(c)
      reaper.ImGui_TableNextColumn(c)
      reaper.ImGui_TextColored(c, TK.accent, titles[category])
    end
    reaper.ImGui_TableNextRow(c)
    reaper.ImGui_TableNextColumn(c)
    reaper.ImGui_TextWrapped(c, model.label)
    reaper.ImGui_TableNextColumn(c)
    reaper.ImGui_Text(c, string.format("%.1f MB", model.bytes / 1000000))
    reaper.ImGui_TableNextColumn(c)
    local installed = module:stem_registration(id)
    local active = id == module.split_model
    if module.job and module.job.model == id and module.job.action == "install" then
      reaper.ImGui_TextColored(c, TK.accent, ui_text("Установка…", "Installing…"))
    elseif installed then
      reaper.ImGui_TextColored(c, TK.green, active and ui_text("Активна", "Active") or ui_text("Установлена", "Installed"))
      if reaper.ImGui_IsItemHovered(c) then reaper.ImGui_SetTooltip(c, installed) end
    else
      reaper.ImGui_TextColored(c, TK.text_muted, ui_text("Не установлена", "Not installed"))
    end
    reaper.ImGui_TableNextColumn(c)
    reaper.ImGui_BeginDisabled(c, module:busy() or module.storage.restart_required or (installed and active) == true)
    local label = installed and ui_text("Выбрать", "Select") or ui_text("Установить", "Install")
    if reaper.ImGui_Button(c, label .. "##model_" .. id) then
      if installed then
        module.split_model = id
        module:save_settings()
      else
        action(function() module:install(id) end)
      end
    end
    reaper.ImGui_EndDisabled(c)
  end
  reaper.ImGui_EndTable(c)
end

local function draw_engine_settings(c)
  if not reaper.ImGui_CollapsingHeader(c, ui_text("Движок разделения аудио", "Stem separation engine")) then return end
  local engine, ready = module:engine()
  reaper.ImGui_Text(c, ready and ("stems.cpp · " .. engine.version .. " · Vulkan / CPU") or
    ui_text("Восстановите движок из установщика Ai ReaStems.", "Restore the engine from the Ai ReaStems installer."))
  if ready then reaper.ImGui_TextWrapped(c, engine.root) end
  reaper.ImGui_BeginDisabled(c, module:busy() or module.storage.restart_required == true)
  if reaper.ImGui_Button(c, ui_text("Проверить обновления", "Check for updates")) then
    action(function() module:request_engine("check") end)
  end
  local update = module:available_update()
  if update then
    reaper.ImGui_SameLine(c)
    if reaper.ImGui_Button(c, ui_text("Обновить до ", "Update to ") .. update) then
      action(function() module:request_engine("install", update) end)
    end
  end
  local device = module:device()
  reaper.ImGui_Text(c, ui_text("Устройство вычисления", "Compute device"))
  reaper.ImGui_SetNextItemWidth(c, ui_size(230))
  local auto = ui_text("Авто (Vulkan / CPU)", "Auto (Vulkan / CPU)")
  if reaper.ImGui_BeginCombo(c, "##device", device == "cpu" and "CPU" or auto) then
    if reaper.ImGui_Selectable(c, auto, device == "auto") then save("device", "auto") end
    if reaper.ImGui_Selectable(c, "CPU", device == "cpu") then save("device", "cpu") end
    reaper.ImGui_EndCombo(c)
  end
  reaper.ImGui_EndDisabled(c)
end

local function draw_folder_path(c, id, current, blocked, apply)
  local path = folder_drafts[id] or current
  reaper.ImGui_SetNextItemWidth(c, -1)
  local flags = blocked and reaper.ImGui_InputTextFlags_ReadOnly() or 0
  local changed, entered = reaper.ImGui_InputText(c, "##folder_path_" .. id, path, flags)
  if changed then
    path = entered
    folder_drafts[id] = path
  end

  if reaper.ImGui_Button(c, ui_text("Копировать путь", "Copy path") .. "##folder_copy_" .. id) then
    reaper.ImGui_SetClipboardText(c, path)
  end
  reaper.ImGui_SameLine(c)
  if reaper.ImGui_Button(c, ui_text("Открыть папку", "Open folder") .. "##folder_open_" .. id) then
    action(function() module.storage:open_folder(current) end)
  end
  reaper.ImGui_SameLine(c)
  reaper.ImGui_BeginDisabled(c, blocked or path == current or not path:find("%S"))
  if reaper.ImGui_Button(c, ui_text("Применить", "Apply") .. "##folder_apply_" .. id) then
    action(function()
      apply(path)
      folder_drafts[id] = nil
    end)
  end
  reaper.ImGui_EndDisabled(c)
end

local function draw_storage_settings(c)
  local storage = module.storage
  local blocked = module:busy() or storage.restart_required == true
  if reaper.ImGui_CollapsingHeader(c, ui_text("Папка данных скрипта", "Script data folder")) then
    muted_text(c, ui_text("Временные WAV, кэш и журналы заданий.", "Temporary WAVs, cache and job logs."), true)
    draw_folder_path(c, "data", storage.root, blocked, function(path) storage:set_data("custom", path) end)
    reaper.ImGui_BeginDisabled(c, blocked)
    if storage.mode ~= "portable" and reaper.ImGui_Button(c, ui_text("Хранить рядом с этим REAPER", "Store with this REAPER"), -1) then
      action(function() storage:set_data("portable"); folder_drafts.data = nil end)
    end
    if storage.mode ~= "system" and reaper.ImGui_Button(c, ui_text("Использовать папку пользователя Windows", "Use Windows user folder"), -1) then
      action(function() storage:set_data("system"); folder_drafts.data = nil end)
    end
    reaper.ImGui_EndDisabled(c)
  end
  if reaper.ImGui_CollapsingHeader(c, ui_text("Папка для загрузки моделей", "Model download folder")) then
    draw_folder_path(c, "models", storage.model_folder, blocked, function(path) storage:set_models(path) end)
    reaper.ImGui_BeginDisabled(c, blocked)
    if storage.model_folder ~= storage.default_models and
        reaper.ImGui_Button(c, ui_text("Папка по умолчанию", "Default folder"), -1) then
      action(function() storage:set_models(); folder_drafts.models = nil end)
    end
    reaper.ImGui_EndDisabled(c)
  end
  if storage.restart_required then
    muted_text(c, ui_text("Папка данных изменена. Откройте Ai ReaStems заново.", "Reopen Ai ReaStems to use the new data folder."), true)
  end
end

local function draw_settings(c)
  reaper.ImGui_SetNextWindowPos(c, settings_anchor_x, settings_anchor_y,
    reaper.ImGui_Cond_Appearing(), 1, 0)
  reaper.ImGui_SetNextWindowSizeConstraints(c, ui_size(465), 0, ui_size(650), ui_size(650))
  reaper.ImGui_PushStyleVar(c, reaper.ImGui_StyleVar_WindowPadding(), 14, 10)
  if reaper.ImGui_BeginPopup(c, "settings_popup") then
    draw_settings_models(c)
    draw_engine_settings(c)
    draw_storage_settings(c)
    if module.message then muted_text(c, module.message, true) end
    draw_support(c, "settings")
    if module:busy() and module.job and module.job.action ~= "separate" then
      reaper.ImGui_ProgressBar(c, module.progress or 0, -1, 0)
      reaper.ImGui_BeginDisabled(c, module.cancel_requested)
      if reaper.ImGui_Button(c, ui_text("Остановить", "Stop") .. "##settings_stop") then
        action(function() module:cancel() end)
      end
      reaper.ImGui_EndDisabled(c)
    end
    reaper.ImGui_Separator(c)
    local langs = {{"ru", "RU"}, {"en", "EN"}}
    local themes = {{"cyan", ui_text("Циан", "Cyan")}, {"dark", ui_text("Тёмная", "Dark")}, {"light", ui_text("Светлая", "Light")}}
    local scales = {{.75, "75%"}, {1, "100%"}, {1.25, "125%"}, {1.5, "150%"}}
    local selections = {
      {"language", "language", ui_text("Язык", "Language"), langs},
      {"theme", "theme", ui_text("Тема", "Theme"), themes},
      {"scale", "ui_scale", ui_text("Масштаб", "Scale"), scales},
    }
    for _, selection in ipairs(selections) do
      local key, saved, label, options = table.unpack(selection)
      muted_text(c, label, false)
      reaper.ImGui_SetNextItemWidth(c, ui_size(230))
      local title = options[1][2]
      for _, option in ipairs(options) do if option[1] == settings[key] then title = option[2] end end
      if reaper.ImGui_BeginCombo(c, "##" .. key, title) then
        for _, option in ipairs(options) do
          if reaper.ImGui_Selectable(c, option[2], settings[key] == option[1]) then
            settings[key] = option[1]
            save(saved, option[1])
          end
        end
        reaper.ImGui_EndCombo(c)
      end
    end
    if module.split_model == "mdx23c_drumsep" then
      reaper.ImGui_Separator(c)
      reaper.ImGui_BeginDisabled(c, module:busy())
      local changed, enabled = reaper.ImGui_Checkbox(c, ui_text("Гейт стемов", "Stem gate"), module.gate_settings.enabled)
      if changed then
        module.gate_settings.enabled = enabled
        module:save_settings()
      end
      if enabled then
        reaper.ImGui_SetNextItemWidth(c, ui_size(230))
        local moved, threshold = reaper.ImGui_SliderDouble(c, "##gate_threshold", module.gate_settings.threshold_db,
          -60, 0, ui_text("Порог %.1f дБFS", "Threshold %.1f dBFS"))
        if moved then
          module.gate_settings.threshold_db = threshold
          module:save_settings()
        end
      end
      reaper.ImGui_EndDisabled(c)
    end
    reaper.ImGui_EndPopup(c)
  end
  reaper.ImGui_PopStyleVar(c)
end

local function attach_fonts(ctx)
  local files = {
    inter_reg = "Inter_18pt-Regular.ttf", inter_light = "Inter_18pt-Light.ttf",
    inter_semi = "Inter_18pt-SemiBold.ttf", inter_bold = "Inter_18pt-Bold.ttf",
    mono_reg = "JetBrainsMono-Regular.ttf", mono_med = "JetBrainsMono-Medium.ttf", lucide = "lucide.ttf",
  }
  for key, file in pairs(files) do
    FONT[key] = nil
    local path = backend.fonts .. file
    if reaper.file_exists(path) then
      local ok, font = pcall(reaper.ImGui_CreateFontFromFile, path, 0, 0)
      if ok and font and pcall(reaper.ImGui_Attach, ctx, font) then FONT[key] = font end
    end
  end
end

local function draw(c)
  local colors, vars = push_theme(c)
  local font = push_font(c, FONT.inter_reg, 13)
  local viewport = reaper.ImGui_GetMainViewport(c)
  local vx, vy = reaper.ImGui_Viewport_GetWorkPos(viewport)
  local vw, vh = reaper.ImGui_Viewport_GetWorkSize(viewport)
  local first_use = reaper.ImGui_Cond_FirstUseEver()
  reaper.ImGui_SetNextWindowPos(c, vx + vw / 2, vy + vh / 2, first_use, .5, .5)
  reaper.ImGui_SetNextWindowSize(c, ui_size(540), ui_size(450), first_use)
  reaper.ImGui_SetNextWindowSizeConstraints(c, ui_size(440), 255, math.max(vw, ui_size(440)), math.max(vh, 255))
  local visible, open = reaper.ImGui_Begin(c, name, true, reaper.ImGui_WindowFlags_NoNavInputs())
  if visible then
    draw_hero(c)
    local w, h = reaper.ImGui_GetContentRegionAvail(c)
    local body = reaper.ImGui_BeginChild(c, "##main_body", w, math.max(1, h))
    if body then
      draw_source_card(c)
      reaper.ImGui_Dummy(c, 1, 5)
      local model = draw_model(c)
      local marked = type(module.split_outputs[model]) == "table" and module.split_outputs[model] or {}
      reaper.ImGui_Dummy(c, 1, 5)
      local count = model and draw_outputs(c, model, marked) or 0
      draw_actions(c, model, marked, count)
      reaper.ImGui_EndChild(c)
    end
    draw_settings(c)
    reaper.ImGui_End(c)
  end
  pop_font(c, font)
  reaper.ImGui_PopStyleVar(c, vars)
  reaper.ImGui_PopStyleColor(c, colors)
  return open
end

return {draw = draw, attach_fonts = attach_fonts}
end
