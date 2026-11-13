{
  config,
  lib,
  pkgs,
  ...
}:
let
  c = config.lib.stylix.colors.withHashtag;

  mod = "Mod4"; # the Framework key (Super),
  alt = "Mod1"; # Alt (Option on a Mac)
  hyper = "Mod4+Mod1+Control+Shift"; # what keyd sends while Caps is held

  noteFile = "$HOME//drquark/oasis/vault/2026/QuickNotes"; # syncs via Syncthing
  noteId = "com.drquark.quicknote"; # the window's name for Sway

  # Show / hide the note; start it if it isn't running yet
  quicknote = pkgs.writeShellScript "quicknote" ''
    if swaymsg -t get_tree | grep -q '"app_id": "${noteId}"'; then
      swaymsg '[app_id="${noteId}"] scratchpad show'
    else
      mkdir -p "$(dirname "${noteFile}")"
      ${pkgs.ghostty}/bin/ghostty --class=${noteId} -e ${pkgs.micro}/bin/micro "${noteFile}" &
    fi
  '';

  # The dimmest the brightness keys go, in percent. Some panels turn the
  # backlight fully off near 0, so raise this if the screen goes black.
  dimmest = "0.1";

  # Brightness keys: steps of 5%, then 1% steps from 5% down to 1%.
  # Below 1% each press halves (or doubles) the raw backlight level, down
  # to `dimmest`. SwayOSD only does whole percents, so brightnessctl sets
  # those levels and SwayOSD just shows the pop-up.
  brightness = pkgs.writeShellScript "brightness" ''
    bctl=${pkgs.brightnessctl}/bin/brightnessctl
    IFS=, read -r _ _ cur _ max < <($bctl -m -c backlight)
    one=$(( max / 100 ))
    floor=$(${pkgs.gawk}/bin/awk -v m="$max" 'BEGIN { f = int(m * ${dimmest} / 100); print (f < 1 ? 1 : f) }')
    pct=$(( cur * 100 / max ))

    fine() {
      $bctl -q -c backlight set "$1"
      swayosd-client --custom-icon display-brightness-symbolic \
        --custom-progress "$(${pkgs.gawk}/bin/awk -v v="$1" -v m="$max" 'BEGIN { print v / m }')" \
        --custom-progress-text "$(${pkgs.gawk}/bin/awk -v v="$1" -v m="$max" 'BEGIN { printf "%.2g%%", v * 100 / m }')"
    }

    if [ "$1" = up ]; then
      if [ "$cur" -lt "$one" ]; then
        new=$(( cur * 2 )); [ "$new" -gt "$one" ] && new=$one
        fine "$new"
      else
        step=+5; [ "$pct" -lt 5 ] && step=+1
        swayosd-client --brightness "$step" --min-brightness 1
      fi
    else
      if [ "$cur" -le "$one" ]; then
        new=$(( cur / 2 )); [ "$new" -lt "$floor" ] && new=$floor
        fine "$new"
      else
        step=-5; [ "$pct" -le 5 ] && step=-1
        swayosd-client --brightness "$step" --min-brightness 1
      fi
    fi
  '';
in
{
  # ── Launcher: Vicinae ────────
  programs.vicinae = {
    enable = true;
    systemd = {
      enable = true; # runs in the background from login, so it opens instantly
      autoStart = true;
    };
  };

  # Media keys control the player you used most recently
  services.playerctld.enable = true;

  # SwayOSD: a small, flat pop-up for volume, brightness and Caps Lock.
  # Icon size (32px) and minimum width (250px) are fixed by SwayOSD itself.
  services.swayosd = {
    enable = true;
    stylePath = pkgs.writeText "swayosd.css" ''
      window#osd {
        border-radius: 6px;
        border: 1px solid ${c.base02};
        background: ${c.base00};
      }
      window#osd #container {
        margin: 6px 14px;
      }
      window#osd image,
      window#osd label {
        color: ${c.base05};
      }
      window#osd progressbar:disabled,
      window#osd image:disabled {
        opacity: 0.5;
      }
      window#osd progressbar,
      window#osd segmentedprogress {
        min-height: 3px;
        border-radius: 2px;
        background: transparent;
        border: none;
      }
      window#osd trough,
      window#osd segment {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${c.base02};
      }
      window#osd progress,
      window#osd segment.active {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${c.base0D};
      }
      window#osd segment {
        margin-left: 8px;
      }
      window#osd segment:first-child {
        margin-left: 0;
      }
    '';
  };

  # swayr: Mac-style window switching (remembers which windows you used last).
  # Its daemon runs as a service; menus open in Vicinae.
  programs.swayr = {
    enable = true;
    systemd.enable = true;
    settings = {
      menu = {
        executable = "vicinae";
        args = [
          "dmenu"
          "--no-quick-look"
          "--placeholder"
          "{prompt}"
        ];
      };
      # Plain text: Vicinae shows markup as-is
      format = {
        window_format = "{urgency_start}{title}{urgency_end}  · {app_name} on {workspace_name}";
        workspace_format = "Workspace {name} on {output_name}";
        container_format = "Container [{layout}] on workspace {workspace_name}";
        output_format = "Output {name}";
        urgency_start = "! ";
        urgency_end = "";
        html_escape = false;
      };
    };
  };

  # ── Sway's keys ─────────────────────────────────────
  wayland.windowManager.sway.config = {
    modifier = mod;
    terminal = "ghostty";
    menu = "vicinae toggle";

    # mkOptionDefault ADDS these to Sway's built-in shortcuts instead of replacing them
    keybindings = lib.mkOptionDefault {
      # Mac-style keybindings
      "${alt}+space" = "exec vicinae toggle";
      "${alt}+Shift+v" = "exec vicinae vicinae://extensions/vicinae/clipboard/history";
      "${mod}+t" = "exec ghostty";
      "${mod}+g" = "exec xdg-open https://www.google.com";
      "${mod}+o" = "exec dolphin";
      "${mod}+q" = "kill";
      "${mod}+Control+q" = "exec swaylock -f";
      "${mod}+Shift+s" = "exec grim -g \"$(slurp)\" - | wl-copy";
      "Print" = "exec grim - | wl-copy";
      "${mod}+n" = "exec swaync-client -t -sw"; # notification centre
      "${mod}+Shift+n" = "exec swaync-client -C -sw"; # clear all notifications
      "${mod}+Tab" = "workspace back_and_forth";
      "${mod}+Shift+Escape" = "exec systemctl suspend"; # sleep
      # Laptop keys: volume and brightness, shown on screen by SwayOSD
      "XF86AudioRaiseVolume" = "exec swayosd-client --output-volume +5 --max-volume 100";
      "XF86AudioLowerVolume" = "exec swayosd-client --output-volume -5";
      "XF86AudioMute" = "exec swayosd-client --output-volume mute-toggle";
      "XF86MonBrightnessUp" = "exec ${brightness} up";
      "XF86MonBrightnessDown" = "exec ${brightness} down";
      "--release Caps_Lock" = "exec swayosd-client --caps-lock"; # after the light has changed

      # Media: play/pause, next, previous (F4–F6)
      "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
      "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
      "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
      "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";

      # Quick note using (hyper(caps) + n))
      "${hyper}+n" = "exec ${quicknote}";

      # Monitors: send the window, or the whole workspace, to the other screen
      "${mod}+${alt}+Left" = "move container to output left";
      "${mod}+${alt}+Right" = "move container to output right";
      "${mod}+${alt}+Shift+Left" = "move workspace to output left";
      "${mod}+${alt}+Shift+Right" = "move workspace to output right";

      # Mac-style app switching
      "${alt}+Tab" = "exec swayr switch-to-urgent-or-lru-window"; # back to the last window
      "${alt}+Shift+Tab" = "exec swayr next-window all-workspaces"; # step through every window
    };
  };
}
