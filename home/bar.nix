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

  # Battery charge limit, in the bar; Joi's battery tool shares it
  chargeLimit = import ./charge-limit.nix { inherit pkgs; };

  # CERN VPN on/off, in the bar
  vpn = import ./vpn.nix { inherit pkgs; };

  # Window names, sizes, and which bar each one drops from
  popups = {
    "com.drquark.popup.network" = {
      w = 560;
      h = 460;
      bar = "top";
    };
    "com.drquark.popup.bluetooth" = {
      w = 640;
      h = 460;
      bar = "top";
    };
    "org.pulseaudio.pavucontrol" = {
      w = 560;
      h = 480;
      bar = "top";
    };
    "com.drquark.popup.btop" = {
      w = 900;
      h = 560;
      bar = "bottom";
    };
  };
in
{
  # Floating, sized, placed under the mouse, then nudged clear of the bar
  wayland.windowManager.sway.config.window.commands = lib.mapAttrsToList (id: p: {
    criteria = {
      app_id = id;
    };
    command =
      "floating enable, resize set ${toString p.w} ${toString p.h}, move position mouse, "
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

      modules-left = [
        "sway/workspaces"
        "sway/mode"
        "sway/window"
      ];
      modules-center = [ "clock" ];
      modules-right = [
        "tray"
        "power-profiles-daemon"
        "custom/vpn"
        "network"
        "bluetooth"
        "pulseaudio"
        "backlight"
        "battery"
        "custom/notifications"
      ];

      # Notification count; click for the notification centre, right-click for Do Not Disturb
      "custom/notifications" = {
        exec = "swaync-client --subscribe-waybar";
        return-type = "json";
        format = "{icon} {}"; # e.g. NTF 3, or DND 3 while muted
        format-icons = {
          none = "NTF";
          notification = "NTF";
          inhibited-none = "NTF";
          inhibited-notification = "NTF";
          dnd-none = "DND";
          dnd-notification = "DND";
          dnd-inhibited-none = "DND";
          dnd-inhibited-notification = "DND";
        };
        on-click = "swaync-client -t -sw";
        on-click-right = "swaync-client -d -sw";
        escape = true;
      };

      # Text labels instead of icon glyphs: nothing to render as boxes, and it suits the HUD look
      "sway/window".max-length = 60;
      clock = {
        format = "{:%a %d %b  %H:%M}";
        tooltip-format = "<tt>{calendar}</tt>";
      };
      battery = {
        states = {
          warning = 25;
          critical = 10;
        };
        format = "PWR {capacity}%";
        format-charging = "CHG {capacity}%";
        format-plugged = "AC {capacity}%";
      };
      backlight.format = "BRT {percent}%";
      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "VOL"; # dimmed while muted
        on-click = "${popup} org.pulseaudio.pavucontrol pavucontrol";
      };
      # Click to connect or disconnect; right-click for the eduVPN window
      "custom/vpn" = {
        exec = "${vpn}";
        return-type = "json";
        interval = 5;
        signal = 9;
        on-click = "${vpn} toggle";
        on-click-right = "${pkgs.eduvpn-client}/bin/eduvpn-gui";
      };
      # Short states in the bar; hover for names. On and off show as colour.
      network = {
        format-wifi = "NET {signalStrength}%";
        format-ethernet = "NET WIRED";
        format-disconnected = "NET";
        tooltip-format = "{ipaddr}";
        tooltip-format-wifi = "{essid} ({signalStrength}%)  {ipaddr}";
        on-click = termPopup "com.drquark.popup.network" "nmtui";
      };
      bluetooth = {
        format = "BT";
        format-connected = "BT {num_connections}"; # e.g. BT 1
        tooltip-format-connected = "{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}";
        on-click = termPopup "com.drquark.popup.bluetooth" "bluetui";
      };
      power-profiles-daemon = {
        format = "{icon}";
        format-icons = {
          default = "BAL";
          performance = "PERF";
          balanced = "BAL";
          power-saver = "ECO";
        };
      };
      tray.spacing = 8;
    };

    settings.stats = {
      layer = "top";
      position = "bottom";
      height = 26;
      spacing = 4;

      modules-left = [
        "cpu"
        "memory"
        "temperature"
        "disk"
      ];
      modules-right = [
        "custom/charge-limit"
        "network#speed"
        # Joi adds her face after these (wallace/joi/desktop.nix)
      ];
      modules-center = [ "mpris" ];

      # Now playing: Spotify, or whichever player was used last
      mpris = {
        format = "NOW {dynamic}"; # e.g. NOW Meltdown - Clint Mansell
        format-paused = "PAUSED {dynamic}";
        dynamic-order = [
          "title"
          "artist"
        ]; # what to show, in this order
        dynamic-len = 40; # shorten long titles
        tooltip-format = "{player}: {title} - {artist} ({album})";
        on-click = "${pkgs.playerctl}/bin/playerctl play-pause";
        on-click-right = "${pkgs.playerctl}/bin/playerctl next";
        on-scroll-up = "${pkgs.playerctl}/bin/playerctl previous";
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
      # Click: 80% limit for days at the desk, 100% before a day out
      "custom/charge-limit" = {
        exec = "${chargeLimit}";
        return-type = "json";
        interval = 60;
        signal = 8;
        on-click = "${chargeLimit} toggle";
      };
    };

    # Stylix writes the colours; this only adds the lettering on top
    style = lib.mkAfter ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        letter-spacing: 1px;
      }
      /* Same padding Stylix gives the built-in labels, so the gaps match */
      #tray,
      #power-profiles-daemon,
      #mpris,
      #custom-vpn,
      #custom-notifications,
      #custom-charge-limit {
        padding: 0 5px;
      }
      /* Green while the battery is protected; full charge stands out, so it isn't left on by accident */
      #custom-charge-limit.limited {
        color: @base0B;
      }
      #custom-charge-limit.full {
        color: @base09;
      }
      /* Switches read like the VPN: green while on, dimmed while off */
      #bluetooth.on,
      #bluetooth.connected {
        color: @base0B;
      }
      #bluetooth.off,
      #bluetooth.disabled,
      #network.disconnected,
      #pulseaudio.muted {
        color: @base03;
      }
      /* Green while the VPN is up, dimmed while it's off */
      #custom-vpn.on {
        color: @base0B;
      }
      #custom-vpn.off {
        color: @base03;
      }
      #custom-vpn.busy {
        color: @base0A;
      }
      /* Lights up while something is waiting; orange while Do Not Disturb is on */
      #custom-notifications.notification {
        color: @base0A;
      }
      #custom-notifications.dnd-none,
      #custom-notifications.dnd-notification {
        color: @base09;
      }
    '';
  };

  # ── swaync: notifications, and a centre that slides in from the right ──
  # Coloured by Stylix
  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";
      timeout = 5; # seconds
      timeout-low = 3;
      timeout-critical = 0; # stays until dismissed
      control-center-margin-top = 8;
      control-center-margin-right = 8;
      control-center-margin-bottom = 8;
      hide-on-clear = true;
      notification-window-width = 360;
      notification-icon-size = 32;
      widgets = [
        "title"
        "dnd"
        "mpris"
        "notifications"
      ];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear all";
        };
        dnd.text = "Do Not Disturb";
        mpris.image-size = 64;
      };
    };
    # Small, quiet notifications: one thin border, small icon, tighter text.
    # Matte music player: a flat card, without the blurred cover behind it or shadows.
    style = lib.mkAfter ''
      :root {
        --notification-icon-size: 32px;
        --font-size-summary: 13px;
        --font-size-body: 12px;
        --border-radius: 6px;
      }
      .notification-row,
      .notification-row .notification-background {
        outline: none;
        border: none;
        box-shadow: none;
      }
      .notification-row .notification-background {
        padding: 3px 8px;
      }
      .notification-row .notification-background .notification {
        box-shadow: none;
        border-radius: 6px;
        background: @base00;
      }
      .notification-row .notification-background .notification.low,
      .notification-row .notification-background .notification.normal {
        border: 1px solid @base03;
      }
      .notification-row .notification-background .notification .notification-content {
        border: none;
        padding: 2px;
        background: transparent;
      }
      .notification-row .notification-background .notification .notification-default-action {
        padding: 4px;
      }
      .notification-content .app-icon {
        -gtk-icon-size: 0;
        margin: 0;
      }
      .notification-content .text-box .time {
        font-size: 11px;
        margin-right: 24px;
      }

      .widget-mpris .widget-mpris-player {
        box-shadow: none;
        border-radius: 6px;
      }
      .widget-mpris .widget-mpris-player .mpris-background {
        opacity: 0;
      }
      .widget-mpris .widget-mpris-player .mpris-overlay {
        background-color: @base01;
      }
      .widget-mpris .widget-mpris-player .widget-mpris-album-art {
        box-shadow: none;
        border-radius: 4px;
      }
    '';
  };

  # Opened by clicking the bar's sound and Bluetooth labels
  home.packages = with pkgs; [
    pavucontrol
    bluetui
  ];

  # btop: opened by clicking CPU or RAM in the bottom bar (coloured by Stylix)
  programs.btop.enable = true;
}
