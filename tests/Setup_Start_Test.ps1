param([Parameter(Mandatory=$true)][string]$PackageRoot)

$ErrorActionPreference='Stop'
. (Join-Path $PackageRoot 'Install.ps1') -LibraryOnly

$script:LicenseWindowChecked=$false
function Show-SetupLicenseWindow([string]$Text) {
    if($Text -notmatch ('^Ai ReaStems '+[regex]::Escape($script:SetupVersion))){
        throw 'The setup license sheet has an incorrect version.'
    }
    $form=New-SetupLicenseWindow $Text
    try {
        $controls=$form.Tag
        if($controls.Next.Enabled -or -not $controls.Decline.Checked){
            throw 'The Next button must be disabled until the user accepts the license.'
        }
        $controls.Accept.Checked=$true
        if(-not $controls.Next.Enabled){throw 'The Next button did not become enabled.'}
        $controls.Decline.Checked=$true
        if($controls.Next.Enabled){throw 'The Next button stayed enabled after declining.'}
        $script:LicenseWindowChecked=$true
    } finally { $form.Dispose() }
    return $false
}

Show-SetupWindow
if(-not $script:LicenseWindowChecked){throw 'The setup entry point did not reach the license window.'}
Write-Output 'Installer entry point, license text and acceptance controls verified.'
