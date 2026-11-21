-- REAPER's async ExecProcess path can create a visible console before
-- PowerShell handles -WindowStyle. Wait only for a short hidden launcher;
-- the supervised runner stays detached for the duration of transcription.
local M={}
local function quote(value)
  assert(type(value)=='string'and value~=''and not value:find('[%z\r\n"]'),'Некорректный путь запуска помощника.')
  return '"'..value:gsub('(\\+)$','%1%1')..'"'
end
local function launch(r,directory,arguments)
  local ps=(os.getenv('SystemRoot')or'C:\\Windows')..'\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
  local cmd=quote(ps)..' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File '..
    quote(directory..'\\setup\\launch.ps1')..arguments
  -- This is not the neural process timeout. The launcher only starts the real
  -- runner with CreateNoWindow, acknowledges creation and exits immediately.
  local response=r.ExecProcess(cmd,5000)
  local code=type(response)=='string'and tonumber(response:match('^(%-?%d+)'))or type(response)=='number'and response
  assert(code==0,'Не удалось подтвердить фоновый запуск помощника. Проверьте журнал задания и разрешения Windows PowerShell. '..tostring(response or'Нет ответа.'):sub(1,1200))
  return response
end
function M.launch(r,directory,root,work,mode)
  assert(mode=='Run'or mode=='Check','Неизвестный режим помощника.')
  return launch(r,directory,' -WorkDir '..quote(work)..' -StateRoot '..quote(root)..' -Mode '..mode)
end
function M.identity(reply,id)
  local job,pid,started
  if type(reply)=='string'then job,pid,started=reply:match('AIT2LAUNCH:(%x+):(%d+):(%d+)')end
  if job==id and started and started~='0'then return {pid=pid,started=started}end
end
function M.probe(r,directory,runner)
  assert(runner.pid:match('^%d+$')and runner.started:match('^%d+$'),'Некорректный идентификатор помощника.')
  return launch(r,directory,' -RunnerPid '..runner.pid..' -RunnerStarted '..runner.started)
end
return M
