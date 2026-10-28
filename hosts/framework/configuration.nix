# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # The community Framework kernel driver currently fails to build on kernel 7.2; re-enable later
  hardware.framework.enableKmod = false;
  
  networking.hostName = "delorean"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Paris";

  # Select internationalisation properties.
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

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # ------- Desktop 1 : KDE Plasma ------
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "mac";
  };

  # -------- Desktop 2: Sway -------
  programs.sway = {
    enable = true;              # adds "Sway" to SDDM's session menu
    wrapperFeatures.gtk = true;
    extraPackages = [ ];        # Home Manager installs tools on sway
  };
  security.polkit.enable = true;
  # swaylock: password only (with fingerprint on, it waits for a finger after you press Enter)
  security.pam.services.swaylock.fprintAuth = false;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    # jack.enable = true;
  };
  hardware.bluetooth.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."drquark" = {
    isNormalUser = true;
    description = "Drquark";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    git
    wget
    neo
    vim
    hyfetch
    firefox-devedition
    code-cursor
   ];

  # Electron and Chromium apps (Cursor, Discord, Helium) run natively on Wayland: sharp, not blurry
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

 # nh: nicer rebuilds, shows what changed, and cleans up old generations
 programs.nh = {
   enable = true;
   flake = "/home/drquark/nixos";   # so you never have to type the path
   clean = {
     enable = true;                 # runs a cleanup once a week
     extraArgs = "--keep-since 7d --keep 5";
   };
 };
  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;
# Mac-style copy and paste: Alt (where Cmd sits on a Mac) + C / V, in every app
services.keyd = {
  enable = true;
  keyboards.default = {
    ids = [ "*" ];
    settings = {
      alt = {
        c = "C-insert";   # copy   = Ctrl+Insert (works even in terminals)
        v = "S-insert";   # paste  = Shift+Insert
	a = "C-a"; # select all
      };
      # Leave Alt+Shift+V alone: it's Vicinae's clipboard history
      "alt+shift" = {
        v = "A-S-v";
      };
    };
  };
};

# keyd appears as a new keyboard; this keeps "ignore touchpad while typing" working
environment.etc."libinput/local-overrides.quirks".text = ''
  [Serial Keyboards]
  MatchUdevType=keyboard
  MatchName=keyd virtual keyboard
  AttrKeyboardIntegration=internal
'';

# Syncthing: syncs the Obsidian vault with the Mac
services.syncthing = {
  enable = true;
  user = "drquark";
  dataDir = "/home/drquark";
  configDir = "/home/drquark/.config/syncthing";
  openDefaultPorts = true;    # lets the Mac connect directly over your Wi-Fi
  overrideDevices = false;    # keep devices and folders you add in the web page
  overrideFolders = false;
};

# Token2 / Keyroost: security-key management
programs.appimage = {
  enable = true;
  binfmt = true;           # lets .AppImage files run directly, like normal programs
};
services.pcscd.enable = true;   # smart-card channel: PIV, OpenPGP, on-device OTP

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  networking.networkmanager.wifi.macAddress = "permanent";
  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}
