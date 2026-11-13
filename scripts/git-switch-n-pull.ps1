<#
.SYNOPSIS
    Troca todos os repositorios da pasta para uma branch e atualiza com pull.

.EXAMPLE
    .\trocar-branch.ps1 homolog

.NOTES
    - O core nunca e trocado (lista em -Ignorar).
    - Repositorio com alteracoes locais e ignorado, para nao perder trabalho.
    - Repositorio sem a branch continua na branch atual.
    - O pull usa --ff-only: nunca cria merge. Se a branch divergiu da origin, e reportado como falha.
    - Retorna exit code 1 se algum repositorio falhar.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Branch,

    [string]$Path = $PSScriptRoot,

    [string[]]$Ignorar = @('core')
)

function Invoke-Git {
    param([string]$Repo, [string[]]$GitArgs)

    $saida = & git -C $Repo @GitArgs 2>&1 | ForEach-Object { $_.ToString() }
    [pscustomobject]@{
        Ok    = ($LASTEXITCODE -eq 0)
        Saida = ($saida -join "`n").Trim()
    }
}

function Get-UltimaLinha {
    param([string]$Texto)

    ($Texto -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
}

function Update-Repositorio {
    param([string]$Repo)

    $status = Invoke-Git $Repo @('status', '--porcelain')
    if (-not $status.Ok) { return 'FALHA', (Get-UltimaLinha $status.Saida) }
    if ($status.Saida) { return 'IGNORADO', 'possui alteracoes locais' }

    $fetch = Invoke-Git $Repo @('fetch', '--prune', 'origin')
    if (-not $fetch.Ok) { return 'FALHA', "fetch: $(Get-UltimaLinha $fetch.Saida)" }

    $local = (Invoke-Git $Repo @('show-ref', '--verify', '--quiet', "refs/heads/$Branch")).Ok
    $remota = (Invoke-Git $Repo @('show-ref', '--verify', '--quiet', "refs/remotes/origin/$Branch")).Ok
    if (-not $local -and -not $remota) { return 'SEM BRANCH', 'nao existe localmente nem na origin' }

    $switch = Invoke-Git $Repo @('switch', $Branch)
    if (-not $switch.Ok) { return 'FALHA', "switch: $(Get-UltimaLinha $switch.Saida)" }

    if (-not $remota) { return 'SEM PULL', 'branch existe apenas localmente' }

    $antes = (Invoke-Git $Repo @('rev-parse', 'HEAD')).Saida
    $pull = Invoke-Git $Repo @('pull', '--ff-only')
    if (-not $pull.Ok) { return 'FALHA', "pull: $(Get-UltimaLinha $pull.Saida)" }

    if ((Invoke-Git $Repo @('rev-parse', 'HEAD')).Saida -eq $antes) { return 'OK', 'ja estava atualizada' }
    return 'OK', 'atualizada com pull'
}

$cores = @{
    'OK'         = 'Green'
    'SEM PULL'   = 'Yellow'
    'SEM BRANCH' = 'Yellow'
    'IGNORADO'   = 'Yellow'
    'FALHA'      = 'Red'
}

$repos = Get-ChildItem -LiteralPath $Path -Directory |
    Where-Object { $Ignorar -notcontains $_.Name -and (Test-Path -LiteralPath (Join-Path $_.FullName '.git')) }

if (-not $repos) {
    Write-Host "Nenhum repositorio encontrado em $Path" -ForegroundColor Red
    exit 1
}

Write-Host "Trocando $(@($repos).Count) repositorios para '$Branch'`n" -ForegroundColor Cyan

$resultados = foreach ($repo in $repos) {
    $resultado, $detalhe = Update-Repositorio $repo.FullName
    $atual = (Invoke-Git $repo.FullName @('branch', '--show-current')).Saida

    Write-Host ("{0,-10} {1,-28} [{2}] {3}" -f $resultado, $repo.Name, $atual, $detalhe) -ForegroundColor $cores[$resultado]
    [pscustomobject]@{ Resultado = $resultado; Repositorio = $repo.Name }
}

Write-Host ''
$resultados | Group-Object Resultado | ForEach-Object {
    Write-Host ("{0,-10} {1}" -f $_.Name, $_.Count) -ForegroundColor $cores[$_.Name]
}

if ($resultados | Where-Object { $_.Resultado -eq 'FALHA' }) { exit 1 }


