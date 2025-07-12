{ pkgs, lib, mkImage, ... }: {
  default = mkImage {
    options = with lib;
      let
        # Based on https://github.com/NixOS/nixpkgs/blob/4fbaec7faa5c19d7c933bf6afcb550f06303c947/nixos/modules/services/databases/openldap.nix#L33
        ldapValueType = let
          singleLdapValueType = mkOptionType {
            name = "LDAPValueType";
            description = ''
              string ot attrset with 'path' or 'base64' field
            '';
            check = x: isString x || (isAttrs x && (x ? path || x ? base64));
            merge = mergeEqualOption;
          };
        in types.either singleLdapValueType (types.listOf singleLdapValueType);

        ldapAttrsOptions = let
          options = {
            attrs = mkOption {
              type = types.attrsOf ldapValueType;
              default = { };
              description = ''
                Entry attributes;
              '';
            };

            children = mkOption {
              type = let
                hiddenOptions =
                  lib.mapAttrs (_: attr: attr // { visible = false; }) options;
              in types.attrsOf (types.submodule { options = hiddenOptions; });
              default = { };
              description = ''
                Child entries.
              '';
            };

            includes = mkOption {
              type = types.listOf types.path;
              default = [ ];
              description = ''
                Files included for entry.
              '';
            };
          };
        in options;
      in {
        package = mkPackageOption pkgs "openldap" { };

        uid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            UID for openldap.
          '';
        };
        gid = mkOption {
          default = 1000;
          type = types.int;
          description = ''
            GID for openldap.
          '';
        };

        port = mkOption {
          type = types.port;
          default = 1389;
          description = ''
            Port for ldap.
          '';
        };

        debugLevel = mkOption {
          type = types.listOf (types.enum [
            "any"
            "trace"
            "packets"
            "args"
            "conns"
            "ber"
            "filter"
            "config"
            "acl"
            "stats"
            "stats2"
            "shell"
            "parse"
            "sync"
            "none"
            "0"
          ]);
          default = [ "0" ];
          description = ''
            Log level
          '';
        };

        settings = mkOption {
          type = types.submodule { options = ldapAttrsOptions; };
          description = ''
            OpenLDAP configuration.
          '';
        };

        printConfig = mkOption {
          type = types.bool;
          default = false;
          internal = true;
        };
      };

    image = { config, ... }:
      let
        configDir = "/var/lib/openldap/slapd.d";
        runtimeDir = "/var/lib/openldap/data";
        UIDGID = "${toString config.uid}:${toString config.gid}";

        valueToLdif = value:
          if lib.isAttrs value then
            if value ? "path" then
              "< file://${value.path}"
            else
              ": ${value.base64}"
          else
            " ${lib.replaceStrings [ "\n" ] [ "\n " ] value}";

        attrsToLdif = dn:
          { attrs ? { }, children ? { }, includes ? [ ], ... }:
          lib.strings.concatStringsSep "\n" ([ "" "dn: ${dn}" ] ++ (lib.flatten
            (lib.mapAttrsToList (attr: values:
              let
                valuesList =
                  if lib.isList values then values else lib.singleton values;
              in map (value: "${attr}:${valueToLdif value}") valuesList) attrs))
            ++ (lib.lists.optional ((builtins.length includes) != 0) "") ++ (map
              (path: ''
                include: file://${path}
              '') includes)
            ++ lib.mapAttrsToList (key: value: attrsToLdif "${key},${dn}" value)
            children);

        baseSettings = {
          attrs = {
            objectClass = "olcGlobal";
            cn = "config";
          };
          children."cn=schema".attrs = {
            cn = "schema";
            objectClass = "olcSchemaConfig";
          };
        };

        settings = lib.recursiveUpdate baseSettings config.settings;

        configText = attrsToLdif "cn=config" settings;
        configHash = builtins.hashString "md5"
          "${configText}-${lib.strings.concatStrings config.debugLevel}-${
            toString config.port
          }";

        configFile = pkgs.writeText "config.ldif" configText;

        debugParams = lib.strings.concatStringsSep " "
          (map (x: "-d ${x}") config.debugLevel);

        initScript = pkgs.writeShellApplication {
          name = "openldap-entrypoint";
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            #Load config
            ${lib.strings.optionalString config.printConfig ''
              ${pkgs.coreutils}/bin/cat ${configFile}
            ''}

            if [ ! -e "${configDir}/cn=config.ldif" ]; then
              ${config.package}/bin/slapadd -F "${configDir}" -bcn=config -l ${configFile}
            fi

            #Test configuration
            ${config.package}/bin/slaptest -u -F "${configDir}"

            #Running preStart hook
            ${config.preStart}

            #Start server
            ulimit -n 1000
            echo "Starting OpenLDAP"
            ${config.package}/libexec/slapd ${debugParams} -F "${configDir}" -h ldap://0.0.0.0:${
              toString config.port
            };
          '';
        };
      in {
        name = "openldap";
        tag = "${config.package.version}-${configHash}";

        enableFakechroot = true;
        fakeRootCommands = ''
          mkdir -p "${configDir}"
          chown -R ${UIDGID} "${configDir}"

          # To be able to start without mounts in case of non persistant run
          mkdir -p "${runtimeDir}"
          chown -R ${UIDGID} "${runtimeDir}"
        '';

        config = {
          User = UIDGID;
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
        };
      };

    defaultBuildArgs = { settings = { }; };

    tests = [
      {
        name = "Simple ldap configuration";
        config = {
          args = {
            settings.children = {
              "cn=schema".includes = [
                "${pkgs.openldap}/etc/schema/core.ldif"
                "${pkgs.openldap}/etc/schema/cosine.ldif"
                "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
                "${pkgs.openldap}/etc/schema/nis.ldif"
              ];

              "cn=module{0}".attrs = {
                objectClass = [ "olcModuleList" ];
                olcModuleLoad = [ "{0}memberof" ];
              };

              "olcDatabase={1}mdb" = {
                attrs = {
                  objectClass = [ "olcDatabaseConfig" "olcMdbConfig" ];
                  olcDatabase = "{1}mdb";
                  olcDbDirectory = "/var/lib/openldap/data";
                  olcSuffix = "dc=test,dc=local";

                  olcRootDN = "cn=admin,dc=test,dc=local";
                  olcRootPW = "password";

                  olcAccess = [
                    ''
                      {0}to attrs=userPassword
                                     by self write  by anonymous auth
                                     by * none''
                    "{1}to * by * read"
                  ];
                };
              };
            };
          };
          ports = [ "1389:1389" ];
        };
        script = ''
          LDAP_HOST=localhost
          LDAP_PORT=1389
          TMP_DIR=$(mktemp -d)

          TIMEOUT=10

          trap "rm -f -- $''${TMP_DIR@Q}" EXIT

          OUT_FILE="$TMP_DIR/ldapsearch_output"

          # wait for LDAP to start
          for ((i=1; i<=TIMEOUT; i++)); do
            if ${pkgs.openldap}/bin/ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT; then
              break
            fi
            sleep 1
          done

          ${pkgs.openldap}/bin/ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT -b "" -s base > "$OUT_FILE"

          if ! grep -q '^dn:' "$OUT_FILE"; then
            exit 1
          fi

          ${pkgs.openldap}/bin/ldapwhoami -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "cn=admin,dc=test,dc=local" -w password > "$OUT_FILE"

          if [[ $? -ne 0 ]]; then
            exit 1
          fi
          exit 0
        '';
      }
      {
        name = "Password from file";
        config = {
          args = {
            printConfig = true;

            preConfig = ''
              echo -n "password" > /var/lib/openldap/data/pass
            '';
            settings.children = {
              "cn=schema".includes = [
                "${pkgs.openldap}/etc/schema/core.ldif"
                "${pkgs.openldap}/etc/schema/cosine.ldif"
                "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
                "${pkgs.openldap}/etc/schema/nis.ldif"
              ];

              "cn=module{0}".attrs = {
                objectClass = [ "olcModuleList" ];
                olcModuleLoad = [ "{0}memberof" ];
              };

              "olcDatabase={1}mdb" = {
                attrs = {
                  objectClass = [ "olcDatabaseConfig" "olcMdbConfig" ];
                  olcDatabase = "{1}mdb";
                  olcDbDirectory = "/var/lib/openldap/data";
                  olcSuffix = "dc=test,dc=local";

                  olcRootDN = "cn=admin,dc=test,dc=local";
                  olcRootPW.path = "/var/lib/openldap/data/pass";

                  olcAccess = [
                    ''
                      {0}to attrs=userPassword
                                     by self write  by anonymous auth
                                     by * none''
                    "{1}to * by * read"
                  ];
                };
              };
            };
          };
          ports = [ "1389:1389" ];
        };
        script = ''
          LDAP_HOST=localhost
          LDAP_PORT=1389
          TMP_DIR=$(mktemp -d)

          TIMEOUT=10

          trap "rm -f -- $''${TMP_DIR@Q}" EXIT

          OUT_FILE="$TMP_DIR/ldapsearch_output"

          # wait for LDAP to start
          for ((i=1; i<=TIMEOUT; i++)); do
            if ${pkgs.openldap}/bin/ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT; then
              break
            fi
            sleep 1
          done

          ${pkgs.openldap}/bin/ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT -b "" -s base > "$OUT_FILE"

          if ! grep -q '^dn:' "$OUT_FILE"; then
            exit 1
          fi

          ${pkgs.openldap}/bin/ldapwhoami -x -H ldap://$LDAP_HOST:$LDAP_PORT -D "cn=admin,dc=test,dc=local" -w password > "$OUT_FILE"

          if [[ $? -ne 0 ]]; then
            exit 1
          fi
          exit 0
        '';
      }
    ];
  };
}
