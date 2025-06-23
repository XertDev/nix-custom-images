{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    options = with lib; {
      package = mkPackageOption pkgs "postgresql" { };

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
        default = "localhost";
        description = ''
          The address to which the service should bind.
        '';
      };

      settings = mkOption {
        type = with types;
          submodule {
            freeformType = attrsOf (oneOf [ bool float int str ]);
            options = {
              log_line_prefix = mkOption {
                type = str;
                default = "[%p] ";
                description = ''
                  Prefix added before each log line.
                  See https://www.postgresql.org/docs/current/runtime-config-logging.html#GUC-LOG-LINE-PREFIX.
                '';
              };
            };
          };

        default = { };
        description = ''
          Postgres configuration
        '';
      };

      authentication = mkOption {
        type = types.lines;
        default = ''
          local all postgres         peer map=postgres
          local all all              peer
          host  all all 127.0.0.1/32 md5
          host  all all ::1/128      md5
        '';
        description = ''
          Rules for user authentication to the server.
          This option sets content of [pg_hba.conf](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html) file.
          Default behaviour:
            * Unix socker - peer based authentication
            * TCP - md5 password authentication
        '';
      };

      ensureDatabases = mkOption {
        type = with types; listOf str;
        default = [ ];
        description = "Creates database if missing.";
      };

      ensureUsers = mkOption {
        type = with types;
          listOf (submodule {
            options = {
              name = mkOption {
                type = str;
                description = "User name";
              };

              ensureDBOwnership = mkOption {
                type = bool;
                default = false;
                description =
                  "Grant ownership to a database with the same name.";
              };
            };
          });

        default = [ ];
        description = "Creates users if missing.";
      };

      extensions = mkOption {
        type = with types;
          coercedTo (listOf path) (path: _ignorePg: path)
          (functionTo (listOf path));
        default = _: [ ];
        description = "Packages with PostgreSQL extensions to install.";
      };
    };

    image = { config, ... }:
      let
        UIDGID = "${toString config.uid}:${toString config.gid}";

        toStr = value:
          if true == value then
            "yes"
          else if false == value then
            "no"
          else if builtins.isString value then
            "'${lib.replaceStrings [ "'" ] [ "''" ] value}'"
          else
            builtins.toString value;

        package = if config.extensions == [ ] then
          config.package
        else
          config.package.withPackages config.extensions;

        authentication = ''
          # Generated file
          ${config.authentication}
        '';

        identMap = ''
          postgres postgres postgres
        '';

        dataDir = "/var/lib/postgresql/${package.psqlSchema}";

        defaultConfig = {
          hba_file = "${pkgs.writeText "pg_hba.conf" authentication}";
          ident_file = "${pkgs.writeText "pg_ident.conf" identMap}";

          log_destination = "stderr";
          listen_addresses = config.bind;
        };

        settings = defaultConfig // config.settings;

        configFile = pkgs.writeTextDir "postgresql.conf"
          (lib.strings.concatStringsSep "\n"
            (lib.attrsets.mapAttrsToList (n: v: "${n} = ${toStr v}")
              (lib.attrsets.filterAttrs (lib.trivial.const (x: x != null))
                settings)));

        initScript = pkgs.writeShellApplication {
          name = "postgresql-entrypoint";
          runtimeInputs = [ pkgs.coreutils package ];
          text = ''
            export PSQL="psql --port=${builtins.toString config.port}"
            declare DATABASE_ALREADY_EXISTS
            DATABASE_ALREADY_EXISTS='false'

            echo "Starting postgres container..."

            if [[ -s "${dataDir}/PG_VERSION" ]]; then
              echo "Initializing db..."
              DATABASE_ALREADY_EXISTS='true'
            fi

            if [[ $DATABASE_ALREADY_EXISTS = 'false' ]]; then
              rm -f ${dataDir}/*.conf

              initdb -U postgres

              touch "${dataDir}/.first_startup"
              echo "Db initialized."
            fi

            ln -sfn "${configFile}/postgresql.conf" "${dataDir}/postgresql.conf"

            # Temp start
            set -- -c listen_addresses=\"\" -p "${
              builtins.toString config.port
            }"

            NOTIFY_SOCKET=''' pg_ctl -D "${dataDir}" -o "$(printf '%q ' "$@")" -w start -p "${package}/bin/postgres"

            #Init
            echo "Temporary db start"
            ${lib.strings.concatMapStrings (db: ''
              $PSQL -tAc 'CREATE DATABASE "${db}"'
            '') config.ensureDatabases}

            echo "Applying scripts..."
            ${lib.strings.concatMapStrings (user: ''
              $PSQL -tAc 'CREATE USER "${user.name}"'
              ${lib.strings.optionalString user.ensureDBOwnership ''
                $PSQL -tAc 'ALTER DATABASE "${user.name}" OWNER TO "${user.name}";'
              ''}
            '') config.ensureUsers}
            echo "Applying scripts done"

            # Temp stop
            pg_ctl -D "${dataDir}" -m fast -w stop -p "${package}/bin/postgres"
            echo "Temporary db stop"

            #Start
            postgres
          '';
        };
      in {
        name = "postgresql";

        contents = with pkgs; [
          dockerTools.binSh
          (dockerTools.fakeNss.override {
            extraPasswdLines = [
              "postgres:x:${UIDGID}:postgres database server user:/var/empty:/sbin/nologin"
            ];
            extraGroupLines = [ "postgres:x:${toString config.gid}:postgres" ];
          })
        ];

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${dataDir}"
          chown -R ${UIDGID} "${dataDir}"

          mkdir -p "/run/postgresql/"
          chown -R ${UIDGID} "/run/postgresql/"
        '';

        config = {
          User = UIDGID;

          Env = [ "PGDATA=${dataDir}" ];
          WorkingDir = dataDir;

          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
        };
      };
  };
}
