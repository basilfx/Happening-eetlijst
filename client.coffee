Db = require "db"
Dom = require "dom"
Modal = require "modal"
Obs = require "obs"
Plugin = require "plugin"
Server = require "server"
Ui = require "ui"
Form = require "form"
Time = require "time"
tr = require("i18n").tr

# Open dialog to select an user
userSelect = (opts) ->
	doModal = !->
		Modal.show opts.title, !->
			Dom.style width: "80%"
			Ui.list !->
				Dom.style
					maxHeight: "40%"
					overflow: "auto"
					_overflowScrolling: "touch"
					backgroundColor: "#eee"
					margin: "-12px -12px -15px -12px"
				Plugin.users.iterate (user) !->
					Ui.item !->
						Ui.avatar user.get("avatar")
						Dom.text user.get("name")

						if user.key() is opts.value
							Dom.style fontWeight: "bold"

							Dom.div !->
								Dom.style
									padding: "0 10px"
									WebkitBoxFlex: 1
									textAlign: "right"
									fontSize: "150%"
									color: "#72BB53"
								Dom.text "✓"

						Dom.onTap !->
							opts.onSave user.key()
							Modal.remove()

	user = Plugin.users.get(opts.value)
	if content = opts.content
		content user, doModal

# Render the settings UI. The Settings UI has an username and password field.
# Optionally, the user can clear all data.
exports.renderSettings = ->
	credentials = Obs.create()

	# Helper for merging the credential data
	merge = (d) !->
		if not d
			log "Received no credentials. Plugin not configured?"
		else
			credentials.merge(d)

	# Request server credentials
	Server.call "getCredentials", merge

	Obs.observe !->
		# Wait for data to be ready
		if credentials.get("username") is null
			Ui.spinner 24
			return

		# Username
		Form.input
			name: "username"
			text: tr("Username")
			value: credentials.get("username")
			onSave: (value) ->
				Server.sync "setCredentials", {"username": value}, merge, !->
					credentials.set "username", value

		# Password
		Form.input
			name: "password"
			text: tr("Password")
			type: "password"
			value: credentials.get("password")
			onSave: (value) ->
				Server.sync "setCredentials", {"password": value}, merge, !->
					credentials.set("password", value)

		# Clear all
		Ui.bigButton tr("Clear all data"), !->
			Modal.confirm tr("Clear all data"), tr("Are you sure you want to clear all data?"), !->
				credentials.set
					username: null
					password: null
				Server.call "clearAll"

# Render the UI
exports.render = ->
	# Ask the server to refresh the data. In case new data is available, it will
	# be pushed to the client. The lastVisit variable will store the last visit,
	# so new information can be highlighted.
	Server.call "refresh", (lastVisit) ->
		Db.local.set "lastVisit", lastVisit
		setTimeout ->
			# Set to greater number, so highlights won't appear again.
			Db.local.set("lastVisit", new Date().getTime())
		, 5000

	# App not configured
	if not Db.shared.get("info")
		# Title
		Dom.h1 "Eetlijst"

		# Warning message
		if Plugin.userIsAdmin()
			Dom.p tr("This application isn't configured yet. Please enter the
				credentials on the settings page.")
		else
			Dom.p tr("This application isn't configured yet. Only admins of this
				Happening can configure it.")

	# Some error occured, e.g. wrong credentials
	else if Db.shared.get("info", "error")
		Dom.h1 "Eetlijst"

		Dom.p tr("Some error occured while configuring this plugin. Are the
			credentials correctly entered?")

	# App is configured
	else
		# Title
		Dom.h1 !->
			Dom.style
				whiteSpace: "nowrap"
			Dom.text Db.shared.get("info", "name") + " - Eetlijst"

		# Noticeboard
		Dom.h2 tr("Noticeboard")
		Dom.form !->
			Form.text
				name: "tapText"
				autogrow: true
				format: (t) -> Dom.richText(t)
				value: Db.shared.get("noticeboard")
				title: tr("Noticeboard is empty!")
				onSave: (v) !->
					Server.sync "setNoticeboard", v, ->
						Db.shared.set("noticeboard", v)

		# List of todays statuses
		Dom.h2 tr("Statuses")

		Obs.observe !->
			today = Db.shared.ref("today")

			if not today
				Dom.p tr("There is no status information available for today")
				return

			# Verify deadline
			deadline = new Date(today.peek("deadline") * 1000)
			deadlinePassed = new Date().getTime() > deadline.getTime()

			if deadlinePassed
				Time.deltaText deadline / 1000, "default", (t) !->
					Dom.p tr("You cannot change the status for today. The \
						deadline of %1 has already passed!", t)
			else
				Time.deltaText deadline.getTime() / 1000, "default", (t) !->
					Dom.p tr("The deadline will expire in %1.", t)

			# Draw all rows
			Ui.list !-> today.iterate "statuses", (status) !->
				resident = status.peek("resident")

				# Draw single row
				Ui.item !->
					Dom.style
						padding: "0"
						height: "64px"

					# User avatar
					userSelect
						name: "user"
						title: tr("Map user %1 to:", resident)
						value: Db.shared.get("mapping", status.key())
						onSave: (userId) !-> Server.sync "setUser", status.key(), userId, !->
							# An userId cannot be associated with two residents
							for k, v of Db.shared.get("mapping")
								if v == userId
									Db.shared.set "mapping", k, null

							# Set new mapping
							Db.shared.set "mapping", status.key(), userId
						content: (user, modal) !->
							Dom.div !->
								Dom.style
									margin: "0 8px 0 0"
									width: "38px"
								Ui.avatar user?.avatar
								Dom.onTap modal

							Dom.div !->
								Dom.style
									whiteSpace: "nowrap"
									overflow: "hidden"
									Flex: 1

								# Resident name and last changed
								if user
									Dom.text user.name + " "
									Dom.span ->
										Dom.style
											color: "#ccc"
										Dom.text "(" + resident + ")"
								else
									Dom.text resident
								Dom.br()
								Dom.span !->
									lastChanged = status.get("lastChanged")
									lastVisit = Db.local.get("lastVisit") or 0

									if lastChanged > lastVisit
										Dom.style
											color: "red"
									else
										Dom.style
											color: "#ccc"

									Time.deltaText lastChanged, "short"

					Obs.observe !->
						value = status.get("value")

						# Helper for toggling state, including deadline check
						toggleStatus = (resident, value) ->
							if deadlinePassed
								Modal.show "Deadline passed", "The deadline has already passed."
							else
								Server.sync "setStatus", resident, value, today.peek("timestamp"), ->
									Db.shared.set("today", "statuses", resident, "value", value)
									Db.shared.set("today", "statuses", resident, "lastChanged", (new Date().getTime() / 1000))

						# Diner button
						Ui.button !->
							extra = ""

							if value < 0
								Dom.style
									backgroundColor: "#72bb53"
									border: "1px #72bb53 solid"
									color: "white"

								# Extra people attend dinner
								if value < -1
									extra = " +" + (-1 * value - 1)
							else
								Dom.style
									backgroundColor: "#fff"
									border: "1px #72bb53 solid"
									color: "black"

							Dom.text tr("Diner") + extra
						, -> toggleStatus(status.key(), if value < 0 then (value - 1) else -1)

						# No button
						Ui.button !->
							if value == 0
								Dom.style
									backgroundColor: "gray"
									border: "1px gray solid"
									color: "white"
							else
								Dom.style
									backgroundColor: "#fff"
									border: "1px gray solid"
									color: "black"

							Dom.text tr("No")
						, -> toggleStatus(status.key(), 0)

						# Cook button
						Ui.button !->
							extra = ""

							if value > 0
								Dom.style
									backgroundColor: "#a00"
									border: "1px #a00 solid"
									color: "white"

								# Extra people attend dinner
								if value > 1
									extra = " +" + (value - 1)
							else
								Dom.style
									backgroundColor: "#fff"
									border: "1px #a00 solid"
									color: "black"

							Dom.text tr("Cook") + extra
						, -> toggleStatus(status.key(), if value > 0 then (value + 1) else 1)
