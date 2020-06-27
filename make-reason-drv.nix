{ name, src, yarnLock ? "${src}/yarn.lock", packageJSON ? "${src}/package.json"
, yarnNix ? null, nodeEnv ? "production", ocaml_exported ? null
, modulesPreBuild ? "", preInstallFixup ? "", doCheck ? false, preBuild ? ""
, preCheck ? "", installPhase ? ''
  if [[ -d build ]]; then
    mv build $out
  elif [[ -d dist ]]; then
    mv dist $out
  else
    echo "No build or dist found in output dir. Provide a custom installPhase"
    exit -1
  fi
'', localDeps ? [ ], shellHook ? "", postFixup ? "" }:
{ stdenv, writeScript, callPackage, yarn, nodejs, rsync, bs-platform
, ocamlPackages, utillinux }:
let

  node_modules = callPackage (mkYarnModulesWithBsPlatform {
    name = "${name}-modules";
    inherit yarnLock packageJSON yarnNix localDeps postFixup;
    version = "0.0.0";
    preBuild = modulesPreBuild;
  }) { };

  bringModules = ''
    cp  --reflink=auto -R --no-preserve=mode \
      ${node_modules}/node_modules .
    (chmod -R a+rwx node_modules 2>/dev/null) || true
  '';

  yarnPreinstall = ''
    # yarn preinstall was not executed by yarn2nix so run it here and fixup
    if grep -q '"preinstall"' package.json; then
      yarn preinstall
    fi
    ${preInstallFixup}
  '';
  mkYarnModulesWithBsPlatform = { name, version, yarnLock, packageJSON
    , yarnNix ? null
      # This list should contain all NPM packages which live in the all repository
      # we'd like to include in the node_modules dir
    , localDeps ? [ ], preBuild ? "", postFixup ? "" }:
    { stdenv, mkYarnModules, bs-platform, mkYarnNix }:
    (stdenv.lib.overrideDerivation (mkYarnModules {
      inherit name version yarnLock packageJSON;
      pname = "${name}-${version}";

      yarnNix = if yarnNix == null then mkYarnNix yarnLock else yarnNix;

      # This yarn `preBuild` hook is executed before yarn install is called
      # by yarn2nix copies all localDeps into the build dir so
      # yarn can find them in the place it expects them
      preBuild = ''
        ${stdenv.lib.concatMapStrings (path: "unpackFile ${path};") localDeps}
      '';
    }) (old: {
      propagatedBuildInputs = (old.propagatedBuildInputs or [ ])
        ++ [ bs-platform ];
      phases = old.phases ++ [ "fixupPhase" ];
      fixupPhase = ''
        ( cd $out
          chmod +x node_modules/.bin/*
          # Remove the unusable (do to it being un-compiled) bs-platform
          # that yarn2nix has brought for us and link in the node2nix-generated
          # one which actually works
          # rm -rf node_modules/bs-platform
          # ln -s ${bs-platform} node_modules/bs-platform
          rm -rf node_modules/bs-platform/linux/bsb.exe
          rm -rf node_modules/bs-platform/lib/bsb.exe
          mkdir -p node_modules/bs-platform/lib
          mkdir -p node_modules/bs-platform/linux
          ln -s ${bs-platform}/bin/bsb node_modules/bs-platform/linux/bsb.exe
          ln -s ${bs-platform}/bin/bsb node_modules/bs-platform/lib/bsb.exe
          ${postFixup}
        )
      '';
    }));

in stdenv.mkDerivation {
  inherit name src doCheck preBuild preCheck installPhase;

  nativeBuildInputs = [
    nodejs
    yarn
    ocamlPackages.ocaml
    ocamlPackages.reason
    node_modules
    rsync
    utillinux
  ];

  buildPhase = ''

    # First bring in the node_modules from the "modules" derivation
    ${bringModules}
    ${yarnPreinstall}

    ${stdenv.lib.optionalString (ocaml_exported != null) ''
      # Copy ocaml_exported types
      chmod -R u+w .
      rsync -a ${ocaml_exported}/ ./
      chmod -R u+w .
    ''}

    # Finally, build!
    mkdir -p lib
    export NODE_ENV=${nodeEnv}
    runHook preBuild
    yarn build
  '';

  checkPhase = ''
    runHook preCheck
    yarn test
  '';

  # The shellHook provides some functions useful when in a nix-shell
  shellHook = ''
    copy_nix_node_modules() {
      if [ -d node_modules ]; then
        echo "Will not copy node_modules because node_modules already exists"
        echo "To proceed move it elsewhere or delete it and run this command again"
      else
        ${bringModules}
      fi
    }
    nix_yarn_install() {
      copy_nix_node_modules
      ${yarnPreinstall}
    }
    ${shellHook}
  '';

  passthru = { inherit node_modules ocaml_exported; };
}
