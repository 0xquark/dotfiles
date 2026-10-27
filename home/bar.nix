{ lib, pkgs, ... }:
{
  # ── Waybar: the top bar ─────────────────────────────
  programs.waybar = {
    enable = true;
    settings.main = {
      layer = "top";
      position = "top";
      height = 30;
      spacing = 4;

      modules-left   = [ "sway/workspaces" "sway/mode" "sway/window" ];
      modules-center = [ "clock" ];
      modules-right  = [ "tray" "power-profiles-daemon" "network" "bluetooth" "pulseaudio" "backlight" "battery" ];

      # Text labels instead of icon glyphs: nothing to render as boxes, and it suits the HUD look
      "sway/window".max-length = 60;
      clock = {
        format = "{:%a %d %b  %H:%M}";
        tooltip-format = "<tt>{calendar}</tt>";
      };
      battery = {
        states = { warning = 25; critical = 10; };
        format = "PWR {capacity}%";
        format-charging = "CHG {capacity}%";
        format-plugged = "AC {capacity}%";
      };
      backlight.format = "BRT {percent}%";
      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "VOL MUTE";
        on-click = "pavucontrol";
      };
      network = {
        format-wifi = "NET {essid}";
        format-ethernet = "NET WIRED";
        format-disconnected = "NET OFF";
        tooltip-format = "{ipaddr}";
        on-click = "ghostty -e nmtui";
      };
      bluetooth = {
        format = "BT {status}";
        format-connected = "BT {device_alias}";
        on-click = "ghostty -e bluetui";
      };
      power-profiles-daemon = {
        format = "{icon}";
        format-icons = { default = "BAL"; performance = "PERF"; balanced = "BAL"; power-saver = "ECO"; };
      };
      tray.spacing = 8;
    };

    settings.stats = {
      layer = "top";
      position = "bottom";
      height = 26;
      spacing = 4;

      modules-left  = [ "cpu" "memory" "temperature" "disk" ];
      modules-right = [ "network#speed" ];

      cpu = {
        format = "CPU {usage}%";
        interval = 2;
        on-click = "ghostty -e btop";
      };
      memory = {
        format = "RAM {percentage}%";
        interval = 5;
        on-click = "ghostty -e btop";
      };
      temperature = {
        format = "TMP {temperatureC}°C";
        critical-threshold = 85;
      };
      disk = {
        format = "DSK {percentage_used}%";
        path = "/";
      };
      "network#speed" = {
        format = "DN {bandwidthDownBytes}  UP {bandwidthUpBytes}";
        interval = 2;
      };
    };

    # Stylix writes the colours; this only adds the lettering on top
    style = lib.mkAfter ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        letter-spacing: 1px;
      }
    '';
  };

  # ── mako: notifications ─────────────────────────────
  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000;   # milliseconds
      anchor = "top-right";
      border-size = 2;
      border-radius = 6;
    };
  };

  # Opened by clicking the bar's sound and Bluetooth labels
  home.packages = with pkgs; [ pavucontrol bluetui ];

  # btop: opened by clicking CPU or RAM in the bottom bar (coloured by Stylix)
  programs.btop.enable = true;
}