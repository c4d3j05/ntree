# bash completion for ntree
# shellcheck disable=SC2207  # COMPREPLY=( $(compgen ...) ) is the standard idiom; mapfile isn't in bash 3.2
# Commands and workspace names come from `ntree __complete`, so this file never
# drifts from the CLI and works from inside a worktree too.
_ntree() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    # commands, plus workspace names for the `ntree <workspace>` cd shortcut
    COMPREPLY=( $(compgen -W "$(command ntree __complete commands) $(command ntree __complete workspaces)" -- "$cur") )
    return
  fi

  case "${COMP_WORDS[1]}" in
    stop|open|git|desc|sync|sync-deps|path|cd|rm)
      [[ $COMP_CWORD -eq 2 ]] && COMPREPLY=( $(compgen -W "$(command ntree __complete workspaces)" -- "$cur") )
      ;;
    new)
      [[ "$prev" == "--from" ]] && COMPREPLY=( $(compgen -W "$(git branch --format='%(refname:short)' 2>/dev/null)" -- "$cur") )
      [[ "$cur" == -* ]] && COMPREPLY=( $(compgen -W "--from --ports -m --desc" -- "$cur") )
      ;;
    run)
      [[ "$prev" == "--from" ]] && COMPREPLY=( $(compgen -W "$(git branch --format='%(refname:short)' 2>/dev/null)" -- "$cur") )
      [[ "$cur" == -* ]] && COMPREPLY=( $(compgen -W "--from --ports -m --desc --rm --detach -d --" -- "$cur") )
      ;;
  esac
}
complete -F _ntree ntree
