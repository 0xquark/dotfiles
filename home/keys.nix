{ lib, pkgs, ... }:
let
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
      "${mod}+n" = "exec makoctl dismiss --all";
      "${mod}+Tab" = "workspace back_and_forth";
      "${mod}+Shift+Escape" = "exec systemctl suspend"; # sleep
      # Laptop keys: volume and brightness
      "XF86AudioRaiseVolume" = "exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
      "XF86AudioLowerVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
      "XF86AudioMute" = "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
      "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";

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
