Db = require "db"
Plugin = require "plugin"
Http = require "http"

TIMEOUT_INFO = (1000 * 60 * 60)
TIMEOUT_STATUS = (1000 * 60 * 5)
TIMEOUT_NOTICEBOARD = (1000 * 60 * 5)

# Temporary solution for the lack of scraping and requests support in Happening.
# Uses external proxy to convert results into JSON format
class ProxiedEetlijst
	# API URl without trailing slash
	API_URL = "http://eetlijst.apps.basilfx.net"

	# Construct new instance.
	constructor: (username, password) ->
		@username = username
		@password = password

	isValid: ->
		return !!@get("info")

	# Get the basic info of the list
	getInfo: ->
		return @get("info").result

	# Get the contents of the noticeboard. The response is a string.
	getNoticeboard: ->
		return @get("noticeboard").result

	# Set the contents of the noticeboard.
	setNoticeboard: (content) ->
		data = "content=" + encodeURIComponent(content)

		return @post("noticeboard", data).result

	# Get the status
	getStatus: ->
		return @get("status").result

	# Set the status
	setStatus: (resident, value, timestamp) ->
		log JSON.stringify([resident, value, timestamp])

		data = "resident=" + encodeURIComponent(resident) \
			+ "&value=" + encodeURIComponent(value) \
			+ "&timestamp=" + encodeURIComponent(timestamp)

		return @post("status", data)

	# Shortcut for request(Http.get, path, data)
	get: (path, data) ->
		cb = (d) -> Http.get(d)
		@request(cb, path, data)

	# Shortcut for request(Http.post, path, data)
	post: (path, data) ->
		cb = (d) -> Http.post(d)
		@request(cb, path, data)

	# Invoke a request. Build URL and add username/password. Data should be a
	# encoded querystring.
	request: (method, path, data) !->
		url = API_URL + "/" + path \
			+ "?username=" + encodeURIComponent(@username) \
			+ "&password=" + encodeURIComponent(@password) \
			+ (if data then "&" + data else "")

		# Request response
		log "Calling URL: " + url

		try
			response = method(url)
		catch
			response = null

		# Validate response
		if not response
			log "Expected a response"
		else
			try
				result = JSON.parse(response)
			catch
				result = null

			if not result
				log "Could not decode response."
			else if result.error
				log "Server returned error: " + result.error
			else
				return result

# Build a new Eetlijst instance, with the  given credentials, or the ones stored
# in the shared database. Returns a new instance, or none if username and/or
# password not configured.
getInstance = (credentials)->
	credentials = credentials || Db.shared("_credentials *")

	if not credentials or not credentials.username or not credentials.password
		log "Missing username and/or password"
		return

	return new ProxiedEetlijst(credentials.username, credentials.password)

# Initialize default values for the database.
exports.onInstall = ->
	Db.shared "_credentials",
		username: "",
		password: ""
	Db.shared "_lastSync",
		info: 0,
		noticeboard: 0,
		status: 0

	Db.shared "info", null
	Db.shared "noticeboard", null
	Db.shared "today", null

# Get the credentials, for the settings screen. Can only be invoked by plugin
# admin.
exports.client_getCredentials = (cb) ->
	Plugin.assertAdmin()

	cb.reply Db.shared("_credentials *")

# Set the credentials, and validate them. Can only be invoked by plugin admin.
exports.client_setCredentials = (credentials, cb) ->
	Plugin.assertAdmin()

	Db.shared("_credentials", credentials)
	cb.reply Db.shared("_credentials *")

# Check if the stored credentials are valid and can be used for signing in.
# Returns true on success, false otherwise. Can only be invoked by plugin admin.
exports.client_checkCredentials = (cb) ->
	Plugin.assertAdmin()

	eetlijst = getInstance()
	cb.reply(eetlijst and eetlijst.isValid())

# Change the content of the noticeboard
exports.client_setNoticeboard = (content) ->
	eetlijst = getInstance()

	eetlijst.setNoticeboard(content)
	Db.shared "noticeboard", content

exports.client_setStatus = (resident, value, timestamp) ->
	eetlijst = getInstance()

	eetlijst.setStatus(resident, value, timestamp)
	Db.shared "today statuses #{resident} value", value
	Db.shared "today statuses #{resident} lastChanged", (new Date().getTime() / 1000)

# Clear all data
exports.client_clearAll = ->
	Plugin.assertAdmin()
	exports.onInstall()

# (Re)load data from Eetlijst. Not all parts are refreshed at once, but only if
# they are expired (see TIMEOUT constants on top).
exports.client_refresh = ->
	eetlijst = getInstance()

	if not eetlijst
		return

	# Synchronize general information
	lastSync = new Date().getTime() - (Db.shared "_lastSync info")

	if lastSync > TIMEOUT_INFO
		Db.shared "info", eetlijst.getInfo()
		Db.shared "_lastSync info", new Date().getTime()

	# Synchronize noticeboard
	lastSync = new Date().getTime() - (Db.shared "_lastSync noticeboard")

	if lastSync > TIMEOUT_NOTICEBOARD
		Db.shared "noticeboard", eetlijst.getNoticeboard()
		Db.shared "_lastSync noticeboard", new Date().getTime()

	# Synchronize status row and merge it with the residents to provide todays
	# view.
	lastSync = new Date().getTime() - (Db.shared "_lastSync status")

	if lastSync > TIMEOUT_STATUS
		Db.shared "status", eetlijst.getStatus()[0]
		Db.shared "_lastSync status", new Date().getTime()

		residents = Db.shared("info residents")
		statusRow = Db.shared("status *")
		statuses = {}

		for resident, index in residents
			statuses[index] =
				resident: resident,
				value: statusRow.statuses[index].value,
				lastChanged: statusRow.statuses[index].last_changed

		# Save data for today
		Db.shared "today",
			_MODE_: "replace"
			deadline: statusRow.deadline,
			timestamp: statusRow.timestamp,
			statuses: statuses