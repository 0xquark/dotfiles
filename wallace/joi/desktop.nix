# Joi on the desktop: her face at the right end of the bottom bar, the keys and
# launcher entries that talk to her, and the moments she starts herself
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./shared.nix { inherit config pkgs; })
    cfg
    home
    health
    state
    mutedFile
    handoffs
    hush
    joiPower
    joiMute
    bubble
    ;
  hyper = config.wallace.hyperKey;

  # Hold to talk: the pill rises out of Joi's face, the reply comes in a bubble
  joiVoice = pkgs.writeShellApplication {
    name = "joi-voice";
    text = ''
      activity="$XDG_RUNTIME_DIR/joi/activity"
      pressed="$XDG_RUNTIME_DIR/joi/pressed"
      mkdir -p "$XDG_RUNTIME_DIR/joi"
      case "''${1:-}" in
        start)
          date +%s%3N > "$pressed"
          # Talking to her wakes her up; the bubble waits for the model
          systemctl --user is-active -q hermes-agent || ${joiPower}/bin/joi-power on
          ${hush}
          echo listening > "$activity"
          exec dictate start joi
          ;;
        stop)
          held=$(( $(date +%s%3N) - $(cat "$pressed" 2>/dev/null || echo 0) ))
          echo thinking > "$activity"
          dictate stop ${bubble}/bin/joi-bubble
          # A quick tap (dictate drops those too) opens the box to type to her
          if [ "$held" -lt 300 ]; then
            exec ${bubble}/bin/joi-bubble --type
          fi
          # Nothing was said, so there's no bubble to finish the turn
          if grep -qx thinking "$activity"; then echo ready > "$activity"; fi
          ;;
        hush)
          # Stop her now: no more talking, and the bubble goes
          ${hush}
          kill "$(cat "$XDG_RUNTIME_DIR/joi/bubble.pid" 2>/dev/null)" 2>/dev/null || true
          echo ready > "$activity"
          ;;
        type)
          # Type to her instead: the bubble opens with a text box
          systemctl --user is-active -q hermes-agent || ${joiPower}/bin/joi-power on
          ${hush}
          exec ${bubble}/bin/joi-bubble --type
          ;;
      esac
    '';
  };

  # Her face in the bar
  face = pkgs.writeShellScriptBin "joi-face" ''
    export PATH=${pkgs.systemd}/bin:${pkgs.playerctl}/bin:${pkgs.wl-clipboard}/bin:$PATH
    export JOI_HEALTH="${health}"
    export JOI_MUTED_FILE="${mutedFile}"
    export JOI_HANDOFFS="${handoffs}"
    exec ${pkgs.python3}/bin/python3 ${./scripts/face.py}
  '';

  # Lines she says by herself now and then, from what K is doing: good morning,
  # back after hours away, this song again, skipping everything, a low battery
  moments = pkgs.writeShellScriptBin "joi-moments" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.procps
        pkgs.playerctl
        pkgs.systemd
        pkgs.swaynotificationcenter
        pkgs.sway
      ]
    }:$PATH
    export JOI_STATE="${state}"
    export JOI_BUBBLE="${bubble}/bin/joi-bubble"
    export JOI_POWER="${joiPower}/bin/joi-power"
    export JOI_HEALTH="${health}"
    export JOI_NOTES="${cfg.notesFile}"
    export JOI_SESSIONS="${home}/profiles/joi/state.db"
    exec ${pkgs.python3}/bin/python3 ${./scripts/moments.py}
  '';
in
{
  home.packages = [
    bubble
    joiPower
    joiMute
  ];

  # Runs with the desktop, even while she sleeps: the morning one wakes her,
  # and songs are counted all week
  systemd.user.services.joi-moments = {
    Unit = {
      Description = "Joi's small moments";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${moments}/bin/joi-moments";
      Restart = "on-failure";
    };
  };

  # The same controls in Vicinae, or any app launcher
  xdg.desktopEntries =
    lib.mapAttrs
      (name: e: {
        name = "Joi: ${e.title}";
        comment = e.comment;
        exec = e.exec;
        icon = "audio-input-microphone";
        categories = [ "Utility" ];
      })
      {
        joi-type = {
          title = "type to her";
          comment = "Opens the bubble to type a message to Joi";
          exec = "${joiVoice}/bin/joi-voice type";
        };
        joi-mute = {
          title = "mute or unmute";
          comment = "Joi keeps typing but stops speaking, or speaks again";
          exec = "${joiMute}/bin/joi-mute";
        };
        joi-power = {
          title = "wake up or sleep";
          comment = "Starts or stops Joi's model, voice and gateway";
          exec = "${joiPower}/bin/joi-power toggle";
        };
        joi-hush = {
          title = "stop talking";
          comment = "Stops Joi mid-sentence and closes her bubble";
          exec = "${joiVoice}/bin/joi-voice hush";
        };
      };

  # Joi lives at the right end of the bottom bar: click to switch her on and off,
  # right-click to mute her voice, middle-click to type to her
  programs.waybar.settings.stats.modules-right = lib.mkAfter [ "custom/joi" ];
  programs.waybar.settings.stats."custom/joi" = {
    exec = "${face}/bin/joi-face";
    return-type = "json";
    on-click = "${joiPower}/bin/joi-power toggle";
    on-click-right = "${joiMute}/bin/joi-mute";
    on-click-middle = "${joiVoice}/bin/joi-voice type";
  };
  programs.waybar.style = lib.mkAfter ''
    /* Room at the screen edge for the note; the pill is placed to rise
       from her middle, so change it in wallace/dictation/whisper.nix too */
    #custom-joi {
      padding: 0 10px;
      margin: 0;
      color: @base0E;
    }
    #custom-joi.asleep {
      color: @base03;
    }
    #custom-joi.listening {
      color: @base0D;
    }
    #custom-joi.replying {
      color: @base0B;
    }
    #custom-joi.happy {
      color: @base0A;
    }
    #custom-joi.music {
      color: @base0C;
    }
    #custom-joi.reading,
    #custom-joi.looking {
      color: @base0D;
    }
    #custom-joi.snap {
      color: @base0A;
    }
    #custom-joi.muted {
      color: @base03;
    }
    #custom-joi.alarm {
      color: @base08;
    }
    #custom-joi.oops {
      color: @base09;
    }
    #custom-joi.waking,
    #custom-joi.thinking {
      animation: joi-pulse 0.9s ease-in-out infinite alternate;
    }
    @keyframes joi-pulse {
      to {
        opacity: 0.45;
      }
    }
  '';

  # Hold Hyper + Space and talk to Joi. Letting go of either key sends it.
  # A quick tap opens the box to type to her instead.
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "--no-repeat ${hyper}+space" = "exec ${joiVoice}/bin/joi-voice start";
    "--release ${hyper}+space" = "exec ${joiVoice}/bin/joi-voice stop";
    # Tap Hyper + Space to type to her instead. These do the same:
    "${hyper}+Return" = "exec ${joiVoice}/bin/joi-voice type";
    # Mute or unmute her, wake her or put her to sleep, and stop her mid-sentence
    "${hyper}+m" = "exec ${joiMute}/bin/joi-mute";
    "${hyper}+j" = "exec ${joiPower}/bin/joi-power toggle";
    "${hyper}+Escape" = "exec ${joiVoice}/bin/joi-voice hush";
  };
}
