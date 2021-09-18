FROM debian:latest

# disable installation of suggested and recommended packages
RUN echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf \
  && echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf

# get needed system packages
RUN apt-get update \
  && apt-get upgrade \
  && apt-get install -y \
    git \
    ruby-dev \
    binutils \
    build-essential \
    libffi-dev \
    libssl-dev \
    bundler \
    nginx \
    rsync

# configure the webserver
COPY nginx_site.conf /etc/nginx/sites-available/default

# copy run scripts
COPY run.sh run_wrapper.sh /

# execute
CMD ["/run_wrapper.sh", "/run.sh"]
