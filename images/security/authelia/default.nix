{ pkgs, lib, mkImage, ... }:
let format = pkgs.formats.yaml { };
in {
  default = mkImage {
    supportSnapshotter = true;

    options = with lib; {
      package = mkPackageOption pkgs "authelia" { };

      uid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          Uid for authelia instance.
        '';
      };
      gid = mkOption {
        default = 1000;
        type = types.int;
        description = ''
          Gid for authelia instance.
        '';
      };

      secrets = mkOption {
        description = ''
          Paths for various secrets used in authelia.
          This attribute allows you to enable usage of secrets and to configure the location of secret files.
        '';

        default = { };
        type = types.submodule {
          options = {
            jwtSecretFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to JWT secret.
              '';
            };
            storageEncryptionKeyFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to storage encryption secret.
              '';
            };
            sessionSecretFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to session secret.
              '';
            };
            authenticationBackendLDAPPasswordFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to password file used for LDAP authentication.
              '';
            };

            oidcHmacSecretFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to secret file OIDC HMAC.
              '';
            };

            oidcIssuerPrivateKeyFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to OIDC private key.
              '';
            };
          };
        };
      };
      settings = mkOption {
        description = ''
          Autheliad config.yml

          https://github.com/authelia/authelia/blob/master/config.template.yml
        '';
        default = { };
        type = types.submodule { freeformType = format.type; };
      };
    };

    image = { config, ... }:
      let
        configFile = format.generate "config.yml" config.settings;
        secretEnvs = with lib.attrsets;
          mapAttrsToList (k: v: "${k}=${v}") (filterAttrs (_: v: v != null)
            (mapAttrs (_: v: attrByPath [ v ] null config.secrets) {
              AUTHELIA_JWT_SECRET_FILE = "jwtSecretFile";
              AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "storageEncryptionKeyFile";
              AUTHELIA_SESSION_SECRET_FILE = "sessionSecretFile";
              AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE =
                "authenticationBackendLDAPPasswordFile";
              AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE =
                "oidcIssuerPrivateKeyFile";
              AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE =
                "oidcHmacSecretFile";
            }));
        settingsHash = builtins.hashFile "md5" configFile;
        secretFilesHash =
          builtins.hashString "md5" (lib.strings.concatStrings secretEnvs);
        fullConfigHash =
          builtins.hashString "md5" "${settingsHash}${secretFilesHash}";

        initScript = pkgs.writeShellApplication {
          name = "authelia-entrypoint";
          runtimeInputs = [ config.package ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            #Running preStart hook
            ${config.preStart}

            authelia --config "${configFile}"
          '';
        };
      in {
        name = "authelia";
        tag = "${config.package.version}-${fullConfigHash}";
        config = {
          Env = secretEnvs;
          Cmd = [ (pkgs.lib.meta.getExe initScript) ];
          User = "${toString config.uid}:${toString config.gid}";
        };
      };
  };
}
