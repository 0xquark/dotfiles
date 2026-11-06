{ pkgs, inputs, ... }:

let
  # Unstable nixpkgs, used only where named below (allowUnfree for Cursor)
  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in

{
  imports = [
    ./hardware-configuration.nix
    ./desktop.nix
    ./keyboard.nix
    ./services.nix
  ];

  # ── Boot ──────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10; # keeps the 1 GB /boot from filling up
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # The community Framework kernel driver currently fails to build on kernel 7.2; re-enable later
  hardware.framework.enableKmod = false;

  # ── Network ───────────────────────────────────────
  networking.hostName = "delorean";
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.macAddress = "permanent";

  # ── Language and time: English, French formats ────
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  # ── User ──────────────────────────────────────────
  users.users.drquark = {
    isNormalUser = true;
    description = "Drquark";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # ── Nix ───────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true; # stores identical files once
  nixpkgs.config.allowUnfree = true;

  # Newest Claude Code instead of the one in stable nixpkgs
  nixpkgs.overlays = [ inputs.claude-code.overlays.default ];

  # nh: nicer rebuilds, shows what changed, and cleans up old generations
  programs.nh = {
    enable = true;
    flake = "/home/drquark/nixos"; # so you never have to type the path
    clean = {
      enable = true; # runs a cleanup once a week
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  # Lets prebuilt Linux binaries run: pip/uv wheels (numpy, torch…), tools Go downloads, editor extensions
  programs.nix-ld.enable = true;

  # ── Apps for every user ───────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    neo
    hyfetch
    firefox-devedition
    unstable.code-cursor
  ];

  # The NixOS version first installed here. Keep it as is, even after upgrading.
  system.stateVersion = "26.05";
}
