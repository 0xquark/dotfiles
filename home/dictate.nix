{ config, lib, pkgs, ... }:
let
  hyper = "Mod4+Mod1+Control+Shift"; # what keyd sends while Caps is held

  inherit (import ./voice.nix { inherit config pkgs; }) model pill;

  # Hold to record, release to type out what was said. Runs offline on the Arc GPU.
  dictate = pkgs.writeShellApplication {
    name = "dictate";
    runtimeInputs = [
      pkgs.pipewire
      pkgs.wtype
      pkgs.whisper-cpp-vulkan
      pill
    ];
    text = ''
      dir="$XDG_RUNTIME_DIR/dictate"
      mkdir -p "$dir"

      case "''${1:-}" in
        start)
          # Each recording gets its own folder, so a new one can start
          # while the last is still being transcribed
          id=$(date +%s%3N)
          rec="$dir/$id"
          mkdir -p "$rec"
          echo "$id" > "$dir/current"
          pw-record --rate 16000 --channels 1 --format s16 "$rec/audio.wav" &
          echo $! > "$rec/recorder"
          # `dictate start joi` puts the pill over Joi in the bar
          dictate-pill "$rec/audio.wav" "''${2:-}" &
          echo $! > "$rec/pill"
          ;;
        stop)
          id=$(cat "$dir/current" 2>/dev/null) || exit 0
          rm -f "$dir/current"
          rec="$dir/$id"
          # On a very quick tap, give start a moment to write its PIDs
          for _ in {1..50}; do
            [ -f "$rec/pill" ] && break
            sleep 0.02
          done
          recorder=$(cat "$rec/recorder" 2>/dev/null || true)
          pill=$(cat "$rec/pill" 2>/dev/null || true)
          # However this ends, the pill gets its goodbye and the files go
          trap 'kill -USR2 "$pill" 2>/dev/null || true; rm -rf "$rec"' EXIT

          # SIGINT lets pw-record finish writing the WAV header
          kill -INT "$recorder" 2>/dev/null || true
          while kill -0 "$recorder" 2>/dev/null; do sleep 0.02; done

          # Skip accidental taps
          if [ $(( $(date +%s%3N) - id )) -lt 300 ]; then
            kill "$pill" 2>/dev/null || true
            exit 0
          fi

          kill -USR1 "$pill" 2>/dev/null || true
          # Join the lines and drop Whisper's sound tags like [BLANK_AUDIO] or (music)
          text=$(whisper-cli -m ${model} -f "$rec/audio.wav" -nt -np -l en -t 8 2>/dev/null \
            | tr '\n' ' ' \
            | sed -E 's/\[[^]]*\]|\([^)]*\)//g; s/ +/ /g; s/^ //; s/ $//') || text=""
          # The pill smiles once more and closes itself
          kill -USR2 "$pill" 2>/dev/null || true
          if [ -z "$text" ]; then
            exit 0
          elif [ -n "''${2:-}" ]; then
            # `dictate stop <command>` hands the text to that command, like Joi
            "$2" "$text"
          else
            wtype -- "$text"
          fi
          ;;
      esac
    '';
  };
in
{
  home.packages = [ dictate ];

  # Hold Hyper + ` to dictate. Letting go of either key stops it.
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "--no-repeat ${hyper}+grave" = "exec ${dictate}/bin/dictate start";
    "--release ${hyper}+grave" = "exec ${dictate}/bin/dictate stop";
  };
}
