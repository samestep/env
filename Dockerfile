FROM ubuntu
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y curl git sudo xz-utils
RUN useradd -m -s /bin/bash agent \
    && usermod -aG sudo agent \
    && mkdir -m 0755 /nix \
    && chown agent /nix
USER agent
RUN curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --no-daemon \
    && mkdir -p ~/.config/nix \
    && echo 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf
ENV USER=agent
ENV PATH=/home/agent/.nix-profile/bin:$PATH
RUN git clone https://github.com/samestep/env.git ~/github/samestep/env \
    && ln -fsT ~/github/samestep/env ~/.config/home-manager \
    && nix run ~/github/samestep/env#home-manager -- init --switch -b backup
