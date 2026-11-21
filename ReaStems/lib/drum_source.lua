-- Source identity for one open processing session; queue hashes remain strict.
local M={}
local editable={POSITION=true,LENGTH=true,SNAPOFFS=true,FADEIN=true,FADEOUT=true,SOFFS=true,SM=true,SEL=true}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e12 end
function M.fingerprint(text)
  text=text:gsub('\r',''):gsub('\n%s*SEL [^\n]*','')
  local hash=2166136261;for i=1,#text do hash=((hash~text:byte(i))*16777619)&0xFFFFFFFF end
  return #text..':'..string.format('%08x',hash)
end
local function lines(chunk,fn)
  local out,depth={},0;chunk=chunk:gsub('\r','')
  for line in(chunk..'\n'):gmatch('(.-)\n')do
    local clean=line:match('^%s*(.-)%s*$')
    if clean:sub(1,1)=='>'then depth=depth-1 end
    local replacement=fn(line,depth,clean:match('^(%S+)'))
    if replacement~=false then out[#out+1]=replacement or line end
    if clean:sub(1,1)=='<'then depth=depth+1 end
  end
  -- Preserve the original final newline for stable chunk fingerprints.
  return table.concat(out,'\n')
end
function M.describe(r,item,take,chunk)
  if type(r.GetMediaItemTakeInfo_Value)~='function'or type(chunk)~='string'then return nil end
  local rate=r.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE');local offset=r.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS')
  local position=r.GetMediaItemInfo_Value(item,'D_POSITION')
  if not finite(rate)or rate<=0 or not finite(offset)or not finite(position)then return nil end
  local canonical=lines(chunk,function(line,depth,key)if depth==1 and editable[key]then return false end end)
  local markers={};local count=type(r.GetTakeNumStretchMarkers)=='function'and r.GetTakeNumStretchMarkers(take)or 0
  assert(count>=0 and count<=20000,'Слишком много stretch-маркеров для проверки исходника.')
  for index=0,count-1 do
    local valid,at,source=r.GetTakeStretchMarker(take,index)
    local slope=type(r.GetTakeStretchMarkerSlope)=='function'and r.GetTakeStretchMarkerSlope(take,index)or 0
    assert(valid>=0 and finite(at)and finite(source)and finite(slope),'Не удалось проверить stretch-маркеры исходного аудио.')
    local time=position+at/rate
    markers[#markers+1]=string.format('%.6f:%.6f:%.9f',time==0 and 0 or time,source==0 and 0 or source,slope==0 and 0 or slope)
  end
  return {schema=1,content=M.fingerprint(canonical),rate=rate,anchor=offset-position*rate,markers=M.fingerprint(table.concat(markers,';'))}
end
local function valid(d)
  return type(d)=='table'and d.schema==1 and type(d.content)=='string'and #d.content<64 and
    type(d.markers)=='string'and #d.markers<64 and finite(d.rate)and d.rate>0 and finite(d.anchor)
end
function M.equal(a,b)
  return valid(a)and valid(b)and a.content==b.content and a.markers==b.markers and
    math.abs(a.rate-b.rate)<1e-10 and math.abs(a.anchor-b.anchor)<1e-7
end
function M.compatible(original,current)
  for _,key in ipairs({'item_guid','take_guid','track_guid'})do if original[key]~=current[key]then return false end end
  if original.edit_identity~=nil then return M.equal(original.edit_identity,current.edit_identity)end
  if original.fingerprint==current.fingerprint then return true end
  return false
end
function M.media_files(r,items)
  local files={}
  for _,item in ipairs(items)do
    local take=r.GetActiveTake(item)
    local source=take and r.GetMediaItemTake_Source(take)
    local _,guid=r.GetSetMediaItemInfo_String(item,'GUID','',false)
    local path
    -- Section/reverse sources can wrap the actual file.
    for _=1,16 do
      if not source then break end
      path=r.GetMediaSourceFileName(source,'')
      if type(path)=='string'and path~=''then break end
      source=r.GetMediaSourceParent and r.GetMediaSourceParent(source)
    end
    if type(path)~='string'or path==''then return nil end
    files[#files+1]={guid=guid,path=path}
  end
  table.sort(files,function(a,b)return a.guid<b.guid end)
  local paths={}
  for i,file in ipairs(files)do paths[i]=file.path end
  return #paths>0 and paths or nil
end
return M
