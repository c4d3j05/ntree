# bash completion for ntree
_ntree() {
  local cur prev cmds
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmds="new run list stop open git sync-deps allow path cd rm doctor version help"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return
  fi

  case "${COMP_WORDS[1]}" in
    stop|open|git|sync-deps|path|cd|rm)
      # complete workspace names from .ntree/state.json
      local root names
      root="$(git rev-parse --show-toplevel 2>/dev/null)" || return
      if [[ -f "$root/.ntree/state.json" ]] && command -v jq >/dev/null; then
        names="$(jq -r '.workspaces | keys[]' "$root/.ntree/state.json" 2>/dev/null)"
        COMPREPLY=( $(compgen -W "$names" -- "$cur") )
      fi
      ;;
    new)
      [[ "$prev" == "--from" ]] && COMPREPLY=( $(compgen -W "$(git branch --format='%(refname:short)' 2>/dev/null)" -- "$cur") )
      [[ "$cur" == -* ]] && COMPREPLY=( $(compgen -W "--from" -- "$cur") )
      ;;
    run)
      [[ "$prev" == "--from" ]] && COMPREPLY=( $(compgen -W "$(git branch --format='%(refname:short)' 2>/dev/null)" -- "$cur") )
      [[ "$cur" == -* ]] && COMPREPLY=( $(compgen -W "--from --rm --detach -d --" -- "$cur") )
      ;;
  esac
}
complete -F _ntree ntree
