# shellcheck shell=bash
# shellcheck disable=SC2207

_katazuke() {
  local cur prev words
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == "--theme" ]]; then
    COMPREPLY=($(compgen -W "kodougu catppuccin-mocha catppuccin-latte dracula nord gruvbox tokyo-night mono" -- "${COMP_WORDS[COMP_CWORD]}"))
    return
  fi

  if [[ "${prev}" == "--order" ]]; then
    COMPREPLY=($(compgen -W "dirs files mixed" -- "${cur}"))
    return
  fi
  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "--natural --no-natural --order --eject --no-eject --allow-internal --json --theme" -- "${cur}"))
    return
  fi
  words="$(compgen -f -- "${cur}" || true)"
  if [[ "${COMP_CWORD}" -eq 1 ]]; then
    words="check doctor version help ${words}"
  fi
  COMPREPLY=($(compgen -W "${words}" -- "${cur}"))
}

complete -F _katazuke katazuke
