{
  dlib,
  lib,
}: let
  b = builtins;
  l = lib // builtins;
  nodejsUtils = import ../../utils.nix {inherit lib;};

  getPackageLock = tree: project:
    nodejsUtils.getWorkspaceLockFile tree project "package-lock.json";

  translate = {
    translatorName,
    utils,
    ...
  }: {
    project,
    source,
    tree,
    # translator args
    noDev,
    nodejs,
    ...
  } @ args: let
    b = builtins;

    dev = ! noDev;
    name = project.name;
    tree = args.tree.getNodeFromPath project.relPath;
    relPath = project.relPath;
    source = "${args.source}/${relPath}";
    workspaces = project.subsystemInfo.workspaces or [];

    packageLock = (getPackageLock args.tree project).jsonContent or null;

    packageJson =
      (tree.getNodeFromPath "package.json").jsonContent;

    packageLockDeps =
      if packageLock == null
      then {}
      else packageLock.dependencies or {};

    rootDependencies = packageLockDeps;

    packageJsonDeps = nodejsUtils.getPackageJsonDeps packageJson noDev;

    parsedDependencies =
      l.filterAttrs
      (name: dep: packageJsonDeps ? "${name}")
      packageLockDeps;

    identifyGitSource = dependencyObject:
    # TODO: when integrity is there, and git url is github then use tarball instead
    # ! (dependencyObject ? integrity) &&
      dlib.identifyGitUrl dependencyObject.version;

    getVersion = dependencyObject: let
      # example: "version": "npm:@tailwindcss/postcss7-compat@2.2.4",
      npmMatch = b.match ''^npm:.*@(.*)$'' dependencyObject.version;
    in
      if npmMatch != null
      then b.elemAt npmMatch 0
      else if identifyGitSource dependencyObject
      then "0.0.0-rc.${b.substring 0 8 (dlib.parseGitUrl dependencyObject.version).rev}"
      else if lib.hasPrefix "file:" dependencyObject.version
      then let
        path = getPath dependencyObject;
      in
        (
          b.fromJSON
          (b.readFile "${source}/${path}/package.json")
        )
        .version
      else if lib.hasPrefix "https://" dependencyObject.version
      then "unknown"
      else dependencyObject.version;

    getPath = dependencyObject:
      lib.removePrefix "file:" dependencyObject.version;

    pinVersions = dependencies: parentScopeDeps:
      lib.mapAttrs
      (
        pname: pdata: let
          selfScopeDeps = parentScopeDeps // dependencies;
          requires = pdata.requires or {};
          dependencies = pdata.dependencies or {};
        in
          pdata
          // {
            depsExact =
              lib.forEach
              (lib.attrNames requires)
              (reqName: {
                name = reqName;
                version = getVersion selfScopeDeps."${reqName}";
              });
            dependencies = pinVersions dependencies selfScopeDeps;
          }
      )
      dependencies;

    pinnedRootDeps =
      pinVersions rootDependencies rootDependencies;

    createMissingSource = name: version: {
      type = "http";
      url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
    };
  in
    utils.simpleTranslate
    ({
      getDepByNameVer,
      dependenciesByOriginalID,
      ...
    }: rec {
      inherit translatorName;
      location = relPath;

      # values
      inputData = pinnedRootDeps;

      defaultPackage =
        if name != "{automatic}"
        then name
        else
          packageJson.name
          or (throw (
            "Could not identify package name. "
            + "Please specify extra argument 'name'"
          ));

      packages =
        {"${defaultPackage}" = packageJson.version or "unknown";}
        // (nodejsUtils.getWorkspacePackages tree workspaces);

      mainPackageDependencies =
        lib.mapAttrsToList
        (pname: pdata: {
          name = pname;
          version = getVersion pdata;
        })
        (lib.filterAttrs
          (pname: pdata: ! (pdata.dev or false) || dev)
          parsedDependencies);

      subsystemName = "nodejs";

      subsystemAttrs = {nodejsVersion = args.nodejs;};

      # functions
      serializePackages = inputData: let
        serialize = inputData:
          lib.mapAttrsToList # returns list of lists
          
          (pname: pdata:
            [
              (pdata
                // {
                  inherit pname;
                  depsExact =
                    lib.filter
                    (req: (! (pdata.dependencies."${req.name}".bundled or false)))
                    pdata.depsExact or {};
                })
            ]
            ++ (lib.optionals (pdata ? dependencies)
              (lib.flatten
                (serialize
                  (lib.filterAttrs
                    (pname: data: ! data.bundled or false)
                    pdata.dependencies)))))
          inputData;
      in
        lib.filter
        (pdata:
          dev || ! (pdata.dev or false))
        (lib.flatten (serialize inputData));

      getName = dependencyObject: dependencyObject.pname;

      inherit getVersion;

      getSourceType = dependencyObject:
        if identifyGitSource dependencyObject
        then "git"
        else if lib.hasPrefix "file:" dependencyObject.version
        then "path"
        else "http";

      sourceConstructors = {
        git = dependencyObject:
          dlib.parseGitUrl dependencyObject.version;

        http = dependencyObject:
          if lib.hasPrefix "https://" dependencyObject.version
          then rec {
            version = getVersion dependencyObject;
            url = dependencyObject.version;
            hash = dependencyObject.integrity;
          }
          else if dependencyObject.resolved == false
          then
            (createMissingSource
              (getName dependencyObject)
              (getVersion dependencyObject))
            // {
              hash = dependencyObject.integrity;
            }
          else rec {
            url = dependencyObject.resolved;
            hash = dependencyObject.integrity;
          };

        path = dependencyObject: rec {
          path = getPath dependencyObject;
        };
      };

      getDependencies = dependencyObject:
        dependencyObject.depsExact;
    });
in rec {
  version = 2;

  inherit translate;

  projectName = {source}: let
    packageJson = "${source}/package.json";
    parsed = b.fromJSON (b.readFile packageJson);
  in
    if b.pathExists packageJson && parsed ? name
    then parsed.name
    else null;

  compatible = {source}:
    dlib.containsMatchingFile
    [
      ''.*package-lock\.json''
      ''.*package.json''
    ]
    source;

  extraArgs = {
    name = {
      description = "The name of the main package";
      examples = [
        "react"
        "@babel/code-frame"
      ];
      default = "{automatic}";
      type = "argument";
    };

    noDev = {
      description = "Exclude development dependencies";
      type = "flag";
    };

    # TODO: this should either be removed or only used to select
    # the nodejs version for translating, not for building.
    nodejs = {
      description = "nodejs version to use for building";
      default = "14";
      examples = [
        "14"
        "16"
      ];
      type = "argument";
    };
  };
}
