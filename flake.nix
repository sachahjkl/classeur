{
  description = "classeur: a file manager, built with gui_toolkit";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605";
    git-hooks = {
      url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    git-hooks,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib;

    wgpu = pkgs.fetchurl {
      url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-x86_64-release.zip";
      sha256 = "95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a";
    };

    odin = pkgs.stdenv.mkDerivation {
      pname = "odin";
      version = "dev-2026-11a";
      src = pkgs.fetchurl {
        url = "https://github.com/odin-lang/Odin/releases/download/dev-2026-11a/odin-linux-amd64-dev-2026-11a.tar.gz";
        sha256 = "65c9f6e97d6f8a30930e151f270ce5aeaa98fe8b2ba49fe067394e2af04f7618";
      };
      nativeBuildInputs = [pkgs.makeWrapper pkgs.unzip];
      dontBuild = true;
      dontPatchELF = true;
      installPhase = ''
        mkdir -p $out/lib/odin $out/bin
        cp -r . $out/lib/odin
        dest=$out/lib/odin/vendor/wgpu/lib/wgpu-linux-x86_64-release
        mkdir -p $dest
        unzip -qo ${wgpu} -d $dest
        echo 29.0.1.1 > $dest/VERSION
        makeWrapper $out/lib/odin/odin $out/bin/odin --set ODIN_ROOT $out/lib/odin/ --prefix PATH : ${lib.makeBinPath [pkgs.clang pkgs.lld]}
      '';
    };

    runtime = with pkgs; [
      vulkan-loader
      mesa
      libxkbcommon
      wayland
      libx11
      libxcb
      libxcb-cursor
      fontconfig
      freetype
      dbus
    ];

    # APP_VERSION of src/main.odin
    version = let
      line = lib.findFirst (lib.hasPrefix "APP_VERSION ::") "" (lib.splitString "\n" (builtins.readFile ./src/main.odin));
    in
      builtins.head (builtins.match ''APP_VERSION :: "([^"]+)".*'' line);

    # classeur, built from this tree as the release is: classeurtool build release.
    classeur = pkgs.stdenv.mkDerivation {
      pname = "classeur";
      inherit version;
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.difference ./. (lib.fileset.unions (map lib.fileset.maybeMissing [./site ./build]));
      };
      # the crates of the toolkit's text library, vendored: cargo makes no request
      cargoDeps = pkgs.rustPlatform.importCargoLock {lockFile = ./ext/gui_toolkit/native/text/Cargo.lock;};

      nativeBuildInputs = [odin pkgs.cargo pkgs.rustc pkgs.clang pkgs.lld pkgs.autoPatchelfHook pkgs.copyDesktopItems];
      buildInputs = [pkgs.fontconfig pkgs.freetype pkgs.stdenv.cc.cc.lib];
      # what it opens with dlopen goes in its RUNPATH; the Vulkan driver is the system's (/run/opengl-driver)
      runtimeDependencies = runtime;
      # Odin links a foreign library as -l:<absolute path> with -L/, which the purity check of the linker wrapper drops
      NIX_ENFORCE_PURITY = 0;

      configurePhase = ''
        runHook preConfigure
        export HOME="$TMPDIR"
        mkdir -p "$HOME/.cargo"
        cat > "$HOME/.cargo/config.toml" <<EOF
        [source.crates-io]
        replace-with = "vendored-sources"
        [source.vendored-sources]
        directory = "$cargoDeps"
        EOF
        export CARGO_NET_OFFLINE=true
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild
        mkdir -p build
        odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -- build release
        runHook postBuild
      '';

      desktopItems = [
        (pkgs.makeDesktopItem {
          name = "classeur";
          desktopName = "Classeur";
          genericName = "File Manager";
          comment = "A fast file manager: tabs, panels, search, preview, keyboard first.";
          exec = "classeur";
          icon = "classeur";
          categories = ["System" "FileTools" "FileManager"];
          keywords = ["files" "folders" "explorer" "browser"];
          startupWMClass = "classeur";
        })
      ];

      installPhase = ''
        runHook preInstall
        install -Dm755 build/classeur $out/bin/classeur
        for size in 16 32 64 128 256; do
          install -Dm644 assets/logo_$size.png "$out/share/icons/hicolor/''${size}x''${size}/apps/classeur.png"
        done
        install -Dm644 -t $out/share/doc/classeur LICENSE README.md CHANGELOG.md
        install -Dm644 ext/gui_toolkit/src/lucide/LICENSE.txt $out/share/doc/classeur/LUCIDE-LICENSE.txt
        runHook postInstall
      '';

      meta = {
        description = "A fast file manager for Linux and Windows";
        homepage = "https://classeur.sacha.house/";
        license = lib.licenses.mit;
        platforms = [system];
        mainProgram = "classeur";
      };
    };

    preCommitCheck = git-hooks.lib.${system}.run {
      package = pkgs.prek;
      src = ./.;
      hooks = {
        alejandra.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
  in {
    packages.${system} = {
      inherit classeur odin;
      default = classeur;
    };
    apps.${system}.default = {
      type = "app";
      program = "${classeur}/bin/classeur";
    };
    checks.${system} = {
      pre-commit = preCommitCheck;
      inherit classeur;
    };
    formatter.${system} = pkgs.alejandra;

    devShells.${system}.default = pkgs.mkShell {
      # (sway: classeurtool shots)
      packages = [odin] ++ (with pkgs; [cargo rustc sway]) ++ preCommitCheck.enabledPackages;
      buildInputs = [pkgs.fontconfig];
      shellHook =
        preCommitCheck.shellHook
        + ''
          export LD_LIBRARY_PATH=${lib.makeLibraryPath runtime}
        '';
    };
  };
}
