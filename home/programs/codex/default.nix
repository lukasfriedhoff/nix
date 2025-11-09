{ pkgs, lib, ... }:

let
  codexCli = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      set -euo pipefail

      show_help() {
        cat <<'USAGE'
Usage: codex [options] [PROMPT]

Send a prompt to the configured OpenAI Codex-compatible model.

Options:
  -m, --model NAME   Override the model (default: $CODEX_MODEL or gpt-4o-mini)
  --plain            Output plain text without extra formatting
  -h, --help         Show this help message

If PROMPT is omitted, codex reads from standard input.
The script looks for OPENAI_API_KEY or a decrypted
~/.config/secrets/openai.env.
USAGE
      }

      model="$CODEX_MODEL"
      if [ -z "$model" ]; then
        model="gpt-4o-mini"
      fi
      plain=0
      prompt=""

      while [ "$#" -gt 0 ]; do
        case "$1" in
          -m|--model)
            shift || {
              echo "codex: missing model name" >&2
              exit 1
            }
            model="$1"
            ;;
          --plain)
            plain=1
            ;;
          -h|--help)
            show_help
            exit 0
            ;;
          --)
            shift
            if [ "$#" -gt 0 ]; then
              prompt="${prompt:+$prompt }$*"
            fi
            break
            ;;
          *)
            prompt="${prompt:+$prompt }$1"
            ;;
        esac
        shift || break
      done

      if [ -z "$prompt" ]; then
        if [ -t 0 ]; then
          echo "codex: provide a prompt or pipe text in" >&2
          exit 1
        else
          prompt="$(cat)"
        fi
      fi

      if [ -z "''${OPENAI_API_KEY+x}" ]; then
        secret_file="$HOME/.config/secrets/openai.env"
        if [ -r "$secret_file" ]; then
          while IFS='=' read -r key value; do
            if [ "$key" = "OPENAI_API_KEY" ]; then
              OPENAI_API_KEY="$value"
              break
            fi
          done < "$secret_file"
        fi
      fi

      if [ -z "''${OPENAI_API_KEY+x}" ]; then
        echo "codex: OPENAI_API_KEY is not set" >&2
        exit 1
      fi

      payload=$(jq -n --arg model "$model" --arg input "$prompt" '{model:$model,input:$input}')

      auth_header="Authorization: Bearer $OPENAI_API_KEY"

      response=$(curl -sS -X POST https://api.openai.com/v1/responses \
        -H "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$payload")

      if [ "$plain" -eq 0 ]; then
        echo "$response" | jq -r '
          if .output then
            [ .output[]?.content[]? | select(.type == "output_text") | .text ] | join("\n\n")
          elif .choices then
            [ .choices[]?.message?.content? | if type == "array" then map(.text // .content // .value) | join("\n") else . end ] | join("\n\n")
          else
            .
          end' | sed '/^[[:space:]]*$/d'
      else
        echo "$response" | jq -r '
          if .output then
            [ .output[]?.content[]? | select(.type == "output_text") | .text ] | join("\n")
          elif .choices then
            [ .choices[]?.message?.content? | if type == "array" then map(.text // .content // .value) | join("\n") else . end ] | join("\n")
          else
            .
          end'
      fi
    '';
  };
in
{
  home.packages = [ codexCli ];

  home.sessionVariables.CODEX_MODEL = lib.mkDefault "gpt-4o-mini";
}
