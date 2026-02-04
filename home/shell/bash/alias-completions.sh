#!/usr/bin/env bash
# Provide bash completions for common CLI aliases.


if [[ ! -v BASH_COMPLETION_VERSINFO ]]; then
  . "${HOME_MANAGER_BASH_COMPLETION_PATH:-${HOME}/.nix-profile/etc/profile.d/bash_completion.sh}"
fi

# kubectl alias completion (k)
if type __start_kubectl &>/dev/null; then
  complete -o default -F __start_kubectl k
fi

# terraform alias completion (tf)
if type __start_terraform &>/dev/null; then
  complete -o default -F __start_terraform tf
fi

# docker compose alias completion (dc)
if type _docker &>/dev/null; then
  __dc_completion() {
    local original_words=("${COMP_WORDS[@]}")
    local original_cword=$COMP_CWORD
    local original_line=$COMP_LINE
    local original_point=$COMP_POINT

    COMP_WORDS=("docker" "compose" "${COMP_WORDS[@]:1}")
    COMP_CWORD=$((original_cword + 1))
    COMP_LINE="docker compose${original_line#dc}"
    COMP_POINT=${#COMP_LINE}

    _docker "$@"
    local status=$?

    COMP_WORDS=("${original_words[@]}")
    COMP_CWORD=$original_cword
    COMP_LINE=$original_line
    COMP_POINT=$original_point
    return $status
  }
  complete -o default -F __dc_completion dc
fi
