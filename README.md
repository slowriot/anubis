Full documentation TODO

Deploy to Akash using the `deploy.yaml` manifest file.

To test git pages locally, use `jekyll` and `bundle` in the publication root directory:
```bundle install && bundle exec jekyll serve --incremental --watch```

Run the build and host container in a local Docker instance:
```docker build -t my_image . && docker run -p 4000:4000 -e PUBLISH_REPO="https://github.com/daattali/beautiful-jekyll.git" -e PUBLISH_BRANCH="gh-pages" -e PUBLISH_PATH="/" my_image```

For convenience, you can quickly halt all docker containers with:
```docker kill $(docker ps -q)```

...and clean up disk space used by all containers with:
```docker system prune -a```
