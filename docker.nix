{
  lib,
  nix2container,
  python-kidra,
  buildEnv,
  runCommand,
  wlo-topic-assistant,
  wlo-classification,
  its-jointprobability,
}:
let
  # this function takes a list of image layers and nests them, such that all
  # previous layers are dependencies of later layers. this avoids duplicate
  # dependencies
  # from https://blog.eigenvalue.net/2023-nix2container-everything-once/
  foldImageLayers =
    let
      mergeToLayer =
        priorLayers: component:
        assert builtins.isList priorLayers;
        assert builtins.isAttrs component;
        let
          layer = nix2container.buildLayer (component // { layers = priorLayers; });
        in
        priorLayers ++ [ layer ];
    in
    layers: lib.foldl mergeToLayer [ ] layers;
in
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
  layers =
    let
      layerDefinitions = [
        {
          deps = [ wlo-classification ];
          # while we could probably increase the number of automatically
          # generated layers a bit, due to inherent redundancy between the
          # manually defined layers, choosing these such that the total number
          # of layers is less than 100 is always going to be safe (whereas
          # choosing something larger may cause issues)
          maxLayers = 25;
        }
        {
          deps = [ its-jointprobability ];
          maxLayers = 25;
        }
        {
          deps = [ wlo-topic-assistant ];
          maxLayers = 25;
        }
      ];
    in
    # de-duplicate the manually defined layers
    foldImageLayers layerDefinitions;
  maxLayers = 25;
}
