function Test-DrumSepFile([string]$Path,$Entry,[string]$Algorithm='SHA256') {
    return [IO.File]::Exists($Path) -and (Get-Item -LiteralPath $Path).Length -eq [long]$Entry.bytes -and
        (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash -ieq [string]$Entry.($Algorithm.ToLowerInvariant())
}
function Invoke-DrumSepManagedDownload($Entry,[string]$Partial,[string]$Component='DrumSep') {
    $response=$null;$stream=$null;$file=$null
    try {
        $offset=if([IO.File]::Exists($Partial)){[long](Get-Item -LiteralPath $Partial).Length}else{0L}
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $request=[Net.HttpWebRequest]::Create([string]$Entry.url);$request.UserAgent='Ai-Transcriber';$request.Timeout=30000;$request.ReadWriteTimeout=30000
        $request.KeepAlive=$false
        if($offset){$request.AddRange($offset)}
        $response=$request.GetResponse();$stream=$response.GetResponseStream()
        if($offset -and [int]$response.StatusCode -ne 206){$offset=0L}
        if([int]$response.StatusCode -eq 206 -and [string]$response.Headers['Content-Range'] -cne ('bytes '+$offset+'-'+([long]$Entry.bytes-1)+'/'+[long]$Entry.bytes)){throw 'AITN-722: Сервер вернул неверный диапазон файла.'}
        $file=[IO.File]::Open($Partial,$(if($offset){'Append'}else{'Create'}),'Write','None')
        $buffer=New-Object byte[] 262144;$received=$offset;$last=[datetime]::MinValue
        while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            Assert-AitNotCancelled
            if([datetime]::UtcNow -gt $script:DrumSepDeadline){throw ('AIT2-211: Превышено время загрузки '+$Component+'.')}
            $received+=$count;if($received -gt [long]$Entry.bytes){throw 'AITN-722: Сервер вернул лишние данные.'}
            $file.Write($buffer,0,$count)
            if([datetime]::UtcNow -gt $last.AddMilliseconds(500)){
                $last=[datetime]::UtcNow
                Write-AitEvent 'downloading' ($Component+': '+[IO.Path]::GetFileName($Partial).Replace('.part','')) ($script:DrumSepDone+$received) $script:DrumSepTotal
            }
        }
        if($received -ne [long]$Entry.bytes){throw 'AIT2-213: Загрузка файла оборвалась до завершения.'}
    } finally {if($file){$file.Dispose()};if($stream){$stream.Dispose()};if($response){$response.Dispose()}}
}
function Invoke-DrumSepCurlDownload($Entry,[string]$Partial,[string]$Label,[string]$Log) {
    $curl=Join-Path $env:SystemRoot 'System32\curl.exe'
    if(-not [IO.File]::Exists($curl)){throw 'AITN-721: Системный curl.exe недоступен.'}
    $remaining=[int][math]::Max(1,[math]::Floor(($script:DrumSepDeadline-[datetime]::UtcNow).TotalSeconds))
    $arguments=@('--disable','--location','--fail','--silent','--show-error','--connect-timeout','30','--max-time',[string]$remaining,
        '--speed-limit','1','--speed-time','30','--max-filesize',[string]$Entry.bytes,'--proto','=https','--proto-redir','=https',
        '--continue-at','-','--output',$Partial,'--write-out','AIT_HTTP:%{http_code}',[string]$Entry.url)
    $code=Invoke-AiLiveProcess $curl $arguments $Log -Label $Label -MonitorFile $Partial -TimeoutSeconds ($remaining+2) `
        -ProgressBaseBytes $script:DrumSepDone -ProgressTotalBytes $script:DrumSepTotal -SizeLimitBytes ([long]$Entry.bytes) -OwnProcess
    if($code -ne 0){
        $kind=switch($code){5{'AIT2-212'}6{'AIT2-212'}7{'AIT2-213'}18{'AIT2-213'}28{'AIT2-211'}35{'AIT2-222'}52{'AIT2-213'}55{'AIT2-213'}56{'AIT2-213'}60{'AIT2-210'}63{'AITN-722'}default{'AITN-721'}}
        throw ($kind+': Резервная загрузка завершилась с кодом '+$code+'. '+(Read-AitLogTail $Log))
    }
}
function Get-DrumSepFile($Entry,[string]$Path,[string]$Algorithm='SHA256',[string]$Component='DrumSep') {
    Assert-AitOrdinaryPath $Path
    if(Test-DrumSepFile $Path $Entry $Algorithm){return}
    $replace=[IO.File]::Exists($Path)
    if($replace -and -not $script:DrumSepRepairFiles.ContainsKey($Path.ToLowerInvariant())){throw ('AITN-722: Файл '+[IO.Path]::GetFileName($Path)+' не совпадает с моделью '+$Component+'. Выберите другую папку компонентов; существующий файл сохранён.')}
    $partial=$Path+'.part';Assert-AitOrdinaryPath $partial
    if([IO.File]::Exists($partial) -and (Get-Item -LiteralPath $partial).Length -eq [long]$Entry.bytes){
        if(Test-DrumSepFile $partial $Entry $Algorithm){
            if($replace){[IO.File]::Replace($partial,$Path,$Path+'.corrupt-'+$env:AIT2_JOB_ID)}else{[IO.File]::Move($partial,$Path)};return
        }
        [IO.File]::Move($partial,$partial+'.corrupt-'+$env:AIT2_JOB_ID)
    }
    $log=if($env:AIT2_JOB_DIR){Join-Path $env:AIT2_JOB_DIR 'drumsep_download.log'}else{$Path+'.download.log'}
    $curl=Join-Path $env:SystemRoot 'System32\curl.exe'
    for($attempt=1;$attempt -le 3;$attempt++) {
        $transport=if($attempt -eq 2 -and [IO.File]::Exists($curl)){'curl'}else{'managed'}
        try {
            Assert-AitNotCancelled
            if([datetime]::UtcNow -gt $script:DrumSepDeadline){throw ('AIT2-211: Превышено время установки '+$Component+'.')}
            $offset=if([IO.File]::Exists($partial)){[long](Get-Item -LiteralPath $partial).Length}else{0L}
            if($offset -gt [long]$Entry.bytes){throw 'AITN-722: Размер незавершённой загрузки больше ожидаемого.'}
            if($offset -eq [long]$Entry.bytes){break}
            $label=$Component+': '+[IO.Path]::GetFileName($Path)+' · попытка '+$attempt+' из 3'
            Write-AitEvent 'downloading' $label ($script:DrumSepDone+$offset) $script:DrumSepTotal
            [IO.File]::AppendAllText($log,('attempt='+$attempt+' transport='+$transport+' file='+[IO.Path]::GetFileName($Path)+"`n"),[Text.UTF8Encoding]::new($false))
            if($transport -eq 'curl'){Invoke-DrumSepCurlDownload $Entry $partial $label $log}
            else{Invoke-DrumSepManagedDownload $Entry $partial $Component}
            break
        } catch {
            Assert-AitNotCancelled
            $detail=Protect-AitMessage $_.Exception.ToString()
            [IO.File]::AppendAllText($log,($detail.Substring(0,[math]::Min(8192,$detail.Length))+"`n"),[Text.UTF8Encoding]::new($false))
            if($detail -match 'AITN-722'){throw}
            if($attempt -eq 3 -or [datetime]::UtcNow -gt $script:DrumSepDeadline){
                $issue=Get-AitDiagnostic -Text $detail -Code 'AIT2-200' -Stage 'downloading' -Exception $_.Exception
                $known=[regex]::Match($detail,'\bAIT2-(?:210|211|212|213|214|215|216|222)\b').Value
                $code=if($known){$known}elseif($issue.code -match '^AIT2-(?:210|211|212|213|214|215|216|222)$'){$issue.code}else{'AITN-721'}
                throw ($code+': Не удалось скачать '+[IO.Path]::GetFileName($Path)+' после 3 попыток. Загруженная часть сохранена. '+$issue.title+'. '+$_.Exception.Message)
            }
            Start-Sleep -Milliseconds 750
        }
    }
    Write-AitEvent 'checking' ($Component+': проверка '+[IO.Path]::GetFileName($Path))
    if(-not (Test-DrumSepFile $partial $Entry $Algorithm)){throw 'AITN-722: Контрольная сумма не совпала. Повторите установку; повреждённый файл не подключён.'}
    if($replace){[IO.File]::Replace($partial,$Path,$Path+'.corrupt-'+$env:AIT2_JOB_ID)}else{[IO.File]::Move($partial,$Path)}
}
