{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./battery.nix
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

  # eduVPN (CERN) hands out WireGuard or OpenVPN profiles; NetworkManager needs a plugin for OpenVPN
  networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
  # A full-tunnel WireGuard VPN routes replies by firewall mark, which the strict
  # reverse-path check drops; loose still blocks spoofed addresses
  networking.firewall.checkReversePath = "loose";

  # CERN Kerberos: `kinit` gets a ticket for lxplus, EOS and SSO
  security.krb5 = {
    enable = true;
    settings = {
      libdefaults = {
        default_realm = "CERN.CH";
        forwardable = true; # lets lxplus get AFS/EOS tokens from your ticket
        rdns = false;
        udp_preference_limit = 0; # use TCP, which works better off-site
        ticket_lifetime = "25h";
        renew_lifetime = "120h";
      };
      realms."CERN.CH" = {
        default_domain = "cern.ch";
        kdc = "cerndc.cern.ch";
        admin_server = "cerndc.cern.ch";
        kpasswd_server = "cerndc.cern.ch";
      };
      domain_realm = {
        "cern.ch" = "CERN.CH";
        ".cern.ch" = "CERN.CH";
      };
    };
  };

  # CERN services (CRIC, MONIT, ...) use certificates from CERN's own root CA, which isn't in the default bundle
  security.pki.certificateFiles = [ ./certs/cern-root-ca-2.crt ];

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
    shell = pkgs.zsh;
  };

  # zsh as login shell; Home Manager writes the rest (home/shell.nix)
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false; # Home Manager sets up completion itself
  };
  environment.pathsToLink = [ "/share/zsh" ]; # completions for installed programs

  # ── Nix ───────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true; # stores identical files once
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    # Newest Claude Code instead of the one in stable nixpkgs
    inputs.claude-code.overlays.default
    # pkgs.unstable: unstable nixpkgs, for the few apps that need it (Cursor, in home/apps.nix)
    (_final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = prev.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
    })
  ];

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
  ];

  # The NixOS version first installed here. Keep it as is, even after upgrading.
  system.stateVersion = "26.05";
}
