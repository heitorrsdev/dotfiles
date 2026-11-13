#!/usr/bin/env bash
#
# Troca todos os repositorios da pasta para uma branch e atualiza com pull.
#
# Uso:
#   git-switch-n-pull.sh <branch> [-p|--path <pasta>] [-i|--ignorar <repo>]...
#
# Exemplo:
#   git-switch-n-pull.sh homolog
#   git-switch-n-pull.sh homolog -p ~/back -i core -i out
#
# Notas:
#   - O core nunca e trocado (padrao de --ignorar; informar --ignorar substitui o padrao).
#   - Sem --path, usa o diretorio atual.
#   - Repositorio com alteracoes locais e ignorado, para nao perder trabalho.
#   - Repositorio sem a branch continua na branch atual.
#   - O pull usa --ff-only: nunca cria merge. Se a branch divergiu da origin, e reportado como falha.
#   - Retorna exit code 1 se algum repositorio falhar.

set -uo pipefail

uso() {
    echo "Uso: $(basename "$0") <branch> [-p|--path <pasta>] [-i|--ignorar <repo>]..." >&2
    exit 2
}

branch=''
path='.'
ignorar=()

while (($#)); do
    case "$1" in
        -p | --path)
            [[ $# -ge 2 ]] || uso
            path="$2"
            shift 2
            ;;
        -i | --ignorar)
            [[ $# -ge 2 ]] || uso
            ignorar+=("$2")
            shift 2
            ;;
        -h | --help) uso ;;
        -*) uso ;;
        *)
            [[ -z "$branch" ]] || uso
            branch="$1"
            shift
            ;;
    esac
done

[[ -n "$branch" ]] || uso
((${#ignorar[@]})) || ignorar=('core')

if [[ -t 1 ]]; then
    declare -A cores=(
        ['OK']=$'\033[0;32m'
        ['SEM PULL']=$'\033[0;33m'
        ['SEM BRANCH']=$'\033[0;33m'
        ['IGNORADO']=$'\033[0;33m'
        ['FALHA']=$'\033[0;31m'
    )
    ciano=$'\033[0;36m'
    vermelho=$'\033[0;31m'
    nc=$'\033[0m'
else
    declare -A cores=()
    ciano='' vermelho='' nc=''
fi

# Executa git no repositorio; a saida (stdout + stderr) fica em $saida.
invoke_git() {
    local repo="$1"
    shift
    saida=$(git -C "$repo" "$@" 2>&1)
}

ultima_linha() {
    printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | tail -n 1
}

# Define $resultado e $detalhe.
update_repositorio() {
    local repo="$1" saida antes local_ok=0 remota_ok=0

    if ! invoke_git "$repo" status --porcelain; then
        resultado='FALHA' detalhe=$(ultima_linha "$saida")
        return
    fi
    if [[ -n "$saida" ]]; then
        resultado='IGNORADO' detalhe='possui alteracoes locais'
        return
    fi

    if ! invoke_git "$repo" fetch --prune origin; then
        resultado='FALHA' detalhe="fetch: $(ultima_linha "$saida")"
        return
    fi

    invoke_git "$repo" show-ref --verify --quiet "refs/heads/$branch" && local_ok=1
    invoke_git "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" && remota_ok=1
    if ((!local_ok && !remota_ok)); then
        resultado='SEM BRANCH' detalhe='nao existe localmente nem na origin'
        return
    fi

    if ! invoke_git "$repo" switch "$branch"; then
        resultado='FALHA' detalhe="switch: $(ultima_linha "$saida")"
        return
    fi

    if ((!remota_ok)); then
        resultado='SEM PULL' detalhe='branch existe apenas localmente'
        return
    fi

    invoke_git "$repo" rev-parse HEAD
    antes="$saida"
    if ! invoke_git "$repo" pull --ff-only; then
        resultado='FALHA' detalhe="pull: $(ultima_linha "$saida")"
        return
    fi

    invoke_git "$repo" rev-parse HEAD
    if [[ "$saida" == "$antes" ]]; then
        resultado='OK' detalhe='ja estava atualizada'
    else
        resultado='OK' detalhe='atualizada com pull'
    fi
}

repos=()
for dir in "$path"/*/; do
    [[ -d "$dir" ]] || continue
    dir="${dir%/}"
    nome="${dir##*/}"
    for ign in "${ignorar[@]}"; do
        [[ "$nome" == "$ign" ]] && continue 2
    done
    [[ -e "$dir/.git" ]] && repos+=("$dir")
done

if ((${#repos[@]} == 0)); then
    echo "${vermelho}Nenhum repositorio encontrado em $path${nc}"
    exit 1
fi

printf '%sTrocando %d repositorios para '\''%s'\''%s\n\n' "$ciano" "${#repos[@]}" "$branch" "$nc"

declare -A contagem=()
ordem=()
falhou=0

for repo in "${repos[@]}"; do
    update_repositorio "$repo"
    invoke_git "$repo" branch --show-current
    atual="$saida"

    printf '%s%-10s %-28s [%s] %s%s\n' "${cores[$resultado]:-}" "$resultado" "${repo##*/}" "$atual" "$detalhe" "$nc"

    [[ -n "${contagem[$resultado]:-}" ]] || ordem+=("$resultado")
    contagem[$resultado]=$((${contagem[$resultado]:-0} + 1))
    [[ "$resultado" == 'FALHA' ]] && falhou=1
done

echo
for r in "${ordem[@]}"; do
    printf '%s%-10s %d%s\n' "${cores[$r]:-}" "$r" "${contagem[$r]}" "$nc"
done

exit "$falhou"
