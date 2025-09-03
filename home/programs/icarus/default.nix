{config, pkgs, lib, utils, ...}: let
	# Set to {id}-{branch}-{password} for betas.
	steam-app = "2089300";
in {
	imports = [
		./steam.nix
	];

	users.users.icarus = {
		isSystemUser = true;
		# icarus puts save data in the home directory.
		home = "/var/lib/icarus";
		createHome = true;
		homeMode = "750";
		group = "icarus";
	};

	users.groups.icarus = {};

	systemd.services.icarus = {
		wantedBy = [ "multi-user.target" ];

		# Install the game before launching.
		wants = [ "steam@${steam-app}.service" ];
		after = [ "steam@${steam-app}.service" ];

		serviceConfig = {
			ExecStart = utils.escapeSystemdExecArgs [
				"/var/lib/steam-app-${steam-app}/icarus_server.x86_64"
				"-nographics"
				"-batchmode"
				# "-crossplay" # This is broken because it looks for "party" shared library in the wrong path.
				"-savedir" "/var/lib/icarus/save"
				"-name" "h4xxarus"
				"-port" "2456"
				"-world" "Dedicated"
				"-password" "Modeco80Icarus"
				"-public" "0" # icarus now supports favourite servers in-game which I am using instead of listing in the public registry.
				"-backups" "0" # I take my own backups, if you don't you can remove this to use the built-in basic rotation system.
			];
			Nice = "-5";
			PrivateTmp = true;
			Restart = "always";
			User = "icarus";
			WorkingDirectory = "~";
		};
		environment = {
			# linux64 directory is required by icarus.
			LD_LIBRARY_PATH = "/var/lib/steam-app-${steam-app}/linux64:${pkgs.glibc}/lib";
			SteamAppId = "2089300";
		};
	};
}