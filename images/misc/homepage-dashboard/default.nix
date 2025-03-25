{ pkgs, lib, mkImage, ... }:
let
	format = pkgs.formats.yaml {};
in
{
	default = mkImage {
		options = with lib; {
			package = mkPackageOption pkgs "homepage-dashboard" {};

			uid = mkOption {
				default = 1000;
				type = types.int;
				description = "UID for fava";
			};
			gid = mkOption {
				default = 1000;
				type = types.int;
				description = "GID for fava";
			};

			port = mkOption {
				type = types.port;
				default = 5000;
				description = ''
					Port for web interface
				'';
			};

			bookmarks = mkOption {
				type  = format.type;
				description = ''
          See <https://gethomepage.dev/configs/bookmarks/>.
				'';
				default = [];
			};

			services = mkOption {
				type  = format.type;
				description = ''
          See <https://gethomepage.dev/configs/services/>.
				'';
				default = [];
			};

			widgets = mkOption {
				type  = format.type;
				description = ''
          See <https://gethomepage.dev/widgets/>.
				'';
				default = [];
			};

			kubernetes = mkOption {
				type  = format.type;
				description = ''
          See <https://gethomepage.dev/configs/kubernetes/>.
				'';
				default = {};
			};

			docker = mkOption {
				type  = format.type;
				description = ''
          See <https://gethomepage.dev/configs/kubernetes/>.
				'';
				default = {};
			};

			settings = mkOption {
				type  = format.type;
				description = ''
          See <https://gethomepage.dev/configs/settings/>.
				'';
				default = {};
			};
		};

		image = { config, ... }: let

			UIDGID = "${toString config.uid}:${toString config.gid}";

			configFiles = [
				(format.generate "bookmarks.yaml" config.bookmarks)
        (format.generate "services.yaml" config.services)
        (format.generate "widgets.yaml" config.widgets)
        (format.generate "kubernetes.yaml" config.kubernetes)
        (format.generate "docker.yaml" config.docker)
        (format.generate "settings.yaml" config.settings)
			];

			configDir = pkgs.buildEnv {
				name = "homepage-dashboard-config";
				paths = configFiles;
			};

			configEnv = "${toString config.port}${configDir}";
			fullConfigHash = builtins.hashString "md5" configEnv;
		in
		{
			name = "homepage-dashboard";
			tag = "${config.package.version}-${fullConfigHash}";

			config = {
				Env = [
					"HOMEPAGE_CONFIG_DIR=${configDir}"
					"PORT=${toString config.port}"
					"LOG_TARGETS=stdout"
				];
				Entrypoint = pkgs.lib.meta.getExe config.package;
				User = UIDGID;
			};
		};
	};
}