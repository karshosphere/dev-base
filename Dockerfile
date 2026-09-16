# base image for every project: alpine + vim, git, curl, claude-code
#
# build:
#   docker build -t dev-base:latest \
#     --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" .
FROM alpine:latest

ARG USERNAME=dev
ARG UID=1000
ARG GID=1000

# the claude-code musl build needs libgcc, libstdc++ and a system ripgrep at runtime
RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        git \
        less \
        libgcc \
        libstdc++ \
        openssh-client \
        ripgrep \
        tzdata \
        vim

# anthropic's signed apk repository, key checked against the checksum published in the docs
RUN wget -q -O /etc/apk/keys/claude-code.rsa.pub \
        https://downloads.claude.ai/keys/claude-code.rsa.pub \
    && echo "395759c1f7449ef4cdef305a42e820f3c766d6090d142634ebdb049f113168b6  /etc/apk/keys/claude-code.rsa.pub" \
        | sha256sum -c - \
    && echo "https://downloads.claude.ai/claude-code/apk/stable" >> /etc/apk/repositories \
    && apk add --no-cache claude-code

# macos hands out gids that alpine already assigns (20 is staff on the host, dialout here),
# so join the group that owns the gid instead of failing to create a second one
RUN group="$(awk -F: -v gid="${GID}" '$3 == gid { print $1 }' /etc/group)" \
    && if [ -z "$group" ]; then \
           addgroup -g "${GID}" "${USERNAME}"; \
           group="${USERNAME}"; \
       fi \
    && adduser -D -u "${UID}" -G "$group" -s /bin/bash "${USERNAME}"

# the container never owns the repo it works on, so let git trust whatever is bind mounted in.
# this is a system level setting, the mounted ~/.gitconfig stays untouched
RUN git config --system --add safe.directory '*'

# pre-create the bind mount targets so docker does not create them root owned at run time.
# ~/.vim is the symlink that makes vim pick up the mounted ~/.config/vim: it is both a vimrc
# search location and part of the default runtimepath, so plugins and colours resolve too
RUN mkdir -p "/home/${USERNAME}/.config/vim" "/home/${USERNAME}/.claude" /workspace \
    && touch "/home/${USERNAME}/.gitconfig" \
    && ln -s "/home/${USERNAME}/.config/vim" "/home/${USERNAME}/.vim" \
    && chown -R "${UID}:${GID}" "/home/${USERNAME}" /workspace

USER ${USERNAME}
ENV USER=${USERNAME}
ENV HOME=/home/${USERNAME}
ENV XDG_CONFIG_HOME=/home/${USERNAME}/.config
ENV SHELL=/bin/bash
ENV PATH=/home/${USERNAME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# alpine ships busybox as `vi`, and busybox vi reads no vimrc at all. with neither variable
# set, claude-code's ctrl+g picks the first of code/vi/nano on PATH and so lands on busybox
# rather than the vim installed above: name the real binary explicitly
ENV EDITOR=vim
ENV VISUAL=vim

# keeps .claude.json and .credentials.json inside the mounted directory rather than
# dropping them loose in the home directory, so one mount covers all of claude's state
ENV CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude

# the musl build cannot use the ripgrep bundled with claude-code, point it at the apk one
ENV USE_BUILTIN_RIPGREP=0
# claude-code comes from apk here, so there is nothing for its background updater to do
ENV DISABLE_AUTOUPDATER=1

WORKDIR /workspace
CMD ["bash"]
