{ lib, ... }:

let
  port = 3142;
in
{
  name = "aurral";
  meta.maintainers = with lib.maintainers; [ epireyn ];

  nodes = {
    customized =
      { pkgs, ... }:
      {
        services.aurral = {
          enable = true;
          settings = {
            PORT = port;
          };
        };
      };
  };

  interactive.sshBackdoor.enable = true;
  testScript = ''
    start_all()

    customized.succeed("systemctl restart aurral")
    customized.wait_for_unit("aurral.service")
    customized.wait_for_open_port(${toString port})
    customized.succeed(
        "curl --fail 'http://localhost:${toString port}' | grep -i aurral"
    )
  '';
}
