{
  mkShell,
  python3,
  python-kidra,
  pyright,
  nix-tree,
  swagger-cli,
  dive
}:
mkShell {
  packages = [
    (python3.withPackages (
      py-pkgs:
      with py-pkgs;
      [
        black
        pyflakes
        isort
        ipython
        jupyter
      ]
      ++ (python-kidra.propagatedBuildInputs)
    ))
    pyright
    nix-tree
    swagger-cli
    dive
  ];
}
