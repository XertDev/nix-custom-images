{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    options = with lib; {
      package = mkPackageOption pkgs "fava" { };

      uid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          UID for fava
        '';
      };
      gid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          GID for fava.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 5000;
        description = ''
          Port for web interface.
        '';
      };
      bind = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = ''
          The address to which the service should bind.
        '';
      };

      ledgerFile = mkOption {
        type = types.path;
        default = "/var/lib/fava/ledger.beancount";
        description = ''
          Ledger account path
        '';
      };
    };

    image = { config, ... }:
      let
        configAggregated =
          "${config.ledgerFile}${config.bind}${builtins.toString config.port}";
        fullConfigHash = builtins.hashString "md5" configAggregated;

        initScript = pkgs.writeShellApplication {
          name = "fava-entrypoint";
          runtimeInputs = [ pkgs.coreutils config.package ];
          text = ''
            if [ ! -f '${config.ledgerFile}' ]; then
              echo 'Creating initial ledger file: ${config.ledgerFile}';
              touch '${config.ledgerFile}';
            fi

            #Running preStart hook
            ${config.preStart}

            echo 'Starting fava'
            fava ${config.ledgerFile} --host ${config.bind} --port ${
              builtins.toString config.port
            }
          '';
        };

        UIDGID = "${toString config.uid}:${toString config.gid}";
      in {
        name = "fava";
        tag = "${config.package.version}-${fullConfigHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          DATA_DIR=$(dirname '${config.ledgerFile}')
          mkdir -p "$DATA_DIR"
          chown -R "${UIDGID}" "$DATA_DIR"
        '';

        config = {
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          User = "${toString config.uid}:${toString config.gid}";
        };
      };
  };
}
