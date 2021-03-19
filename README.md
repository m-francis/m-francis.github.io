This is a Jekyll project.

## Development environment

Setup Ruby and Jekyll on your machine. Follow [Jekyll's step-by-step setup and installation guide](https://jekyllrb.com/docs/step-by-step/01-setup/).

## Run it locally

Clone the project and run the following:

```
bundle exec jekyll serve --livereload
```

By default it servers on loopback. To make it accessible from your IP on other devices:

```
bundle exec jekyll serve --livereload -H 0.0.0.0
```

## Build it locally

The build is done using Jekyll:

```
bundle exec jekyll build
```

This will populate contents in ```_site``` directory.

To build for production (includes Firebase config) set the environment variable:

```
JEKYLL_ENV=production bundle exec jekyll build
```

## Emulate for Firebase

This is a great feature provided by Firebase, allowing to validate its configuration and making sure ```_site``` works.

```
firebase emulators:start
```
