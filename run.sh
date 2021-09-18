#!/bin/bash

repo_url="$1"
branch="$2"
path="$3"

webroot="/webroot"

if [ -z "$branch" ]; then
  echo "Usage: $0 repo_url.git branch"
  exit 1
fi
if [ -z "$path" ]; then
  path="/"
fi

echo "Repository: $repo_url, branch: $branch, path: $path"

# check out the repo and the specific publication source
git config --global advice.detachedHead false
git clone "$repo_url" "/target"
cd "/target"
git fetch -p
git checkout "origin/$branch"
git reset --hard HEAD
git clean -d --force
git submodule update --init

cd ./"$path"
# determine whether we should use jekyll
if [ -f ".nojekyll" ]; then
  echo "Found .nojekyll file in root of repo - not using jekyll to process the site."
else
  echo "Using jekyll to build the site..."

  bundle config set --local system 'true'
  bundle install

  bundle exec jekyll build --incremental
  #bundle exec jekyll serve --host 0.0.0.0 --incremental --watch

  if [ -d "_site" ]; then
    # move to the jekyll generated site (for the next copy command)
    cd "_site"
  else
    echo "WARNING: Failed to generate site using Jekyll - serving the publication path anyway as a fallback" >&2
  fi
fi
# copy all files from the site to the web root
mkdir -vp "$webroot"
cp -rv ./* "$webroot"

# launch the webserver in the background - see nginx_site.conf for site configuration
nginx

service nginx status
if [ "$?" != 0 ]; then
  echo "Did not succeed in starting nginx - see above for details." >&2
  exit 1
fi

echo "Webserver running.  Watching for source changes..."
cd "/target"
# monitor for any upstream changes and rebuild
while true; do
  sleep 30
  # TODO
done
