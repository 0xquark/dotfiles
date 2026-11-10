# Joi's voice: Kokoro's Heart, kept loaded while she's awake
{ config, pkgs, ... }:
let
  inherit (import ./shared.nix { inherit config pkgs; }) awakeFile;

  # Warm and natural. Pinned to one revision of the model.
  kokoro =
    let
      file =
        name: sha256:
        pkgs.fetchurl {
          url = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/f3ff3571791e39611d31c381e3a41a3af07b4987/${name}";
          inherit sha256;
        };
    in
    {
      config = file "config.json" "0zy18fdnn68mpqis8jdd1mx9s81y8ihf3z847pq2n1rv83i03fss";
      model = file "kokoro-v1_0.pth" "1r6iibqm6b0zxr3nxzl9zj1h8vi1vkdqiz1fvgrzan0sil8vlva9";
      voice = file "voices/af_heart.pt" "1zxl5h82lf0jggbd0fi56dvsyq2vyyc1vlcwhkyrpcgsiydp1d8a";
    };

  # Keeps the voice loaded while Joi is on, so she starts speaking right away
  speaker = pkgs.writeShellScriptBin "joi-speaker" ''
    export PATH=${pkgs.pipewire}/bin:$PATH
    # Everything it needs is in the Nix store; never reach for Hugging Face
    export HF_HUB_OFFLINE=1
    exec ${
      pkgs.unstable.python3.withPackages (ps: [
        ps.kokoro
        ps.spacy-models.en_core_web_sm
      ])
    }/bin/python3 ${./scripts/speaker.py} ${kokoro.config} ${kokoro.model} ${kokoro.voice}
  '';
in
{
  # Her voice, also only while Joi is on
  systemd.user.services.joi-speaker = {
    Unit = {
      Description = "Joi's voice";
      ConditionPathExists = awakeFile;
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${speaker}/bin/joi-speaker";
      Restart = "on-failure";
    };
  };
}
