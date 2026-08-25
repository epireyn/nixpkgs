{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  nix-update-script,
  nixosTests,
  sqlite,
  autoPatchelfHook,
  stdenv,
  musl,
}:
let
  version = "2.6.1";
  sharedMeta = {
    maintainers = with lib.maintainers; [
      epireyn
    ];
    license = lib.licenses.mit;
    homepage = "https://aurral.org";
    platforms = lib.platforms.all;
  };

  src = fetchFromGitHub {
    owner = "lklynet";
    repo = "aurral";
    rev = "v${version}";
    hash = "sha256-4UugohC9D/d9AuqQA/Av8aOrF/QyGmLwOZgjVZb/FC0=";
  };

  nodejs = nodejs_22;

  frontend = buildNpmPackage {
    pname = "aurral-frontend";
    inherit version;

    inherit nodejs;

    inherit src;

    npmDepsHash = "sha256-Qa/TcKzMEY/w8FWKMiHUeqVB9cMxxWtEwF30y0nndkg=";

    npmWorkspace = "frontend";

    npmInstallFlags = [
      "--include-workspace-root=false"
    ];

    env = rec {
      APP_VERSION = version;
      GITHUB_REPO = "lklynet/aurral";
      RELEASE_CHANNEL = "stable";
      VITE_APP_VERSION = APP_VERSION;
      VITE_GITHUB_REPO = GITHUB_REPO;
      VITE_RELEASE_CHANNEL = RELEASE_CHANNEL;
    };

    preBuild = ''
      cp -r $src/lib lib
    '';

    installPhase = ''
      runHook preInstall
      cp -r frontend/dist $out
      runHook postInstall
    '';

    passthru.updateScript = nix-update-script { };

    meta = sharedMeta // {
      description = "Frontend for Aurral";
    };
  };

in
buildNpmPackage (finalAttrs: {
  pname = "aurral";
  inherit version;

  inherit nodejs;

  inherit src;

  npmDepsHash = "sha256-Qa/TcKzMEY/w8FWKMiHUeqVB9cMxxWtEwF30y0nndkg=";

  npmWorkspace = "backend";

  npmInstallFlags = [
    "--omit=dev"
    "--include=optional"
    "--include-workspace-root=false"
  ];

  dontNpmBuild = true; # It is not meant to be built

  nativeBuildInputs = [
    autoPatchelfHook
  ]; # Needed for native libraries

  buildInputs = [
    sqlite
    stdenv.cc.cc.lib
    musl
  ]; # Needed for building honker-node native library

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{frontend,bin}

    cp -r $src/backend $out/backend
    ln -sf ${frontend} $out/frontend/dist
    cp -r ./lib $out/lib

    cp -r ./node_modules $out/lib
    rm $out/lib/node_modules/aurral-frontend
    rm $out/lib/node_modules/aurral-backend

    ln -sf ./lib/node_modules $out

    makeWrapper ${lib.getExe nodejs} $out/bin/aurral --add-flags "$out/backend/server.js"
    runHook postInstall
  '';

  passthru = {
    updateScript = nix-update-script { };
  };

  meta = sharedMeta // {
    description = "Open-source self-hosted music discovery and Lidarr companion";
    longDescription = "Aurral is the Lidarr companion for self-hosted music discovery. Best-in-class recommendations, rotating flows, and playlist downloads, built on Lidarr instead of replacing it.";
    mainProgram = "aurral";
  };
})
