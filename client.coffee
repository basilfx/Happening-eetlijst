Db = require "db"
Dom = require "dom"
Modal = require "modal"
Obs = require "obs"
Plugin = require "plugin"
Server = require "server"
Widgets = require "widgets"
Form = require "form"
Time = require "time"
tr = require("i18n").tr

exports.renderSettings = ->
	error = Obs.value(false)
	credentials = Obs.hash()
	Server.call "getCredentials", credentials

	Obs.observe !->
		if (credentials "username") and (credentials "password")
			Server.call "checkCredentials", (success) -> error(!success)

	Obs.observe !->
		if !(credentials "username")?
			Widgets.spinner 24
			return

		if error()
			Dom.section !->
				Dom.text tr("Username and/or password incorrect")

		Form.input
			name: "username"
			text: tr "Username"
			value: (credentials "&username")
			onSave: (value) ->
				credentials "username", value
				Server.call "setCredentials", credentials("*"), credentials
		Form.input
			name: "password"
			text: tr "Password"
			type: "password"
			value: (credentials "&password")
			onSave: (value) ->
				credentials "password", value
				Server.call "setCredentials", credentials("*"), credentials

		Widgets.bigButton tr("Clear all data"), !->
			Modal.confirm tr("Clear all data"), tr("Are you sure you want to clear all data?"), !->
				Server.sync "clearAll", !->
					credentials "username", ""
					credentials "password", ""

exports.render = ->
	Server.call "refresh"

	# App not configured
	if not Db.shared("info")
		# Title
		Dom.h1 "Eetlijst"

		# Warning message
		if Plugin.userIsAdmin()
			Dom.p tr("This application isn't configured yet. Please enter the
				credentials on the settings page.")
		else
			Dom.p tr("This application isn't configured yet. Only the admin of
				this Happening can configure it.")

	# App is configured
	else
		# Title
		Dom.h1 Db.shared("info name") + " - Eetlijst"

		# Noticeboard
		Dom.h2 tr("Noticeboard")
		Dom.form !->
			Form.text
				name: "tapText"
				autogrow: true
				format: (t) -> Dom.richText(t)
				value: (Db.shared "&noticeboard")
				title: tr("Noticeboard is empty!")
				onSave: (v) !->
					Server.sync "setNoticeboard", v, ->
						Db.shared "noticeboard", v

		# Todays status
		Dom.h2 tr("Statuses")

		Obs.observe !->
			timestamp = Db.shared("today timestamp")
			deadline = Db.shared("today deadline")

			if (new Date().getTime() / 1000) > deadline
				Dom.p tr("You cannot change the status for today. The deadline has \
					already passed!")

			# Draw all rows
			Dom.ul ->
				(Db.shared "today statuses") (index, status) !->
					resident = status("resident")
					value = status("value")

					# Helper for toggling state, including deadline check
					toggleStatus = (resident, value) ->
						if (new Date().getTime() / 1000) > deadline
							Modal.show "Deadline passed", "The deadline has already passed."
						else
							Server.sync "setStatus", resident, value, timestamp, ->
								Db.shared "today statuses #{resident} value", value
								Db.shared "today statuses #{resident} lastChanged", (new Date().getTime() / 1000)

					# Draw single row
					Dom.li !->
						Dom.div !->
							Dom.style
								width: "38px"
								height: "38px"
								backgroundSize: "cover"
								backgroundPosition: "50% 50%"
								margin: "0 4px 0 0"
								border: "solid 2px #aaa"
								borderRadius: "36px"

							Dom.style
								backgroundImage:  "url(#{Plugin.resourceUri("silhouette-aaa.png")})"

						Dom.div !->
							Dom.style
								_boxFlex: 1
							Dom.text resident

						# Last changed
						Dom.div !->
							Dom.style
								width: "33%"
							Time.deltaText (status "lastChanged")

						# Diner button
						Widgets.button !->
							extra = ""

							if value < 0
								Dom.style
									backgroundColor: "#72bb53"
									borderColor: "#72bb53"
									color: "white"

								# Extra people attend dinner
								if value < -1
									extra = " +" + (-1 * value - 1)
							else
								Dom.style
									borderColor: "#72bb53"
									color: "black"

							Dom.text tr("Diner") + extra
						, -> toggleStatus(index, if value < 0 then (value - 1) else -1)

						# No button
						Widgets.button !->
							if value == 0
								Dom.style
									backgroundColor: "gray"
									borderColor: "gray"
									color: "white"
							else
								Dom.style
									borderColor: "gray"
									color: "black"

							Dom.text tr("No")
						, -> toggleStatus(index, 0)

						# Cook button
						Widgets.button !->
							extra = ""

							if value > 0
								Dom.style
									backgroundColor: "#a00"
									borderColor: "#a00"
									color: "white"

								# Extra people attend dinner
								if value > 1
									extra = " +" + (value - 1)
							else
								Dom.style
									borderColor: "#a00"
									color: "black"

							Dom.text tr("Cook") + extra
						, -> toggleStatus(index, if value > 0 then (value + 1) else 1)
