{ ... }: {
  imports = [ ./sway.nix ./keys.nix ./apps.nix ./shell.nix ];

  home.username = "drquark";
  home.homeDirectory = "/home/drquark";
  home.stateVersion = "26.05";  # matches system.stateVersion; never bump it casually
  programs.home-manager.enable = true;
}
