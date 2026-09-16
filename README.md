# dev-base

My personal dev container setup: a lite Alpine base image with vim, git and claude-code baked in,
plus a shared vimrc and a couple of compose templates to drop into new projects. Each project
is containerised in it's own container with shared vimrc and claude-code credentials.

`devenv.sh` is a thin wrapper round `docker compose` that handles starting, connecting to and
rebuilding the container, and copies a template into whichever project it's run from. It lives at
`~/.local/dev-base` and expects to be run from a project root.


## Usage

```
Usage: script [action] [args...]

Actions:
  up              start dev container
  down            stop dev container
  restart         restart dev container
  delete          remove dev container
  build           rebuild dev container image
  exec <CMD>      run CMD in dev container
  connect         open shell in dev container
  claude [args]   run claude in dev container
  list            list docker containers

Templates:
  tsetup          copy the full template .devcontainer into this project
  tmsetup         copy the mini template .devcontainer into this project
  tupdate         rebuild the dev-base:latest image from the base Dockerfile

Other:
  <action>        run entry from .commands file

Notes:
  - runs from git repo root if present
  - requires .devcontainer/compose.yaml with a dev service
  - requires the dev-base:latest image, build it with tupdate
  - templates and the base Dockerfile are read from $DEV_BASE_DIR
    (default ~/.local/dev-base, override by exporting DEV_BASE_DIR)
  - requires .commands for custom actions
```

* PS: add a symlink with a shorter alias, like:
```sh
$ ln -s ~/.local/dev-base/devenv.sh ~/.local/bin/d
```


## The .commands file

Anything that isn't one of the built-in actions above gets looked up in a `.commands` file at the
project root, which is where per-project shortcuts live. The idea is that the same short action
name means the same thing everywhere, even when the command behind it is completely different from
one project to the next. The format is one `name = 'command'` entry per line:

```
test = 'pytest -q'
serve = 'npm run dev'
logs = 'docker compose logs -f $@'
```

Any arguments are appended to the command, or substituted in place if the entry contains `$@`.
It's the same file [switchboard.nvim](https://github.com/karnull/switchboard.nvim) reads, so the
same shortcuts work from inside vim too.
