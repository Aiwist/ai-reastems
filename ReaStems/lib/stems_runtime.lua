-- The same Vulkan/CPU runtime is used for every separation model.
local M={}
local function sized(path,bytes)
  local f=io.open(path,'rb');if not f then return false end;local n=f:seek('end');f:close();return n==bytes
end
local function bundled_runtime(owner)
  local catalog=owner.drumsep_catalog or owner.json.load_json(owner.dir..'/engine_catalog.json',{})
  owner.drumsep_catalog=catalog
  local runtime=catalog.runtime or{}
  return {schema=1,bundled=true,backend='vulkan',version=runtime.version,identity=runtime.commit,root=owner.dir..'/'..(runtime.root or''),file=runtime.file,files=runtime.files}
end
local function newer(candidate, current)
  if type(candidate)~='string' or type(current)~='string' then return false end
  local a,b,c=candidate:match('^(%d+)%.(%d+)%.(%d+)$')
  local x,y,z=current:match('^(%d+)%.(%d+)%.(%d+)$')
  if not a or not x then return false end
  local proposed,installed={tonumber(a),tonumber(b),tonumber(c)},{tonumber(x),tonumber(y),tonumber(z)}
  for i=1,3 do
    if proposed[i]~=installed[i] then return proposed[i]>installed[i] end
  end
  return false
end
local function managed(owner, spec, bundled)
  if type(spec)~='table' or spec.schema~=2 or spec.bundled or spec.backend~='vulkan'
    or type(spec.identity)~='string' or #spec.identity~=129 or not spec.identity:match('^%x+:%x+$')
    or type(spec.root)~='string' or not newer(spec.version,bundled.version) then return false end
  local path=spec.root:gsub('\\','/'):gsub('/+$',''):lower()
  local name=path:match('/([^/]+)$')
  local prefix='v'..spec.version..'-vulkan'
  if not name then return false end
  local suffix=name:sub(#prefix+1)
  local valid_name=name==prefix or name:sub(1,#prefix)==prefix and #suffix==33 and suffix:match('^%-%x+$')
  local parent=owner.dir:gsub('\\','/'):gsub('/+$',''):lower()..'/runtime/stems-updates/versions/'
  return valid_name and path==parent..name and owner.r.file_exists(spec.root..'/runtime.json')
end
local function ready(spec)
  if type(spec.version)~='string' or not spec.version:match('^%d+%.%d+%.%d+$')
    or spec.file~='stems-split.exe' or type(spec.files)~='table' or #spec.files<8 or #spec.files>256 then return false end
  for _,entry in ipairs(spec.files) do
    if type(entry)~='table' or type(entry.file)~='string' or not entry.file:match('^[%w_.-]+$')
      or entry.file=='.' or entry.file=='..' or type(entry.sha256)~='string' or #entry.sha256~=64
      or not entry.sha256:match('^%x+$') or not sized(spec.root..'/'..entry.file,entry.bytes) then return false end
  end
  return true
end
function M.get(owner,force)
  local saved=owner.native.stems_runtime
  local now=owner.r.time_precise()
  local cached=owner.stems_runtime_health
  if not force and cached and cached.saved==saved and now-cached.at<2 then return cached.spec,cached.ready end
  local spec=bundled_runtime(owner)
  local available
  if managed(owner,saved,spec) and ready(saved) then
    spec=saved;available=true
  else
    available=ready(spec)
  end
  owner.stems_runtime_health={saved=saved,at=now,spec=spec,ready=available}
  return spec,available
end
M.newer = newer
return M
