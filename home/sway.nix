{ pkgs, ... }:
{
  wayland.windowManager.sway = {
    enable = true;
    package = null;   # use the system Sway, the one SDDM lists

    config = {
      # ── Input ─────────────────────────────────────────
      input = {
        "type:touchpad" = { tap = "enabled"; natural_scroll = "enabled"; dwt = "enabled"; };
        "type:keyboard" = { xkb_layout = "us"; xkb_variant = "mac"; repeat_delay = "250"; repeat_rate = "40"; };
      };

      # ── Display (find the name with: swaymsg -t get_outputs) ──
      output."eDP-1".scale = "2";   # keep whatever value you settled on

      # ── Look: gaps, thin borders, no title bars ─────────
      gaps = { inner = 10; outer = 4; };
      window = { titlebar = false; border = 2; };
      floating = { titlebar = false; border = 2; };

      # ── Bar: Waybar (bar.nix) ───────
      bars = [ { command = "waybar"; } ];

      # ── Started with Sway, and only with Sway ──────────
      startup = [
        # Password pop-ups for admin tasks
        { command = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"; }
        # Notifications
        { command = "mako"; }
        # Lock after 5 min, screen off after 10, lock before sleep
        { command = "swayidle -w timeout 300 'swaylock -f' timeout 600 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"' before-sleep 'swaylock -f'"; }
      ];
    };
  };

  programs.swaylock.enable = true;   # coloured by Stylix

  home.packages = with pkgs; [
    swayidle
    brightnessctl        # brightness keys
    wl-clipboard         # wl-copy, wl-paste
    grim slurp           # screenshots
  ];
}