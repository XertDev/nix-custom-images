{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    options = with lib;
      let
        listenerSettingsOptions = {
          allowAnonymous = mkOption {
            type = types.bool;
            default = false;
            description = ''
              If set to true clients that connect without providing a username are allowed to connect.
            '';
          };

          allowZeroLengthClientid = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Generate client if if client connect with zero length client if.
            '';
          };
        };

        listenerOptions = {
          port = mkOption {
            type = types.port;
            default = 1883;
            description = ''
              Listen port.
            '';
          };

          acl = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Acls for listener.
            '';
          };

          settings = mkOption {
            type = types.submodule { options = listenerSettingsOptions; };
            default = { };
            description = ''
              Listener settings
            '';
          };
        };
      in {
        package = mkPackageOption pkgs "mosquitto" { };

        uid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            UID for mosquitto.
          '';
        };
        gid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            GID for mosquitto.
          '';
        };

        logType = mkOption {
          type = types.listOf (types.enum [
            "debug"
            "error"
            "warning"
            "notice"
            "information"
            "subscribe"
            "unsubscribe"
            "websockets"
            "none"
            "all"
          ]);
          default = [ ];
          description = ''
            Log configuration.
          '';
        };

        persistence = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Store messages and subscriptions persistently.
          '';
        };

        listeners = mkOption {
          type = types.listOf (types.submodule { options = listenerOptions; });
          default = [ ];
          description = ''
            Listeners configuration.
          '';
        };
      };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";

        dataDir = "/var/lib/mosquitto";

        logType = lib.strings.concatMapStringsSep "\n" (x: "log_type ${x}")
          config.logType;

        mkAclFile = acls:
          pkgs.writeText "acl.conf" (lib.strings.concatStringsSep "\n" acls);

        listenersConfig = lib.strings.concatMapStringsSep "\n" (listener: ''
          listener ${builtins.toString listener.port}
          acl_file ${mkAclFile listener.acl}

          allow_anonymous ${lib.boolToString listener.settings.allowAnonymous}
          allow_zero_length_clientid ${
            lib.boolToString listener.settings.allowZeroLengthClientid
          }
        '') config.listeners;

        configText = ''
          per_listener_settings true
          persistence ${lib.boolToString config.persistence}

          log_dest stdout
          ${logType}

          ${listenersConfig}
        '';

        configFile = pkgs.writeText "mosquitto.conf" configText;
        configHash = builtins.hashString "md5" configText;

        initScript = pkgs.writeShellApplication {
          name = "mosquitto-entrypoint";
          runtimeInputs = [ config.package ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            #Running preStart hook
            ${config.preStart}

            mosquitto -c "${configFile}"
          '';
        };
      in {
        name = "mosquitto";
        tag = "${config.package.version}-${configHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p ${dataDir}

          chown -R ${UIDGID} ${dataDir}
        '';

        config = {
          User = UIDGID;

          WorkingDir = dataDir;

          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
        };
      };

    tests = [{
      name = "Message sending and receiving";
      config = {
        args = {
          listeners = [{
            acl = [ "pattern readwrite #" ];
            port = 1883;
            settings.allowAnonymous = true;
          }];
        };
        ports = [ "1883:1883" ];
      };
      script = ''
        TMP_DIR=$(mktemp -d)
        TEST_MSG="hello_world"
        trap "rm -f -- $''${TMP_DIR@Q}" EXIT

        ${pkgs.mosquitto}/bin/mosquitto_sub -h localhost -t "test" -C 1 > "$TMP_DIR/sub_out" &
        SUB_PID=$!

        sleep 1

        ${pkgs.mosquitto}/bin/mosquitto_pub -h localhost -t "test" -m "$TEST_MSG"

        wait $SUB_PID
        RECEIVED_MSG=$(cat "$TMP_DIR/sub_out")

        if [ "$RECEIVED_MSG" != "$TEST_MSG" ]; then
          exit 1
        fi

        exit 0
      '';
    }];
  };
}
