{ pkgs, lib, mkImage, ... }:
let format = pkgs.formats.yaml { };
in {
  default = mkImage {
    options = with lib; {
      package = mkPackageOption pkgs "zigbee2mqtt_2" { };

      uid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          UID for homepage-dashboard
        '';
      };
      gid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          GID for homepage-dashboard
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

      settings = mkOption {
        type = format.type;
        default = { };
        description = ''
          https://www.zigbee2mqtt.io/information/configuration.html
        '';
      };

      externalConverters = mkOption {
        type = with types; listOf package;
        default = [ ];

        description = ''
          List of external converters packages to be loaded.
        '';
      };
    };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";
        configFile = format.generate "zigbee2mqtt" config.settings;

        configFileHash = builtins.hashFile "md5" configFile;
        fullConfigHash = builtins.hashString "md5" ''
          ${toString config.port}${config.bind}${configFileHash}
          ${lib.strings.concatStrings config.externalConverters}
        '';

        dataDir = "/var/lib/zigbee2mqtt";

        initScript = pkgs.writeShellApplication {
          name = "zigbee2mqtt-entrypoint";
          runtimeInputs = [ pkgs.coreutils config.package ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            mkdir -p "${dataDir}"
            if [ ! -f '${dataDir}/configuration.yaml' ]; then
              cp --no-preserve=mode "${configFile}" "${dataDir}/configuration.yaml"
            fi

            rm -rf "${dataDir}/external_converters/"
            mkdir -p "${dataDir}/external_converters"
            ${lib.strings.concatStringsSep "\n" (map (converter:
              "ln -fns '${converter}' '${dataDir}/external_converters/'")
              config.externalConverters)}

            #Running preStart hook
            ${config.preStart}

            # Let's start
            "zigbee2mqtt"
          '';
        };
      in {
        name = "zigbee2mqtt";
        tag = "${config.package.version}-${fullConfigHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${dataDir}"
          chown -R "${UIDGID}" "${dataDir}"
        '';

        config = {
          Env = [ "ZIGBEE2MQTT_DATA=${dataDir}" ];

          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          User = UIDGID;
        };
      };
  };
}
