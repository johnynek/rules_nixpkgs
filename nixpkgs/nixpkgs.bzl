"""Rules for importing Nixpkgs packages."""

def _nixpkgs_git_repository_impl(ctx):
  ctx.file('BUILD', content = 'filegroup(name = "%s", glob = ["**"])' % ctx.name)
  # XXX Hack because ctx.path below bails out if resolved path not a regular file.
  ctx.file(ctx.name)
  ctx.download_and_extract(
    url = "https://github.com/NixOS/nixpkgs/archive/%s.tar.gz" % ctx.attr.revision,
    stripPrefix = "nixpkgs-" + ctx.attr.revision,
  )

nixpkgs_git_repository = repository_rule(
  implementation = _nixpkgs_git_repository_impl,
  attrs = {
    "revision": attr.string(),
  },
  local = False,
)

def _nixpkgs_package_impl(ctx):
  if ctx.attr.build_file and ctx.attr.build_file_content:
    fail("Specify one of 'build_file' or 'build_file_content', but not both.")
  elif ctx.attr.build_file:
    ctx.symlink(ctx.attr.build_file, "BUILD")
  elif ctx.attr.build_file_content:
    ctx.file("BUILD", content = ctx.attr.build_file_content)
  else:
    ctx.template("BUILD", Label("@io_tweag_rules_nixpkgs//nixpkgs:BUILD.pkg"))

  if ctx.attr.nix_file and ctx.attr.nix_file_content:
    fail("Specify one of 'nix_file' or 'nix_file_content', but not both.")
  elif ctx.attr.nix_file:
    ctx.symlink(ctx.attr.nix_file, "default.nix")
  elif ctx.attr.nix_file_content:
    expr_args = ["-E", ctx.attr.nix_file_content]
  else:
    expr_args = ["-E", "import <nixpkgs> {}"]

  expr_args.extend([
    "-A", ctx.attr.attribute_path
          if ctx.attr.nix_file or ctx.attr.nix_file_content
          else ctx.attr.attribute_path or ctx.attr.name,
  ])

  # If neither repository or path are set, leave empty which will use
  # default value from NIX_PATH.
  path = []
  if ctx.attr.repository and ctx.attr.path:
    fail("'repository' and 'path' fields are mutually exclusive.")
  if ctx.attr.repository:
    # XXX Another hack: the repository label typically resolves to
    # some top-level package in the external workspace. So we use
    # dirname to get the actual workspace path.
    path = ["-I", "nixpkgs={0}".format(ctx.path(ctx.attr.repository).dirname)]
  if ctx.attr.path:
    path = ["-I", "nixpkgs={0}".format(ctx.attr.path)]

  nix_build = ["nix-build"] + path + ["--no-out-link"] + expr_args

  res = ctx.execute(nix_build, quiet = False)
  if res.return_code == 0:
    output_path = res.stdout.splitlines()[-1]
  else:
    fail("Cannot build Nix attribute %s." % ctx.attr.name)
  ctx.symlink(output_path, "nix")

nixpkgs_package = repository_rule(
  implementation = _nixpkgs_package_impl,
  attrs = {
    "attribute_path": attr.string(),
    "nix_file": attr.label(allow_single_file = [".nix"]),
    "nix_file_content": attr.string(),
    "path": attr.string(),
    "repository": attr.label(),
    "build_file": attr.label(),
    "build_file_content": attr.string(),
  },
  local = True,
  environ = ["NIX_PATH"],
)
