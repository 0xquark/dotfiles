# What the parts of Joi share: ports, paths, and the commands more than one
# part runs. Each part imports this; the same inputs give the same packages.
{ config, pkgs }:
let
  cfg = config.wallace.joi;
  c = config.lib.stylix.colors.withHashtag;
in
rec {
  inherit cfg;
  home = config.services.hermes-agent.hermesHome;
  gatewayPort = 8650;
  modelPort = 8091;
  health = "http://127.0.0.1:${toString modelPort}/health http://127.0.0.1:${toString gatewayPort}/health";

  state = "${config.xdg.stateHome}/joi";
  # Joi is on while this file exists; the model and the gateway only start then
  awakeFile = "${state}/awake";
  # She types without speaking while this one exists
  mutedFile = "${state}/muted";
  # Jobs Joi hands to Claude or Darlene, and what came back
  handoffs = "${state}/handoffs";
  speakerSocket = "$XDG_RUNTIME_DIR/joi/speaker.sock";
  # Holds the API server key, made on first switch and kept out of the Nix store
  keyFile = "${home}/api-server.env";

  # Stops her mid-sentence
  hush = "${pkgs.socat}/bin/socat -u /dev/null \"UNIX-CONNECT:${speakerSocket}\" 2>/dev/null || true";

  # Switches the model and the gateway on and off together
  joiPower = pkgs.writeShellApplication {
    name = "joi-power";
    text = ''
      on() {
        mkdir -p "$(dirname ${awakeFile})"
        touch ${awakeFile}
        systemctl --user start llama-server hermes-agent joi-speaker
      }
      off() {
        rm -f ${awakeFile}
        systemctl --user stop hermes-agent llama-server joi-speaker
      }
      case "''${1:-toggle}" in
        on) on ;;
        off) off ;;
        toggle) if systemctl --user is-active -q hermes-agent; then off; else on; fi ;;
      esac
    '';
  };

  # go_to_sleep: switch off in a few seconds, once her goodnight is out
  joiSleepSoon = pkgs.writeShellScript "joi-sleep-soon" ''
    sleep 10
    exec ${joiPower}/bin/joi-power "$@"
  '';

  # Right-click her face: she keeps typing, but stops speaking
  joiMute = pkgs.writeShellApplication {
    name = "joi-mute";
    runtimeInputs = [ pkgs.libnotify ];
    text = ''
      mkdir -p "$(dirname ${mutedFile})"
      event="$XDG_RUNTIME_DIR/joi/event"
      mkdir -p "$(dirname "$event")"
      # joi-mute on|off|toggle (toggle when nothing's given)
      want=''${1:-toggle}
      if [ "$want" = toggle ]; then
        if [ -e ${mutedFile} ]; then want=off; else want=on; fi
      fi
      if [ "$want" = off ]; then
        rm -f ${mutedFile}
        echo unmuted > "$event"
        notify-send --app-name=Joi -t 2000 Joi "I'll talk again"
      else
        touch ${mutedFile}
        ${hush}
        echo muted > "$event"
        notify-send --app-name=Joi -t 2000 Joi "I'll keep quiet"
      fi
    '';
  };

  # When a timer from her remind tool is up. It rings through Do Not Disturb,
  # and she says it too if she's awake.
  joiRing = pkgs.writeShellApplication {
    name = "joi-ring";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.pipewire
    ];
    text = ''
      notify-send --app-name=Joi --urgency=critical Joi "$1"
      mkdir -p "$XDG_RUNTIME_DIR/joi"
      echo alarm > "$XDG_RUNTIME_DIR/joi/event"
      pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga || true
      if [ ! -e ${mutedFile} ]; then
        printf "K, time's up. %s." "$1" | ${pkgs.socat}/bin/socat -u - "UNIX-CONNECT:${speakerSocket}" 2>/dev/null || true
      fi
    '';
  };

  # The chat bubble above her corner of the bar, which also makes the call to her
  bubble = pkgs.stdenv.mkDerivation {
    name = "joi-bubble";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [
      pkgs.gtk3
      pkgs.gtk-layer-shell
    ];
    installPhase = ''
      install -Dm755 ${pkgs.writeScript "joi-bubble" ''
        #!${pkgs.python3.withPackages (ps: [ ps.pygobject3 ])}/bin/python3
        ${builtins.readFile ./scripts/bubble.py}
      ''} $out/bin/joi-bubble
    '';
    preFixup = ''
      gappsWrapperArgs+=(
        --set JOI_URL http://127.0.0.1:${toString gatewayPort}/p/joi/v1/chat/completions
        --set JOI_HEALTH "${health}"
        --set JOI_KEY_FILE ${keyFile}
        --set JOI_MUTED_FILE ${mutedFile}
        --set JOI_BG "${c.base00}"
        --set JOI_BORDER "${c.base02}"
        --set JOI_FG "${c.base05}"
        --set JOI_DIM "${c.base04}"
      )
    '';
  };

  # Runs a job she handed to Claude or Darlene, and tells K when it's done
  handoff = pkgs.writeShellScriptBin "joi-handoff" ''
    export PATH=${pkgs.libnotify}/bin:$PATH
    export JOI_STATE="${state}"
    export JOI_CLAUDE="${pkgs.claude-code}/bin/claude"
    export JOI_DARLENE_URL="http://127.0.0.1:${toString gatewayPort}/p/darlene/v1/chat/completions"
    export JOI_KEY_FILE="${keyFile}"
    export JOI_MUTED_FILE="${mutedFile}"
    # She tells K what came back, if she's awake
    export JOI_BUBBLE="${bubble}/bin/joi-bubble"
    export JOI_HEALTH="${health}"
    exec ${pkgs.python3}/bin/python3 ${./scripts/handoff.py} "$@"
  '';
}
