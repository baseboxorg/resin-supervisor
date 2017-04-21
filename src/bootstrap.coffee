Promise = require 'bluebird'
knex = require './db'
utils = require './utils'
deviceRegister = require 'resin-register-device'
{ resinApi, request } = require './request'
fs = Promise.promisifyAll(require('fs'))
config = require './config'
configPath = '/boot/config.json'
appsPath  = '/boot/apps.json'
_ = require 'lodash'
deviceConfig = require './device-config'
TypedError = require 'typed-error'
userConfig = {}

DuplicateUuidError = message: '"uuid" must be unique.'
exports.ExchangeKeyError = class ExchangeKeyError extends TypedError

bootstrapper = {}

loadPreloadedApps = ->
	devConfig = {}
	knex('app').truncate()
	.then ->
		fs.readFileAsync(appsPath, 'utf8')
	.then(JSON.parse)
	.map (app) ->
		utils.extendEnvVars(app.env, userConfig.uuid, app.appId, app.name, app.commit)
		.then (extendedEnv) ->
			app.env = JSON.stringify(extendedEnv)
			_.merge(devConfig, app.config)
			app.config = JSON.stringify(app.config)
			knex('app').insert(app)
	.then ->
		deviceConfig.set({ targetValues: devConfig })
	.catch (err) ->
		utils.mixpanelTrack('Loading preloaded apps failed', { error: err })

exchangeKey = ->
	resinApi.get
		resource: 'device'
		options:
			filter:
				uuid: userConfig.uuid
		customOptions:
			apikey: userConfig.apiKey
	.catchReturn([])
	.timeout(config.apiTimeout)
	.then ([ device ]) ->
		if not device?
			throw new ExchangeKeyError("Couldn't fetch device with provisioning key")
		# We found the device, we can try to generate a working device key for it
		request.postAsync("#{config.apiEndpoint}/api-key/device/#{device.id}/device-key")
		.spread (res, body) ->
			if res.status != 200
				throw new ExchangeKeyError("Couldn't generate device key with provisioning key")
			userConfig.deviceApiKey = body
		.return(device)

bootstrap = ->
	Promise.try ->
		userConfig.deviceType ?= 'raspberry-pi'
		if userConfig.registered_at?
			return userConfig

		deviceRegister.register(
			userId: userConfig.userId
			applicationId: userConfig.applicationId
			uuid: userConfig.uuid
			deviceType: userConfig.deviceType
			deviceApiKey: userConfig.deviceApiKey
			provisioningApiKey: userConfig.apiKey
			apiEndpoint: config.apiEndpoint
		)
		.timeout(config.apiTimeout)
		.catch DuplicateUuidError, ->
			console.log('UUID already registered, checking if our device key is valid for it')
			resinApi.get
				resource: 'device'
				options:
					filter:
						uuid: userConfig.uuid
				customOptions:
					apikey: userConfig.deviceApiKey
			.catchReturn([])
			.timeout(config.apiTimeout)
			.then ([ device ]) ->
				if device?
					console.log('Fetched device, all is good')
					return device
				# If we couldn't fetch with the device key then we can try to key exchange in case the provisioning key is an old 'user-api-key'
				console.log("Couldn't fetch the device, trying to exchange for a valid key")
				exchangeKey()
				.tapCatch ExchangeKeyError, (err) ->
					# If it fails we just have to reregister as a provisioning key doesn't have the ability to change existing devices
					console.log('Exchanging key failed, having to reregister')
					generateRegistration(true)
				.then (device) ->
		.then ({ id }) ->
			userConfig.registered_at = Date.now()
			userConfig.deviceId = id
			# Delete the provisioning key now.
			delete userConfig.apiKey
			fs.writeFileAsync(configPath, JSON.stringify(userConfig))
		.return(userConfig)
	.then (userConfig) ->
		console.log('Finishing bootstrapping')
		knex('config').whereIn('key', ['uuid', 'apiKey', 'username', 'userId', 'version']).delete()
		.then ->
			knex('config').insert([
				{ key: 'uuid', value: userConfig.uuid }
				{ key: 'apiKey', value: userConfig.deviceApiKey }
				{ key: 'username', value: userConfig.username }
				{ key: 'userId', value: userConfig.userId }
				{ key: 'version', value: utils.supervisorVersion }
			])
		.tap ->
			bootstrapper.doneBootstrapping()

readConfig = ->
	fs.readFileAsync(configPath, 'utf8')
	.then(JSON.parse)

generateRegistration = (forceReregister = false) ->
	Promise.try ->
		if forceReregister
			userConfig.uuid = deviceRegister.generateUniqueKey()
			userConfig.deviceApiKey = deviceRegister.generateUniqueKey()
		else
			userConfig.uuid ?= deviceRegister.generateUniqueKey()
			userConfig.deviceApiKey ?= deviceRegister.generateUniqueKey()
		fs.writeFileAsync(configPath, JSON.stringify(userConfig))
		.return(userConfig.uuid)
	.catch (err) ->
		console.log('Error generating and saving UUID: ', err)
		Promise.delay(config.bootstrapRetryDelay)
		.then ->
			generateRegistration()

bootstrapOrRetry = ->
	utils.mixpanelTrack('Device bootstrap')
	# If we're in offline mode, we don't start the provisioning process so bootstrap.done will never fulfill
	return if bootstrapper.offlineMode
	bootstrap().catch (err) ->
		utils.mixpanelTrack('Device bootstrap failed, retrying', { error: err, delay: config.bootstrapRetryDelay })
		setTimeout(bootstrapOrRetry, config.bootstrapRetryDelay)

bootstrapper.done = new Promise (resolve) ->
	bootstrapper.doneBootstrapping = ->
		bootstrapper.bootstrapped = true
		resolve(userConfig)
		# If we're still using an old api key we can try to exchange it for a valid device key
		if userConfig.apiKey?
			exchangeKey()
			.then ->
				delete userConfig.apiKey
				knex('config').update(value: userConfig.deviceApiKey).where(key: 'apiKey')
				.then ->
					fs.writeFileAsync(configPath, JSON.stringify(userConfig))


bootstrapper.bootstrapped = false
bootstrapper.startBootstrapping = ->
	# Load config file
	readConfig()
	.then (configFromFile) ->
		userConfig = configFromFile
		bootstrapper.offlineMode = Boolean(userConfig.supervisorOfflineMode)
		knex('config').select('value').where(key: 'uuid')
	.then ([ uuid ]) ->
		if uuid?.value
			bootstrapper.doneBootstrapping() if !bootstrapper.offlineMode
			return uuid.value
		console.log('New device detected. Bootstrapping..')

		generateRegistration()
		.tap ->
			loadPreloadedApps()
		.tap (uuid) ->
			if bootstrapper.offlineMode
				return knex('config').insert({ key: 'uuid', value: uuid })
			else
				bootstrapOrRetry()
				# Don't wait on bootstrapping here, bootstrapper.done is for that.
				return

module.exports = bootstrapper
