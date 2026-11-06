{ ... }:

{
  # ── Sound, Bluetooth, printing ────────────────────
  security.rtkit.enable = true; # realtime priority for PipeWire, so audio doesn't crackle
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  hardware.bluetooth.enable = true;
  services.printing.enable = true;

  # ── Sync and apps from outside nixpkgs ────────────
  # Syncthing: syncs the Obsidian vault with the Mac
  services.syncthing = {
    enable = true;
    user = "drquark";
    dataDir = "/home/drquark";
    configDir = "/home/drquark/.config/syncthing";
    openDefaultPorts = true; # lets the Mac connect directly over your Wi-Fi
    overrideDevices = false; # keep devices and folders you add in the web page
    overrideFolders = false;
  };

  # Flatpak, for the odd app that isn't safely packaged in nixpkgs (e.g. Stremio)
  services.flatpak.enable = true;

  # Token2 / Keyroost: security-key management
  programs.appimage = {
    enable = true;
    binfmt = true; # lets .AppImage files run directly, like normal programs
  };
  services.pcscd.enable = true; # smart-card channel: PIV, OpenPGP, on-device OTP
}
