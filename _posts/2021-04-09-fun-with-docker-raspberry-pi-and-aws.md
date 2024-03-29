---
author: mfrancis
title: Fun With Docker, Raspberry Pi, and AWS
---

I thought it would be fun to dockerize this website and try hosting it from my Raspberry Pi, and AWS.

I'm already using Jekyll to build the static representation of this website hence I can just use that output and serve it up from nginx inside a Docker container.

The plan:

<ul>
<li>Dockerize the Website (build and run the image locally)</li>
<li>Share the Image (push the image into Docker Hub)</li>
<li>Run Containers on Ubuntu and Raspbian (pull from Docker Hub)</li>
<li>Run Containers on AWS (push the image into Amazon ECR and run in Amazon ECS)</li>
</ul>

<h2>Dockerize the Website</h2>

Let's start by installing Docker. I run Ubuntu on my laptop so we can do this by following [these Docker docs](https://docs.docker.com/engine/install/ubuntu/). When done we can see it's functional by running the hello-world image:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-8">
<code>sudo docker run hello-world

Hello from Docker!
This message shows that your installation appears to be working correctly.
...
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
...</code>
</pre>

<i>Note: step 2 in the output mentions the CPU architecture of the system, namely `amd64`. This will become important later as we'll need to do additional things to provide support for Raspberry Pi that runs on `arm32v7`.</i>

Next, we'll need a web server to run inside the container; I've selected nginx for this purpose. We can locate [the nginx image](https://hub.docker.com/_/nginx) on Docker Hub where the documentation includes the instructions we need. Thus the `Dockerfile` looks like this:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2,3">
<code>cat Dockerfile 
FROM nginx
COPY _site /usr/share/nginx/html</code>
</pre>

It means I'm copying the contents of the Jekyll build output (which is in the same directory as the `Dockerfile`) into the directory used by nginx to host the static website. When nginx starts it will accept connections on tcp/80 by default.

Now that we have a `Dockerfile` we can build an image from the root directory:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-8">
<code>sudo docker build -t mfrancisdev .
Sending build context to Docker daemon  6.231MB
Step 1/2 : FROM nginx
 ---> b8cf2cbeabb9
Step 2/2 : COPY _site /usr/share/nginx/html
 ---> f3f772e9934b
Successfully built f3f772e9934b
Successfully tagged mfrancisdev:latest</code>
</pre>

To start it we can use `docker run` (it will bind the ports on the host's tcp/8080 to the container's tcp/80):

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2,4,5">
<code>sudo docker run -d -p 8080:80 mfrancisdev
e27b22dcc03ac68f7936694da5eec7d79ef2c98a756a0509119c7affcc025e92</code>
</pre>

To verify the container is running we can use `docker ps`:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-3">
<code>sudo docker ps
CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS          PORTS                  NAMES
e27b22dcc03a   mfrancisdev   "/docker-entrypoint.…"   15 seconds ago   Up 14 seconds   0.0.0.0:8080->80/tcp   confident_agnesi</code>
</pre>

...and we can also see the bytes are being served back to us when making an HTTP call to the loopback:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-22">
<code>curl -sv 'http://localhost:8080' > /dev/null
*   Trying 127.0.0.1:8080...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8080 (#0)
> GET / HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/7.68.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Server: nginx/1.19.8
< Date: Tue, 06 Apr 2021 07:49:12 GMT
< Content-Type: text/html
< Content-Length: 1581
< Last-Modified: Tue, 06 Apr 2021 07:45:58 GMT
< Connection: keep-alive
< ETag: "606c11b6-62d"
< Accept-Ranges: bytes
< 
{ [1581 bytes data]
* Connection #0 to host localhost left intact</code>
</pre>

Given that the `_site` directory itself is just 396K it would be good to know how big the Docker image is :)

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-3">
<code>sudo docker images mfrancisdev
REPOSITORY    TAG       IMAGE ID       CREATED         SIZE
mfrancisdev   latest    f3f772e9934b   7 minutes ago   133MB</code>
</pre>

Executing `docker images` tells us the grand total is 133M which makes sense given it's the size of the nginx image:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-3">
<code>sudo docker images nginx
REPOSITORY   TAG       IMAGE ID       CREATED       SIZE
nginx        latest    b8cf2cbeabb9   10 days ago   133MB</code>
</pre>

At this point I have containerized my static website, and I'm able to serve it from my development machine.

Now let's run it on a Raspberry Pi!

<h2>Running on Raspberry Pi</h2>

I want to build my website only once, hence I want to be able to build the Docker image on the same build server I build my website on.

I also do not want to export the image and <i>push</i> it across the network using rsync or similar mechanisms. Instead I want it to be <i>pulled</i> hence the simplest way then would be to integrate with a container registry such as [Docker Hub](https://docs.docker.com/get-started/04_sharing_app/) allowing us to pull the image from anywhere.

Let's start by installing Docker on Raspbian by following [these Docker docs](https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script). Once done we can see it's functional by running the hello-world image:

<pre class="language-bash command-line" data-user="pi" data-host="queen" data-output="2-13">
<code>sudo docker run hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
4ee5c797bcd7: Already exists 
Digest: sha256:308866a43596e83578c7dfa15e27a73011bdd402185a84c5cd7f32a88b501a24
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.
...
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (arm32v7)
...</code>
</pre>

<i>Note: the CPU architecture printed out in step 2 is `arm32v7`.</i>

The name of the Raspberry Pi is `queen`, and user `pi` has root permissions. Let's run containers as a non-root user, `martin`, by adding it to the `docker` group:

<pre class="language-bash command-line" data-user="pi" data-host="queen">
<code>sudo adduser martin
sudo usermod -aG docker martin</code>
</pre>

To test this out I can `ssh` to the node as myself and run the hello-world image without using `sudo`:

<pre class="language-bash command-line" data-user="martin" data-host="queen" data-output="2-8">
<code>docker run hello-world

Hello from Docker!
This message shows that your installation appears to be working correctly.
...
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (arm32v7)
...</code>
</pre>

The image is already in the cache so it doesn't need to download it again.

With Docker Hub's Free Plan we can get one private repository. My username has already been taken so let's pick the name of one of the earlier container runs for my account, hence my repository is `agitatedkepler/mfrancisdev` :)

To be able to push to the registry we need to login through the Docker CLI (whose default registry is Docker Hub):

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-7">
<code>sudo docker login -u agitatedkepler
Password: 
WARNING! Your password will be stored unencrypted in /root/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credentials-store

Login Succeeded</code>
</pre>

To be able to push the image we need to tag it for the Docker Hub repository:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu">
<code>sudo docker tag mfrancisdev agitatedkepler/mfrancisdev</code>
</pre>

...and then we can push it:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-11">
<code>sudo docker push agitatedkepler/mfrancisdev
Using default tag: latest
The push refers to repository [docker.io/agitatedkepler/mfrancisdev]
d32a385ed220: Pushed 
00436d7e1be2: Layer already exists 
9cb4f14884ef: Layer already exists 
0e426deef675: Layer already exists 
199e51fa0f59: Layer already exists 
7ddea056b71a: Layer already exists 
0270c2d5ad72: Layer already exists 
latest: digest: sha256:74da2fd4d0d4c4f40463fcb21f28e44fa92be6473d4be6365e4831163eb20e13 size: 1779</code>
</pre>

Now that the image is on Docker Hub let's see if we can pull it to the Pi:

<pre class="language-bash command-line" data-user="martin" data-host="queen" data-output="2-13">
<code>docker run -p 8080:80 --pull always agitatedkepler/mfrancisdev
latest: Pulling from agitatedkepler/mfrancisdev
ac2522cc7269: Already exists 
09de04de3c75: Already exists 
b0c8a51e6628: Already exists 
08b11a3d692c: Already exists 
a0e0e6bcfd2c: Already exists 
4fcb23e29ba1: Already exists 
45801035b98e: Pull complete 
Digest: sha256:74da2fd4d0d4c4f40463fcb21f28e44fa92be6473d4be6365e4831163eb20e13
Status: Downloaded newer image for agitatedkepler/mfrancisdev:latest
WARNING: The requested image's platform (linux/amd64) does not match the detected host platform (linux/arm/v7) and no specific platform was requested
standard_init_linux.go:219: exec user process caused: exec format error</code>
</pre>

As expected this fails to run because we built the image for `linux/amd64` not `linux/arm/v7` (indirectly because the default builder instance is for the system it executes on).

We need to build the Docker image for multiple architectures. We could use an emulator (QEMU) for this purpose, or we could use the Raspberry Pi node itself by utilizing the built-in support provided by Docker (experimental feature under [buildx](https://docs.docker.com/buildx/working-with-buildx/)). I'm going to use the latter to see how that works.

Let's start by editing the `dockerd` service config on the Pi:

<pre class="language-bash command-line" data-user="pi" data-host="queen">
<code>sudo systemctl edit docker.service</code>
</pre>

The following configuration instructs `dockerd` on the Pi to be exposed externally, thereby allowing us to connect to it from other machines:

<pre class="language-bash">
<code>[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375</code>
</pre>

Before we can use it we need to restart the service:

<pre class="language-bash command-line" data-user="pi" data-host="queen">
<code>sudo systemctl daemon-reload
sudo systemctl restart docker.service</code>
</pre>

...and now we can see it's listening on 2375 externally.

<pre class="language-bash command-line" data-user="pi" data-host="queen" data-output="2">
<code>sudo netstat -lntp | grep dockerd
tcp6    0    0 :::2375    :::*    LISTEN    591/dockerd</code>
</pre>

To test the setup from my development machine I can do `docker run` against the Pi by using the `DOCKER_HOST` env variable:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-8">
<code>DOCKER_HOST=queen:2375 docker run hello-world

Hello from Docker!
This message shows that your installation appears to be working correctly.
...
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (arm32v7)
...</code>
</pre>

<i>Note the architecture in the output is `arm32v7` which confirms it ran on the Pi.</i>

Let's create a new builder instance to instruct Docker to do `arm32v7` builds against `queen`:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2">
<code>sudo docker buildx create --use --name arm32v7build --platform linux/arm/v7 queen 
arm32v7build</code>
</pre>

We can verify by viewing all builder instances by running `docker buildx ls`:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-6">
<code>sudo docker buildx ls
NAME/NODE       DRIVER/ENDPOINT  STATUS   PLATFORMS
arm32v7build *  docker-container          
  arm32v7build0 tcp://queen:2375 inactive linux/arm/v7*
default         docker                    
  default       default          running  linux/amd64, linux/386</code>
</pre>

Before we can do a multi-platform build we need to tweak the `Dockerfile` by passing in the `--platform` arg for the target platform to `buildx`:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2,3">
<code>cat Dockerfile 
FROM --platform=$TARGETPLATFORM nginx
COPY _site /usr/share/nginx/html</code>
</pre>

Now we can do a build for the Raspberry Pi and push it to Docker Hub (note the `armv7l` tag I'm specifying for the image):

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-19">
<code>sudo docker buildx build --platform linux/arm/v7 -t agitatedkepler/mfrancisdev:armv7l . --push
[+] Building 4.7s (8/8) FINISHED                                          
 => [internal] load build definition from Dockerfile                 0.2s
 => => transferring dockerfile: 31B                                  0.2s
 => [internal] load .dockerignore                                    0.1s
 => => transferring context: 2B                                      0.0s
 => [internal] load metadata for docker.io/library/nginx:latest      2.6s
 => [auth] library/nginx:pull token for registry-1.docker.io         0.0s
 => [1/2] FROM docker.io/library/nginx@sha256:bae781e7f518e0fb02245  0.1s
 => => resolve docker.io/library/nginx@sha256:bae781e7f518e0fb02245  0.1s
 => [internal] load build context                                    0.1s
 => => transferring context: 1.23kB                                  0.0s
 => CACHED [2/2] COPY _site /usr/share/nginx/html                    0.0s
 => exporting to image                                               1.6s
 => => exporting layers                                              0.0s
 => => exporting manifest sha256:66a5f7da5af07a354798f8a8a69a8afd6a  0.0s
 => => exporting config sha256:dbfdbed8ff42644cfd5ac69de30e28519e61  0.0s
 => => pushing layers                                                1.2s
 => => pushing manifest for docker.io/agitatedkepler/mfrancisdev:ar  0.3s</code>
</pre>

Now we can pull the image with the `armv7l` tag on the Pi and run a container:

<pre class="language-bash command-line" data-user="martin" data-host="queen" data-output="2-5">
<code>docker run -d -p 8080:80 --pull always agitatedkepler/mfrancisdev:armv7l
armv7l: Pulling from agitatedkepler/mfrancisdev
Digest: sha256:66a5f7da5af07a354798f8a8a69a8afd6a7916db0c9238a722e2e564191f6dc3
Status: Image is up to date for agitatedkepler/mfrancisdev:armv7l
8dbb996a5f5cfeeefba24366eadb81bfc0912d77ff5e2e179db04c37a483af9e</code>
</pre>

...and to verify from my development machine against `queen`:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-22">
<code>curl -sv http://queen:8080 > /dev/null
*   Trying 192.168.1.120:8080...
* TCP_NODELAY set
* Connected to queen (192.168.1.120) port 8080 (#0)
> GET / HTTP/1.1
> Host: queen:8080
> User-Agent: curl/7.68.0
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Server: nginx/1.19.9
< Date: Tue, 06 Apr 2021 08:53:11 GMT
< Content-Type: text/html
< Content-Length: 1581
< Last-Modified: Tue, 06 Apr 2021 08:43:22 GMT
< Connection: keep-alive
< ETag: "606c1f2a-62d"
< Accept-Ranges: bytes
< 
{ [1581 bytes data]
* Connection #0 to host queen left intact</code>
</pre>

However, it's not very nice that we need to pull against a specific tag. It would be much nicer if we could pull-in the `latest` on both platforms and the machines would decide which image to download according to the CPU architecture.

To do this I'll do another build on my development machine and tag it for `amd64` and push it into Docker Hub:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-32">
<code>sudo docker buildx build --platform linux/amd64 -t agitatedkepler/mfrancisdev:amd64 . --push
[+] Building 38.7s (9/9) FINISHED                                         
 => [internal] load build definition from Dockerfile                 0.1s
 => => transferring dockerfile: 31B                                  0.1s
 => [internal] load .dockerignore                                    0.0s
 => => transferring context: 2B                                      0.0s
 => [internal] load metadata for docker.io/library/nginx:latest      3.5s
 => [auth] library/nginx:pull token for registry-1.docker.io         0.0s
 => [1/2] FROM docker.io/library/nginx@sha256:bae781e7f518e0fb0224  24.1s
 => => resolve docker.io/library/nginx@sha256:bae781e7f518e0fb02245  0.1s
 => => sha256:3be359fed358edc61cf876b2e243dd091fa3d 1.40kB / 1.40kB  0.3s
 => => sha256:b5fc821c48a15923de42ea88d788ecf513e65c367 895B / 895B  0.6s
 => => sha256:71a81b5270eb65fc7a27581432a7f1ffb38fb384a 602B / 602B  0.8s
 => => sha256:da3f514a642846dbe27bd407a7c5b073b972fb680 666B / 666B  1.0s
 => => sha256:6128033c842f93fdade243165510c7f59e 26.58MB / 26.58MB  10.8s
 => => sha256:75646c2fb4101d306585c9b106be1dfa7d8 27.14MB / 27.14MB  8.3s
 => => extracting sha256:75646c2fb4101d306585c9b106be1dfa7d82720baa  7.0s
 => => extracting sha256:6128033c842f93fdade243165510c7f59e60745991  3.3s
 => => extracting sha256:71a81b5270eb65fc7a27581432a7f1ffb38fb384aa  1.0s
 => => extracting sha256:b5fc821c48a15923de42ea88d788ecf513e65c367c  3.1s
 => => extracting sha256:da3f514a642846dbe27bd407a7c5b073b972fb680f  0.2s
 => => extracting sha256:3be359fed358edc61cf876b2e243dd091fa3d7ce63  0.2s
 => [internal] load build context                                    0.1s
 => => transferring context: 1.23kB                                  0.0s
 => [2/2] COPY _site /usr/share/nginx/html                           2.7s
 => exporting to image                                               7.6s
 => => exporting layers                                              2.1s
 => => exporting manifest sha256:849a6d4f1ec6e02ec4d48d48518b439a3e  0.0s
 => => exporting config sha256:32df98c748b07910f7869c009b575b63fdd8  0.0s
 => => pushing layers                                                4.6s
 => => pushing manifest for docker.io/agitatedkepler/mfrancisdev:am  0.8s
 => [auth] agitatedkepler/mfrancisdev:pull,push token for registry-  0.0s</code>
</pre>

Now that we have built images for both architectures we can create a manifest and push it as the `latest` image:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2,4">
<code>sudo docker manifest create agitatedkepler/mfrancisdev:latest agitatedkepler/mfrancisdev:amd64 agitatedkepler/mfrancisdev:armv7l
Created manifest list docker.io/agitatedkepler/mfrancisdev:latest
sudo docker manifest push agitatedkepler/mfrancisdev:latest
sha256:c7eb14cbeff71d93dd4b49e035708ba1a42d24312c7f17f4acdef46905cf8830</code>
</pre>

To test this we can force `docker run` to pull in the latest image:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-5">
<code>sudo docker run -d -p 8080:80 --pull always agitatedkepler/mfrancisdev:latest
latest: Pulling from agitatedkepler/mfrancisdev
Digest: sha256:c7eb14cbeff71d93dd4b49e035708ba1a42d24312c7f17f4acdef46905cf8830
Status: Image is up to date for agitatedkepler/mfrancisdev:latest
76e11620427280f08d21a5841ef67b428ad1571fc69691ffa521f1f2c5db1f27</code>
</pre>

<pre class="language-bash command-line" data-user="martin" data-host="queen" data-output="2-5">
<code>docker run -d -p 8080:80 --pull always agitatedkepler/mfrancisdev:latest
latest: Pulling from agitatedkepler/mfrancisdev
Digest: sha256:c7eb14cbeff71d93dd4b49e035708ba1a42d24312c7f17f4acdef46905cf8830
Status: Downloaded newer image for agitatedkepler/mfrancisdev:latest
a3f140e40d5ca69318f1d408bcfc0398ba19663fb037ab359d0c4a33d3450804</code>
</pre>

<i>Note how the digest checksums match on both machines.</i>

We can also do a single `buildx build` for both platforms and push them in under the `latest` tag, and run from `latest` on both platforms.

<pre class="language-bash command-line" data-user="martin" data-host="queen" data-output="2-27">
<code>sudo docker buildx build --no-cache --platform linux/amd64,linux/arm/v7 -t agitatedkepler/mfrancisdev:latest --push .
[+] Building 24.6s (12/12) FINISHED                                                                                                             
 => [internal] load build definition from Dockerfile                                                                                       0.1s
 => => transferring dockerfile: 31B                                                                                                        0.1s
 => [internal] load .dockerignore                                                                                                          0.0s
 => => transferring context: 2B                                                                                                            0.0s
 => [linux/amd64 internal] load metadata for docker.io/library/nginx:latest                                                                3.4s
 => [linux/arm/v7 internal] load metadata for docker.io/library/nginx:latest                                                               4.1s
 => [auth] library/nginx:pull token for registry-1.docker.io                                                                               0.0s
 => CACHED [linux/arm/v7 1/2] FROM docker.io/library/nginx@sha256:bae781e7f518e0fb02245140c97e6ddc9f5fcf6aecc043dd9d17e33aec81c832         0.0s
 => => resolve docker.io/library/nginx@sha256:bae781e7f518e0fb02245140c97e6ddc9f5fcf6aecc043dd9d17e33aec81c832                             0.1s
 => [internal] load build context                                                                                                          0.1s
 => => transferring context: 90.92kB                                                                                                       0.1s
 => CACHED [linux/amd64 1/2] FROM docker.io/library/nginx@sha256:bae781e7f518e0fb02245140c97e6ddc9f5fcf6aecc043dd9d17e33aec81c832          0.0s
 => => resolve docker.io/library/nginx@sha256:bae781e7f518e0fb02245140c97e6ddc9f5fcf6aecc043dd9d17e33aec81c832                             0.1s
 => [linux/amd64 2/2] COPY _site /usr/share/nginx/html                                                                                     0.3s
 => [linux/arm/v7 2/2] COPY _site /usr/share/nginx/html                                                                                    0.3s
 => exporting to image                                                                                                                    19.6s
 => => exporting layers                                                                                                                   10.7s
 => => exporting manifest sha256:b33fb35b2969ffd76b0fe7c6406a017c2ce8a31860e89f364276451d8845b2b5                                          0.0s
 => => exporting config sha256:71aa0a6d3249d4f9d41f547949ff3cc76d4ee2de034249638b491d84961ef110                                            0.0s
 => => exporting manifest sha256:7a23f85f6617308db9b14b4e62c831e0fa3fe80983a51182f9ae795901b3f9d9                                          0.0s
 => => exporting config sha256:475e42db8ef05b971d544884d3c36f23f8e1ad94026a45801e7dd97440d1801d                                            0.1s
 => => exporting manifest list sha256:2807a7c34108ed3dc2135ae826444e6356170ac25550049dc0bbe96bcb114690                                     0.2s
 => => pushing layers                                                                                                                      6.1s
 => => pushing manifest for docker.io/agitatedkepler/mfrancisdev:latest                                                                    2.4s
 => [auth] agitatedkepler/mfrancisdev:pull,push token for registry-1.docker.io                                                             0.0s</code>
</pre>

This allows the `latest` tag of the image to be used on both platforms.

<h3>GitHub Actions</h3>

I don't want to be manually constructing Docker images every time there's a change to this website. Let's make use of GitHub Actions to build the images and push them into Docker Hub. This is fairly well [documented on GitHub](https://docs.github.com/en/actions/guides/publishing-docker-images). I just need to ensure the repository secrets are defined, and that I'm using the `buildx` action in my workflow ([documented here](https://github.com/marketplace/actions/build-and-push-docker-images)).

My workflow in GitHub Actions uses the QEMU emulator to do the multi-platform builds. The changes (additions) required to my existing GitHub Actions workflow file are the following:

<pre class="language-bash">
<code>- name: Setup QEMU
  uses: docker/setup-qemu-action@v1

- name: Setup Docker Buildx
  uses: docker/setup-buildx-action@v1

- name: Login to DockerHub
  uses: docker/login-action@v1
  with:
    {% raw %}username: ${{ secrets.DOCKER_HUB_USERNAME }}{% endraw %}
    {% raw %}password: ${{ secrets.DOCKER_HUB_PASSWORD }}{% endraw %}

- name: Build and Push
  uses: docker/build-push-action@v2
  with:
    context: .
    platforms: linux/amd64,linux/arm/v7
    push: true
    tags: |
      {% raw %}${{ secrets.DOCKER_HUB_USERNAME }}/mfrancisdev{% endraw %}</code>
</pre>

Having gone through this exercise we have learnt how to do multi-platform Docker builds, and how to have an automated CI pipeline for Docker containers using GitHub Actions. This is a great start to continue integrating with AWS.

<h2>Running in AWS</h2>

To get the Docker image to AWS I'm going with a similar architecture to my set-up for Docker Hub and Raspberry Pi. I'll first integrate with Amazon ECR (Elastic Container Registry) using the support offered by the official [AWS for GitHub Actions](https://github.com/aws-actions) tooling. When pushing to ECR it's important the tag includes the full path to the registry.

<i>Side note: this tooling worked as long as I tried to push to a private ECR repository. When I tried it against a public one (with fewer restrictions and more generous allowances) I always ended up with `401 Not Authorized` even after setting fairly wide permissions for the IAM user.</i>

We'll need a user to be defined in Amazon IAM (Identity and Access Management) to be able to push from GitHub Actions to Amazon ECR. It's important the user has certain permissions granted, namely:

<pre class="language-bash">
<code>"Action": [
  "ecr:GetDownloadUrlForLayer",
  "ecr:BatchGetImage",
  "ecr:BatchCheckLayerAvailability",
  "ecr:PutImage",
  "ecr:InitiateLayerUpload",
  "ecr:UploadLayerPart",
  "ecr:CompleteLayerUpload"
]</code>
</pre>

To limit the scope of the user we'll define the resource it is authorized on:

<pre class="language-bash">
<code>"Resource": "arn:aws:ecr:$REGION:$ACCOUNT_ID:repository/mfrancisdev"</code>
</pre>

Once created Amazon IAM provides a password for the user. It's important we do not expose this publicly, hence we should store it as a secret in GitHub. We can then refer to the secrets in GitHub Actions:

<pre class="language-bash">
<code>- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v1
  with:
    {% raw %}aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}{% endraw %}
    {% raw %}aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}{% endraw %}
    aws-region: ap-southeast-1</code>
</pre>

Then we can login (this is similar to how we went about getting auth against Docker Hub):

<pre class="language-bash">
<code>- name: Login to Amazon ECR
  uses: aws-actions/amazon-ecr-login@v1
  id: login-ecr</code>
</pre>

...and the push stage now includes an additional tag to push:

<pre class="language-bash">
<code>- name: Build and Push
  uses: docker/build-push-action@v2
  with:
    context: .
    platforms: linux/amd64,linux/arm/v7
    push: true
    tags: |
      {% raw %}${{ secrets.DOCKER_HUB_USERNAME }}/mfrancisdev:latest{% endraw %}
      {% raw %}${{ steps.login-ecr.outputs.registry }}/mfrancisdev:latest{% endraw %}</code>
</pre>

This will push images into Amazon ECR every time the GitHub pipeline runs. However, being on the Amazon Free Tier my private repository is limited to 500 MB of content. To help me stay within the limits we can setup a Lifecycle Policy to automatically purge old images, as described [here](https://aws.amazon.com/blogs/compute/clean-up-your-container-images-with-amazon-ecr-lifecycle-policies/) and [here](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html).

Now that the image is in Amazon ECR we have a choice on how to run it. I won't go into much detail as there's plenty of resources available, but in summary I will go with Amazon ECS (Elastic Container Service) because it's simpler than Amazon EKS (Elastic Kubernetes Service). With ECS we have a choice between AWS Fargate (serveless) and EC2 (self-managed compute). I'm going with Fargate for this because it's simplest.

I must say the UX in Amazon is not great. It almost feels like an internal platform built by some large enterprise where the only way to get things done is to know the people to ask questions to :) I guess that's one more reason why "Cloud Architects" are now in demand.

After starting the service and task in Fargate we get a private and public IP which I could verify returned me the content of the website. However, my website is under `.dev` domain so I need a certificate. Thankfully there's Amazon Certificate Manager which provides these things out of the box; I requested a certificate for `*.aws.mfrancis.dev`.

My initial thought was to use a network load balancer in front of the container, however this would have required the container to be accepting connections on tcp/443, and subsequently a certificate inside the container. That would complicate it unnecessarily as I trust the communications link between the load balancer and the container. To setup end-to-end encryption one could follow [this guide](https://aws.amazon.com/blogs/containers/maintaining-transport-layer-security-all-the-way-to-your-container-using-the-application-load-balancer-with-amazon-ecs-and-envoy/) which simply offloads the problem to an instance of Envoy running on the node to decrypt and proxy the requests over tcp/80 on loopback.

To simplify this we can use an application load balancer (ALB) instead which decrypts the communications and forwards the requests to the container(s) within the VPC (Virtual Private Cloud) over tcp/80.

To allow external communications the security group associated with the EC2 instance needed to be updated to allow inbound tcp/443.

Ultimately I ended up with `https://fargate.aws.mfrancis.dev` serving the website out of a single container running in AWS ECS/Fargate.

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-4">
<code>host fargate.aws.mfrancis.dev
fargate.aws.mfrancis.dev is an alias for mfrancisdev-986243151.ap-southeast-1.elb.amazonaws.com.
mfrancisdev-986243151.ap-southeast-1.elb.amazonaws.com has address 54.251.177.216
mfrancisdev-986243151.ap-southeast-1.elb.amazonaws.com has address 13.228.245.29</code>
</pre>

We can get the certificate information using `nmap`:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-21">
<code>nmap -p 443 --script ssl-cert fargate.aws.mfrancis.dev
Starting Nmap 7.91 ( https://nmap.org ) at 2021-04-08 14:59 +08
Nmap scan report for fargate.aws.mfrancis.dev (13.228.245.29)
Host is up (0.0079s latency).
Other addresses for fargate.aws.mfrancis.dev (not scanned): 54.251.177.216
rDNS record for 13.228.245.29: ec2-13-228-245-29.ap-southeast-1.compute.amazonaws.com

PORT    STATE SERVICE
443/tcp open  https
| ssl-cert: Subject: commonName=*.aws.mfrancis.dev
| Subject Alternative Name: DNS:*.aws.mfrancis.dev
| Issuer: commonName=Amazon/organizationName=Amazon/countryName=US
| Public Key type: rsa
| Public Key bits: 2048
| Signature Algorithm: sha256WithRSAEncryption
| Not valid before: 2021-04-02T00:00:00
| Not valid after:  2022-05-01T23:59:59
| MD5:   2b33 fa99 b2c6 d00f 7f61 a57f de29 4982
|_SHA-1: 0441 4c17 4482 33a8 ff60 ebf3 68aa b037 f0c0 c6bb

Nmap done: 1 IP address (1 host up) scanned in 0.38 seconds</code>
</pre>

I was wondering whether we can discover the public IP address of the service instance, however `traceroute` just sends us down a rabbit hole:

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-18">
<code>traceroute fargate.aws.mfrancis.dev -m 50
traceroute to fargate.aws.mfrancis.dev (54.251.177.216), 50 hops max, 60 byte packets
 1  _gateway (192.168.1.254)  8.003 ms  4.032 ms  4.002 ms
 2  bb220-255-55-254.singnet.com.sg (220.255.55.254)  9.371 ms  9.353 ms  9.335 ms
 3  202.166.123.134 (202.166.123.134)  9.318 ms  9.933 ms  19.322 ms
 4  202.166.123.133 (202.166.123.133)  9.769 ms  10.161 ms  10.140 ms
 5  ae8-0.tp-cr03.singnet.com.sg (202.166.122.50)  29.520 ms  10.367 ms  29.484 ms
 6  ae4-0.tp-er03.singnet.com.sg (202.166.123.70)  10.068 ms  6.601 ms  6.543 ms
 7  203.208.145.233 (203.208.145.233)  8.565 ms 203.208.191.197 (203.208.191.197)  8.627 ms 203.208.191.113 (203.208.191.113)  21.087 ms
 8  203.208.158.190 (203.208.158.190)  8.492 ms 203.208.153.186 (203.208.153.186)  8.859 ms 203.208.158.190 (203.208.158.190)  8.916 ms
 9  203.208.171.109 (203.208.171.109)  8.878 ms  8.839 ms  9.610 ms
10  203.208.168.26 (203.208.168.26)  9.728 ms  10.153 ms  10.348 ms
11  * * *
12  * * *
13  * * *
14  * * *
15  * * *
...</code>
</pre>

I guess their TCP/IP stack has been configured to not respond to probing requests...

<pre class="language-bash command-line" data-user="martin" data-host="mubuntu" data-output="2-5">
<code>ping fargate.aws.mfrancis.dev -w3
PING mfrancisdev-986243151.ap-southeast-1.elb.amazonaws.com (54.251.177.216) 56(84) bytes of data.

--- mfrancisdev-986243151.ap-southeast-1.elb.amazonaws.com ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2052ms</code>
</pre> 

Anyway, whilst this was a fun thing to try out I won't keep running the service out of AWS - it's costing me about $0.37 p/d after all :)

<h2>Summary</h2>

In this post I explored Docker locally, including multi-platform builds. I published images to Docker Hub, allowing images to be pulled in from a remote repository and executed using the same tag on multiple platforms (`amd64` and `arm32v7`). The same was setup as a CI pipeline using GitHub Actions to build the image and push into Docker Hub upon merge on `main`. Afterwards I integrated the GitHub Actions workflow with Amazon ECR and started a service on tcp/443 in Amazon ECS/Fargate.
