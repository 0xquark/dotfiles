{ lib, pkgs, ... }:
let
  mod = "Mod4";  # Super
in {
  wayland.windowManager.sway = {
    enable = true;
    package = null;  # use the system Sway from programs.sway (the one SDDM knows)
    config = {
      modifier = mod;
    };
  };

  home.packages = with pkgs; [ brightnessctl wl-clipboard grim slurp ];
}