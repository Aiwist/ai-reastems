-- Standalone audio binding and durable, unnormalised stem export.
local here=debug.getinfo(1,'S').source:sub(2):match('^(.*)[/\\]')
local Identity=dofile(here..'/drum_source.lua')
local Gate=dofile(here..'/drumsep_gate.lua')
local M={names={kick={'Бочка','Kick'},snare={'Рабочий','Snare'},toms={'Томы','Toms'},hh={'Хай-хэт','Hi-Hat'},ride={'Райд','Ride'},crash={'Крэш','Crash'}}}
M.order={'kick','snare','toms','hh','ride','crash'}
M.composition_names={drums={'Барабаны','Drums'},bass={'Бас','Bass'},vocals={'Вокал','Vocals'},
  other={'Остальное','Other'},guitar={'Гитара','Guitar'},piano={'Фортепиано','Piano'},
  instrumental={'Инструментал','Instrumental'}, denoised={'Без шума','Denoised'}, noise={'Шум','Noise'},
  no_echo={'Без эха','No Echo'}, echo={'Эхо','Echo'}, no_reverb={'Без реверберации','No Reverb'},
  noreverb={'Без реверберации','No Reverb'}, reverb={'Реверберация','Reverb'}}
local filenames={hh='hi-hat', noreverb='no_reverb'}
function M.title(name)
  return filenames[name] or name
end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
function M.snapshot(r,J,items,describe)
  assert(#items>0 and #items<=200,'Выберите от 1 до 200 аудиофрагментов на одной дорожке.')
  local members,track={},nil
  for _,item in ipairs(items)do
    assert(r.ValidatePtr2(0,item,'MediaItem*'),'Исходный фрагмент удалён.')
    local current=r.GetMediaItem_Track(item);assert(not track or current==track,'Выберите аудиофрагменты на одной дорожке.');track=current
    members[#members+1]=describe(r,item,true)
  end
  table.sort(members,function(a,b)if a.position==b.position then return a.item_guid<b.item_guid end;return a.position<b.position end)
  local source=copy(members[1]);local last=source.position+source.duration
  for _,part in ipairs(members)do last=math.max(last,part.position+part.duration)end
  source.duration=last-source.position
  if #members>1 then source.members=members;source.name=source.track_name~=''and source.track_name or source.name end
  source.fingerprint=Identity.fingerprint(J.encode(members))
  assert(source.duration>0 and source.duration<=1500,'Выберите фрагмент длительностью до 25 минут.')
  return source,track,members
end
function M.selected(r)
  local items,parts={},{}
  for i=0,r.CountSelectedMediaItems(0)-1 do
    local item=r.GetSelectedMediaItem(0,i)
    local take=r.GetActiveTake(item)
    if take and not r.TakeIsMIDI(take)then
      items[#items+1]=item
      parts[#parts+1]=tostring(item)..':'..tostring(take)..':'..tostring(r.GetMediaItem_Track(item))
    end
  end
  return items,table.concat(parts,'|')
end
function M.wav(path)
  local f=assert(io.open(path,'rb'),'AITN-725: Не удалось открыть WAV: '..tostring(path))
  local ok,value=xpcall(function()
    local h=assert(f:read(12));assert(h:sub(1,4)=='RIFF'and h:sub(9,12)=='WAVE','AITN-725: Неизвестный WAV.')
    local spec={}
    for _=1,64 do
      local raw=f:read(8);if not raw or #raw~=8 then break end
      local name,n=string.unpack('<c4I4',raw);local at=f:seek()
      if name=='fmt 'then
        assert(n>=16 and n<=4096,'AITN-725: Неверный WAV.')
        local body=assert(f:read(n));spec.format,spec.channels,spec.rate,spec.average,spec.alignment,spec.bits=string.unpack('<I2I2I4I4I2I2',body)
        if spec.format==0xfffe and #body>=40 then spec.format=string.unpack('<I2',body,25)end
      elseif name=='data'then spec.offset=at;spec.bytes=n;break end
      f:seek('set',at+n+n%2)
    end
    assert(spec.offset and spec.rate and spec.rate>=12000 and spec.rate<=96000 and(spec.channels==1 or spec.channels==2)and
      ((spec.format==1 and spec.bits==16)or(spec.format==3 and spec.bits==32))and spec.alignment==spec.channels*spec.bits//8,'AITN-725: Неподдерживаемый WAV.')
    assert(spec.bytes%spec.alignment==0 and spec.offset+spec.bytes<=f:seek('end'),'AITN-725: WAV обрезан.')
    spec.frames=spec.bytes//spec.alignment;return spec
  end,debug.traceback)
  f:close();assert(ok,value);return value
end
function M.trim(from,to,padding,duration,yield_fn,gate)
  local spec=M.wav(from);local first=math.floor(padding*spec.rate+.5);local count=math.floor(duration*spec.rate+.5)
  assert(first+count<=spec.frames,'AITN-725: Стем короче исходного аудио.')
  local exists=io.open(to,'rb');if exists then exists:close();error('Файл назначения уже существует: '..to)end
  local plan=Gate.plan(from,spec,first,count,gate,yield_fn)
  local input=assert(io.open(from,'rb'));local output
  local ok,problem=xpcall(function()
    output=assert(io.open(to,'wb'),'Не удалось сохранить стем в папку проекта.')
    local bytes=count*spec.alignment
    local header='RIFF'..string.pack('<I4',36+bytes)..'WAVEfmt '..string.pack('<I4I2I2I4I4I2I2',16,spec.format,spec.channels,spec.rate,spec.rate*spec.alignment,spec.alignment,spec.bits)..'data'..string.pack('<I4',bytes)
    assert(output:write(header))
    input:seek('set',spec.offset+first*spec.alignment)
    local done=0
    while bytes>0 do
      local size=math.min(bytes,65536);local raw=assert(input:read(size));assert(#raw==size,'Стем обрезан.')
      if plan then raw=Gate.encode(Gate.apply(Gate.decode(raw,spec),size//spec.alignment,spec.channels,first+done,plan),spec)end
      assert(output:write(raw));bytes=bytes-size;done=done+size//spec.alignment
      if yield_fn then yield_fn()end
    end
    assert(output:close());output=nil
  end,debug.traceback)
  input:close();if output then output:close()end;assert(ok,problem)
  return spec
end
function M.media_folder(r,project,id,composition)
  -- GetProjectPathEx honours the project's configured media directory, including
  -- portable REAPER. For an unsaved tab REAPER supplies its default media path.
  local folder=r.GetProjectPathEx(project,'');assert(type(folder)=='string'and folder~='','Не удалось определить папку медиа проекта. Сохраните проект и повторите.')
  return folder..(composition and '/ReaStems/' or '/DrumSep/')..id
end
function M.build_source_peaks(r,pcm,yield_fn,progress)
  local building=false
  local ok,problem=xpcall(function()
    if r.PCM_Source_BuildPeaks(pcm,0)~=0 then
      building=true
      repeat
        local remaining=r.PCM_Source_BuildPeaks(pcm,1)
        if progress then progress(math.max(0,math.min(1,1-remaining/100)))end
        if yield_fn then yield_fn()end
      until remaining==0
      r.PCM_Source_BuildPeaks(pcm,2);building=false
    end
  end,debug.traceback)
  if building then pcall(r.PCM_Source_BuildPeaks,pcm,2)end
  assert(ok,problem)
end
function M.build_peaks(r,path,yield_fn,progress)
  -- Temporary source before import; existing project sources stay caller-owned.
  local pcm=assert(r.PCM_Source_CreateFromFile(path),'Не удалось открыть стем для построения волны.')
  local ok,problem=pcall(M.build_source_peaks,r,pcm,yield_fn,progress)
  r.PCM_Source_Destroy(pcm);assert(ok,problem)
end
function M.insert_stems(r,project,track,source,files)
  local created={};local began=false
  r.PreventUIRefresh(1)
  local ok,problem=xpcall(function()
    r.Undo_BeginBlock2(project);began=true
    local index=math.floor(r.GetMediaTrackInfo_Value(track,'IP_TRACKNUMBER'))
    for i,file in ipairs(files)do
      r.InsertTrackAtIndex(index+i-1,true);local target=assert(r.GetTrack(project,index+i-1));created[#created+1]=target
      local title=M.title(file.name)
      r.GetSetMediaTrackInfo_String(target,'P_NAME',title,true)
      local item=assert(r.AddMediaItemToTrack(target));r.SetMediaItemInfo_Value(item,'D_POSITION',source.position);r.SetMediaItemInfo_Value(item,'D_LENGTH',source.duration)
      r.SetMediaItemInfo_Value(item,'D_FADEINLEN',0);r.SetMediaItemInfo_Value(item,'D_FADEOUTLEN',0)
      local take=assert(r.AddTakeToMediaItem(item));local pcm=assert(r.PCM_Source_CreateFromFile(file.path),'Не удалось открыть сохранённый стем.')
      r.SetMediaItemTake_Source(take,pcm);r.GetSetMediaItemTakeInfo_String(take,'P_NAME',title,true)
      r.UpdateItemInProject(item)
    end
  end,debug.traceback)
  if not ok then for i=#created,1,-1 do pcall(r.DeleteTrack,created[i])end end
  if began then pcall(r.Undo_EndBlock2,project,'Ai ReaStems: разделить на стемы',-1)end
  pcall(r.PreventUIRefresh,-1);pcall(r.TrackList_AdjustWindows,false);pcall(r.UpdateArrange)
  assert(ok,problem);return created
end
return M
