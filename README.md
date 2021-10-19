# Anubis - Git-based webpages for Akash and Radicle

Host a website anonymously, using decentralised [Akash](https://akash.network/) resources, directly from a [Radicle](https://radicle.xyz/) or git repository.  Updating the repository will rebuild and update the website automatically.  Existing [GitHub Pages](https://pages.github.com/) repositories can be migrated with no alteration.

Anubis runs on Akash, and fetches a git repository - either from a public git url on the internet, or a repository on Radicle - and renders it as a webpage.  This is effectively identical to how GitHub Pages works, but without the requirement to host your content on Github (although it will also work with Github URLs).

Anubis can also be run locally, or on other hosting providers - anywhere you can execute a [Docker](https://www.docker.com/) image.

## The Akash part
Deploying on the Akash system allows for decentralised, anonymous, censorship-resistant hosting, at a lower price than equivalent resources from major cloud providers such as AWS.

Anubis provides a set of scripts to automatically deploy its image on Akash, requesting a default set of computing resources (which can be adjusted in `deploy.yaml`).  It gets bids from Akash providers, finds the best offer, and prompts you to accept it.

Akash hosting is paid for with a cryptocurrency token, AKT.  For more info, see "Payment" below.

## The Radicle part
Radicle provides decentralised, peer to peer git repository hosting.  The advantage of using Radicle here is removing any reliance on centralised git hosting providers, which again increases censorship resistance and prevents reliance on any one provider.

Any existing git repository can be uploaded to Radicle with no modification, and all git features and history are retained.

It is not necessary to use Radicle to host your repository - you can also just provide a normal https git URL, or even your existing Github repository if you already use GitHub Pages.  Anubis is designed to be flexible enough to support either seamlessly.

## Jekyll & nginx hosting in Docker
Akash allows you to quickly deploy a Docker container to computing resources with any specifications you require.  This repository contains the source for a Docker image which does all the hard work.  This fetches a git repository and renders a website using Jekyll, in a very similar way to how GitHub Pages works behind the scenes.

You do not need to build the Docker image, or have Docker installed locally, to run Anubis.  A pre-built Docker image is uploaded by the maintainer to the Docker registry, and this is used by default - see "quick start" below.

Anubis aims to emulate the specific features and configuration of GitHub Pages, so any pages you may already be hosting with GitHub Pages can be smoothly transitioned to render with Anubis with no changes required to your pages.  If you find an inconsistency between how Anubis and GitHub Pages renders a site, please raise an issue.

Anubis frequently checks for updates in the repository, and if a change has been found, it will automatically rebuild the website.  To push changes to your site, all you have to do is commit a change to your repo.  This check happens every 30 seconds by default - the delay can be configured in `deploy.yaml`.

The webserver used for the site is nginx.  The default site configuration can be tweaked in `docker/nginx_site.conf`.


# Dependencies
- [akash CLI](https://docs.akash.network/guides/deploy#part-1-install-akash)
- curl: `apt install curl`
- jq: `apt install jq`
- yq: `pip install yq`

# Setup for Akash
Prior to using the deploy scripts to deploy to Akash, you need to [create a wallet](https://docs.akash.network/guides/wallet).

If you haven't ordered any Akash deployments before, you will also need to [create a certificate](https://docs.akash.network/guides/deployment#create-a-certificate).

You can skip this portion if you want to run the Docker container locally or on hosting other than Akash.

# Paying for deployment
Deployments are paid for with the AKT cryptocurrency token.  You can buy the token on [various exchanges](https://akash.network/token).

At the time of writing, you must have a minimum of 5AKT in your wallet - this is [held in escrow](https://docs.akash.network/glossary/escrow) for the duration of the deployment, and will be returned to you, minus the hosting costs you accrue.

Typical costs for running a server with default settings, at the time of writing, are just 1uAKT per block (uAKT = 1/1,000,000th of an AKT).  At the time of writing this is approximately equivalent to $1.17 per month.

## Estimating costs
A script is provided to estimate costs.  This is also called by the deploy script, to give you an estimate of costs before confirming a bid.  You can call it directly with:
```
./estimate_cost.sh 3
```
(where 3 is the amount in uAKT).

# Quick start
Edit `deploy.yaml` to configure your deployment.  You can configure all aspects of the deployment, but to get started, you only need to update the `PUBLISH_REPO`, `PUBLISH_BRANCH` and `PUBLISH_PATH` variables, to point to the repository you want to use.  Alternatively, a simple default is provided to verify everything works.

To deploy an Anubis instance to Akash, simply run
```
deploy.sh -y
```
This will get bids to the container with the repo you specified in deploy.yaml, automatically select the lowest bidder, and deploy without further confirmation.  You will receive a URL for your newly deployed website on the commandline.



# Scripts
## deploy.sh
Execute with `./deploy.sh`.

The script will verify all dependencies are present, and check that a suitable wallet exists; if more than one wallet is present on the system, it will prompt you to select the one you want to use.  It does not attempt to verify that you have enough funds, so please make sure you have sufficient funding for the esc>

The script downloads the latest list of nodes, and automatically selects the best one based on its ping time relative to you.

The script sends the deployment request to the blockchain, and gives you a `dseq` number - you can use this to manage the deployment manually without the script, or to close it down later.

The script automatically chooses the best bidder for the deployment - it waits a pre-defined amount of time, collects bids, and chooses the lowest bidder, then asks you interactively to confirm.  If there is more than one bidder at the lowest price, it selects randomly between them.  If you don't want to confirm manually, call the script with `deploy.sh -y` to automatically accept the lowest bid.

The script then reports the address of the provider it's chosen, and sends the manifest.  Once the manifest has been accepted, you get a report of the lease status.

The script then gives you a URL and port, which you can open with your browser.  Bear in mind it can take a minute or two for the image to spin up, once the lease has been created, so be patient if you can't connect immediately.  Once it comes up, it can take a few minutes for the site to build - but in the interim, Anubis will display a holding message on the site.

The script also generates `akash` commands for you to run if you want to retrieve the server console log, or the Kubernetes logs for the container.

The result of all transactions is verified by query commands after, so even if a transaction response gets lost due to a timeout or RPC error, the script (and the deployment) will continue and succeed.

## close.sh
Execute with `./close.sh`.

A convenience wrapper to automatically find the last deployment you launched, and tell akash to close it (i.e. shut it down) immediately.

You do not need to use this to close a deployment - it is provided just as a convenience function.  You can always just close down deployments manually as per the user guide, using the `dseq` number which was given to you by the `deploy.sh` script.  Guidance for how to close a deployment manually: https://docs.akas>

Be careful - if you have launched other deployments more recently, it will simply attempt to close the last one you launched.

## Debugging
The scripts can be run with various environment variables set for debugging purposes:
- `debug=true` - will print out every `akash` command the scripts are about to run, allowing you to duplicate the workflow or debug errors.
- `dry_run=true` - will only execute query commands, and will not commit anything to the blockchain.  Use in conjunction with `debug=true` to see a dry run of a deployment - however, bear in mind that as the new deployment won't be committed to the blockchain, subsequent commands querying that deployment will fail >

Example debugging commandline usage: `debug=true dry_run=true ./deploy.sh`

# Testing a site locally
You do not need to spin up an Akash instance, or even a local Docker container, to test changes to your GitHub Pages-style site before you push them.

To test a GitHub Pages-compatible site locally, use [jekyll](https://jekyllrb.com/) and [bundler](https://jekyllrb.com/docs/) in the publication root directory of the repo you wish to publish:
```
bundle install
bundle exec jekyll serve --incremental --watch
```

It is also possible to test your site with the full docker image locally before deploying to Akash - see below.


# Uploading to Radicle
Radicle projects are managed with the [Radicle Upstream](https://radicle.xyz/downloads.html) client.

Refer to the [Radicle documentation](https://docs.radicle.xyz/docs/using-radicle/creating-projects) for info on how to create and share Radicle projects.

Be aware that at the time of writing, Radicle is in active development, and replication is not fully functional on some public nodes - you may need to run your own seed node at this point to share a new project.  This project is configured with a seed node that is known to work at the time of writing.

An existing Radicle project that is known to work at the time of writing is `rad:git:hnrk8ueib11sen1g9n1xbt71qdns9n4gipw1o` - for debugging, try to feed this to Anubis as your first test.  If it succeeds, but your own project fails, the issue may be with replication on Radicle's side.


# Configuring deploy.yaml
For full details of how to configure deploy.yaml, refer to the [Akash documentation](https://docs.akash.network/cli/deployment#create-your-configuration).  This portion covers only the custom variables defined in this config:

- `PUBLISH_REPO` - the URL of the repository to publish.  Either a web git URL or a Radicle URN.
- `PUBLISH_BRANCH` - what branch of the repo should be published.  For GitHub Pages migrations this will usually be `gh-pages` by convention, otherwise you'll probably want to use `master`.
- `PUBLISH_PATH` - the subpath in your repository to use as the web root.  If you want to use the top level, just specify `/`.
- `RADICLE_SEEDS` - initial seeds to use to connect to the Radicle network.  If you're running your own org, or want a specific project on a given seed, update this.  Can be safely ignored (and deleted) for non-Radicle projects.
- `REFRESH_DELAY` - how many seconds to wait between checking for changes on the remote repository.


# Building the container
It should not normally be necessary to build the container yourself - a pre-built container is provided in the Docker registry, and used by default in `deploy.yaml`.  This should be ready to deploy.  However, there are some circumstances where you may wish to edit and build your own image.

All files relating to the Docker container live in the `Docker/` subdirectory.  If you wish to make any changes to the scripts which fetch the repository or run the webserver, or if you want to alter the build process, you will need to build your own version of the container.

Radicle is currently under intensive development at the time of writing, so it may be necessary to build a new version of the container to keep up with recent changes, if it stops working.  The Dockerfile is configured to use the latest Debian Docker image, to pull the latest Radicle source from github, and build the binaries.  If you find that something doesn't work with the image, the first thing to try is to rebuild it - which will get the latest versions of all necessary software - and see if that resolves the issue.

You will need `Docker` installed locally for this.

To build a new version of the Docker container and push it to the Docker registry:
```
docker build -t your_user_name/anubis docker/
docker push your_user_name/anubis
```

Once you're ready to push to Akash, don't forget to edit deploy.yaml and update `image:` to point to your new image, rather than the pre-built one included.

## Testing a site with the container locally

You can test the container locally with a repo of your choice (example repo given below) with:
```
docker run -p 4000:80 -e PUBLISH_REPO="https://github.com/daattali/beautiful-jekyll.git" -e PUBLISH_BRANCH="gh-pages" -e PUBLISH_PATH="/" your_user_name/anubis
```
This will expose the web service locally at [http://localhost:4000](http://localhost:4000).

## Stopping

For convenience, you can quickly halt all Docker containers with:
```docker kill $(docker ps -q)```

...and clean up disk space used by all containers with:
```docker system prune -a```

Be careful using these commands - they will affect all docker images you have running.

## Report issues

If you find a breaking change that requires a new image build, please also raise an issue on this repository, and the maintainer will endeavour to update the pre-built image.
