{ lib, pkgs, ... }:
let
  mod = "Mod4";   # the Framework key (Super), 
  alt = "Mod1";   # Alt (Option on a Mac)
in
{
  # ── Launcher: Vicinae ────────
  programs.vicinae = {
    enable = true;
    systemd = {
      enable = true;      # runs in the background from login, so it opens instantly
      autoStart = true;
    };
  };

  # Media keys control the player you used most recently
  services.playerctld.enable = true;

  # ── Sway's keys ─────────────────────────────────────
  wayland.windowManager.sway.config = {
    modifier = mod;
    terminal = "ghostty";
    menu = "vicinae toggle";

    # mkOptionDefault ADDS these to Sway's built-in shortcuts instead of replacing them
    keybindings = lib.mkOptionDefault {
      # Mac-style keybindings
      "${alt}+space"     = "exec vicinae toggle";
      "${alt}+Shift+v"   = "exec vicinae vicinae://extensions/vicinae/clipboard/history";
      "${mod}+t"         = "exec ghostty";
      "${mod}+g"         = "exec xdg-open https://www.google.com";
      "${mod}+o"         = "exec dolphin";
      "${mod}+q"         = "kill";
      "${mod}+Control+q" = "exec swaylock -f";
      "${mod}+Shift+s"   = "exec grim -g \"$(slurp)\" - | wl-copy";
      "Print"            = "exec grim - | wl-copy";
      "${mod}+n"         = "exec makoctl dismiss --all";
      "${mod}+Tab"       = "workspace back_and_forth";
      "${mod}+Shift+Escape" = "exec systemctl suspend";   # sleep
      # Laptop keys: volume and brightness
      "XF86AudioRaiseVolume"  = "exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
      "XF86AudioLowerVolume"  = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
      "XF86AudioMute"         = "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      "XF86MonBrightnessUp"   = "exec brightnessctl set 5%+";
      "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";

      # Media: play/pause, next, previous (F4–F6)
      "XF86AudioPlay"  = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
      "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
      "XF86AudioNext"  = "exec ${pkgs.playerctl}/bin/playerctl next";
      "XF86AudioPrev"  = "exec ${pkgs.playerctl}/bin/playerctl previous";
    };
  };
}
