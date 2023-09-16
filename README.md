This is a Jekyll project.

## Development environment

Setup Ruby and Jekyll on your machine. Follow [Jekyll's step-by-step setup and installation guide](https://jekyllrb.com/docs/step-by-step/01-setup/).

## Run it locally

Clone the project and run the following:

```
bundle exec jekyll serve --livereload
```

By default it serves on loopback. To make it accessible from your IP on other devices:

```
bundle exec jekyll serve --livereload -H 0.0.0.0
```

## Build it locally

The build is done using Jekyll:

```
bundle exec jekyll build
```

This will populate contents in ```_site``` directory.

To build for production set the environment variable:

```
JEKYLL_ENV=production bundle exec jekyll build
```

## Emulate for Firebase

This is a great feature provided by Firebase, allowing to validate its configuration and making sure ```_site``` works.

```
firebase emulators:start
```

## Build and Push to Docker Hub

This website can be built as a Docker image for two platforms.

For amd64:

```
sudo docker buildx build --platform linux/amd64 -t agitatedkepler/mfrancisdev:amd64 . --push
```

...then on Ubuntu:

```
sudo docker run -p 3000:80 --pull always agitatedkepler/mfrancisdev:amd64
```

For arm/v7:

```
sudo docker buildx build --platform linux/arm/v7 -t agitatedkepler/mfrancisdev:armv7l . --push
```

...then on Raspberry Pi:

```
docker run -p 3000:80 --pull always agitatedkepler/mfrancisdev:armv7l
```

When the Docker image has been built using GitHub Actions the `latest` one can be run on either architecture:

```
docker run -p 3000:80 --pull always agitatedkepler/mfrancisdev:latest
```
