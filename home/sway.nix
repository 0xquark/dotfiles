{ pkgs, ... }:
{
  wayland.windowManager.sway = {
    enable = true;
    package = null;   # use the system Sway, the one SDDM lists

    extraConfig = ''
      # Lid closed: switch the laptop screen off; Sway moves its workspaces to the monitor
      bindswitch --reload --locked lid:on  output eDP-1 disable
      # Lid opened: switch it back on
      bindswitch --reload --locked lid:off output eDP-1 enable
      # 1–6 live on the monitor; 7–9 live on the laptop, but join the monitor while the lid is shut
      workspace 1 output DP-1 eDP-1
      workspace 2 output DP-1 eDP-1
      workspace 3 output DP-1 eDP-1
      workspace 4 output DP-1 eDP-1
      workspace 5 output DP-1 eDP-1
      workspace 6 output DP-1 eDP-1
      workspace 7 output eDP-1 DP-1
      workspace 8 output eDP-1 DP-1
      workspace 9 output eDP-1 DP-1
    '';

    config = {
      # ── Input ─────────────────────────────────────────
      input = {
        "type:touchpad" = { tap = "enabled"; natural_scroll = "enabled"; dwt = "enabled"; };
        "type:pointer"  = { natural_scroll = "enabled"; };   # mice: scroll inverted
	"type:keyboard" = { xkb_layout = "us"; xkb_variant = "mac"; repeat_delay = "250"; repeat_rate = "40"; };
      };

      # ── Display (find the name with: swaymsg -t get_outputs) ──
      # Laptop on the left, monitor to its right (Sway uses these positions for dragging and moving)
      output."eDP-1"  = { scale = "2"; position = "0,0"; };       #laptop
      output."DP-1"   = { scale = "1"; position = "1440,0"; };    #monitor

      # ── Look: gaps, thin borders, no title bars ─────────
      gaps = { inner = 10; outer = 4; };
      window = {
        titlebar = false;
        border = 2;
        commands = [
          # Quick note: floating, centred, hidden in the scratchpad when not shown
          {
            criteria = { app_id = "com.drquark.quicknote"; };
            command = "floating enable, resize set 720 520, move position center, move scratchpad, scratchpad show";
          }
        ];
      };
      floating = { titlebar = false; border = 2; };

      # ── Bar: Waybar (bar.nix) ───────
      bars = [ { command = "waybar"; } ];

      # ── Started with Sway, and only with Sway ──────────
      startup = [
        # Lock right after autologin at boot (only on start, not on config reload)
        { command = "swaylock -f"; }
        # Password pop-ups for admin tasks
        { command = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"; }
        # Notifications
        { command = "mako"; }
        # KDE Connect: tray icon in Waybar; also starts the background service
        { command = "kdeconnect-indicator"; }
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
