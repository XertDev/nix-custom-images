{ pkgs, lib, mkImage, ... }: {
  default = mkImage (let dataDir = "/var/lib/freshrss";
  in {
    options = with lib; {
      package = mkPackageOption pkgs "freshrss" { };

      uid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          UID for freshrss.
        '';
      };

      gid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          GID for freshrss.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 5000;
        description = ''
          Port for web interface.
        '';
      };

      extensions = mkOption {
        type = with types; listOf package;
        default = [ ];
        description = ''
          Extensions to be added.
        '';
      };

      language = mkOption {
        type = types.str;
        default = "en";
        description = ''
          Default FreshRSS language.
        '';
      };

      database = {
        type = mkOption {
          type = types.enum [ "sqlite" "pgsql" "mysql" ];
          default = "sqlite";
          description = ''
            Database type.
          '';
        };

        host = mkOption {
          type = types.str;
          default = "${dataDir}/database.sqlite";
          description = ''
            Database host.
          '';
        };
        port = mkOption {
          type = with types; nullOr port;
          default = null;
          description = ''
            Database port.
          '';
        };

        user = mkOption {
          type = types.str;
          default = "freshrss";
          description = ''
            Database user.
          '';
        };
        passFile = mkOption {
          type = with types; nullOr path;
          default = null;
          description = ''
            Database password file path.
          '';
        };

        name = mkOption {
          type = types.str;
          default = "freshrss";
          description = ''
            Database name.
          '';
        };
      };

      authType = mkOption {
        type = types.enum [ "http_auth" "none" ];
        default = "none";
        description = ''
          "Authentication type for instance. "form" not supported currently.
        '';
      };
    };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";

        defaultUser = "admin";

        caddyHome = "/var/lib/caddy";
        caddyFile = pkgs.writeText "Caddyfile" ''
          :${toString config.port} {
            root * ${config.package}/p
            php_fastcgi unix//var/run/php-fpm.sock {
              ${
                lib.optionalString (config.authType == "http_auth") ''
                  env REMOTE_USER {http.request.header.X-Remote-User}
                ''
              }
            }
            file_server
          }
        '';

        extensionsEnv = pkgs.buildEnv {
          name = "extensions";
          paths = config.extensions;
        };

        envVars = {
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          FRESHRSS_PATH = config.package;
          DATA_PATH = dataDir;
        } // lib.optionalAttrs (config.extensions != [ ]) {
          THIRDPARTY_EXTENSIONS_PATH = "${extensionsEnv}/share/freshrss";
        };

        phpfpmConf = pkgs.writeText "php-fpm.conf" ''
          [global]
          error_log = /proc/self/fd/2
          daemonize = no

          [www]
          user = freshrss
          group = freshrss

          listen = /var/run/php-fpm.sock

          pm = dynamic
          pm.max_children = 32
          pm.max_requests = 500
          pm.start_servers = 2
          pm.min_spare_servers = 2
          pm.max_spare_servers = 5

          clear_env = no

          catch_workers_output = yes

          php_admin_value[error_log] = /proc/self/fd/2
          php_admin_flag[log_errors] = on
        '';

        supervisordConf = pkgs.writeText "suprvisord.conf" ''
          [supervisord]
          nodaemon = true
          user = freshrss

          loglevel = info
          logfile = /dev/null
          logfile_maxbytes=0

          pidfile = /var/run/supervisord.pid

          [program:caddy]
          command = ${pkgs.caddy}/bin/caddy run --config ${caddyFile} --adapter caddyfile
          user = freshrss
          stdout_logfile=/dev/stdout
          stdout_logfile_maxbytes=0
          stderr_logfile=/dev/stderr
          stderr_logfile_maxbytes=0
          autostart=true
          autorestart=true
          priority=10
          environment=HOME=${caddyHome}

          [program:php-fpm]
          command = ${pkgs.php83}/bin/php-fpm -F -y ${phpfpmConf}
          user = freshrss
          stdout_logfile = /dev/stdout
          stdout_logfile_maxbytes = 0
          stderr_logfile = /dev/stderr
          stderr_logfile_maxbytes = 0
          autostart = true
          autorestart = true
          priority = 5
        '';

        initScriptText = let
          flags = lib.strings.concatStringsSep " "
            (lib.attrsets.mapAttrsToList (k: v: "${k} ${toString v}") {
              "--default-user" = ''"${defaultUser}"'';
              "--auth-type" = ''"${config.authType}"'';
              "--language" = ''"${config.language}"'';
              "--db-type" = "${config.database.type}";

              ${if config.database.port != null then "--db-host" else null} =
                ''"${config.database.host}:${toString config.database.port}"'';
              ${if config.database.port == null then "--db-host" else null} =
                ''"${config.database.host}"'';

              "--db-user" = ''"${config.database.user}"'';
              ${
                if config.database.passFile != null then
                  "--db-password"
                else
                  null
              } = ''"$(cat ${config.database.passFile})"'';

              "--db-base" = ''"${config.database.name}"'';
            });
        in ''
          #Running preConfig hook
          ${config.preConfig}

          if [ -f "${dataDir}/config.php" ]; then
            ${config.package}/cli/reconfigure.php ${flags}
          else
            ${config.package}/cli/prepare.php
            ${config.package}/cli/do-install.php ${flags}
            ${config.package}/cli/create-user.php --user ${defaultUser}
          fi

          #Running preStart hook
          ${config.preStart}

          ${pkgs.python3Packages.supervisor}/bin/supervisord -c ${supervisordConf}
        '';

        initScript = pkgs.writeShellApplication {
          name = "freshrss-entrypoint";
          runtimeInputs = [ config.package ];
          text = initScriptText;
        };

        configHash = builtins.hashString "md5"
          "${initScriptText}${toString extensionsEnv}";
      in {
        name = "freshrss";
        tag = "${config.package.version}-${configHash}";

        contents = with pkgs;
          [
            (dockerTools.fakeNss.override {
              extraPasswdLines =
                [ "freshrss:x:${UIDGID}:freshrss user:/var/empty:/bin/sh" ];
              extraGroupLines = [
                "freshrss:x:${toString config.gid}:freshrss"
                "nogroup:x:65534:"
              ];
            })
          ];

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p ${dataDir}
          mkdir -p ${dataDir}/favicons
          mkdir -p ${dataDir}/cache
          mkdir -p ${dataDir}/users

          mkdir -p ${caddyHome}

          mkdir -p /tmp
          mkdir -p /var/run

          chown -R ${UIDGID} ${dataDir}
          chown -R ${UIDGID} ${caddyHome}

          chown -R ${UIDGID} /var/run
          chown -R ${UIDGID} /tmp
        '';

        config = {
          User = UIDGID;

          Env = lib.attrsets.mapAttrsToList (k: v: "${k}=${v}") envVars;

          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
        };
      };
  });
}
