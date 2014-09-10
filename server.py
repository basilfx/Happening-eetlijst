from flask import request, abort, jsonify, Flask

from werkzeug.contrib.cache import SimpleCache, RedisCache

from datetime import datetime

import pytz
import cPickle
import eetlijst
import calendar
import functools

# App definition
app = Flask(__name__)
app.debug = True

# Use simple cache for cli-mode. For WSGI mode use a shared cache.
if __name__ == "__main__":
    cache = SimpleCache()
else:
    cache = RedisCache("10.0.0.3", key_prefix="eetlijst")

def to_unix_timestamp(timestamp):
    """
    Convert datetime object to unix timestamp. Input is local time, result is an
    UTC timestamp.
    """

    if timestamp is not None:
        return calendar.timegm(timestamp.utctimetuple())

def from_unix_timestamp(timestamp):
    """
    Convert unix timestamp to datetime object. Input is a UTC timestamp, result
    is local time.
    """

    if timestamp is not None:
        return datetime.fromtimestamp(int(timestamp), tz=pytz.UTC).astimezone(
            eetlijst.TZ_LOCAL)

def inject_client(func):
    """
    Inject the Eetlijst client from cache, if available. Otherwise, create a new
    one.
    """

    @functools.wraps(func)
    def _inner():
        username = request.args.get("username")
        password = request.args.get("password")

        if not username or not password:
            return abort(400)

        # Fetch eetlijst client from cache
        key = username + "-" + password
        client = cache.get(key)

        if client:
            try:
                client = cPickle.loads(client)
            except cPickle.UnpicklingError:
                client = None

        if not client:
            app.logger.debug("Creating new client")

            try:
                client = eetlijst.Eetlijst(username=username, password=password,
                    login=True)
            except eetlijst.LoginError:
                return abort(401)
        else:
            app.logger.debug("Continuing existing client")

        # Invoke original method
        try:
            result = func(client)

            # Store in cache again
            cache.set(key, cPickle.dumps(client,
                protocol=cPickle.HIGHEST_PROTOCOL), timeout=60)
        except:
            app.logger.debug("Client state NOT updated due to exception")
            raise

        return result
    return _inner

@app.route("/info", methods=["GET"])
@inject_client
def get_info(client):
    return jsonify({
        "result": {
            "name": client.get_name(),
            "residents": client.get_residents()
        }
    })

@app.route("/status", methods=["GET"])
@inject_client
def get_status(client):
    status_rows = client.get_statuses(limit=1)

    return jsonify({
        "result": [{
            "statuses": [{
                "value": status.value,
                "last_changed": to_unix_timestamp(status.last_changed)
            } for status in status_row.statuses ],
            "deadline": to_unix_timestamp(status_row.deadline),
            "timestamp": to_unix_timestamp(status_row.timestamp)
        } for status_row in status_rows ]
    })

@app.route("/status", methods=["POST"])
@inject_client
def set_status(client):
    timestamp = from_unix_timestamp(request.args["timestamp"])
    resident = request.args["resident"]
    value = request.args["value"]

    client.set_status(resident, value, timestamp)

    return jsonify({
        "result": True
    })

@app.route("/noticeboard", methods=["GET"])
@inject_client
def get_noticeboard(client):
    return jsonify({
        "result": client.get_noticeboard()
    })

@app.route("/noticeboard", methods=["POST"])
@inject_client
def set_noticeboard(client):
    client.set_noticeboard(request.args["content"])

    return jsonify({
        "result": True
    })

# E.g. `python server.py'
if __name__ == '__main__':
    app.run()