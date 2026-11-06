{
  config,
  lib,
  pkgs,
  ...
}:

let
  # SDDM used to set the session type; Chromium-based apps read it to pick Wayland
  sway = "env XDG_SESSION_TYPE=wayland ${config.programs.sway.package}/bin/sway";
in

{
  # ── Login: greetd ─────────────────────────────────
  # Boot straight into Sway; it locks itself at start (sway.nix).
  # After logging out, tuigreet asks for a password in the terminal.
  services.greetd = {
    enable = true;
    useTextGreeter = true; # keeps boot messages off the login screen
    settings = {
      initial_session = {
        user = "drquark";
        command = sway;
      };
      default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --cmd '${sway}'";
    };
  };

  # ── Sway ──────────────────────────────────────────
  programs.sway = {
    enable = true;
    # SwayFX: Sway plus rounded corners, blur and shadows (effects in home/sway.nix)
    package = pkgs.swayfx;
    wrapperFeatures.gtk = true;
    extraPackages = [ ]; # Home Manager installs tools on sway
  };

  # swaylock and greetd: password + Enter, or Enter on an empty field then touch the sensor.
  # Fingerprint is checked after the password (pam_unix is 11700).
  security.pam.services = lib.genAttrs [ "swaylock" "greetd" ] (name: {
    fprintAuth = true;
    rules.auth.fprintd.order = config.security.pam.services.${name}.rules.auth.unix.order + 50;
  });

  # Electron and Chromium apps (Cursor, Discord, Helium) run natively on Wayland: sharp, not blurry
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ── Desktop services ──────────────────────────────
  # Power profiles for Waybar's button; upower for battery info
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # App menu for Dolphin's "Open with" list
  environment.etc."xdg/menus/applications.menu".source =
    "${pkgs.gnome-menus}/etc/xdg/menus/gnome-applications.menu";

  # KDE Wallet: keeps app passwords, asks for its own password once per boot
  environment.systemPackages = with pkgs; [
    kdePackages.kwallet
    kdePackages.kwalletmanager
    # Starts the wallet when an app asks for it
    (writeTextDir "share/dbus-1/services/org.freedesktop.secrets.service" ''
      [D-BUS Service]
      Name=org.freedesktop.secrets
      Exec=${kdePackages.kwallet}/bin/ksecretd
    '')
  ];

  # KDE Connect: phone notifications, file sharing, clipboard (opens its firewall ports)
  programs.kdeconnect = {
    enable = true;
    package = pkgs.kdePackages.kdeconnect-kde;
  };
}
