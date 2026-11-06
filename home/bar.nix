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

  # Battery charge limit: shows it in the bar, and switches between 80% and 100% on click
  # The laptop's controller keeps the limit; framework_tool sets it (sudo rule in battery.nix).
  # Reading it needs root too, so the last value set is kept in a file; every boot starts at 80.
  chargeLimit = pkgs.writeShellScript "charge-limit" ''
    state="$XDG_RUNTIME_DIR/charge-limit"
    now=$(cat "$state" 2>/dev/null || echo 80)
    if [ "$1" = toggle ]; then
      if [ "$now" -le 80 ]; then new=100; else new=80; fi
      /run/wrappers/bin/sudo -n ${pkgs.framework-tool}/bin/framework_tool --charge-limit "$new" >/dev/null \
        && echo "$new" > "$state"
      pkill -RTMIN+8 waybar   # refresh the bar right away
      exit
    fi
    if [ "$now" -le 80 ]; then
      echo '{"text": "LIM 80%", "tooltip": "Battery stops at 80%. Click to charge to 100%.", "class": "limited"}'
    else
      echo '{"text": "LIM OFF", "tooltip": "Charging to 100%. Click to stop at 80%.", "class": "full"}'
    fi
  '';

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
        format-muted = "VOL MUTE";
        on-click = "${popup} org.pulseaudio.pavucontrol pavucontrol";
      };
      network = {
        format-wifi = "NET {essid}";
        format-ethernet = "NET WIRED";
        format-disconnected = "NET OFF";
        max-length = 12; # long names end in "…"; hover for the full one
        tooltip-format = "{ipaddr}";
        tooltip-format-wifi = "{essid} ({signalStrength}%)  {ipaddr}";
        on-click = termPopup "com.drquark.popup.network" "nmtui";
      };
      bluetooth = {
        format = "BT {status}";
        format-connected = "BT {device_alias}";
        max-length = 12;
        tooltip-format-connected = "{device_alias}";
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
      /* Green while the battery is protected; full charge stands out, so it isn't left on by accident */
      #custom-charge-limit.limited {
        color: @base0B;
      }
      #custom-charge-limit.full {
        color: @base09;
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
