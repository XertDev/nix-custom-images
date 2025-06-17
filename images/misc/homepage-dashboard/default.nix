{ pkgs, lib, mkImage, gnused, ... }:
let format = pkgs.formats.yaml { };
in {
  default = mkImage {
    options = with lib; {
      package = mkPackageOption pkgs "homepage-dashboard" { };

      uid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          UID for homepage-dashboard.
        '';
      };
      gid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          GID for homepage-dashboard.
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

      allowedHosts = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Allowed external addresses.
        '';
      };

      bookmarks = mkOption {
        type = format.type;
        default = [ ];
        description = ''
          See <https://gethomepage.dev/configs/bookmarks/>.
        '';
      };

      services = mkOption {
        type = format.type;
        default = [ ];
        description = ''
          See <https://gethomepage.dev/configs/services/>.
        '';
      };

      widgets = mkOption {
        type = format.type;
        default = [ ];
        description = ''
          See <https://gethomepage.dev/widgets/>.
        '';
      };

      kubernetes = mkOption {
        type = format.type;
        default = { };
        description = ''
          See <https://gethomepage.dev/configs/kubernetes/>.
        '';
      };

      docker = mkOption {
        type = format.type;
        default = { };
        description = ''
          See <https://gethomepage.dev/configs/kubernetes/>.
        '';
      };

      settings = mkOption {
        type = format.type;
        default = { };
        description = ''
          See <https://gethomepage.dev/configs/settings/>.
        '';
      };
    };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";

        configFiles = [
          (format.generate "bookmarks.yaml" config.bookmarks)
          (format.generate "services.yaml" config.services)
          (format.generate "widgets.yaml" config.widgets)
          (format.generate "kubernetes.yaml" config.kubernetes)
          (format.generate "docker.yaml" config.docker)
          (format.generate "settings.yaml" config.settings)
          (pkgs.writeTextFile {
            name = "custom.css";
            text = "";
          })
          (pkgs.writeTextFile {
            name = "custom.js";
            text = "";
          })
        ];

        configDir = pkgs.runCommand "homepage-dashboard-config" {
          paths = configFiles;
          passAsFile = [ "paths" ];
          preferLocalBuild = true;
          allowSubstitutes = false;
        } ''
          mkdir -p $out
          for i in $(cat $pathsPath); do
            BASENAME=$(basename $i | ${gnused}/bin/sed -n -e 's/^.*-//p')
            ln -s "$i" "$out/"$BASENAME
          done
        '';

        configEnv = "${toString config.port}${configDir}${config.bind}${
            lib.optionalString (config.allowedHosts != null) config.allowedHosts
          }";
        fullConfigHash = builtins.hashString "md5" configEnv;

        cacheDir = "/var/cache/homepage-dashboard";

        initScript = pkgs.writeShellApplication {
          name = "homepage-dashboard-entrypoint";
          runtimeInputs = [ config.package ];
          text = ''
            #Running preStart hook
            ${config.preStart}

            homepage
          '';
        };
      in {
        name = "homepage-dashboard";
        tag = "${config.package.version}-${fullConfigHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${cacheDir}"
          chown -R "${UIDGID}" "${cacheDir}"
        '';

        contents = with pkgs; [ fakeNss ];

        config = {
          Env = [
            "HOMEPAGE_CONFIG_DIR=${configDir}"
            "PORT=${toString config.port}"
            "LOG_TARGETS=stdout"
            "NIXPKGS_HOMEPAGE_CACHE_DIR=${cacheDir}"
            "HOSTNAME=${config.bind}"

            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ] ++ (lib.optionals (config.allowedHosts != null)
            [ "HOMEPAGE_ALLOWED_HOSTS=${config.allowedHosts}" ]);
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          User = UIDGID;
        };
      };
  };
}
