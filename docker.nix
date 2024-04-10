{
  nix2container,
  python-kidra,
  buildEnv,
  runCommand,
  wlo-topic-assistant,
  wlo-classification,
  its-jointprobability,
}:
nix2container.buildImage {
  name = python-kidra.pname;
  tag = python-kidra.version;

  config = {
    Cmd = [ "${python-kidra}/bin/python-kidra" ];
    ExposedPorts = {
      "8080/tcp" = { };
    };
  };

  # create an empty /tmp directory for playwright (playwright assumes there to
  # be a /tmp directory and will fail if it does not exist -- nix does not
  # create one for the image by default)
  copyToRoot = buildEnv {
    name = "tmp";
    pathsToLink = [ "/tmp" ];
    paths = [
      (runCommand "mk-tmp" { } ''
        mkdir -p $out/tmp
      '')
    ];
  };

  # separate out some of the larger dependencies into their own layers, so that
  # we don't need to push / pull them every time
  layers = (
    map
      (
        { pkg, maxLayers }:
        nix2container.buildLayer {
          deps = [ pkg ];
          inherit maxLayers;
        }
      )
      [
        {
          pkg = wlo-topic-assistant;
          maxLayers = 40;
        }
        {
          pkg = wlo-classification;
          maxLayers = 30;
        }
        {
          pkg = its-jointprobability;
          maxLayers = 20;
        }
      ]
  );
  maxLayers = 5;
}
