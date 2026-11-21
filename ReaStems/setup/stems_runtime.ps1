# Managed updates and the bundled engine both use the same Vulkan/CPU layout.
function Get-BundledStemsRuntime([string]$App) {
    $catalog=Read-AitJson (Join-Path $App 'engine_catalog.json')
    $runtime=$catalog.runtime
    $root=if($runtime.root){Join-Path $App $runtime.root}else{''}
    return @{schema=1;bundled=$true;backend='vulkan';version=$runtime.version;identity=$runtime.commit;root=$root;file=$runtime.file;files=$runtime.files}
}
function Test-ManagedStemsRuntime($Runtime) {
    return ($Runtime.schema -eq 2 -and -not $Runtime.bundled -and $Runtime.backend -ceq 'vulkan' -and
        $Runtime.version -match '^\d{1,9}\.\d{1,9}\.\d{1,9}$' -and $Runtime.identity -match '^[0-9a-f]{64}:[0-9a-f]{64}$')
}
function Get-StemsUpdateRoot([string]$App) {
    return Join-Path $App 'runtime\stems-updates'
}
function Assert-StemsRuntime([string]$App,[string]$State='',$Runtime=$null) {
    if(-not (Test-ManagedStemsRuntime $Runtime)){$Runtime=Get-BundledStemsRuntime $App}
    if($Runtime.version -notmatch '^\d{1,9}\.\d{1,9}\.\d{1,9}$' -or -not $Runtime.root){
        throw 'AITN-741: Неверный каталог stems.cpp.'
    }
    $root=[IO.Path]::GetFullPath([string]$Runtime.root).TrimEnd('\')
    $inventory=$Runtime
    if($Runtime.bundled){
        $parent=[IO.Path]::GetFullPath((Join-Path $App 'runtime')).TrimEnd('\')+'\'
        if(-not $root.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){throw 'AITN-741: Недопустимая папка встроенного stems.cpp.'}
    }else{
        $parent=[IO.Path]::GetFullPath((Join-Path (Get-StemsUpdateRoot $App) 'versions')).TrimEnd('\')
        $prefix=[regex]::Escape('v'+$Runtime.version+'-vulkan')
        if([IO.Path]::GetDirectoryName($root) -ine $parent -or [IO.Path]::GetFileName($root) -cnotmatch ('^'+$prefix+'(?:-[a-fA-F0-9]{32})?$')){
            throw 'AITN-741: Недопустимая папка обновления stems.cpp.'
        }
        $record=Join-Path $root 'runtime.json'
        Assert-AitOrdinaryPath $record
        $inventory=Read-AitJson $record
        if(-not (Test-ManagedStemsRuntime $inventory) -or $inventory.version -cne $Runtime.version -or $inventory.identity -cne $Runtime.identity){
            throw 'AITN-741: Сведения о проверенной сборке stems.cpp недоступны. Повторите обновление.'
        }
    }
    Assert-AitOrdinaryPath $root
    if($inventory.file -cne 'stems-split.exe' -or @($inventory.files).Count -lt 8 -or @($inventory.files).Count -gt 256){
        throw 'AITN-741: Неверный список файлов stems.cpp.'
    }
    $seen=@{}
    foreach($entry in $inventory.files){
        $name=[string]$entry.file
        if($name -notmatch '^[A-Za-z0-9_.-]+$' -or $name -in @('.','..') -or $seen.ContainsKey($name) -or [long]$entry.bytes -le 0 -or $entry.sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'AITN-741: Повреждён список файлов stems.cpp.'}
        $seen[$name]=$true;$path=Join-Path $root $name;Assert-AitOrdinaryPath $path
        if(-not[IO.File]::Exists($path) -or (Get-Item -LiteralPath $path).Length -ne [long]$entry.bytes){throw ('AITN-741: Файл движка недоступен: '+$name)}
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw ('AITN-741: Файл движка не прошёл проверку: '+$name)}
    }
    $required=@('stems-split.exe','stems-ggml.dll','stems-ggml-base.dll','stems-ggml-cpu-x64.dll','stems-ggml-vulkan.dll')
    foreach($name in $required){if(-not $seen[$name]){throw ('AITN-741: В сборке нет '+$name)}}
    foreach($entry in Get-ChildItem -LiteralPath $root -Force){
        if($entry.PSIsContainer -or (-not $seen.ContainsKey($entry.Name) -and ($Runtime.bundled -or $entry.Name -cne 'runtime.json'))){
            throw ('AITN-741: В папке движка stems.cpp найден посторонний файл: '+$entry.Name)
        }
    }
    return $root
}
function Get-ActiveStemsRuntime([string]$App,[string]$State) {
    $bundled=Get-BundledStemsRuntime $App
    $native=Read-AitJson (Join-Path $State 'stems_active.json')
    $saved=$native.stems_runtime
    if((Test-ManagedStemsRuntime $saved) -and [version]$saved.version -gt [version]$bundled.version){
        try{$null=Assert-StemsRuntime $App $State $saved;return $saved}catch{}
    }
    $null=Assert-StemsRuntime $App
    return $bundled
}
