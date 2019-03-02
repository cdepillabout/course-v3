{ nixpkgs ? null
, ldLibraryPathStr ? "/usr/lib/x86_64-linux-gnu"
}:

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

  fastprogress = myPython.pkgs.buildPythonPackage rec {
    pname = "fastprogress";
    version = "0.1.20";

    src = myPython.pkgs.fetchPypi {
      inherit pname version;
      sha256 = "1afrhrr9l8pn7gzr5f5rscj9x64vng7n33cxgl95s022lbc4s489";
    };

    doCheck = false;
  };

  nvidia-ml-py3 = myPython.pkgs.buildPythonPackage rec {
    pname = "nvidia-ml-py3";
    version = "7.352.0";

    src = myPython.pkgs.fetchPypi {
      inherit pname version;
      sha256 = "0xqjypqj0cv7aszklyaad7x3fsqs0q0k3iwq7bk3zmz9ks8h43rr";
    };
  };

  fastai = myPython.pkgs.buildPythonPackage rec {
    pname = "fastai";
    version = "1.0.46";

    src = myPython.pkgs.fetchPypi {
      inherit pname version;
      sha256 = "1px9j8zair0dcbi5rsdzrmnlwkiy56q5rcqwna5qg59c1jb94xnl";
    };

    propagatedBuildInputs = [
      myPython.pkgs.beautifulsoup4
      myPython.pkgs.bottleneck
      fastprogress
      myPython.pkgs.matplotlib
      nvidia-ml-py3
      myPython.pkgs.pandas
      myPython.pkgs.spacy
      myPython.pkgs.torchvision
      myPython.pkgs.typing
    ];

    doCheck = false;
  };

  myPythonPackages = with myPython.pkgs; [
    fastai
    ipykernel
    numpy
    pandas
    pytorch
    scikitlearn
    scipy
    torchvision
  ];

  myPythonEnv = myPython.buildEnv.override {
    extraLibs = myPythonPackages;
    # Both msgpack and msgpack-python try to install the same files.
    ignoreCollisions = true;
  };

  myJupyter = jupyter.override {
    definitions = {
      python3 = {
        displayName = "Python 3";
        argv = [
          "${myPythonEnv.interpreter}"
          "-m"
          "ipykernel_launcher"
          "-f"
          "{connection_file}"
        ];
        language = "python";
        logo32 = "${myPythonEnv.sitePackages}/ipykernel/resources/logo-32x32.png";
        logo64 = "${myPythonEnv.sitePackages}/ipykernel/resources/logo-64x64.png";
      };
    };
  };

in

mkShell {
  name = "fast.ai-course-jupyter-env";
  buildInputs = [
    # You can either use myPythonEnv or myJupyter as a build input, but you
    # can't have both.
    myJupyter
    #myPythonEnv
  ];
  inputsFrom = [ ];
  shellHook = ''
    # Need to set the source date epoch to 1980 because python's zip thing is terrible?
    export SOURCE_DATE_EPOCH=315532800

    # Need to preload CUDA.
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${ldLibraryPathStr}"
  '';
}
