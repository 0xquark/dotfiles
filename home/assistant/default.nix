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

  # Qwen3.5 4B: small, fast on the Arc GPU, and calls tools reliably
  model = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf";
    sha256 = "190ixxlzpl8012kkhfb02f9nzns9c0a22n25c8z4csszzy37kzh0";
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
    joi = profileSettings [ "web" "laptop" ] {
      plugins.enabled = [
        "laptop"
        "spotify"
      ];
      # Naming each chat costs a second model call per question
      auxiliary.title_generation.enabled = false;
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
        systemctl --user start llama-server hermes-agent
      }
      off() {
        rm -f ${awakeFile}
        systemctl --user stop hermes-agent llama-server
      }
      case "''${1:-toggle}" in
        on) on ;;
        off) off ;;
        toggle) if systemctl --user is-active -q hermes-agent; then off; else on; fi ;;
      esac
    '';
  };

  # Hold to talk: the pill rises out of Joi's face, the reply comes in a bubble
  joiVoice = pkgs.writeShellApplication {
    name = "joi-voice";
    text = ''
      activity="$XDG_RUNTIME_DIR/joi/activity"
      mkdir -p "$XDG_RUNTIME_DIR/joi"
      case "''${1:-}" in
        start)
          # Talking to her wakes her up; the bubble waits for the model
          systemctl --user is-active -q hermes-agent || ${joiPower}/bin/joi-power on
          echo listening > "$activity"
          exec dictate start joi
          ;;
        stop)
          echo thinking > "$activity"
          dictate stop ${bubble}/bin/joi-bubble
          # Nothing was said, so there's no bubble to finish the turn
          if grep -qx thinking "$activity"; then echo ready > "$activity"; fi
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
        --set JOI_BG "${c.base00}"
        --set JOI_BORDER "${c.base02}"
        --set JOI_FG "${c.base05}"
        --set JOI_DIM "${c.base04}"
      )
    '';
  };

  # Her face in the bar
  face = pkgs.writeShellScriptBin "joi-face" ''
    export PATH=${pkgs.systemd}/bin:${pkgs.playerctl}/bin:$PATH
    export JOI_HEALTH="${health}"
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
        # Hermes wants at least 64k of context
        "--ctx-size"
        "65536"
        "--parallel"
        "1"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
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

  # The gateway also runs only while Joi is on
  systemd.user.services.hermes-agent.Unit.ConditionPathExists = awakeFile;

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
    ];
  };

  # Profile folders, the API key (made once), and the same key for Joi's profile
  home.activation.hermesProfiles =
    lib.hm.dag.entryBetween [ "hermesAgentSetup" ] [ "writeBoundary" ]
      "run ${pkgs.writeShellScript "hermes-profiles" ''
        set -eu
        umask 077
        mkdir -p ${profileDirs}
        if [ ! -s ${keyFile} ]; then
          echo "API_SERVER_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 24)" > ${keyFile}
        fi
        # Add the key to Joi's .env, keeping anything Hermes wrote there
        if ! grep -qs '^API_SERVER_KEY=' ${home}/profiles/joi/.env; then
          cat ${keyFile} >> ${home}/profiles/joi/.env
        fi
      ''}";

  home.packages = characterCommands ++ [
    bubble
    joiPower
  ];

  # Joi lives at the right end of the bottom bar: click to switch her on and off
  programs.waybar.settings.stats."custom/joi" = {
    exec = "${face}/bin/joi-face";
    return-type = "json";
    on-click = "${joiPower}/bin/joi-power toggle";
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
  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "--no-repeat ${hyper}+space" = "exec ${joiVoice}/bin/joi-voice start";
    "--release ${hyper}+space" = "exec ${joiVoice}/bin/joi-voice stop";
  };
}
