{ checkString } = require './validation'

bootMountPointFromEnv = checkString(process.env.BOOT_MOUNTPOINT)
rootMountPoint = checkString(process.env.ROOT_MOUNTPOINT) ? '/mnt/root'

supervisorNetworkInterface = 'supervisor0'

module.exports =
	rootMountPoint: rootMountPoint
	databasePath: checkString(process.env.DATABASE_PATH) ? '/data/database.sqlite'
	dockerSocket: process.env.DOCKER_SOCKET ? '/var/run/docker.sock'
	supervisorImage: checkString(process.env.SUPERVISOR_IMAGE) ? 'resin/rpi-supervisor'
	ledFile: checkString(process.env.LED_FILE) ? '/sys/class/leds/led0/brightness'
	forceSecret: # Only used for development
		api: checkString(process.env.RESIN_SUPERVISOR_SECRET) ? null
		logsChannel: checkString(process.env.RESIN_SUPERVISOR_LOGS_CHANNEL) ? null
	vpnStatusPath: checkString(process.env.VPN_STATUS_PATH) ? "#{rootMountPoint}/run/openvpn/vpn_status"
	hostOSVersionPath: checkString(process.env.HOST_OS_VERSION_PATH) ? "#{rootMountPoint}/etc/os-release"
	privateAppEnvVars: [
		'RESIN_SUPERVISOR_API_KEY'
		'RESIN_API_KEY'
	]
	dataPath: checkString(process.env.RESIN_DATA_PATH) ? '/resin-data'
	bootMountPointFromEnv: bootMountPointFromEnv
	bootMountPoint: bootMountPointFromEnv ? '/boot'
	configJsonPathOnHost: checkString(process.env.CONFIG_JSON_PATH)
	proxyvisorHookReceiver: checkString(process.env.RESIN_PROXYVISOR_HOOK_RECEIVER) ? 'http://0.0.0.0:1337'
	apiEndpointFromEnv: checkString(process.env.API_ENDPOINT)
	configJsonNonAtomicPath: '/boot/config.json'
	defaultPubnubSubscribeKey: process.env.DEFAULT_PUBNUB_SUBSCRIBE_KEY
	defaultPubnubPublishKey: process.env.DEFAULT_PUBNUB_PUBLISH_KEY
	defaultMixpanelToken: process.env.DEFAULT_MIXPANEL_TOKEN
	supervisorNetworkInterface: supervisorNetworkInterface
	allowedInterfaces: ['resin-vpn', 'tun0', 'docker0', 'lo', supervisorNetworkInterface]
	appsJsonPath: process.env.APPS_JSON_PATH ? '/boot/apps.json'
	ipAddressUpdateInterval: 30 * 1000
	imageCleanupErrorIgnoreTimeout: 3600 * 1000
	maxDeltaDownloads: 3
	defaultVolumeLabels: {
		'io.resin.supervised': 'true'
	}

process.env.DOCKER_HOST ?= "unix://#{module.exports.dockerSocket}"
