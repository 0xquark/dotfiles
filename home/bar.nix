{ lib, pkgs, ... }:
let
  # Pop-up for a bar click: opens next to the mouse, closes on a second click
  # or when another window takes focus
  popup = pkgs.writeShellScript "waybar-popup" ''
    id=$1; shift
    if swaymsg -t get_tree | grep -q "\"app_id\": \"$id\""; then
      swaymsg "[app_id=\"$id\"] kill"
      exit
    fi
    swaymsg -m -t subscribe '["window"]' \
      | ${pkgs.jq}/bin/jq --unbuffered -r 'select(.change == "focus" or .change == "close") | "\(.change) \(.container.app_id)"' \
      | while read -r change app; do
          case "$change $app" in
            "focus $id" | "focus org.kde.polkit-kde-authentication-agent-1") ;;   # itself, or a password prompt it asked for
            "close $id") break ;;
            focus*) swaymsg "[app_id=\"$id\"] kill"; break ;;
          esac
        done &
    exec "$@"
  '';

  # Terminal apps get their own window name, so Sway can tell them apart
  termPopup = id: cmd: "${popup} ${id} ghostty --class=${id} -e ${cmd}";

  # Window names, sizes, and which bar each one drops from
  popups = {
    "com.drquark.popup.network"   = { w = 560; h = 460; bar = "top"; };
    "com.drquark.popup.bluetooth" = { w = 640; h = 460; bar = "top"; };
    "org.pulseaudio.pavucontrol"  = { w = 560; h = 480; bar = "top"; };
    "com.drquark.popup.btop"      = { w = 900; h = 560; bar = "bottom"; };
  };
in
{
  # Floating, sized, placed under the mouse, then nudged clear of the bar
  wayland.windowManager.sway.config.window.commands = lib.mapAttrsToList (id: p: {
    criteria = { app_id = id; };
    command = "floating enable, resize set ${toString p.w} ${toString p.h}, move position mouse, "
      + (if p.bar == "top" then "move down 40 px" else "move up 34 px");
  }) popups;

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
        on-click = "${popup} org.pulseaudio.pavucontrol pavucontrol";
      };
      network = {
        format-wifi = "NET {essid}";
        format-ethernet = "NET WIRED";
        format-disconnected = "NET OFF";
        tooltip-format = "{ipaddr}";
        on-click = termPopup "com.drquark.popup.network" "nmtui";
      };
      bluetooth = {
        format = "BT {status}";
        format-connected = "BT {device_alias}";
        on-click = termPopup "com.drquark.popup.bluetooth" "bluetui";
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
      modules-center = [ "mpris" ];
      
      # Now playing: Spotify, or whichever player was used last
      mpris = {
        format        = "NOW {dynamic}";                 # e.g. NOW Meltdown - Clint Mansell
        format-paused = "PAUSED {dynamic}";
        dynamic-order = [ "title" "artist" ];            # what to show, in this order
        dynamic-len   = 40;                              # shorten long titles
        tooltip-format = "{player}: {title} - {artist} ({album})";
        on-click       = "${pkgs.playerctl}/bin/playerctl play-pause";
        on-click-right = "${pkgs.playerctl}/bin/playerctl next";
        on-scroll-up   = "${pkgs.playerctl}/bin/playerctl previous";
      };  
      cpu = {
        format = "CPU {usage}%";
        interval = 2;
        on-click = termPopup "com.drquark.popup.btop" "btop";
      };
      memory = {
        format = "RAM {percentage}%";
        interval = 5;
        on-click = termPopup "com.drquark.popup.btop" "btop";
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
