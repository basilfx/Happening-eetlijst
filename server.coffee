Db = require "db"
Plugin = require "plugin"
Http = require "http"
Event = require "event"
Timer = require "timer"

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

	# Get the basic info of the list
	getInfo: (success, error) ->
		@get("info", null, success, error)

	# Get the contents of the noticeboard. The response is a string.
	getNoticeboard: (success, error) ->
		@get("noticeboard", null, success, error)

	# Set the contents of the noticeboard.
	setNoticeboard: (content, success, error) ->
		data = "content=" + encodeURIComponent(content)
		@post("noticeboard", data, success, error)

	# Get the status
	getStatus: (success, error) ->
		@get("status", null, success, error)

	# Set the status
	setStatus: (resident, value, timestamp, success, error) ->
		data = "resident=" + encodeURIComponent(resident) \
			+ "&value=" + encodeURIComponent(value) \
			+ "&timestamp=" + encodeURIComponent(timestamp)
		@post("status", data, success, error)

	# Shortcut for request(Http.get, path, data)
	get: (path, data, success, error) ->
		m = (d) -> Http.get(d)
		@request(m, path, data, success, error)

	# Shortcut for request(Http.post, path, data)
	post: (path, data, success, error) ->
		m = (d) -> Http.post(d)
		@request(m, path, data, success, error)

	# Invoke a request. Build URL and add username/password. Data should be a
	# encoded querystring.
	request: (method, path, data, success, error) !->
		url = API_URL + "/" + path \
			+ "?username=" + encodeURIComponent(@username) \
			+ "&password=" + encodeURIComponent(@password) \
			+ (if data then "&" + data else "")

		# Request response
		log "Calling URL: " + url

		# Invoke method
		try
			response = method
				url: url
				args: [success, error]
		catch
			log "Could not invoke request"
			exports[error]()

# Build a new Eetlijst instance, with the  given credentials, or the ones stored
# in the shared database. Returns a new instance, or none if username and/or
# password not configured.
getInstance = (credentials) ->
	credentials = credentials or Db.admin.get("credentials")

	if not credentials or not credentials.username or not credentials.password
		log "Missing username and/or password"
		return

	new ProxiedEetlijst(credentials.username, credentials.password)

# Update Eetlijst data
update = !->
	# Create Eetlijst instance
	eetlijst = getInstance()

	if not eetlijst
		return

	# Synchronize general information
	lastSync = new Date().getTime() - Db.shared.get("lastSync", "info")

	if lastSync > TIMEOUT_INFO
		eetlijst.getInfo "onInfo", "onError"

	# Synchronize noticeboard
	lastSync = new Date().getTime() - Db.shared.get("lastSync", "noticeboard")

	if lastSync > TIMEOUT_NOTICEBOARD
		eetlijst.getNoticeboard "onNoticeboard", "onError"

	# Synchronize status row and merge it with the residents to provide todays
	# view.
	lastSync = new Date().getTime() - Db.shared.get("lastSync", "status")

	if lastSync > TIMEOUT_STATUS
		eetlijst.getStatus "onStatus", "onError"

# Temporary solution to handle incoming response data
exports.onHttpResponse = (success, error, response) !->
	if not response
		log "Expected a response"
	else
		# Parse as JSON
		try
			result = JSON.parse(response)
		catch
			result = null

		# Parse response
		if not result or not result.result
			log "Could not decode response."

			if error
				exports[error]()
		else if result.error
			log "Server returned error: " + result.error

			if error
				exports[error](result.error)
		else
			if success
				exports[success](result.result)

# Initialize default values for the database.
exports.onInstall = !->
	Db.admin.set "credentials",
		username: "",
		password: ""
	Db.shared.set "lastSync",
		info: 0,
		noticeboard: 0,
		status: 0

	# This effectively removes the keys, which is what we want if the caller is
	# exports.client_clearAll.
	Db.shared.set "info", null
	Db.shared.set "today", null
	Db.shared.set "status", null
	Db.shared.set "noticeboard", null
	Db.shared.set "mapping", null

# Get the credentials, for the settings screen. Can only be invoked by plugin
# admin.
exports.client_getCredentials = (cb) !->
	Plugin.assertAdmin()

	cb.reply Db.admin.get("credentials")

# Set the credentials, and validate them. Can only be invoked by plugin admin.
exports.client_setCredentials = (credentials, cb) !->
	Plugin.assertAdmin()

	Db.admin.merge("credentials", credentials)
	cb.reply Db.admin.get("credentials")

# Check if the stored credentials are valid and can be used for signing in.
# Returns true on success, false otherwise. Can only be invoked by plugin admin.
exports.client_checkCredentials = (cb) !->
	Plugin.assertAdmin()

	eetlijst = getInstance()

	if eetlijst
		eetlijst.isValid(cb.reply)
	else
		cb.reply(false)

# Change the content of the noticeboard
exports.client_setNoticeboard = (content) !->
	eetlijst = getInstance()

	eetlijst.setNoticeboard(content)
	Db.shared.set("noticeboard", content)

# Set the status of a resident at a certain timestamp
exports.client_setStatus = (resident, value, timestamp) !->
	eetlijst = getInstance()

	eetlijst.setStatus(resident, value, timestamp)
	Db.shared.set("today", "statuses", resident, "value", value)
	Db.shared.set("today", "statuses", resident, "lastChanged",
		(new Date().getTime() / 1000))

	# Record for event notification
	Db.shared.set("today", "changes", resident, value)
	Timer.set(1000 * 60 * 5, "onTimer")
	#Timer.set(5000, "onTimer")

# Connect a resident with a certain userId
exports.client_setUser = (resident, userId) !->
	# An userId cannot be associated with two residents
	for k, v of Db.shared.get("mapping")
		if v == userId
			Db.shared.set "mapping", k, null

	# Set new mapping
	Db.shared.set "mapping", resident, userId

# Clear all data
exports.client_clearAll = !->
	Plugin.assertAdmin()

	exports.onInstall()

# (Re)load data from Eetlijst. Not all parts are refreshed at once, but only if
# they are expired (see TIMEOUT constants on top).
exports.client_refresh = (cb) !->
	update()

	# Set last visit time
	now = (new Date().getTime() / 1000)

	cb.reply Db.personal(Plugin.userId()).get("lastVisit") or now
	Db.personal(Plugin.userId()).set("lastVisit", now)

# Cronjob
exports.hourly = !->
	update()

# Event timer
exports.onTimer = !->
	residents = Db.shared.get("info", "residents")
	changes = Db.shared.get("today", "changes")
	mapping = Db.shared.get("mapping")

	if not changes
		return

	# Gather names
	names = []

	for resident, value of changes
		if mapping[resident]
			names.push(Plugin.userName(mapping[resident]))
		else
			names.push(residents[resident])

	# Build message
	if names.length == 0
		return
	if names.length == 1
		message = names[0] + " has changed his dinner status"
	else
		last = names.pop()
		message = names.join(", ") + " and " + last + " have changed their dinner status"

	# Send event
	Event.create
		unit: "new"
		text: message

	# Clear tracked changes
	Db.shared.set("today", "changes", null)

# HTTP API callbacks
exports.onError = (reason) !->
	Db.shared.set("info", "error", true)

exports.onInfo = (result) !->
	Db.shared.set("info", result)
	Db.shared.set("lastSync", "info", new Date().getTime())

exports.onNoticeboard = (result) !->
	Db.shared.set("noticeboard", result)
	Db.shared.set("lastSync", "noticeboard", new Date().getTime())

exports.onStatus = (result) !->
	Db.shared.set("status", result[0])
	Db.shared.set("lastSync", "status", new Date().getTime())

	residents = Db.shared.get("info", "residents")
	statusRow = Db.shared.get("status")
	statuses = {}

	for resident, index in residents
		statuses[index] =
			resident: resident,
			value: statusRow.statuses[index].value,
			lastChanged: statusRow.statuses[index].last_changed

	# Save data for today
	Db.shared.set("today",
		deadline: statusRow.deadline,
		timestamp: statusRow.timestamp,
		statuses: statuses
	)