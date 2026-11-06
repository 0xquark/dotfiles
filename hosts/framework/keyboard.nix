{ ... }:

{
  # Layout on the login screen (Sway sets its own in sway.nix)
  services.xserver.xkb = {
    layout = "us";
    variant = "mac";
  };

  # Mac-style copy and paste: Alt (where Cmd sits on a Mac) + C / V, in every app
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          capslock = "overload(hyper, capslock)"; # hold = Hyper, tap = Caps Lock
        };
        alt = {
          c = "C-insert"; # copy   = Ctrl+Insert (works even in terminals)
          v = "S-insert"; # paste  = Shift+Insert
          a = "C-a"; # select all
        };
        # Leave Alt+Shift+V alone: it's Vicinae's clipboard history
        "alt+shift" = {
          v = "A-S-v";
        };
      };
      # The Hyper layer: while Caps is held, it acts as Ctrl+Alt+Super+Shift
      extraConfig = ''
        [hyper:C-A-M-S]
      '';
    };
  };

  # keyd appears as a new keyboard; this keeps "ignore touchpad while typing" working
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Serial Keyboards]
    MatchUdevType=keyboard
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
  '';
}
