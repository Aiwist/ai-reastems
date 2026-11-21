param([Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string]$StateRoot,[ValidateSet('Run','Check')][string]$Mode='Run')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'native_process.ps1')
. (Join-Path $PSScriptRoot 'download_progress.ps1')
. (Join-Path $PSScriptRoot 'stems_updater.ps1')
$app=Split-Path -Parent $PSScriptRoot
$root=[IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
$work=[IO.Path]::GetFullPath($WorkDir).TrimEnd('\')
$id=[IO.Path]::GetFileName($work)
if($id -cnotmatch '^[a-fA-F0-9]{32}$' -or $work -ine (Join-Path $root ('stems_jobs\'+$id))){throw 'Invalid Ai ReaStems job path.'}
Assert-AitOrdinaryPath $work
$result=Join-Path $work 'result.json'
$ownerPath=Join-Path $work 'worker.json'
$env:AIT2_CANCEL=Join-Path $work 'cancel.request'
$env:AIT2_STATUS=Join-Path $work 'status.json'
$env:AIT2_JOB_ID=$id
$env:AIT2_JOB_DIR=$work
function Complete-AiReaStems($Value){
    $Value.job_id=$id
    Write-AitJson $result $Value
}
function Get-ModelEntry([string]$Model){
    $catalog=Read-AitJson (Join-Path $app 'models_catalog.json')
    if($Model -cnotin $catalog.order){throw 'Неизвестная модель Ai ReaStems.'}
    return $catalog.models.$Model
}
function Install-Model($Config,$Entry){
    $folder=[IO.Path]::GetFullPath([string]$Config.folder).TrimEnd('\')
    if($folder -eq [IO.Path]::GetPathRoot($folder).TrimEnd('\')){throw 'Выберите отдельную папку для моделей.'}
    Assert-AitOrdinaryPath $folder
    [void][IO.Directory]::CreateDirectory($folder)
    $target=Join-Path $folder $Entry.file
    $mutex=Lock-NativeModel $target
    try{
        $script:DrumSepRepairFiles=@{}
        $script:DrumSepRepairFiles[$target.ToLowerInvariant()]=$true
        $script:DrumSepDeadline=[datetime]::UtcNow.AddMinutes(30)
        $script:DrumSepDone=0L
        $script:DrumSepTotal=[long]$Entry.bytes
        Get-DrumSepFile $Entry $target 'SHA256' $Entry.label
        Complete-AiReaStems @{ok=$true;message=($Entry.label+' установлена и проверена.')}
    }finally{$mutex.ReleaseMutex();$mutex.Dispose()}
}
function Get-ExistingResult([string]$Id,$Entry){
    if($Id -cnotmatch '^[a-fA-F0-9]{32}$'){return}
    $folder=Join-Path $root ('stems_jobs\'+$Id+'\stems')
    Assert-AitOrdinaryPath $folder
    $manifest=Read-AitJson (Join-Path (Split-Path -Parent $folder) 'stems.json')
    if(-not $manifest -or $manifest.job_id -cne $Id){return}
    $files=@(foreach($stem in $Entry.stems){
        $file=Join-Path $folder ($stem+'.wav')
        Assert-AitOrdinaryPath $file
        $property=$manifest.sizes.PSObject.Properties[$stem]
        if(-not $property -or -not [IO.File]::Exists($file) -or $property.Value -ne (Get-Item -LiteralPath $file).Length){return}
        @{name=$stem;wav=$file}
    })
    return ,$files
}
function Invoke-Separation($Config,$Entry){
    if($Config.duration -le 0 -or $Config.duration -gt 1500 -or $Config.device -cnotin @('auto','cpu')){throw 'Неверные параметры фрагмента.'}
    $model=[IO.Path]::GetFullPath([string]$Config.weights)
    Assert-AitOrdinaryPath $model
    Write-AitEvent 'checking' 'Проверка модели и движка…'
    if(-not (Test-DrumSepFile $model $Entry)){throw 'Файл модели не прошёл проверку SHA-256. Установите модель повторно.'}
    $runtime=Get-ActiveStemsRuntime $app $root
    $input=Join-Path $work 'input.wav'
    Assert-AitOrdinaryPath $input
    $inputHash=(Get-FileHash -LiteralPath $input).Hash
    $key=$inputHash+'-'+$Entry.sha256+'-'+($runtime.identity -replace ':','-')+'-'+$Config.device
    $cache=Join-Path $root 'stems_cache'
    Assert-AitOrdinaryPath $cache
    [void][IO.Directory]::CreateDirectory($cache)
    $digest=[Security.Cryptography.SHA256]::Create()
    try{$keyHash=([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($key)))).Replace('-','')}finally{$digest.Dispose()}
    $index=Join-Path $cache ($keyHash+'.json')
    Assert-AitOrdinaryPath $index
    $files=$null
    try{
        $saved=Read-AitJson $index
        $files=Get-ExistingResult ([string]$saved.job_id) $Entry
    }catch{Assert-AitNotCancelled}
    $cached=$null -ne $files
    if(-not $cached){
        $separated=Join-Path $work 'stems'
        [void][IO.Directory]::CreateDirectory($separated)
        $engineArguments=@('--model',$model,'--input',$input,'--out',$separated,'--float32','--stems',($Entry.stems -join ','))
        if($Config.device -ceq 'cpu'){$engineArguments+=@('--device','cpu')}
        Write-AitEvent 'separating' ('Разделение через '+$Entry.label+'…')
        $log=Join-Path $work 'inference.log'
        $code=Invoke-AiLiveProcess (Join-Path $runtime.root 'stems-split.exe') $engineArguments $log -TimeoutSeconds 3600 -OwnProcess
        if($code -ne 0){throw ('stems.cpp завершился с кодом '+$code+'. '+(Read-AitLogTail $log))}
        $sizes=@{}
        foreach($stem in $Entry.stems){
            $file=Join-Path $separated ($stem+'.wav')
            Assert-AitOrdinaryPath $file
            if(-not [IO.File]::Exists($file) -or (Get-Item -LiteralPath $file).Length -le 44){throw ('Нет выходного файла '+$stem+'.wav.')}
            $sizes[$stem]=(Get-Item -LiteralPath $file).Length
        }
        Write-AitJson (Join-Path $work 'stems.json') @{job_id=$id;sizes=$sizes}
        Write-AitJson $index @{job_id=$id}
        $files=Get-ExistingResult $id $Entry
        if(-not $files){throw 'Движок не создал полный набор стемов.'}
    }
    Assert-AitNotCancelled
    Complete-AiReaStems @{ok=$true;stems=$files;cached=$cached}
}
$lock=$null
try{
    if([IO.File]::Exists($result)){return}
    if($Mode -eq 'Check'){
        $owner=Read-AitJson $ownerPath
        $process=if($owner){Get-Process -Id ([int]$owner.pid) -ErrorAction SilentlyContinue}
        if($process -and $process.StartTime.ToUniversalTime().ToString('o') -ceq $owner.started){return}
        if(-not $owner -and ((Get-Date)-(Get-Item -LiteralPath (Join-Path $work 'config.json')).CreationTime).TotalSeconds -lt 25){return}
        Complete-AiReaStems @{ok=$false;message='Фоновый процесс Ai ReaStems завершился без результата.'}
        return
    }
    try{$lock=[IO.File]::Open((Join-Path $work 'worker.lock'),'OpenOrCreate','ReadWrite','None')}
    catch [IO.IOException]{return}
    if([IO.File]::Exists($result)){return}
    if([IO.File]::Exists($ownerPath)){throw 'Этот запуск Ai ReaStems уже выполнялся.'}
    Write-AitJson $ownerPath @{pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')}
    $config=Read-AitJson (Join-Path $work 'config.json')
    if($config.schema -ne 1 -or $config.id -cne $id){throw 'Неверное задание Ai ReaStems.'}
    if($config.action -ceq 'engine'){
        Invoke-StemsUpdate $config $root $work $id
        return
    }
    Test-AitPayload $app
    $entry=Get-ModelEntry $config.model
    if($config.action -ceq 'install'){Install-Model $config $entry}
    elseif($config.action -ceq 'separate'){Invoke-Separation $config $entry}
    else{throw 'Неизвестное задание Ai ReaStems.'}
}catch{
    $problem=Protect-AitMessage $_.Exception.Message
    $cancelled=$problem -match 'AIT2-CANCELLED'
    Complete-AiReaStems @{ok=$false;cancelled=$cancelled;message=$(if($cancelled){'Операция отменена.'}else{$problem})}
}finally{if($lock){$lock.Dispose()}}
