{ pkgs, ... }:
let
  framework_tool = "${pkgs.framework-tool}/bin/framework_tool";
in
{
  # The battery charge limit lives in the laptop's embedded controller (EC).
  # framework_tool sets it with Framework's own command; this EC ignores the
  # kernel's generic limit (cros_charge_control), so that one stays off.
  environment.systemPackages = [ pkgs.framework-tool ];

  # Charge to 80% from every boot. The bottom bar's LIM button switches to 100% and back.
  systemd.services.battery-charge-limit = {
    description = "Battery charge limit: 80%";
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false; # a rebuild keeps whatever the LIM button set
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # The EC device can show up a little after boot
      for _ in $(seq 30); do
        [ -e /dev/cros_ec ] && break
        sleep 1
      done
      ${framework_tool} --charge-limit 80
    '';
  };

  # Lets the LIM button set 80% or 100% without a password; nothing else
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands =
        map
          (limit: {
            command = "${framework_tool} --charge-limit ${limit}";
            options = [ "NOPASSWD" ];
          })
          [
            "80"
            "100"
          ];
    }
  ];
}
