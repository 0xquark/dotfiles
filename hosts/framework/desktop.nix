{ config, pkgs, ... }:

{
  # ── Login: straight into Sway ─────────────────────
  # Login screen, shown after logging out of Sway
  services.displayManager.sddm.enable = true;
  services.xserver.enable = true; # SDDM's screen runs on X11

  # Boot straight into Sway; it locks itself at start (sway.nix)
  services.displayManager.defaultSession = "sway";
  services.displayManager.autoLogin = {
    enable = true;
    user = "drquark";
  };

  # ── Sway ──────────────────────────────────────────
  programs.sway = {
    enable = true; # adds "Sway" to SDDM's session menu
    wrapperFeatures.gtk = true;
    extraPackages = [ ]; # Home Manager installs tools on sway
  };

  # swaylock: password + Enter, or Enter on an empty field then touch the sensor.
  # Fingerprint is checked after the password (pam_unix is 11700).
  security.pam.services.swaylock = {
    fprintAuth = true;
    rules.auth.fprintd.order = config.security.pam.services.swaylock.rules.auth.unix.order + 50;
  };

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
