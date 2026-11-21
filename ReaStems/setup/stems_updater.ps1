. (Join-Path $PSScriptRoot 'drumsep_setup.ps1')
. (Join-Path $PSScriptRoot 'stems_runtime.ps1')
. (Join-Path $PSScriptRoot 'registration.ps1')

function Get-StemsReleases([string]$Tag='') {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $base='https://api.github.com/repos/betweentwomidnights/stems.cpp/releases'
    $url=if($Tag){$base+'/tags/'+$Tag}else{$base+'?per_page=30'}
    $headers=@{'User-Agent'='Ai-Stems';Accept='application/vnd.github+json'}
    foreach($release in (Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30)){$release}
}
function Convert-StemsRelease($Release) {
    if($Release.draft -or $Release.prerelease -or $Release.tag_name -cnotmatch '^v\d{1,9}\.\d{1,9}\.\d{1,9}$'){return}
    $tag=[string]$Release.tag_name
    $assets=@(foreach($kind in @('core','vulkan')){
        $name='stems-'+$tag+'-windows-x64-'+$kind+'.zip'
        $matchingAssets=@($Release.assets|Where-Object {$_.name -ceq $name})
        if($matchingAssets.Count -ne 1){return}
        $asset=$matchingAssets[0]
        $url='https://github.com/betweentwomidnights/stems.cpp/releases/download/'+$tag+'/'+$name
        if($asset.browser_download_url -cne $url -or $asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$' -or
            [long]$asset.size -le 0 -or [long]$asset.size -gt 128MB){return}
        @{file=$name;url=$url;bytes=[long]$asset.size;sha256=([string]$asset.digest).Substring(7).ToLowerInvariant()}
    })
    return @{version=$tag.Substring(1);assets=$assets}
}
function Get-LatestStemsRelease($Releases) {
    $candidates=@(foreach($release in $Releases){$item=Convert-StemsRelease $release;if($item){$item}})
    return $candidates|Sort-Object {[version]$_.version} -Descending|Select-Object -First 1
}

function Expand-StemsArchives($Archives,[string]$Stage) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $total=0L;$count=0
    foreach($archive in $Archives){
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try{foreach($entry in $zip.Entries){
            Assert-AitNotCancelled;$count++;$total+=$entry.Length;$name=[string]$entry.FullName
            $unixType=($entry.ExternalAttributes -shr 16) -band 0xF000
            if($count -gt 256 -or $total -gt 2GB -or $entry.Length -le 0 -or $entry.Length -gt 1GB -or
                $name -notmatch '^[A-Za-z0-9_.-]+$' -or $name -in @('.','..') -or $unixType -eq 0xA000){throw 'AITN-743: Неподдерживаемое содержимое архива stems.cpp.'}
            $path=Join-Path $Stage $name;$incoming=$path+'.incoming';Assert-AitOrdinaryPath $incoming
            $input=$null;$output=$null
            try{
                $input=$entry.Open();$output=[IO.File]::Open($incoming,'CreateNew','Write','None')
                $buffer=New-Object byte[] 262144;$written=0L
                while(($n=$input.Read($buffer,0,$buffer.Length)) -gt 0){Assert-AitNotCancelled;$written+=$n;if($written -gt $entry.Length){throw 'AITN-743: Неверный размер файла в архиве.'};$output.Write($buffer,0,$n)}
                if($written -ne $entry.Length){throw 'AITN-743: Файл архива обрезан.'}
            }finally{if($output){$output.Dispose()};if($input){$input.Dispose()}}
            if([IO.File]::Exists($path)){
                if((Get-FileHash -LiteralPath $path).Hash -cne (Get-FileHash -LiteralPath $incoming).Hash){throw 'AITN-743: Архивы содержат разные файлы с одинаковым именем.'}
                [IO.File]::Delete($incoming)
            }else{[IO.File]::Move($incoming,$path)}
        }}finally{$zip.Dispose()}
    }
}
function Remove-StemsStage([string]$Stage,[string]$Stages) {
    # This is only our unpublished, GUID-named staging directory. Never remove a
    # published version, the active runtime, or an arbitrary computed path.
    $full=[IO.Path]::GetFullPath($Stage).TrimEnd('\');$parent=[IO.Path]::GetFullPath($Stages).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($full) -ine $parent -or [IO.Path]::GetFileName($full) -notmatch '^[a-fA-F0-9]{32}$'){throw 'AITN-743: Недопустимая временная папка.'}
    if(Test-Path -LiteralPath $full){Assert-AitOrdinaryPath $full;Remove-Item -LiteralPath $full -Recurse -Force}
}
function Receive-StemsArchives($Assets,[string]$Store) {
    $downloads=Join-Path $Store 'downloads';Assert-AitOrdinaryPath $downloads
    [void][IO.Directory]::CreateDirectory($downloads)
    $script:DrumSepRepairFiles=@{};$script:DrumSepDeadline=[datetime]::UtcNow.AddMinutes(30)
    $script:DrumSepDone=0L;$script:DrumSepTotal=0L
    foreach($asset in $Assets){$script:DrumSepTotal+=[long]$asset.bytes}
    foreach($asset in $Assets){
        $path=Join-Path $downloads $asset.file
        Get-DrumSepFile $asset $path 'SHA256' 'stems.cpp'
        $script:DrumSepDone+=[long]$asset.bytes
        $path
    }
}
function Get-StemsDevices([string]$Root,[string]$Work) {
    $log=Join-Path $Work ('stems_devices_'+[guid]::NewGuid().ToString('N')+'.log')
    $code=Invoke-AiLiveProcess (Join-Path $Root 'stems-server.exe') @('--props') $log -TimeoutSeconds 30 -OwnProcess
    if($code -ne 0){throw 'AITN-745: stems.cpp не смогла определить устройства в этой сборке.'}
    foreach($line in [IO.File]::ReadLines($log)){
        if($line.StartsWith('{')){try{return ($line|ConvertFrom-Json)}catch{}}
    }
    throw 'AITN-745: stems.cpp не вернула список устройств.'
}
function Test-StemsCompatibility([string]$Root,[string]$Version,[string]$Work,[switch]$RequireVulkan) {
    $build=Read-AitJson (Join-Path $Root 'BUILD-INFO.json')
    if($build.service -cne 'stems' -or ([string]$build.version).TrimStart('v') -cne $Version -or $build.platform -cne 'windows-x64'){throw 'AITN-741: Неподходящая сборка stems.cpp.'}
    $header=[IO.File]::ReadAllText((Join-Path $Root 'libstems_v1.h'))
    if($header -notmatch '#define\s+STEMS_ABI_VERSION_1\s+1u'){throw 'AITN-741: Несовместимый интерфейс stems.cpp.'}
    foreach($operation in @('version','help')){
        Assert-AitNotCancelled
        $exe=Join-Path $Root 'stems-split.exe'
        $log=Join-Path $Work ('stems_'+$operation+'_'+[guid]::NewGuid().ToString('N')+'.log')
        $code=Invoke-AiLiveProcess $exe @('--'+$operation) $log -TimeoutSeconds 30 -OwnProcess
        if($code -ne 0){throw ('AITN-741: Проверка stems.cpp --'+$operation+' завершилась с ошибкой.')}
        $text=[IO.File]::ReadAllText($log)
        if($operation -eq 'version' -and $text -notmatch ('(?m)^'+[regex]::Escape($Version)+'\s*$')){throw 'AITN-741: Версия движка не совпала.'}
        if($operation -eq 'help'){foreach($token in @('--model','--input','--out','--float32','--device','--stems')){if($text -notmatch [regex]::Escape($token)){throw ('AITN-741: Нет команды '+$token)}}}
    }
    $props=Get-StemsDevices $Root $Work
    if(-not $props.success -or $props.service -cne 'stems' -or $props.version -cne $Version -or -not @($props.devices|Where-Object {$_.backend -eq 'CPU'}).Count){throw 'AITN-741: Движок не подтвердил работоспособность CPU.'}
    foreach($name in (Read-AitJson (Join-Path (Split-Path -Parent $PSScriptRoot) 'models_catalog.json')).order){if($name -notin $props.models.resolved.PSObject.Properties.Name){throw ('AITN-741: Движок не поддерживает '+$name)}}
    if($RequireVulkan -and -not @($props.devices|Where-Object {$_.backend -eq 'Vulkan'}).Count){
        throw 'AITN-741: Обновление не обнаружило доступное устройство Vulkan.'
    }
}

function Install-StemsCandidate([string]$App,[string]$State,[string]$Store,[string]$Work,[string]$Id,$Release,[switch]$RequireVulkan) {
    $assets=$Release.assets
    $identity=[string]::Join(':',@($assets|ForEach-Object {$_.sha256}))
    $versions=Join-Path $Store 'versions';Assert-AitOrdinaryPath $versions
    [void][IO.Directory]::CreateDirectory($versions)
    $name='v'+$Release.version+'-vulkan'
    $destination=Join-Path $versions $name
    if(Test-Path -LiteralPath $destination){
        # A validated directory may exist from a previous interrupted activation.
        Assert-AitOrdinaryPath $destination
        $saved=Read-AitJson (Join-Path $destination 'runtime.json')
        if((Test-ManagedStemsRuntime $saved) -and $saved.version -ceq $Release.version -and $saved.identity -ceq $identity){
            $saved.root=$destination
            try {
                $null=Assert-StemsRuntime $App $State $saved
                Test-StemsCompatibility $destination $Release.version $Work -RequireVulkan:$RequireVulkan
                return $saved
            } catch {Assert-AitNotCancelled}
        }
        $destination=Join-Path $versions ($name+'-'+$Id)
    }

    $archives=@(Receive-StemsArchives $assets $Store)
    $stages=Join-Path $Store 'staging';Assert-AitOrdinaryPath $stages
    [void][IO.Directory]::CreateDirectory($stages)
    $stage=Join-Path $stages $Id
    Assert-AitOrdinaryPath $stage
    if(Test-Path -LiteralPath $stage){throw 'AITN-743: Временная папка обновления уже занята.'}
    [void][IO.Directory]::CreateDirectory($stage)
    try {
        Write-AitEvent 'unpacking' 'Распаковка stems.cpp Vulkan/CPU…'
        Expand-StemsArchives $archives $stage
        if(-not [IO.File]::Exists((Join-Path $stage 'stems-ggml-vulkan.dll'))){
            throw 'AITN-741: В выпуске отсутствует библиотека Vulkan.'
        }
        Write-AitEvent 'checking' 'Проверка движка и моделей разделения…'
        Test-StemsCompatibility $stage $Release.version $Work -RequireVulkan:$RequireVulkan
        $files=@(Get-ChildItem -LiteralPath $stage -File|Sort-Object Name|ForEach-Object {
            @{file=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
        })
        $runtime=@{schema=2;bundled=$false;version=$Release.version;backend='vulkan';identity=$identity;root=$destination;file='stems-split.exe';files=$files}
        Write-AitJson (Join-Path $stage 'runtime.json') $runtime
        Assert-AitNotCancelled
        $source=[IO.Path]::GetFullPath($stage);$target=[IO.Path]::GetFullPath($destination)
        if([IO.Path]::GetDirectoryName($source) -ine [IO.Path]::GetFullPath($stages) -or
            [IO.Path]::GetDirectoryName($target) -ine [IO.Path]::GetFullPath($versions)){
            throw 'AITN-743: Недопустимая папка обновления.'
        }
        Assert-AitOrdinaryPath $target
        [IO.Directory]::Move($source,$target)
        $stage=$null
        $null=Assert-StemsRuntime $App $State $runtime
        foreach($archive in $archives){try{[IO.File]::Delete($archive)}catch [IO.IOException]{}catch [UnauthorizedAccessException]{}}
        return $runtime
    } finally {
        if($stage){Remove-StemsStage $stage $stages}
    }
}

function Invoke-StemsUpdate($Job,[string]$State,[string]$Directory,[string]$Id) {
    $app=Split-Path -Parent $PSScriptRoot
    $store=Get-StemsUpdateRoot $app
    $lock=$null
    try {
        if($Id -notmatch '^[A-Fa-f0-9]{32}$' -or $Job.schema -ne 1 -or $Job.id -cne $Id -or
            $Job.operation -cnotin @('check','install') -or $Job.runtime_backend){
            throw 'AITN-740: Неверная команда обновления stems.cpp.'
        }
        Test-AitPayload $app
        Assert-AitNotCancelled
        Write-AitJson (Join-Path $Directory 'worker.json') @{pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');job_id=$Id}
        if($Job.operation -ceq 'install'){
            Assert-AitOrdinaryPath $store
            [void][IO.Directory]::CreateDirectory($store)
            $lockPath=Join-Path $store 'update.lock';Assert-AitOrdinaryPath $lockPath
            try{$lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')}
            catch [IO.IOException]{throw 'AITN-744: stems.cpp уже обновляется в другом окне.'}
        }
        $native=Read-AitJson (Join-Path $State 'stems_active.json')
        $current=Get-ActiveStemsRuntime $app $State
        $updates=@{}
        if($Job.operation -ceq 'check'){
            Write-AitEvent 'checking' 'Проверка выпусков stems.cpp …'
            $latest=Get-LatestStemsRelease @(Get-StemsReleases)
            if(-not $latest){throw 'AITN-740: Для Windows x64 нет стабильного выпуска Vulkan/CPU с подтверждёнными контрольными суммами.'}
            $updates.stems_update=@{schema=3;latest=@{version=$latest.version};installed_version=$current.version}
            $message=if([version]$latest.version -gt [version]$current.version){
                'Доступна stems.cpp '+$latest.version+' · Vulkan/CPU.'
            }else{'Установлена актуальная сборка stems.cpp '+$current.version+'.'}
        }else{
            $version=[string]$Job.runtime_version
            if($version -notmatch '^\d{1,9}\.\d{1,9}\.\d{1,9}$' -or $native.stems_update.schema -ne 3 -or
                $native.stems_update.latest.version -cne $version){
                throw 'AITN-740: Сначала вручную проверьте обновления stems.cpp.'
            }
            if([version]$version -le [version]$current.version){
                $message='Установлена актуальная сборка stems.cpp '+$current.version+'.'
            }else{
                Write-AitEvent 'checking' ('Проверка файлов выпуска stems.cpp '+$version+'…')
                $release=Get-LatestStemsRelease @(Get-StemsReleases ('v'+$version))
                if(-not $release -or $release.version -cne $version){
                    throw 'AITN-740: Выбранный выпуск Vulkan/CPU недоступен. Повторите проверку обновлений.'
                }
                $requireVulkan=$false
                try {
                    $devices=(Get-StemsDevices $current.root $Directory).devices
                    $requireVulkan=@($devices|Where-Object {$_.backend -eq 'Vulkan'}).Count -gt 0
                } catch {Assert-AitNotCancelled}
                $updates.stems_runtime=Install-StemsCandidate $app $State $store $Directory $Id $release -RequireVulkan:$requireVulkan
                $updates.stems_update=@{schema=3;latest=@{version=$version};installed_version=$version}
                $message='Подключена stems.cpp '+$release.version+' · Vulkan/CPU.'
            }
        }
        Assert-AitNotCancelled
        $next=Update-NativeRegistration $State @{} @{} $updates
        Write-AitJson (Join-Path $Directory 'result.json') @{schema=1;job_id=$Id;action=$Job.action;ok=$true;native_active=$next;message=$message}
    } catch {
        $detail=Protect-AitMessage $_.Exception.Message
        $cancelled=$detail -match 'AIT2-CANCELLED'
        $code=if($detail -match '(AITN-(74[01345])|AIT2-\d{3}|AIT2-CANCELLED)'){$matches[1]}else{'AITN-740'}
        $issue=Get-AitDiagnostic -Text $detail -Code $code -Stage 'stems_update' -Exception $_.Exception
        Write-AitJson (Join-Path $Directory 'result.json') @{schema=1;job_id=$Id;action=$Job.action;ok=$false;cancelled=$cancelled;message=($code+': '+$issue.title);error=$issue}
    } finally {
        if($lock){$lock.Dispose()}
    }
}
