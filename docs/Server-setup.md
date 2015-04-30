# Server Setup

Because Happening has no support for scraping, a proxy must be setup to fetch
data from Eetlijst.nl to Happening.

## Requirements
* Linux server
* Python 2.7+
* Redis (optional)
* Nginx + uWSGI (optional)

## Installation
* Create a directory, e.g. `src/`. Copy `server.py` in here.
* Install the following Python packages with Pip:
 * `pip install flask`
 * `pip install python-eetlijst`
 * `pip install redis`
* Run `python server.py`. A simple server should run now!
* Change the `API_URL` in `server.coffee` to match your own server.

## Dedicated server
Refer to [this tutorial](http://vladikk.com/2013/09/12/serving-flask-with-nginx-on-ubuntu/).

You can use `server:app` as module entry point.

Note: you will need Redis to store client sessions in order to offload
Eetlijst.nl. Without Redis, a cache is kept per-process, instead of per-server.