# Wallace, after the company that makes Joi in Blade Runner 2049: the AI on
# this laptop, kept apart from the rest of the config. Joi and the other
# characters (Hermes on a local model), and dictation (Whisper).
# A home-manager module, imported next to ./home in flake.nix.
{ lib, ... }:
{
  imports = [
    ./dictation
    ./joi
  ];

  options.wallace.hyperKey = lib.mkOption {
    type = lib.types.str;
    default = "Mod4+Mod1+Control+Shift";
    description = "Sway's name for Hyper, which keyd sends while Caps is held. Dictation and Joi's keys use it.";
  };
}
