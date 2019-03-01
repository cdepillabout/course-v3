{ nixpkgs ? null }:

let
  nixpkgsSrc =
    if isNull nixpkgs
      then
        builtins.fetchTarball {
          # nixpkgs-19.03 as of 2019-03-01.
          url = "https://github.com/NixOS/nixpkgs/archive/07e2b59812de95deeedde95fb6ba22d581d12fbc.tar.gz";
          sha256 = "1yxmv04v2dywk0a5lxvi9a2rrfq29nw8qsm33nc856impgxadpgf";
        }
      else nixpkgs;
  pkgs = import nixpkgsSrc {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };
in

with pkgs;

let
  myPython = python37;

  fastai = myPython.buildPythonPackage rec {
    pname = "fastai";
    version = "1.0.46";

    src = fetchPypi {
      inherit pname version;
      sha256 = "6aefa6ff89a993af7a7af40d3df3d0387d6663df99797981ec41b1431ec6d1e3";
    };

    propagatedBuildInputs = [ ];

    checkInputs = [
      # pytest
      # testpath
      # responses
    ];

    # Disable test that needs some ini file.
    # Disable test that wants hg
    checkPhase = ''
      #HOME=$(mktemp -d) pytest -k "not test_invalid_classifier and not test_build_sdist"
    '';
  };

  myPythonPackages = ps: with ps; [
    fastai
    ipykernel
    numpy
    pandas
    pytorch
    scikitlearn
    scipy
    torchvision
  ];

  myJupyter = jupyter.override {
    definitions = {
      python3 =
        let
          env = python37.withPackages myPythonPackages;
        in {
          displayName = "Python 3";
          argv = [
            "${env.interpreter}"
            "-m"
            "ipykernel_launcher"
            "-f"
            "{connection_file}"
          ];
          language = "python";
          logo32 = "${env.sitePackages}/ipykernel/resources/logo-32x32.png";
          logo64 = "${env.sitePackages}/ipykernel/resources/logo-64x64.png";
        };
    };
  };

in

mkShell {
  name = "fast.ai-course-jupyter-env";
  buildInputs = [
    myJupyter
  ];
  inputsFrom = [
    # git
    # libxml2
    # libxslt
    # libzip
    # openssl
    # mypython.env
    # stdenv
    # taglib
    # zlib
  ];
  shellHook = ''
    # Need to set the source date epoch to 1980 because python's zip thing is terrible?
    export SOURCE_DATE_EPOCH=315532800
  '';
}
