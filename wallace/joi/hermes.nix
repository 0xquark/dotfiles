# Hermes: one gateway for every character, their personalities and tools, and
# the `joi`, `darlene`, `caitlyn` and `tars` terminal commands
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
    modelPort
    gatewayPort
    awakeFile
    mutedFile
    handoffs
    keyFile
    joiPower
    joiSleepSoon
    joiMute
    joiRing
    handoff
    ;

  # The official Spotify plugin: login, and the Web API calls behind Joi's play_music
  officialPlugins = pkgs.fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-official-plugins";
    rev = "e7a218f26db88426ab3e7376f0e000b6e356f5e7";
    hash = "sha256-zDjiWUVmWUPAyasy74mUuh+d/dpBi1SBh7GZvuTjxcI=";
  };
  spotifyFiles =
    lib.genAttrs
      [
        "__init__.py"
        "plugin.yaml"
        "spotify_auth.py"
        "spotify_cli.py"
        "spotify_client.py"
        "spotify_tools.py"
      ]
      (
        f:
        # The flake's Hermes reports version 0.0.0, which fails the plugin's minimum-version check
        pkgs.runCommand "spotify-${f}" { }
          "sed '/^requires_hermes:/d' ${officialPlugins}/spotify/${f} > $out"
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
  soul = name: builtins.readFile ./characters/${name}.md + builtins.readFile ./characters/style.md;

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
        # remind, read_aloud, lock_screen and the notes
        ring_command = "${joiRing}/bin/joi-ring";
        muted_file = mutedFile;
        lock_command = "${config.programs.swaylock.package}/bin/swaylock -f";
        notes_file = cfg.notesFile;
      }
      # battery, to charge to full and back
      // lib.optionalAttrs (cfg.chargeLimitCommand != null) {
        charge_command = cfg.chargeLimitCommand;
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

  # `joi`, `darlene` and `caitlyn` chat with that character in the terminal; `tars` is plain `hermes`.
  # They wake the model first if Joi is asleep.
  characterCommand =
    name: args:
    pkgs.writeShellScriptBin name ''
      systemctl --user is-active -q llama-server || ${joiPower}/bin/joi-power on
      exec hermes ${args} "$@"
    '';
  characterCommands = lib.mapAttrsToList (name: _: characterCommand name "-p ${name}") profiles ++ [
    (characterCommand "tars" "")
  ];

  # Hermes expects these in every profile; `hermes profile create` would make them
  profileDirs = lib.concatMapStringsSep " " (
    name: "${home}/profiles/${name}/{cron,sessions,logs,memories,plugins,skills}"
  ) (builtins.attrNames profiles);
in
{
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
      "profiles/joi/plugins/laptop/__init__.py" = ./plugins/laptop/__init__.py;
      "profiles/joi/plugins/laptop/plugin.yaml" = ./plugins/laptop/plugin.yaml;
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

  home.packages = characterCommands;
}
