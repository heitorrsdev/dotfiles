<#
.SYNOPSIS
    Switches every repository in the folder to a branch and updates it with pull.

.EXAMPLE
    .\git-switch-n-pull.ps1 homolog

.NOTES
    - core is never switched (listed in -Ignore).
    - Repositories with local changes are skipped, so no work is lost.
    - Repositories without the branch stay on their current branch.
    - pull uses --ff-only: never creates a merge. If the branch diverged from origin, it is reported as a failure.
    - Exits with code 1 if any repository fails.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Branch,

    [string]$Path = $PSScriptRoot,

    [Alias('Ignorar')]
    [string[]]$Ignore = @('core')
)

function Invoke-Git {
    param([string]$Repo, [string[]]$GitArgs)

    $output = & git -C $Repo @GitArgs 2>&1 | ForEach-Object { $_.ToString() }
    [pscustomobject]@{
        Ok     = ($LASTEXITCODE -eq 0)
        Output = ($output -join "`n").Trim()
    }
}

function Get-LastLine {
    param([string]$Text)

    ($Text -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
}

function Update-Repository {
    param([string]$Repo)

    $status = Invoke-Git $Repo @('status', '--porcelain')
    if (-not $status.Ok) { return 'FAILED', (Get-LastLine $status.Output) }
    if ($status.Output) { return 'SKIPPED', 'has local changes' }

    $fetch = Invoke-Git $Repo @('fetch', '--prune', 'origin')
    if (-not $fetch.Ok) { return 'FAILED', "fetch: $(Get-LastLine $fetch.Output)" }

    $local = (Invoke-Git $Repo @('show-ref', '--verify', '--quiet', "refs/heads/$Branch")).Ok
    $remote = (Invoke-Git $Repo @('show-ref', '--verify', '--quiet', "refs/remotes/origin/$Branch")).Ok
    if (-not $local -and -not $remote) { return 'NO BRANCH', 'does not exist locally nor on origin' }

    $switch = Invoke-Git $Repo @('switch', $Branch)
    if (-not $switch.Ok) { return 'FAILED', "switch: $(Get-LastLine $switch.Output)" }

    if (-not $remote) { return 'NO PULL', 'branch exists only locally' }

    $before = (Invoke-Git $Repo @('rev-parse', 'HEAD')).Output
    $pull = Invoke-Git $Repo @('pull', '--ff-only')
    if (-not $pull.Ok) { return 'FAILED', "pull: $(Get-LastLine $pull.Output)" }

    if ((Invoke-Git $Repo @('rev-parse', 'HEAD')).Output -eq $before) { return 'OK', 'already up to date' }
    return 'OK', 'updated with pull'
}

$colors = @{
    'OK'        = 'Green'
    'NO PULL'   = 'Yellow'
    'NO BRANCH' = 'Yellow'
    'SKIPPED'   = 'Yellow'
    'FAILED'    = 'Red'
}

$repos = Get-ChildItem -LiteralPath $Path -Directory |
    Where-Object { $Ignore -notcontains $_.Name -and (Test-Path -LiteralPath (Join-Path $_.FullName '.git')) }

if (-not $repos) {
    Write-Host "No repositories found in $Path" -ForegroundColor Red
    exit 1
}

Write-Host "Switching $(@($repos).Count) repositories to '$Branch'`n" -ForegroundColor Cyan

$results = foreach ($repo in $repos) {
    $result, $detail = Update-Repository $repo.FullName
    $current = (Invoke-Git $repo.FullName @('branch', '--show-current')).Output

    Write-Host ("{0,-10} {1,-28} [{2}] {3}" -f $result, $repo.Name, $current, $detail) -ForegroundColor $colors[$result]
    [pscustomobject]@{ Result = $result; Repository = $repo.Name }
}

Write-Host ''
$results | Group-Object Result | ForEach-Object {
    Write-Host ("{0,-10} {1}" -f $_.Name, $_.Count) -ForegroundColor $colors[$_.Name]
}

if ($results | Where-Object { $_.Result -eq 'FAILED' }) { exit 1 }
