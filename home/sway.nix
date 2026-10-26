{ lib, pkgs, ... }:
let
  mod = "Mod4";  # Super
in {
  wayland.windowManager.sway = {
    enable = true;
    package = null;  # use the system Sway from programs.sway (the one SDDM knows)
    config = {
      modifier = mod;
      terminal = "alacritty";
      input = {
        "type:touchpad" = { tap = "enabled"; natural_scroll = "enabled"; dwt = "enabled"; };
        "type:keyboard" = { xkb_layout = "us"; xkb_variant = "mac"; repeat_delay = "250"; repeat_rate = "40"; };
      };
      # Find your panel name with: swaymsg -t get_outputs
      output."eDP-1".scale = "2";
      keybindings = lib.mkOptionDefault {
        # Laptop keys
        "XF86AudioRaiseVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        "XF86AudioLowerVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        "XF86AudioMute" = "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
      };
    };
  };

  home.packages = with pkgs; [ brightnessctl wl-clipboard grim slurp ];
}