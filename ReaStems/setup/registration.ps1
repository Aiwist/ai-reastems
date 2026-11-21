function Update-NativeRegistration([string]$State,$Paths,$Sources,$Roots) {
    $lock=$null;$deadline=[datetime]::UtcNow.AddSeconds(30)
    try {
        while(-not $lock){
            Assert-AitNotCancelled
            try{$lock=[IO.File]::Open((Join-Path $State 'native_setup.lock'),'OpenOrCreate','ReadWrite','None')}
            catch [IO.IOException]{
                if([datetime]::UtcNow -gt $deadline){throw 'AITN-235: Не удалось сохранить список моделей: другая установка ещё работает. Дождитесь её завершения и повторите установку.'}
                Start-Sleep -Milliseconds 100
            }
        }
        $path=Join-Path $State 'stems_active.json';$old=Read-AitJson $path
        $next=@{schema=1;weights=@{};sources=@{}}
        if($old){foreach($p in $old.PSObject.Properties){$next[$p.Name]=$p.Value}}
        $mergedWeights=@{};$mergedSources=@{}
        if($old.weights){foreach($p in $old.weights.PSObject.Properties){$mergedWeights[$p.Name]=$p.Value}}
        if($old.sources){foreach($p in $old.sources.PSObject.Properties){$mergedSources[$p.Name]=$p.Value}}
        foreach($name in $Paths.Keys){$mergedWeights[$name]=$Paths[$name]}
        foreach($name in $Sources.Keys){$mergedSources[$name]=$Sources[$name]}
        foreach($name in $Roots.Keys){$next[$name]=$Roots[$name]}
        $next.weights=$mergedWeights;$next.sources=$mergedSources
        $saved=$false
        while(-not $saved){
            Assert-AitNotCancelled
            try{Write-AitJson $path $next;$saved=$true}
            catch [IO.IOException]{
                $win32=$_.Exception.HResult -band 65535
                if($win32 -notin @(32,33) -or [datetime]::UtcNow -gt $deadline){throw}
                Start-Sleep -Milliseconds 100
            }
        }
        return $next
    } finally {if($lock){$lock.Dispose()}}
}
function Lock-NativeModel([string]$Path) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToLowerInvariant())))).Replace('-','')}
    finally{$sha.Dispose()}
    $mutex=[Threading.Mutex]::new($false,('Local\AiTranscriberGGUF_'+$key))
    try{
        $acquired=$false
        try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
        if(-not $acquired){throw 'AITN-234: Эта модель уже загружается в другом окне. Дождитесь завершения той загрузки.'}
        return $mutex
    }catch{$mutex.Dispose();throw}
}
