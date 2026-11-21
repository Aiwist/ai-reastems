-- @description Ai ReaStems — совместимый запуск
-- @version 0.2.5

local target = reaper.GetResourcePath() .. '/Scripts/Aiwist/ReaStems/Aiwist_ReaStems.lua'
if reaper.file_exists(target) then
  dofile(target)
else
  reaper.MB('Установите Ai ReaStems.', 'Ai ReaStems', 0)
end
