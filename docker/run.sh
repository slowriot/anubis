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

git config --global advice.detachedHead false

last_commit=""

function jekyll_build {
  echo "Building web content..."
  cd "/target/$path"
  # determine whether we should use jekyll
  if [ -f ".nojekyll" ]; then
    echo "Found .nojekyll file in root of repo - not using jekyll to process the site."
  else
    echo "Using jekyll to build the site..."

    bundle config set --local system 'true'
    bundle install

    bundle exec jekyll build --incremental

    if [ -d "_site" ]; then
      # move to the jekyll generated site (for the next copy command)
      cd "_site"
    else
      echo "WARNING: Failed to generate site using Jekyll - serving the publication path anyway as a fallback" >&2
    fi
  fi
  # copy all files from the selected site to the web root
  cp -rv ./* "$webroot"
}

function update_repo {
  cd "/target"
  # check out the repo and the specific publication source
  git fetch -p
  latest_commit=$(git log --all --oneline | head -1)
  if [ "$latest_commit" != "$last_commit" ]; then
    echo "New commits have been made since we last checked - updating repo"
    git checkout "origin/$branch"
    git reset --hard HEAD
    git clean -d --force
    git submodule update --init

    last_commit=$(git log --all --oneline | head -1)

    jekyll_build
  else
    echo "No changes since our last check - no need for rebuild"
  fi
}
echo
echo "Repository: $repo_url, branch: $branch, path: $path"

# check out the repo and the specific publication source
git clone "$repo_url" "/target"
if [ "$?" != 0 ]; then
  echo "Unable to clone repository $repo_url - cannot continue" >&2
  exit 1
fi
mkdir -vp "$webroot"
update_repo

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
  update_repo
done
