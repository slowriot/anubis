Documentation WIP

Run a build in a local Docker instance:
```docker build -t my_image . && docker run -p 4000:4000 -e PUBLISH_REPO="https://github.com/daattali/beautiful-jekyll.git" -e PUBLISH_BRANCH="gh-pages" -e PUBLISH_PATH="/" my_image```
