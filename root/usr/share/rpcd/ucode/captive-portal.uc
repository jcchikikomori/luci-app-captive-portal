#!/usr/bin/env ucode

'use strict';

import { cursor } from 'uci';
import { popen } from 'fs';

const uci = cursor();

function get_daemon() {
	return uci.get_first('captive-portal', 'service', 'daemon') || 'nodogsplash';
}

function get_ctl_binary() {
	const daemon = get_daemon();
	if (daemon === 'opennds') {
		return 'openndsctl';
	}
	return 'ndsctl';
}

function service_running() {
	const daemon = get_daemon();
	const fp = popen('pidof ' + daemon + ' 2>/dev/null');
	const pid = trim(fp.read('all') || '');
	fp.close();
	return length(pid) > 0;
}

function get_uptime() {
	const daemon = get_daemon();
	const fp = popen('ps -o etime= -C ' + daemon + ' 2>/dev/null');
	const etime = trim(fp.read('all') || '');
	fp.close();
	return etime;
}

function format_duration(seconds) {
	let s = int(seconds) || 0;
	if (s <= 0) return '0s';

	const h = int(s / 3600);
	const m = int((s % 3600) / 60);
	const r = s % 60;

	let result = '';
	if (h > 0) result += h + 'h ';
	if (m > 0) result += m + 'm ';
	if (r > 0 || result == '') result += r + 's';

	return trim(result);
}

function normalize_mac(mac) {
	const m = mac || '';
	return replace(m, /[a-z]/g, function(c) { return chr(ord(c) - 32); });
}

function lower_mac(mac) {
	const m = mac || '';
	return replace(m, /[A-Z]/g, function(c) { return chr(ord(c) + 32); });
}

function parse_clients_json() {
	const ctl = get_ctl_binary();
	const fp = popen(ctl + ' json 2>/dev/null');
	const output = fp.read('all') || '';
	fp.close();

	if (output == '') {
		return { clients: [], error: 'Unable to read client list' };
	}

	let data = null;
	try {
		data = json(output);
	} catch (e) {
		return { clients: [], error: 'Failed to parse client data' };
	}

	const clients = [];
	const client_map = data.clients || {};

	for (let key in client_map) {
		const c = client_map[key];
		if (c == null) continue;

		push(clients, {
			mac: c.mac || key,
			ip: c.ip || '',
			username: c.username || '',
			uptime: format_duration(c.duration || 0),
			downloaded: c.downloaded || 0,
			uploaded: c.uploaded || 0,
		});
	}

	return { clients: clients };
}

function parse_clients_output() {
	const daemon = get_daemon();
	if (daemon === 'nodogsplash') {
		return parse_clients_json();
	}

	return { clients: [], error: 'Client parsing not implemented for ' + daemon };
}

function get_client_count() {
	const result = parse_clients_output();
	return length(result.clients || []);
}

function sync_nodogsplash_config() {
	uci.load('captive-portal');
	uci.load('nodogsplash');

	const service = {
		interface: uci.get_first('captive-portal', 'service', 'interface') || 'lan',
		gatewayname: uci.get_first('captive-portal', 'service', 'gatewayname') || 'CaptivePortal',
		default_timeout: uci.get_first('captive-portal', 'service', 'default_timeout') || '1200',
	};

	let section_name = '';
	uci.foreach('nodogsplash', 'nodogsplash', function(s) {
		section_name = s['.name'];
		return false;
	});

	if (section_name == '') {
		uci.unload('captive-portal');
		uci.unload('nodogsplash');
		return { success: false, error: 'No nodogsplash section found' };
	}

	uci.set('nodogsplash', section_name, 'gatewayname', service.gatewayname);
	uci.set('nodogsplash', section_name, 'gatewayinterface', service.interface);
	uci.set('nodogsplash', section_name, 'sessiontimeout', service.default_timeout);
	uci.set('nodogsplash', section_name, 'binauth', '/usr/lib/captive-portal/binauth.sh');
	uci.set('nodogsplash', section_name, 'webroot', '/www/captive-portal');
	uci.set('nodogsplash', section_name, 'splashpage', 'splash.html');
	uci.set('nodogsplash', section_name, 'statuspage', 'status.html');

	uci.commit('nodogsplash');
	uci.unload('captive-portal');
	uci.unload('nodogsplash');

	return { success: true };
}

function sync_daemon() {
	const daemon = get_daemon();
	if (daemon === 'nodogsplash') {
		return sync_nodogsplash_config();
	}
	return { success: false, error: 'Sync not implemented for ' + daemon };
}

const methods = {
	get_status: {
		call: function() {
			const daemon = get_daemon();
			const running = service_running();
			const uptime = running ? get_uptime() : '';
			const client_count = running ? get_client_count() : 0;

			uci.load('captive-portal');
			const config = {
				daemon: uci.get_first('captive-portal', 'service', 'daemon') || 'nodogsplash',
				interface: uci.get_first('captive-portal', 'service', 'interface') || 'lan',
				portal_name: uci.get_first('captive-portal', 'service', 'portal_name') || 'Guest WiFi',
				gatewayname: uci.get_first('captive-portal', 'service', 'gatewayname') || 'CaptivePortal',
			};
			uci.unload('captive-portal');

			return {
				running: running,
				daemon: daemon,
				uptime: uptime,
				client_count: client_count,
				config: config,
			};
		}
	},

	get_clients: {
		call: function() {
			if (!service_running()) {
				return { clients: [], error: 'Service not running' };
			}
			return parse_clients_output();
		}
	},

	disconnect_client: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			const mac = data.mac || '';
			const ip = data.ip || '';
			if (!mac && !ip) {
				return { success: false, error: 'No MAC or IP provided' };
			}
			const ctl = get_ctl_binary();
			const target = mac ? lower_mac(mac) : ip;
			const fp = popen(ctl + ' deauth ' + target + ' 2>&1');
			const output = trim(fp.read('all') || '');
			const rc = fp.close();
			if (rc != 0) {
				return { success: false, error: output || 'Failed to disconnect client' };
			}
			return { success: true, output: output };
		}
	},

	block_client: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			const mac = data.mac || '';
			if (!mac) {
				return { success: false, error: 'No MAC provided' };
			}
			const norm_mac = normalize_mac(mac);

			// Deauthenticate first if the daemon is running.
			let deauth = { success: true, output: '' };
			if (service_running()) {
				const ctl = get_ctl_binary();
				const fp = popen(ctl + ' deauth ' + lower_mac(mac) + ' 2>&1');
				const output = trim(fp.read('all') || '');
				const rc = fp.close();
				deauth = {
					success: rc == 0,
					output: output
				};
			}

			uci.load('captive-portal');
			let section = '';
			uci.foreach('captive-portal', 'blocked', function(s) {
				if (normalize_mac(s.mac || '') === norm_mac) {
					section = s['.name'];
					return false;
				}
			});

			if (section == '') {
				section = uci.add('captive-portal', 'blocked');
			}

			uci.set('captive-portal', section, 'mac', norm_mac);
			uci.set('captive-portal', section, 'enabled', '1');
			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true, deauth: deauth };
		}
	},

	get_blocked: {
		call: function() {
			uci.load('captive-portal');
			const blocked = [];

			uci.foreach('captive-portal', 'blocked', function(s) {
				push(blocked, {
					section: s['.name'],
					mac: s.mac || '',
					enabled: s.enabled || '1',
				});
			});
			uci.unload('captive-portal');

			return { blocked: blocked };
		}
	},

	add_blocked: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			const mac = data.mac || '';
			if (!mac) {
				return { success: false, error: 'No MAC provided' };
			}
			const norm_mac = normalize_mac(mac);

			uci.load('captive-portal');
			const section = uci.add('captive-portal', 'blocked');
			uci.set('captive-portal', section, 'mac', norm_mac);
			uci.set('captive-portal', section, 'enabled', '1');
			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true, section: section };
		}
	},

	update_blocked: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			if (!data.section) {
				return { success: false, error: 'No section provided' };
			}

			const has_mac = exists(data, 'mac');
			const has_enabled = exists(data, 'enabled');
			if (!has_mac && !has_enabled) {
				return { success: false, error: 'No MAC or enabled state provided' };
			}
			if (has_mac && !data.mac) {
				return { success: false, error: 'No MAC provided' };
			}

			uci.load('captive-portal');
			const section = data.section;

			if (has_mac) uci.set('captive-portal', section, 'mac', normalize_mac(data.mac));
			if (has_enabled) uci.set('captive-portal', section, 'enabled', data.enabled);

			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true };
		}
	},

	delete_blocked: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			if (!data.section) {
				return { success: false, error: 'No section provided' };
			}
			uci.load('captive-portal');
			uci.delete('captive-portal', data.section);
			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true };
		}
	},

	get_accounts: {
		call: function() {
			uci.load('captive-portal');
			const accounts = [];

			uci.foreach('captive-portal', 'guest', function(s) {
				push(accounts, {
					section: s['.name'],
					username: s.username || '',
					password: s.password || '',
					mac: s.mac || '',
					upload_limit: s.upload_limit || '0',
					download_limit: s.download_limit || '0',
					timeout: s.timeout || '1200',
					auth_method: s.auth_method || 'password',
					enabled: s.enabled || '1',
				});
			});
			uci.unload('captive-portal');

			return { accounts: accounts };
		}
	},

	add_account: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			uci.load('captive-portal');
			const name = uci.add('captive-portal', 'guest');

			uci.set('captive-portal', name, 'username', data.username || '');
			uci.set('captive-portal', name, 'password', data.password || '');
			uci.set('captive-portal', name, 'mac', data.mac || '');
			uci.set('captive-portal', name, 'upload_limit', data.upload_limit || '0');
			uci.set('captive-portal', name, 'download_limit', data.download_limit || '0');
			uci.set('captive-portal', name, 'timeout', data.timeout || '1200');
			uci.set('captive-portal', name, 'auth_method', data.auth_method || 'password');
			uci.set('captive-portal', name, 'enabled', data.enabled || '1');
			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true };
		}
	},

	update_account: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			if (!data.section) {
				return { success: false, error: 'No section provided' };
			}
			uci.load('captive-portal');
			const section = data.section;

			if (exists(data, 'username')) uci.set('captive-portal', section, 'username', data.username);
			if (exists(data, 'password')) uci.set('captive-portal', section, 'password', data.password);
			if (exists(data, 'mac')) uci.set('captive-portal', section, 'mac', data.mac);
			if (exists(data, 'upload_limit')) uci.set('captive-portal', section, 'upload_limit', data.upload_limit);
			if (exists(data, 'download_limit')) uci.set('captive-portal', section, 'download_limit', data.download_limit);
			if (exists(data, 'timeout')) uci.set('captive-portal', section, 'timeout', data.timeout);
			if (exists(data, 'auth_method')) uci.set('captive-portal', section, 'auth_method', data.auth_method);
			if (exists(data, 'enabled')) uci.set('captive-portal', section, 'enabled', data.enabled);

			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true };
		}
	},

	delete_account: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			if (!data.section) {
				return { success: false, error: 'No section provided' };
			}
			uci.load('captive-portal');
			uci.delete('captive-portal', data.section);
			uci.commit('captive-portal');
			uci.unload('captive-portal');

			return { success: true };
		}
	},

	sync_daemon_config: {
		call: function() {
			return sync_daemon();
		}
	},

	restart_service: {
		call: function() {
			const sync = sync_daemon();
			if (!sync.success) {
				return sync;
			}

			const daemon = get_daemon();
			const fp = popen('/etc/init.d/' + daemon + ' restart 2>&1');
			const output = trim(fp.read('all') || '');
			fp.close();
			return { success: true, output: output };
		}
	},
};

return { 'luci.captive-portal': methods };
