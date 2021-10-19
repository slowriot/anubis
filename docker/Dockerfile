FROM debian:latest

# disable installation of suggested and recommended packages
RUN echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf \
  && echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf

# get needed system packages
RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y \
    git \
    curl \
    cmake \
    ruby-dev \
    binutils \
    build-essential \
    libffi-dev \
    libssl-dev \
    bundler \
    nginx \
    rsync \
    jq \
    apg \
    tmux && \
  apt-get autoremove && \
  rm -rf /var/lib/apt/lists/*

# install rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
  . ~/.profile && \
  cargo --version && \
  rustc --version

# build and install radicle client binaries
RUN . ~/.profile && \
  git clone https://github.com/radicle-dev/radicle-upstream.git && \
  cd radicle-upstream && \
  cargo build --release && \
  mv target/release/git-remote-rad target/release/libapi.rlib target/release/radicle-proxy /usr/local/bin && \
  cd / && \
  rm -rf /radicle-upstream /usr/local/cargo/registry /usr/local/cargo/.package-cache

# configure the webserver
COPY nginx_site.conf /etc/nginx/sites-available/default

# copy run scripts
COPY run.sh run_wrapper.sh radicle_fetch.sh /

# execute
CMD ["/run_wrapper.sh", "/run.sh"]
