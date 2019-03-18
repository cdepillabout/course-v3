# This derivation creates a small shell script that can be run to start a
# Jupyter notebook.  This Jupyter notebook should have all the libraries needed
# for working through the fast.ai Practical Deep Learning for Coders course,
# v3.
#
# In order to build the shell script and all dependencies, first you need to
# install nix (https://nixos.org/nix/download.html).  Then, just run
# `nix-build` in this directory.
#
# The only tricky thing this derivation does is setting up paths so that CUDA
# will work correctly.  This derivation takes a `nvidiaLibsPath` argument that
# should be a string corresponding to the path that contains your CUDA
# libraries.  By default it is "/usr/lib/x86_64-linux-gnu", which works on
# Ubuntu, but may need to be changed for other distributions.
#
# Here is how you can change it when running `nix-build`:
#
# $ nix-build --argstr nvidiaLibsPath /usr/local/lib
#
# The output shell script assumes you have the NVIDIA driver version 394
# installed on your system.  You may need to edit the small shell script at the
# end of this file if you have a different version of the NVIDIA driver.
#
# Once you've built the script with `nix-build`, you can directly run it:
#
# $ ./result/bin/run-fastai-jupyter
#
# This should start Jupyter running with a Python kernel with fastai, pytorch,
# numpy, etc.
#
# You can access this Jupyter notebook on http://localhost:8888.


{ # This allows you to use a different nixpkgs version.  Although it is
  # suggested to leave this as null so that you get the known working version
  # of nixpkgs.
  nixpkgs ? null
  # This should be a string to the directory that contains CUDA libraries, like
  # libcuda.so, libnvidia-fatbinaryloader.so.*, libnvidia-ptxjitcompiler.so,
  # libnvidia-ml.so, etc.
  #
  # The output derivation uses LD_PRELOAD to make sure all of these necessary
  # libraries get loaded.  This works well on Ubuntu, but there is probably a
  # better way to do it if you are on NixOS.
, nvidiaLibsPath ? "/usr/lib/x86_64-linux-gnu"
}:

assert builtins.isString nvidiaLibsPath;

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
  # Import nixpkgs and makre sure that cudaSupport is enabled.  This is needed
  # for compiling pytorch with CUDA support.  allowUnfree needs to be true to
  # build CUDA.
  pkgs = import nixpkgsSrc {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };
in

with pkgs;

let

  # Override some python packages with known working versions.
  myPythonPackageOverrides = self: super: {

    pytorch = super.pytorch.overridePythonAttrs (oldAttrs: rec {
      # The hardcoded version of nixpkgs only has pytorch-1.0.0.  This version
      # of pytorch has bugs with code that operates using the multiprocess
      # library.  These bugs appear to have been fixed in pytorch-1.0.1.
      version = "1.0.1";
      pname = "pytorch";
      src = fetchFromGitHub {
        owner  = "pytorch";
        repo   = "pytorch";
        rev    = "v${version}";
        fetchSubmodules = true;
        sha256 = "0xs09i1rk9n13a9i9aw5i7arny5zfsxj2c23ahpb20jdgnc4rr4v";
      };
    });

    # This is needed for fastai.
    fastprogress = self.buildPythonPackage rec {
      pname = "fastprogress";
      version = "0.1.20";

      src = self.fetchPypi {
        inherit pname version;
        sha256 = "1afrhrr9l8pn7gzr5f5rscj9x64vng7n33cxgl95s022lbc4s489";
      };

      # Disable tests because they fail.
      doCheck = false;
    };

    # This is needed for fastai.
    nvidia-ml-py3 = self.buildPythonPackage rec {
      pname = "nvidia-ml-py3";
      version = "7.352.0";

      src = self.fetchPypi {
        inherit pname version;
        sha256 = "0xqjypqj0cv7aszklyaad7x3fsqs0q0k3iwq7bk3zmz9ks8h43rr";
      };
    };

    # Version of fastai that works with the Practical Deep Learning for Coders
    # course v3.
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

      # fastai tests fail.
      doCheck = false;
    };

    ftfy = super.ftfy.overridePythonAttrs (oldAttrs: {
      # These need to be set for the tests to succeed.
      LC_ALL = "C.UTF8";
      LANG = "C.UTF8";
    });

  };

  # myPython is defined to be python-3.7 with our package overrides from above.
  myPython = python37.override { packageOverrides = myPythonPackageOverrides; };

  # These are the packages we want available to the Python kernel running in
  # Jupyter.  You can add more python packages if you need them.
  myPythonPackages = with myPython.pkgs; [
    fastai
    ipykernel
    ipywidgets # I think ideally this would be myIpywidgets we have defined below.
    numpy
    pandas
    pytorch
    scikitlearn
    scipy
    torchvision
    widgetsnbextension # I think ideally this would be myWidgetsnbextension we have defined below.
  ];

  # This is the python environment that contains myPythonPackages.  This will
  # be the environment used in the Python kernel in Jupyter.
  myPythonEnv = myPython.buildEnv.override {
    extraLibs = myPythonPackages;
    # Both msgpack and msgpack-python try to install the same files.
    ignoreCollisions = true;
  };

  myJupyter = jupyter.override {
    # This makes sure Jupyter is built with our python package overrides.
    python3 = myPython;
    definitions = {
      # This is the Python kernel we have defined above.
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

  # ipywidgets needs to have it's notebook argument overridden with
  # myJupyter.  This is so that we don't get collisions when creating
  # myJupyterEnv.
  myIpywidgets = myPython.pkgs.ipywidgets.override {
    notebook = myJupyter;
    widgetsnbextension = myWidgetsnbextension;
  };

  # widgetsnbextension needs to have it's notebook argument overridden with
  # myJupyter.  This is so that we don't get collisions when creating
  # myJupyterEnv.
  myWidgetsnbextension = myPython.pkgs.widgetsnbextension.override {
    notebook = myJupyter;
    ipywidgets = myIpywidgets;
  };

  # myJupyterEnv is an environment that contains Jupyter and some extensions
  # (like ipywidgets and widgetsnbextension).  Extensions have to be enabled
  # for some things in Jupyter to work.  Also, make sure you trust your
  # Jupyter notebooks, or some things may not work correctly.
  myJupyterEnv = myPython.buildEnv.override {
    extraLibs = [
      myJupyter
      myIpywidgets
      myWidgetsnbextension
    ];
  };

  # This is needed to download datasets from kaggle.
  kaggle = with myPython.pkgs; buildPythonApplication rec {
    pname = "kaggle";
    version = "1.5.3";

    src = fetchPypi {
      inherit pname version;
      sha256 = "02ghghq62pdc656s34zs3l2rmflxykd8g6ggav0dg8vj87w6p39b";
    };

    propagatedBuildInputs = [
      certifi
      dateutil
      python-slugify
      requests
      six
      tqdm
    ];

    doCheck = false;
  };

  run-fastai-jupyter-script =
    # This writes a shell script that can be run to start the Jupyter notebook.
    writeShellScriptBin "run-fastai-jupyter" ''
      # This is needed because Python's zip implementation doesn't understand old
      # dates.
      export SOURCE_DATE_EPOCH=315532800

      # Need to preload CUDA.  This assumes that the NVIDIA driver version 396 is
      # being used.  You may need to change this line if you're using a different
      # version of the NVIDIA driver.
      export LD_PRELOAD="${nvidiaLibsPath}/libcuda.so.1 ${nvidiaLibsPath}/libnvidia-fatbinaryloader.so.396.54 ${nvidiaLibsPath}/libnvidia-ptxjitcompiler.so ${nvidiaLibsPath}/libnvidia-ml.so"

      # Start the Jupyter notebook and listen on 0.0.0.0.  Delete the `--ip
      # 0.0.0.0` argument if you only want to listen on localhost.
      ${myJupyterEnv}/bin/jupyter-notebook --ip 0.0.0.0
    '';
in

symlinkJoin {
  name = "run-fastai-jupyter-script-plus-tools";
  paths = [
    kaggle
    run-fastai-jupyter-script
  ];
}
