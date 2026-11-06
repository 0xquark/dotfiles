{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  c = config.lib.stylix.colors;
  # A theme colour moved 10% toward the background, e.g. ff7a1a → e76f18
  dim =
    base:
    let
      mix =
        ch:
        let
          x = lib.toInt c."${base}-rgb-${ch}";
          bg = lib.toInt c."base00-rgb-${ch}";
        in
        lib.fixedWidthString 2 "0" (lib.toHexString ((x * 90 + bg * 10 + 50) / 100));
    in
    "#${mix "r"}${mix "g"}${mix "b"}";
in
{
  imports = [
    inputs.zen-browser.homeModules.beta
    inputs.spicetify-nix.homeManagerModules.spicetify
  ];

  # Keyroost (Token2 key manager): shows up in Vicinae and app menus
  xdg.desktopEntries.keyroost = {
    name = "Keyroost";
    comment = "Manage Token2 and other security keys";
    exec = "/home/drquark/Applications/keyroost.AppImage";
    icon = "security-high";
    categories = [
      "Utility"
      "Security"
    ];
  };
  # ── Browser ──────────────────────────
  programs.zen-browser.enable = true;
  stylix.targets.zen-browser.enable = false; # I theme Zen myself

  # Spotify, coloured by Stylix
  programs.spicetify.enable = true;

  # ── Terminal ─────────────────────────
  programs.ghostty = {
    enable = true;
    settings = {
      window-padding-x = 12;
      window-padding-y = 12;
      cursor-style = "bar";
      confirm-close-surface = false; # close without asking
      # Softer colours than the theme's neon accents (these win over the Stylix theme)
      palette = [
        "1=${dim "base08"}" # red
        "9=${dim "base08"}"
        "2=${dim "base0B"}" # green
        "10=${dim "base0B"}"
        "3=${dim "base0A"}" # yellow
        "11=${dim "base0A"}"
        "4=${dim "base0D"}" # orange (blue slot): folders
        "12=${dim "base0D"}"
        "5=${dim "base0E"}" # magenta
        "13=${dim "base0E"}"
        "6=${dim "base0C"}" # teal
        "14=${dim "base0C"}"
      ];
      keybind = [
        "ctrl+insert=copy_to_clipboard"
        "shift+insert=paste_from_clipboard"
        "ctrl+a=select_all" # Alt+A (via keyd) selects everything
      ];
    };
  };

  # micro: a simple terminal editor
  programs.micro = {
    enable = true;
    settings.autosave = 5; # save automatically every 5 seconds
  };

  # Claude
  programs.claude-code.enable = true;

  # GitHub CLI; also git's HTTPS login for github.com (sign in once with `gh auth login`)
  programs.gh.enable = true;
  programs.git = {
    enable = true; # needed so the gh credential helper lands in ~/.config/git/config
    settings.user = {
      name = "Karanjot Singh";
      email = "drquark@duck.com";
    };
  };

  # ── Editor ───────────────────────────
  programs.neovim = {
    enable = true;
    defaultEditor = true; # used by git commit, sudoedit, etc.
    viAlias = true; # alias for vi
  };

  # ── Other Applications ───────────────
  home.packages = with pkgs; [
    discord
    zoom-us
    obsidian
    element-desktop
    calcurse
    go
    gopls # Go language server, for Cursor and Neovim
    python3
    uv # fast Python package and venv manager (pip replacement)

    # KDE apps: files, images, PDFs, archives
    kdePackages.dolphin
    kdePackages.kio-extras # Dolphin: phones (MTP), network places, thumbnails
    kdePackages.kdegraphics-thumbnailers # PDF and image previews
    kdePackages.ffmpegthumbs # video previews
    kdePackages.gwenview
    kdePackages.okular
    kdePackages.ark
    kdePackages.kate
  ];
}
