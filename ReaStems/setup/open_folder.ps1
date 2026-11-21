param(
    [Parameter(Mandatory=$true)][string]$Folder,
    [switch]$ProbeOnly
)

[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$ErrorActionPreference='Stop'
try {
    $directory=[IO.Path]::GetFullPath($Folder)
    if($directory -match '["\r\n]'){throw 'Invalid folder path.'}
    [void][IO.Directory]::CreateDirectory($directory)
    if(-not $ProbeOnly){
        $explorer=Join-Path $env:SystemRoot 'explorer.exe'
        Start-Process -FilePath $explorer -ArgumentList ('"' + $directory.TrimEnd('\') + '\."') -WindowStyle Normal
    }
    [Console]::WriteLine('AISTEMS_FOLDER_OK')
    exit 0
}catch{
    [Console]::WriteLine($_.Exception.Message)
    exit 1
}
