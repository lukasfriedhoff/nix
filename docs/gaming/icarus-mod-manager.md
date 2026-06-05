# Icarus Mod Manager

The Home Manager module `programs.icarusModManager` installs a Wine launcher for
the standalone upstream `IcarusModManager.exe`.

## Runtime model

- The upstream executable is a native 32-bit Windows GUI application, not a .NET
  Desktop Runtime application.
- The launcher intentionally does not run `winetricks` or install
  `dotnetdesktop8`; that path triggers Wine 11 `advapi32.dll.SystemFunction036`
  failures on this host.
- The launcher uses the default Wine WoW64 package with a normal 64-bit prefix,
  which can run the 32-bit executable. Do not force `WINEARCH=win32` with
  `wineWow64Packages.full`; Wine rejects that combination.
- Font packages are installed through Home Manager and copied into the prefix on
  first launch. Registry substitutions map legacy Windows bitmap fonts to
  Liberation/DejaVu/Noto fonts to avoid unreadable glyphs.
- First launch is pre-seeded before the GUI starts: the launcher installs the
  upstream `UnrealPak.zip`, writes `UE4PakEXE`, and auto-detects the Icarus
  `Content` directory from common Steam library paths. This avoids the Wine file
  chooser path, which currently creates hidden/blocking dialogs.

If auto-detection does not find the game, set the content path explicitly:

```nix
programs.icarusModManager.icarusContentDir =
  "/home/lukasf/media/SteamLibrary/steamapps/common/Icarus/Icarus/Content";
```

## Commands

Reset the prefix and mutable app directory:

```sh
rm -rf ~/.local/share/wineprefixes/icarus-mod-manager ~/.local/share/icarus-mod-manager
```

Initialize and verify the prefix without opening the GUI:

```sh
icarus-mod-manager --self-test
```

On a headless VM or SSH session without an active display, run it under Xvfb:

```sh
xvfb-run -a icarus-mod-manager --self-test
```

Run the GUI smoke test under a temporary X server:

```sh
xvfb-run -a icarus-mod-manager --smoke-test
```

Launch the app normally:

```sh
icarus-mod-manager
```

## Disposable VM test

The flake check `checks.x86_64-linux.icarus-mod-manager` creates a disposable
local NixOS VM using `pkgs.testers.nixosTest`, installs Home Manager, enables the
module for user `icarus`, and runs both launcher tests.

Test VM login details are deliberately non-secret and only exist inside the
ephemeral test VM:

- User: `icarus`
- Password: `icarus-test`

Run the VM-backed test:

```sh
nix build .#checks.x86_64-linux.icarus-mod-manager
```
