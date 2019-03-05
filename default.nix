{ nixpkgs ? null
, nvidiaLibsPath ? "/usr/lib/x86_64-linux-gnu"
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

  myPythonPackageOverrides = self: super: {
    fastprogress = self.buildPythonPackage rec {
      pname = "fastprogress";
      version = "0.1.20";

      src = self.fetchPypi {
        inherit pname version;
        sha256 = "1afrhrr9l8pn7gzr5f5rscj9x64vng7n33cxgl95s022lbc4s489";
      };

      doCheck = false;
    };

    nvidia-ml-py3 = self.buildPythonPackage rec {
      pname = "nvidia-ml-py3";
      version = "7.352.0";

      src = self.fetchPypi {
        inherit pname version;
        sha256 = "0xqjypqj0cv7aszklyaad7x3fsqs0q0k3iwq7bk3zmz9ks8h43rr";
      };
    };

    fastai = self.buildPythonPackage rec {
      pname = "fastai";
      version = "1.0.46";

      src = self.fetchPypi {
        inherit pname version;
        sha256 = "1px9j8zair0dcbi5rsdzrmnlwkiy56q5rcqwna5qg59c1jb94xnl";
      };

      propagatedBuildInputs = with self; [
        beautifulsoup4
        bottleneck
        # dataclasses  # This is not supported with python37.
        fastprogress
        matplotlib
        numexpr
        numpy
        nvidia-ml-py3
        packaging
        pandas
        pillow
        pytorch
        pyyaml
        requests
        scipy
        spacy
        torchvision
        typing
      ];

      checkInputs = with self; [
        pytest
        responses
      ];

      doCheck = false;
    };

    ftfy = super.ftfy.overridePythonAttrs (oldAttrs: {
      # These need to be set for the tests to succeed.
      LC_ALL = "C.UTF8";
      LANG = "C.UTF8";
    });
  };

  # This allows you to choose between python-3.6 and python-3.7.
  #myPython = python36.override { packageOverrides = myPythonPackageOverrides; };
  myPython = python37.override { packageOverrides = myPythonPackageOverrides; };

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

#mkShell {
#  name = "fast.ai-course-jupyter-env";
#  buildInputs = [
#    # You can either use myPythonEnv or myJupyter as a build input, but you
#    # can't have both.
#    myJupyter
#    #myPythonEnv
#  ];
#  inputsFrom = [ ];
#  shellHook = ''
#    # Need to set the source date epoch to 1980 because python's zip thing is terrible?
#    export SOURCE_DATE_EPOCH=315532800

#    # Need to preload CUDA.
#  '';
#}

writeShellScriptBin "run-fastai-jupyter" ''
  export SOURCE_DATE_EPOCH=315532800

  # Need to preload CUDA.
  export LD_PRELOAD="${nvidiaLibsPath}/libcuda.so.1 ${nvidiaLibsPath}/libnvidia-fatbinaryloader.so.396.54 ${nvidiaLibsPath}/libnvidia-ptxjitcompiler.so ${nvidiaLibsPath}/libnvidia-ml.so"

  ${myJupyter}/bin/jupyter-notebook --ip 0.0.0.0
  #${myPythonEnv}/bin/ipython
''
