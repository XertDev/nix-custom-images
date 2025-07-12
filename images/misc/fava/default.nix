{ pkgs, lib, mkImage, ... }:
with lib;
let
  commonOptions = {
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
  };
in {
  default = mkImage {
    options = commonOptions;

    image = { config, ... }:
      let
        ledgerFile = "/var/lib/fava/ledger.beancount";

        configAggregated = "${config.bind}${builtins.toString config.port}";
        fullConfigHash = builtins.hashString "md5" configAggregated;

        initScript = pkgs.writeShellApplication {
          name = "fava-entrypoint";
          runtimeInputs = [ pkgs.coreutils config.package ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            if [ ! -f '${ledgerFile}' ]; then
              echo 'Creating initial ledger file: ${ledgerFile}';
              touch '${ledgerFile}';
            fi

            #Running preStart hook
            ${config.preStart}

            echo 'Starting fava'
            fava ${ledgerFile} --host ${config.bind} --port ${
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
          DATA_DIR=$(dirname '${ledgerFile}')
          mkdir -p "$DATA_DIR"
          chown -R "${UIDGID}" "$DATA_DIR"
        '';

        config = {
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          User = "${toString config.uid}:${toString config.gid}";
        };
      };
  };

  on-steroids = mkImage {
    options = commonOptions // {
      language = mkOption {
        type = types.str;
        default = "en";
        description = "Default interface language";
      };
    };

    image = { config, ... }:
      let
        rootLedgerDir = "/var/lib/fava";
        userDir = "${rootLedgerDir}/user";

        defaultAccountsFile = pkgs.writeTextFile {
          name = "default_accounts.bean";
          text = ''
            1970-01-01 open Expenses:FIXME
          '';
        };

        defaultBeangrowConfig = pkgs.writeTextFile {
          name = "beangrow.config";
          text = ''
            investments {
            }
            groups {
            }
          '';
        };

        defaultImporterConfig = pkgs.writeTextFile {
          name = "importer.py";
          text = ''
            CONFIG = []
            HOOKS = []
          '';
        };

        defaultCurrenciesConfig = pkgs.writeTextFile {
          name = "currencies.bean";
          text = ''
            option "operating_currency" "USD"
            option "inferred_tolerance_default" "*:0.00000001"
            option "inferred_tolerance_default" "USD:0.003"

            option "inferred_tolerance_multiplier" "1.2"
          '';
        };

        favaConfig = [
          ''1970-01-01 custom "fava-option" "language" "${config.language}"''
          ''1970-01-01 custom "fava-extension" "fava_investor" "{}"''
          ''
            1970-01-01 custom "fava-extension" "fava_dashboards" "{
                           'config': '${userDir}/dashboards.yaml'
                       }"''
          ''
            1970-01-01 custom "fava-option" "default-file" "${userDir}/manual.bean"''
          ''
            1970-01-01 custom "fava-extension" "fava_portfolio_returns" "{
                          'beangrow_config': 'user/beangrow.config',
                        }"''
          ''
            1970-01-01 custom "fava-option" "import-config" "${userDir}/importer.py"''
          ''
            1970-01-01 custom "fava-option" "import-dirs" "${userDir}/ingested"''
        ];

        rootLedgerContent = strings.concatStringsSep "\n"
          ([ ''option "plugin_processing_mode" "raw"'' ] ++ [
            ''plugin "beancount.ops.pad"''
            ''plugin "beancount.ops.balance"''
            ''plugin "beancount.ops.documents"''
            ''option "documents" "user/documents"''
            ''plugin "beancount.plugins.implicit_prices"''
            "; default accounts - used by plugins"
            ''include "accounts.default.bean"''
            ''include "user/accounts.bean"''
            ''include "user/currencies.bean"''
            ''include "user/commodities.bean"''
            ''include "user/manual.bean"''
            ''include "user/budgets.bean"''
          ] ++ favaConfig);

        rootLedgerFile = pkgs.writeTextFile {
          name = "root.bean";
          text = rootLedgerContent;
        };

        configAggregated =
          "${config.bind}${builtins.toString config.port}${rootLedgerContent}";
        fullConfigHash = builtins.hashString "md5" configAggregated;

        beangrow = pkgs.callPackage ./plugins/beangrow { };

        favaEnv = pkgs.python3.buildEnv.override {
          extraLibs = [
            (pkgs.python3Packages.toPythonModule
              (pkgs.callPackage ./plugins/fava-portfolio-returns {
                inherit (config) package;
                inherit beangrow;
              }))
            (pkgs.python3Packages.toPythonModule
              (pkgs.callPackage ./plugins/fava-dashboards {
                inherit (config) package;
              }))
            (pkgs.python3Packages.toPythonModule
              (pkgs.callPackage ./plugins/fava_investor {
                inherit (config) package;
              }))
            (pkgs.python3Packages.toPythonModule
              (pkgs.callPackage ./plugins/smart_importer { }))
            (pkgs.python3Packages.toPythonModule config.package)
          ];
        };

        initScript = pkgs.writeShellApplication {
          name = "fava-entrypoint";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            #Running preConfig hook
            ${config.preConfig}

            cp --no-preserve=mode "${defaultAccountsFile}" "${rootLedgerDir}/accounts.default.bean"
            cp --no-preserve=mode "${rootLedgerFile}" "${rootLedgerDir}/root.bean"

            mkdir -p '${userDir}'

            if [ "$(${pkgs.findutils}/bin/find '${userDir}' | wc -l)" -eq "1" ]; then
              echo 'Creating user dir: ${userDir}';

              mkdir -p '${userDir}/ingested'
              mkdir -p '${userDir}/documents'

              touch '${userDir}/accounts.bean'
              touch '${userDir}/commodities.bean'
              touch '${userDir}/budgets.bean'
              touch '${userDir}/manual.bean'

              cp --no-preserve=mode '${defaultCurrenciesConfig}' '${userDir}/currencies.bean'
              cp --no-preserve=mode '${defaultBeangrowConfig}' '${userDir}/beangrow.config'
              cp --no-preserve=mode '${defaultImporterConfig}' '${userDir}/importer.py'

              touch '${userDir}/dashboards.yaml'
              chmod u+rw '${userDir}'
            fi

            #Running preStart hook
            ${config.preStart}

            echo 'Starting fava'
            ${favaEnv}/bin/fava "${rootLedgerDir}/root.bean" --host ${config.bind} --port ${
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
          mkdir -p tmp/matplotlib
          chown -R ${UIDGID} tmp

          mkdir -p "${rootLedgerDir}"
          chown -R "${UIDGID}" "${rootLedgerDir}"
        '';

        config = {
          Env = [ "MPLCONFIGDIR=/tmp/matplotlib" ];
          Entrypoint = [ (pkgs.lib.meta.getExe initScript) ];
          User = "${toString config.uid}:${toString config.gid}";
        };
      };
  };
}
