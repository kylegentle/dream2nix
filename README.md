<p align="center">
<img width="400" src="https://gist.githubusercontent.com/DavHau/755fed3774e89c0b9b8953a0a25309fa/raw/e2a12a60ae49aa5eb11b42775abdd1652dbe63c0/dream2nix-01.png">
</p>

## [WIP] dream2nix - A framework for 2nix tools

dream2nix is a framework for 2nix converters (converting from other build systems to nix).
It focuses on the following aspects:

- Modularity
- Customizability
- Maintainability
- Nixpkgs Compatibility (not enforcing IFD)
- Code de-duplication across 2nix converters
- Code de-duplication in nixpkgs
- Risk free opt-in FOD fetching (no reproducibility issues)
- Common UI across 2nix converters
- Reduce effort to develop new 2nix solutions
- Exploration and adoption of new nix features
- Simplified updating of packages

The goal of this project is to create a standardized, generic, modular framework for 2nix solutions, aiming for better flexibility, maintainability and usability.

The intention is to integrate many existing 2nix converters into this framework, thereby improving many of the previously named aspects and providing a unified UX for all 2nix solutions.

### Test the experimental version of dream2nix
There are different ways how dream2nix can be invoked (CLI, flake, In-tree, IFD).
A simple way to use dream2nix is to drop the following `flake.nix` inside the repository of the project intended to be packaged:
```nix
{
  inputs.dream2nix.url = "github:nix-community/dream2nix";
  outputs = { self, dream2nix }@inputs:
    let
      dream2nix = inputs.dream2nix.lib.init {
        # modify according to your supported systems
        systems = [ "x86_64-linux" ];
        config.projectRoot = ./. ;
      };
    in dream2nix.makeFlakeOutputs {
      source = ./.;

      # configure package builds via overrides
      packageOverrides = {
        # name of the package
        package-name = {
          # name the override
          add-pre-build-steps = {
            # override attributes
            preBuild = "...";
            # update attributes
            buildInputs = old: old ++ [ pkgs.hello ];
          };
        };
      };
    };
}
```
After adding the flake.nix, execute the following commands to list the packages which can be built:
```shell
git add ./flake.nix
nix flake show
```

### Watch the recent presentation
[![dream2nix - A generic framework for 2nix tools](https://gist.githubusercontent.com/DavHau/755fed3774e89c0b9b8953a0a25309fa/raw/3c8b2c56f5fca3bf5c343ffc179136eef39d4d6a/dream2nix-youtube-talk.png)](https://www.youtube.com/watch?v=jqCfHMvCsfQ)

### Further Reading

- [Summary of the core concepts and benefits](/docs/concepts-and-benefits.md)
- [How would this improve the packaging situation in nixpkgs](/docs/nixpkgs-improvements.md)
- [Override System](/docs/override-system.md)
- [Contributors Guide](/docs/contributors-guide.md)

### Community
matrix: https://matrix.to/#/#dream2nix:nixos.org

