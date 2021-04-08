---
author: mfrancis
---

How I host this website, briefly explained.

<h2>The Code</h2>

This is a static website built using [Jekyll](https://jekyllrb.com/), which I came to learn is a great tool for building static websites because development is fast and responsive. The site can be served locally for an immediate feedback loop:
```
bundle exec jekyll serve --livereload
```

The source code is stored in a public GitHub repository so feel free to take a look.

I'm using GitHub Actions for the CI/CD pipeline to automatically build and deploy this site to its hosting servers upon merge on ```main```. The pipeline can also be examined in the source code.

<h2>Domain Name</h2>

The main idea of a name system is to provide a way to identify devices using names that make sense to humans. I for sure don't want to remember the IP addresses hosting this website so let's pick a registrar and register with DNS to let our machines do the work for us.

I've chosen [Google Domains](https://domains.google.com). We can see this by querying DNS:

<pre class="command-line language-bash" data-user="martin" data-host="sentry" data-output="2">
<code>whois mfrancis.dev | grep Registrar:
Registrar: Google LLC.</code>
</pre>

Great. Now we need some IP address(-es) we can use in our resource records.

<h2>Firebase</h2>

They say Firebase is there to help both small and large enterprises to run their apps. I can't say I'm the target audience... however given their Free Plan I won't say no to at least trying it out -- which I suppose is the point :).

I was pleasantly surprised how easy and seamless it was to onboard Firebase. I used their CLI to setup the project in a matter of minutes. You can follow the [setup guide](https://firebase.google.com/docs/web/setup) to try this out for yourself.

I have configured Firebase to deploy the contents of ```_site``` -- the Jekyll build output directory. After doing a build locally we can emulate what Firebase thinks the website looks like according to the build artefacts:

```
firebase emulators:start
```

Upon initialisation Firebase helped generate the GitHub Actions file which I used as a basis to setup automated build & deploy, however I needed to tweak this -- specifically the build stage -- to make it work with Jekyll. It paid off quickly though as the automated pipeline builds and deploys to Firebase upon a merge on ```main```. Sweet.

Firebase also makes it straightforward to integrate its Hosting with my domain by giving me two IPv4 addresses I can use. We can verify that by looking it up in DNS:

<pre class="command-line language-bash" data-user="martin" data-host="sentry" data-output="2-3">
<code>host mfrancis.dev
mfrancis.dev has address 151.101.1.195
mfrancis.dev has address 151.101.65.195</code>
</pre>

For now I'm only using Firebase Hosting and Firebase Analytics but I'm pleased with the experience and tooling so far.

<h2>GitHub Pages</h2>

This is a simple and straightforward one. As I was looking for ways to build Jekyll using GitHub Actions I came across [github.com/limjh16/jekyll-action-ts](https://github.com/limjh16/jekyll-action-ts). Anyone on GitHub Free can host their public GitHub repositories on GitHub Pages.

Similarly to the setup with Firebase we can use GitHub Actions to build & deploy to GitHub Pages automatically.

By default the hosted site is accessible under ```m-francis.github.io``` though it would be nicer if it was under ```mfrancis.dev``` instead. GitHub Pages expects custom domains to have a CNAME definition in DNS; unfortunately we can't add CNAME records, and keep Firebase IPs, for the root domain so I've defined a subdomain instead. We can verify this:

<pre class="command-line language-bash" data-user="martin" data-host="sentry" data-output="2-6">
<code>host gh-pages.mfrancis.dev
gh-pages.mfrancis.dev is an alias for m-francis.github.io.
m-francis.github.io has address 185.199.108.153
m-francis.github.io has address 185.199.109.153
m-francis.github.io has address 185.199.110.153
m-francis.github.io has address 185.199.111.153</code>
</pre>

<h2>Summary</h2>

Static website built using Jekyll. Source code and CI/CD pipeline in GitHub. Hosting done with Firebase and GitHub Pages.
