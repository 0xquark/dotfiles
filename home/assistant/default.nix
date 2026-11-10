{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  c = config.lib.stylix.colors.withHashtag;
  hyper = "Mod4+Mod1+Control+Shift"; # what keyd sends while Caps is held
  home = config.services.hermes-agent.hermesHome;
  gatewayPort = 8650;
  modelPort = 8091;
  health = "http://127.0.0.1:${toString modelPort}/health http://127.0.0.1:${toString gatewayPort}/health";

  # Joi is on while this file exists; the model and the gateway only start then
  awakeFile = "${config.xdg.stateHome}/joi/awake";
  # She types without speaking while this one exists
  mutedFile = "${config.xdg.stateHome}/joi/muted";
  # Minutes with nothing asked of her before she falls asleep
  sleepAfter = 20;
  # Her add_note, read_notes and cross_off tools keep K's list here
  notesFile = "${config.home.homeDirectory}/Documents/notes.md";
  speakerSocket = "$XDG_RUNTIME_DIR/joi/speaker.sock";

  # Joi's voice: Kokoro's Heart, warm and natural. Pinned to one revision of the model.
  kokoro =
    let
      file =
        name: sha256:
        pkgs.fetchurl {
          url = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/f3ff3571791e39611d31c381e3a41a3af07b4987/${name}";
          inherit sha256;
        };
    in
    {
      config = file "config.json" "0zy18fdnn68mpqis8jdd1mx9s81y8ihf3z847pq2n1rv83i03fss";
      model = file "kokoro-v1_0.pth" "1r6iibqm6b0zxr3nxzl9zj1h8vi1vkdqiz1fvgrzan0sil8vlva9";
      voice = file "voices/af_heart.pt" "1zxl5h82lf0jggbd0fi56dvsyq2vyyc1vlcwhkyrpcgsiydp1d8a";
    };

  # Keeps the voice loaded while Joi is on, so she starts speaking right away
  speaker = pkgs.writeShellScriptBin "joi-speaker" ''
    export PATH=${pkgs.pipewire}/bin:$PATH
    # Everything it needs is in the Nix store; never reach for Hugging Face
    export HF_HUB_OFFLINE=1
    exec ${
      pkgs.unstable.python3.withPackages (ps: [
        ps.kokoro
        ps.spacy-models.en_core_web_sm
      ])
    }/bin/python3 ${./speaker.py} ${kokoro.config} ${kokoro.model} ${kokoro.voice}
  '';

  # Stops her mid-sentence
  hush = "${pkgs.socat}/bin/socat -u /dev/null \"UNIX-CONNECT:${speakerSocket}\" 2>/dev/null || true";

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
    export JOI_STATE="${config.xdg.stateHome}/joi"
    export JOI_BUBBLE="${bubble}/bin/joi-bubble"
    export JOI_POWER="${joiPower}/bin/joi-power"
    export JOI_HEALTH="${health}"
    export JOI_NOTES="${notesFile}"
    export JOI_SESSIONS="${home}/profiles/joi/state.db"
    exec ${pkgs.python3}/bin/python3 ${./moments.py}
  '';

  # Qwen3.5 4B: small, fast on the Arc GPU, and calls tools reliably
  model = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf";
    sha256 = "190ixxlzpl8012kkhfb02f9nzns9c0a22n25c8z4csszzy37kzh0";
  };

  # Its eyes: lets the same model read images, for the screen and the clipboard
  vision = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf";
    sha256 = "0r7qj4ld202sjb7ggf82xvmsdzp1nywwbjdh1fb98603ip7yv26d";
  };

  # The official Spotify plugin: login, and the Web API calls behind Joi's play_music
  officialPlugins = pkgs.fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-official-plugins";
    rev = "e7a218f26db88426ab3e7376f0e000b6e356f5e7";
    hash = "sha256-zDjiWUVmWUPAyasy74mUuh+d/dpBi1SBh7GZvuTjxcI=";
  };
  spotifyFiles = lib.genAttrs [
    "__init__.py"
    "plugin.yaml"
    "spotify_auth.py"
    "spotify_cli.py"
    "spotify_client.py"
    "spotify_tools.py"
  ] (
    f:
    # The flake's Hermes reports version 0.0.0, which fails the plugin's minimum-version check
    pkgs.runCommand "spotify-${f}" { } "sed '/^requires_hermes:/d' ${officialPlugins}/spotify/${f} > $out"
  );

  # Settings every character shares, on top of their own toolsets
  profileSettings =
    toolsets: extra:
    lib.recursiveUpdate {
      model = {
        provider = "custom";
        base_url = "http://127.0.0.1:${toString modelPort}/v1";
        default = "local";
        api_key = "none";
      };
      platform_toolsets = {
        cli = toolsets;
        api_server = toolsets;
      };
      # A small model handles a short, fixed list of tools best
      tools.tool_search.enabled = "off";
    } extra;

  yaml = (pkgs.formats.yaml { }).generate;
  soul = name: builtins.readFile ./souls/${name}.md + builtins.readFile ./souls/style.md;

  profiles = {
    joi = profileSettings [ "web" "laptop" "memory" ] {
      plugins.enabled = [
        "laptop"
        "spotify"
      ];
      # Where look_at_screen and look_at_clipboard send pictures
      plugins.entries.laptop.settings = {
        model_url = "http://127.0.0.1:${toString modelPort}/v1/chat/completions";
        # hand_off and check_handoffs
        handoff_command = "${handoff}/bin/joi-handoff";
        handoffs_folder = handoffs;
        # mute_yourself, unmute_yourself and go_to_sleep
        mute_command = "${joiMute}/bin/joi-mute";
        power_command_later = "${joiSleepSoon}";
        # remind, read_aloud, battery, lock_screen and the notes
        ring_command = "${joiRing}/bin/joi-ring";
        muted_file = mutedFile;
        charge_command = "${import ../charge-limit.nix { inherit pkgs; }}";
        lock_command = "${config.programs.swaylock.package}/bin/swaylock -f";
        notes_file = notesFile;
      };
      # Naming each chat costs a second model call per question
      auxiliary.title_generation.enabled = false;
      # She saves things as K mentions them; a review every few turns would hold up the next answer
      memory.nudge_interval = 0;
    };
    darlene = profileSettings [ "terminal" "file" "web" ] { };
    caitlyn = profileSettings [ "web" "memory" ] { };
  };

  profileFiles =
    lib.concatMapAttrs (name: settings: {
      "profiles/${name}/config.yaml" = yaml "${name}-config.yaml" settings;
      "profiles/${name}/SOUL.md" = soul name;
    }) profiles
    // lib.mapAttrs' (f: src: lib.nameValuePair "profiles/joi/plugins/spotify/${f}" src) spotifyFiles;

  # Holds the API server key, made on first switch and kept out of the Nix store
  keyFile = "${home}/api-server.env";

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

  # Two throwaway chats once she's up, so the model has her prompt cached and
  # the first real question is as quick as the rest. The second one is what
  # settles the cache for this model. The laptop plugin blocks their tools.
  joiWarmup = pkgs.writeShellApplication {
    name = "joi-warmup";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      for _ in $(seq 240); do
        curl -sf http://127.0.0.1:${toString modelPort}/health >/dev/null &&
          curl -sf http://127.0.0.1:${toString gatewayPort}/health >/dev/null && break
        sleep 0.5
      done
      key=$(sed -n 's/^API_SERVER_KEY=//p' ${keyFile})
      for n in 1 2; do
        id="warmup-$(date +%s)-$n"
        curl -sf -m 120 -o /dev/null \
          -H "Authorization: Bearer $key" -H "Content-Type: application/json" \
          -H "X-Hermes-Session-Id: $id" \
          -d '{"model": "joi", "messages": [{"role": "user", "content": "What is 2 plus 2?"}]}' \
          http://127.0.0.1:${toString gatewayPort}/p/joi/v1/chat/completions || true
        # Keep them out of her history
        ${config.services.hermes-agent.package}/bin/hermes -p joi sessions delete --yes "$id" >/dev/null || true
      done
    '';
  };

  # Runs every minute while she's awake. The model's task counter moving means
  # someone used her: Joi, a terminal chat, or Darlene on a handoff.
  joiAutosleep = pkgs.writeShellApplication {
    name = "joi-autosleep";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.procps
    ];
    text = ''
      used="$XDG_RUNTIME_DIR/joi/used"
      mkdir -p "$(dirname "$used")"
      slots=$(curl -sf -m 5 http://127.0.0.1:${toString modelPort}/slots) || exit 0
      tasks=$(jq '[.[].id_task // 0] | max' <<<"$slots")
      if jq -e 'any(.[]; .is_processing)' <<<"$slots" >/dev/null ||
        [ "$tasks" != "$(cat "$used" 2>/dev/null)" ]; then
        echo "$tasks" > "$used"
        exit 0
      fi
      # Stay up for a job she handed off, or a terminal chat with one of them
      if ls "${handoffs}"/*.running >/dev/null 2>&1 ||
        pgrep -u "$(id -u)" -f '/bin/hermes( -p [a-z]+)?$' >/dev/null; then
        exit 0
      fi
      # Time passes during suspend too, so after a long one she sleeps within a minute
      last=$({ stat -c %Y "$used" "$XDG_RUNTIME_DIR/joi/activity" ${awakeFile} 2>/dev/null || true; } | sort -n | tail -1)
      if [ $(( $(date +%s) - last )) -ge ${toString (sleepAfter * 60)} ]; then
        exec ${joiPower}/bin/joi-power off
      fi
    '';
  };

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
        ${builtins.readFile ./bubble.py}
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

  # Jobs Joi hands to Claude or Darlene, and what came back
  handoffs = "${config.xdg.stateHome}/joi/handoffs";
  handoff = pkgs.writeShellScriptBin "joi-handoff" ''
    export PATH=${pkgs.libnotify}/bin:$PATH
    export JOI_STATE="${config.xdg.stateHome}/joi"
    export JOI_CLAUDE="${pkgs.claude-code}/bin/claude"
    export JOI_DARLENE_URL="http://127.0.0.1:${toString gatewayPort}/p/darlene/v1/chat/completions"
    export JOI_KEY_FILE="${keyFile}"
    export JOI_MUTED_FILE="${mutedFile}"
    # She tells K what came back, if she's awake
    export JOI_BUBBLE="${bubble}/bin/joi-bubble"
    export JOI_HEALTH="${health}"
    exec ${pkgs.python3}/bin/python3 ${./handoff.py} "$@"
  '';

  # Her face in the bar
  face = pkgs.writeShellScriptBin "joi-face" ''
    export PATH=${pkgs.systemd}/bin:${pkgs.playerctl}/bin:${pkgs.wl-clipboard}/bin:$PATH
    export JOI_HEALTH="${health}"
    export JOI_MUTED_FILE="${mutedFile}"
    export JOI_HANDOFFS="${handoffs}"
    exec ${pkgs.python3}/bin/python3 ${./face.py}
  '';

  # `joi`, `darlene` and `caitlyn` chat with that character in the terminal; `tars` is plain `hermes`.
  # They wake the model first if Joi is asleep.
  characterCommand =
    name: args:
    pkgs.writeShellScriptBin name ''
      systemctl --user is-active -q llama-server || ${joiPower}/bin/joi-power on
      exec hermes ${args} "$@"
    '';
  characterCommands =
    lib.mapAttrsToList (name: _: characterCommand name "-p ${name}") profiles
    ++ [ (characterCommand "tars" "") ];

  # Hermes expects these in every profile; `hermes profile create` would make them
  profileDirs = lib.concatMapStringsSep " " (
    name:
    "${home}/profiles/${name}/{cron,sessions,logs,memories,plugins,skills}"
  ) (builtins.attrNames profiles);
in
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  # The local model, loaded while Joi is on
  systemd.user.services.llama-server = {
    Unit = {
      Description = "Local model for Hermes";
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = lib.escapeShellArgs [
        "${pkgs.unstable.llama-cpp-vulkan}/bin/llama-server"
        "--model"
        model
        "--mmproj"
        vision
        # A full-resolution screenshot would be ~5000 tokens; this keeps a look under ~10s
        "--image-max-tokens"
        "1280"
        "--alias"
        "local"
        "--host"
        "127.0.0.1"
        "--port"
        (toString modelPort)
        "--jinja" # tool calling
        "--flash-attn"
        "on"
        "--n-gpu-layers"
        "99"
        # Two conversations at once, so a job handed to Darlene doesn't hold Joi up.
        # Hermes wants at least 64k of context for each.
        "--ctx-size"
        "131072"
        "--parallel"
        "2"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
        # This model's cache only resumes from saved points. Saving one wherever it's
        # useful lets a new chat pick up right before its first message (1.8s
        # instead of 3.7s); each point is ~50MB, so keep a few.
        "--checkpoint-min-step"
        "0"
        "--ctx-checkpoints"
        "8"
        # Answer straight away, without a thinking pass
        "--chat-template-kwargs"
        ''{"enable_thinking":false}''
        # Qwen's settings for that mode
        "--temp"
        "0.7"
        "--top-p"
        "0.8"
        "--top-k"
        "20"
      ];
      Restart = "on-failure";
    };
  };

  # Her voice, also only while Joi is on
  systemd.user.services.joi-speaker = {
    Unit = {
      Description = "Joi's voice";
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${speaker}/bin/joi-speaker";
      Restart = "on-failure";
    };
  };

  # Each time the gateway starts, so her first answer comes quickly
  systemd.user.services.joi-warmup = {
    Unit = {
      Description = "Get Joi's first answer ready";
      After = [
        "hermes-agent.service"
        "llama-server.service"
      ];
      PartOf = [ "hermes-agent.service" ];
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "hermes-agent.service" ];
    # Started counts as done right away, so waking her never waits on it
    Service = {
      Type = "exec";
      ExecStart = "${joiWarmup}/bin/joi-warmup";
    };
  };

  # She falls asleep after a while with nothing to do, to give the memory back
  systemd.user.services.joi-autosleep = {
    Unit.Description = "Put Joi to sleep when she's idle";
    Service = {
      Type = "oneshot";
      ExecStart = "${joiAutosleep}/bin/joi-autosleep";
    };
  };
  systemd.user.timers.joi-autosleep = {
    Unit = {
      Description = "Check whether Joi is idle";
      PartOf = [ "hermes-agent.service" ];
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "hermes-agent.service" ];
    Timer = {
      OnCalendar = "minutely";
      AccuracySec = "10s";
    };
  };

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

  # The gateway also runs only while Joi is on. It exits with 1 when stopped,
  # so that counts as a clean stop; Restart=always still covers real crashes.
  systemd.user.services.hermes-agent = {
    Unit.ConditionPathExists = awakeFile;
    Service.SuccessExitStatus = "1";
  };

  programs.hermes-agent.enable = true;

  services.hermes-agent = {
    enable = true;
    # The gateway serves every character, and Joi's API at /p/joi
    gateway.enable = true;
    # TARS is the default profile
    settings = profileSettings [
      "terminal"
      "file"
      "web"
      "delegation"
      "todo"
      "memory"
      "cronjob"
    ] { };
    hermesHomeFiles = {
      "SOUL.md" = soul "tars";
      "profiles/joi/plugins/laptop/__init__.py" = ./laptop/__init__.py;
      "profiles/joi/plugins/laptop/plugin.yaml" = ./laptop/plugin.yaml;
    }
    // profileFiles;
    environment = {
      API_SERVER_ENABLED = "true";
      API_SERVER_HOST = "127.0.0.1";
      API_SERVER_PORT = toString gatewayPort;
    };
    environmentFiles = [ keyFile ];
    # Joi's tools run these
    extraPackages = [
      pkgs.playerctl
      pkgs.wireplumber
      pkgs.libnotify
      pkgs.xdg-utils
      pkgs.systemd
      pkgs.grim
      pkgs.wl-clipboard
      pkgs.sway
      pkgs.swaynotificationcenter
      pkgs.brightnessctl
      pkgs.power-profiles-daemon
      pkgs.gtk3 # gtk-launch, for open_app
    ];
  };

  # Profile folders, the API key (made once), and the same key in each profile,
  # which Hermes needs to answer at /p/<name>
  home.activation.hermesProfiles =
    lib.hm.dag.entryBetween [ "hermesAgentSetup" ] [ "writeBoundary" ]
      "run ${pkgs.writeShellScript "hermes-profiles" ''
        set -eu
        umask 077
        mkdir -p ${profileDirs}
        if [ ! -s ${keyFile} ]; then
          echo "API_SERVER_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 24)" > ${keyFile}
        fi
        # Add the key to each .env, keeping anything Hermes wrote there
        for profile in ${lib.concatStringsSep " " (builtins.attrNames profiles)}; do
          if ! grep -qs '^API_SERVER_KEY=' "${home}/profiles/$profile/.env"; then
            cat ${keyFile} >> "${home}/profiles/$profile/.env"
          fi
        done
      ''}";

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

  home.packages = characterCommands ++ [
    bubble
    joiPower
    joiMute
  ];

  # Joi lives at the right end of the bottom bar: click to switch her on and off,
  # right-click to mute her voice, middle-click to type to her
  programs.waybar.settings.stats."custom/joi" = {
    exec = "${face}/bin/joi-face";
    return-type = "json";
    on-click = "${joiPower}/bin/joi-power toggle";
    on-click-right = "${joiMute}/bin/joi-mute";
    on-click-middle = "${joiVoice}/bin/joi-voice type";
  };
  programs.waybar.style = lib.mkAfter ''
    /* Room at the screen edge for the note; the pill is placed to rise
       from her middle, so change it in voice.nix too */
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
