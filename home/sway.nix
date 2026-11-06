{
  config,
  osConfig,
  pkgs,
  ...
}:
{
  wayland.windowManager.sway = {
    enable = true;
    package = null; # use the system one: SwayFX, from desktop.nix

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

      # SwayFX effects: round corners, soft shadows, blur behind see-through windows
      # (Ghostty is 92% opaque), and a light dim on windows you aren't using
      corner_radius 4
      shadows enable
      shadow_blur_radius 20
      shadow_color #000000A0
      shadow_inactive_color #00000060
      blur enable
      blur_passes 1
      blur_radius 3
      default_dim_inactive 0.1
      dim_inactive_colors.unfocused #000000FF

      # Three-finger swipe: next / previous workspace on this screen, Mac direction
      bindgesture swipe:3:left  workspace next_on_output
      bindgesture swipe:3:right workspace prev_on_output
    '';

    config = {
      # ── Input ─────────────────────────────────────────
      input = {
        "type:touchpad" = {
          tap = "enabled";
          natural_scroll = "enabled";
          dwt = "enabled";
        };
        "type:pointer" = {
          natural_scroll = "enabled";
        }; # mice: scroll inverted
        "type:keyboard" = {
          xkb_layout = "us";
          xkb_variant = "mac";
          repeat_delay = "250";
          repeat_rate = "40";
        };
      };

      # ── Display (find the name with: swaymsg -t get_outputs) ──
      # Laptop on the left, monitor to its right (Sway uses these positions for dragging and moving)
      output."eDP-1" = {
        scale = "2";
        position = "0,0";
      }; # laptop
      output."DP-1" = {
        scale = "1";
        position = "1440,0";
      }; # monitor

      # ── Look: gaps, thin borders, no title bars ─────────
      gaps = {
        inner = 10;
        outer = 4;
      };
      window = {
        titlebar = false;
        border = 2;
        commands = [
          # Quick note: floating, centred, hidden in the scratchpad when not shown
          {
            criteria = {
              app_id = "com.drquark.quicknote";
            };
            command = "floating enable, resize set 720 520, move position center, move scratchpad, scratchpad show";
          }
        ];
      };
      floating = {
        titlebar = false;
        border = 2;
      };

      # ── Bar: Waybar (bar.nix) ───────
      bars = [ { command = "waybar"; } ];

      # ── Started with Sway, and only with Sway ──────────
      startup = [
        # Lock at boot, right after autologin
        { command = "swaylock -f"; }
        # Password pop-ups for admin tasks
        { command = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"; }
        # Notifications
        { command = "mako"; }
        # KDE Connect, with its tray icon
        { command = "kdeconnect-indicator"; }
      ];
    };
  };

  programs.swaylock.enable = true; # coloured by Stylix

  # Idle: dim at 4:50, lock at 5 min, screen off at 10, lock before sleep.
  # Runs as a service, so it restarts if it crashes.
  services.swayidle =
    let
      lock = "${config.programs.swaylock.package}/bin/swaylock -f";
      brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
      swaymsg = "${osConfig.programs.sway.package}/bin/swaymsg";
    in
    {
      enable = true;
      timeouts = [
        {
          timeout = 290;
          command = "${brightnessctl} -s set 10%";
          resumeCommand = "${brightnessctl} -r";
        }
        {
          timeout = 300;
          command = lock;
        }
        {
          timeout = 600;
          command = "${swaymsg} 'output * power off'";
          resumeCommand = "${swaymsg} 'output * power on'";
        }
      ];
      events = {
        before-sleep = lock;
        lock = lock; # loginctl lock-session
      };
    };

  home.packages = with pkgs; [
    brightnessctl # brightness keys
    wl-clipboard # wl-copy, wl-paste
    grim
    slurp # screenshots
  ];
}
