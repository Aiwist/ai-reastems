-- Support ZIP writer adapted from Ai Transcriber Plus (Apache-2.0).
-- Support ZIP writer and bounded, fixed-name diagnostic collector. Pure Lua:
-- no PowerShell, Python, downloads, recursive scans or credential-file access.
local M={}
local function replace(text,from,to)
  if type(from)~='string'or from==''or utf8.len(from)==nil then return text end
  return text:gsub(from:gsub('(%W)','%%%1'),function()return to end)
end
function M.redact(value,prefixes)
  local text=tostring(value or '')
  text=text:gsub('hf_[%w_]+','[TOKEN REDACTED]'):gsub('[Bb][Ee][Aa][Rr][Ee][Rr]%s+[^%s"<>]+','Bearer [REDACTED]')
  text=text:gsub('(["\']?)([%w_]+)%1(%s*[:=]%s*)(["\'])(.-)%4',function(keyquote,key,sep,quote,body)
    if key:lower():find('token',1,true)or key:lower():find('password',1,true)or key:lower():find('authorization',1,true)or key:lower():find('api_key',1,true)then body='[REDACTED]'end
    return keyquote..key..keyquote..sep..quote..body..quote
  end)
  text=text:gsub('([%w_]+)(%s*[:=]%s*)([^%s,;}]+)',function(key,sep,body)
    if key:lower():find('token',1,true)or key:lower():find('password',1,true)or key:lower():find('authorization',1,true)or key:lower():find('api_key',1,true)then body='[REDACTED]'end
    return key..sep..body
  end)
  text=text:gsub('(https?://[^%s?"<>]+)%?[^%s"<>]+','%1?[QUERY REDACTED]')
  for _,prefix in ipairs(prefixes or {})do
    text=replace(text,prefix.path,prefix.label)
    text=replace(text,prefix.path and prefix.path:gsub('\\','\\\\'),prefix.label)
  end
  -- Preserve valid Unicode. Render invalid bytes as ASCII diagnostics, rather
  -- than publishing a broken UTF-8 report or guessing the user's code page.
  if not utf8.len(text)then text=text:gsub('[\128-\255]',function(c)return string.format('\\x%02X',c:byte())end)end
  text=text:sub(1,131072)
  while not utf8.len(text)do text=text:sub(1,-2)end
  return text
end
local crc_table={}
for value=0,255 do
  local crc=value
  for _=1,8 do crc=(crc>>1)~((crc&1)==1 and 0xEDB88320 or 0)end
  crc_table[value]=crc
end
local function crc32(text)
  local crc=0xFFFFFFFF
  for i=1,#text do crc=(crc>>8)~crc_table[(crc~text:byte(i))&0xFF]end
  return (~crc)&0xFFFFFFFF
end
local function clean(value,prefixes,depth)
  if type(value)=='string'then return M.redact(value,prefixes)end
  if type(value)~='table'then return value end
  if depth>8 then return '[DETAIL OMITTED]'end
  local copy={}
  for key,item in pairs(value)do
    local name=tostring(key):lower()
    if name:find('token',1,true)or name:find('password',1,true)or name:find('authorization',1,true)or name:find('api_key',1,true)then copy[key]='[REDACTED]'
    else copy[key]=clean(item,prefixes,depth+1)end
  end
  return copy
end
local function utf16(text,big_endian)
  local out={};local index=1
  local function unit(at)
    local a,b=text:byte(at,at+1);if not b then return nil end
    return big_endian and a*256+b or a+b*256
  end
  while index<#text do
    local point=unit(index);index=index+2
    if point>=0xD800 and point<=0xDBFF then
      local low=unit(index)
      if low and low>=0xDC00 and low<=0xDFFF then point=0x10000+(point-0xD800)*1024+low-0xDC00;index=index+2
      else point=0xFFFD end
    elseif point>=0xDC00 and point<=0xDFFF then point=0xFFFD end
    out[#out+1]=utf8.char(point)
  end
  return table.concat(out)
end
local function tail(J,path,prefixes)
  local f=io.open(path,'rb');if not f then return nil,'unavailable'end
  local first=f:read(3)or'';local length=f:seek('end')
  if not length then f:close();return nil,'unreadable'end
  local start=math.max(0,length-131072);local is16=first:sub(1,2)=='\255\254'or first:sub(1,2)=='\254\255'
  if is16 then start=start-start%2 end
  f:seek('set',start);local text=f:read(math.min(131072,length-start))or'';f:close()
  if is16 then
    if start==0 then text=text:sub(3)end
    text=utf16(text,first:sub(1,2)=='\254\255')
  elseif start==0 and first=='\239\187\191'then text=text:sub(4)end
  if start>0 then text=text:match('\n(.*)')or''end
  if text:find('%z')then return nil,'not a text log'end
  -- Parse complete JSON before masking so secrets in escaped detail strings
  -- are cleaned before they are serialized again. Raw requests are never read.
  if path:sub(-5)=='.json'and start==0 then
    local ok,value=pcall(J.decode,text)
    if ok then return M.redact(J.encode(clean(value,prefixes,0)),prefixes)end
  end
  return M.redact(text,prefixes)
end
local function identifier(value)return type(value)=='string'and #value==32 and value:match('^%x+$')end
function M.pack(entries)
  local body,central,seen={},{},{};local offset,count,total=0,0,0
  for _,entry in ipairs(entries)do
    local name,data=entry.name,entry.text
    assert(name:match('^[a-zA-Z0-9_./-]+$')and name:sub(1,1)~='/'and not name:find('..',1,true)and #name<160 and #data<=131072 and not seen[name],'Invalid support ZIP entry')
    seen[name]=true;total=total+#data;assert(total<=4194304,'Support ZIP is too large')
    local crc=crc32(data);local size=#data
    local record=string.pack('<I4I2I2I2I2I2I4I4I4I2I2',0x04034B50,20,0x800,0,0,33,crc,size,size,#name,0)..name..data
    body[#body+1]=record
    central[#central+1]=string.pack('<I4I2I2I2I2I2I2I4I4I4I2I2I2I2I2I4I4',0x02014B50,20,20,0x800,0,0,33,crc,size,size,#name,0,0,0,0,0,offset)..name
    offset=offset+#record;count=count+1
  end
  assert(count>0 and count<=64,'Invalid support ZIP inventory')
  local directory=table.concat(central)
  return table.concat(body)..directory..string.pack('<I4I2I2I2I2I4I4I2',0x06054B50,0,0,count,count,#directory,offset,0)
end

function M.prefixes(r, storage)
  local prefixes = {}
  local function add(path, label)
    if not path or path == '' then return end
    prefixes[#prefixes + 1] = {path = path:gsub('\\', '/'), label = label}
    prefixes[#prefixes + 1] = {path = path:gsub('/', '\\'), label = label}
  end
  if storage then
    add(storage.model_folder, '<models>')
    add(storage.root, '<data>')
  end
  add(r.GetResourcePath(), '<REAPER>')
  add(os.getenv('USERPROFILE'), '<profile>')
  return prefixes
end

function M.record(r, J, root, summary, prefixes)
  local folder = root .. '/logs'
  r.RecursiveCreateDirectory(folder, 0)
  local file = folder .. '/errors.log'
  local previous = tail(J, file, prefixes) or ''
  if #previous > 98000 then previous = previous:sub(-98000):match('\n(.*)') or '' end
  local line = M.redact(J.encode(clean(summary, prefixes, 0)), prefixes)
  local text = previous .. os.date('!%Y-%m-%dT%H:%M:%SZ') .. ' ' .. line .. '\n'
  return J.write(file, text)
end

function M.create(r, J, root, summary, prefixes, job)
  local folder = root .. '/reports'
  r.RecursiveCreateDirectory(folder, 0)
  local name = 'Ai_ReaStems_Support_' .. os.date('%Y-%m-%d_%H-%M-%S') .. '_' .. r.genGuid():gsub('[^%x]', '') .. '.zip'
  local destination = folder .. '/' .. name
  local temporary = destination .. '.part'
  assert(not r.file_exists(destination) and not r.file_exists(temporary), 'Файл отчёта уже существует.')
  local entries = {
    {name = 'README.txt', text = 'Локальный отчёт Ai ReaStems. Включает выбранные сведения об ошибке и текстовые журналы. Аудио, GGUF и исходные конфигурации заданий не включаются.'},
    {name = 'diagnostics.json', text = M.redact(J.encode(clean(summary, prefixes, 0)), prefixes)},
  }
  local function add(name, source)
    local text = tail(J, source, prefixes)
    if text and text ~= '' then entries[#entries + 1] = {name = name, text = text} end
  end
  add('errors.log', root .. '/logs/errors.log')
  if identifier(job) then
    local work = root .. '/stems_jobs/' .. job .. '/'
    for _, file in ipairs({'status.json', 'launch_error.log', 'inference.log', 'drumsep_download.log'}) do
      add('job/' .. file, work .. file)
    end
  end
  local written, problem = J.write(temporary, M.pack(entries))
  if not written then os.remove(temporary) end
  assert(written, 'Не удалось записать ZIP-отчёт: ' .. tostring(problem))
  local committed, move_error = os.rename(temporary, destination)
  if not committed then os.remove(temporary) end
  assert(committed, 'Не удалось завершить ZIP-отчёт: ' .. tostring(move_error))
  return destination
end

return M
