{ lib, pkgs, mkImage, ... }: {
  default = mkImage {
    options = with lib; {
      package = mkPackageOption pkgs "tandoor-recipes" { };

      uid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          UID for tandoor.
        '';
      };
      gid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          GID for tandoor.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 5000;
        description = ''
          Port for web interface
        '';
      };
      bind = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = ''
          The address to which the service should bind.
        '';
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = ''
          Additional tandoor configuration.
          Passed as env variables.
        '';
      };
    };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";

        extraConfigEnvs =
          lib.attrsets.mapAttrsToList (key: val: "${key}=${toString val}")
          config.extraConfig;
        extraConfigForHash = lib.strings.concatStrings extraConfigEnvs;

        fullConfigHash = builtins.hashString "md5"
          "${extraConfigForHash}${toString config.port}${config.bind}";

        pkg = config.package;

        mediaRoot = "/var/lib/tandoor-recipes";

        initScript = pkgs.writeShellApplication {
          name = "tandoor-entrypoint";
          runtimeInputs = [ pkg pkg.python.pkgs.gunicorn ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            # Migrate DB
            tandoor-recipes migrate

            #Running preStart hook
            ${config.preStart}

            # Let's run
            gunicorn recipes.wsgi
          '';
        };

      in {
        name = "tandoor";
        tag = "${config.package.version}-${fullConfigHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${mediaRoot}"
          chown -R "${UIDGID}" "${mediaRoot}"
        '';

        config = {
          Env = [
            "GUNICORN_CMD_ARGS=--bind=${config.bind}:${toString config.port}"
            "DEBUG=0"
            "DEBUG_TOOLBAR=0"
            "MEDIA_ROOT=${mediaRoot}"
            "PYTHONPATH=${
              pkg.python.pkgs.makePythonPath pkg.propagatedBuildInputs
            }:${pkg}/lib/tandoor-recipes"
          ] ++ extraConfigEnvs;

          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          WorkingDir = mediaRoot;
          User = UIDGID;
        };
      };
  };
}
