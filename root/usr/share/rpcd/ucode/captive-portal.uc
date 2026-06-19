#!/usr/bin/env ucode

'use strict';

import { cursor } from 'uci';
import { popen, lsdir } from 'fs';

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

function sync_blocked_json() {
	const fp = popen('/usr/lib/captive-portal/sync-blocked-json.sh 2>&1');
	fp.read('all');
	fp.close();
}

function drop_client(mac) {
	if (!service_running()) {
		return { success: false, error: 'Service not running' };
	}
	const ctl = get_ctl_binary();
	const target = lower_mac(mac);
	const fp = popen(ctl + ' deauth ' + target + ' 2>&1');
	const output = trim(fp.read('all') || '');
	const rc = fp.close();
	if (rc == 0) {
		return { success: true, output: output };
	}
	if (index(output, 'not found') >= 0) {
		const check = popen(ctl + ' json ' + target + ' 2>&1');
		const checkOutput = trim(check.read('all') || '');
		check.close();
		if (checkOutput != '' && index(checkOutput, '"state":"Preauthenticated"') >= 0) {
			return { success: true, output: 'Client has no active session' };
		}
	}
	return { success: false, error: output };
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

function get_daemon_status_text() {
	const ctl = get_ctl_binary();
	const fp = popen(ctl + ' status 2>&1');
	const output = fp.read('all') || '';
	fp.close();
	return output;
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

function bytes_to_mbit(bytes) {
	const b = int(bytes) || 0;
	if (b <= 0) return '0';
	const mbit = (b * 8) / 1000000;
	return '' + int(mbit);
}

function get_bridge_members(iface) {
	const fp = popen('cat /sys/class/net/' + iface + '/brif/* 2>/dev/null || ls /sys/class/net/' + iface + '/brif/ 2>/dev/null');
	const output = trim(fp.read('all') || '');
	fp.close();
	if (output == '') return [];
	const members = split(output, '\n');
	const result = [];
	for (let i = 0; i < length(members); i++) {
		const m = trim(members[i]);
		if (m != '') push(result, m);
	}
	return result;
}

function get_network_devices() {
	const devices = [];
	const dir = lsdir('/sys/class/net');
	for (let i = 0; i < length(dir); i++) {
		const name = dir[i];
		if (name == 'lo') continue;
		push(devices, name);
	}
	sort(devices);
	return devices;
}

function get_qos_interface_names() {
	uci.load('captive-portal');
	const cp_iface = uci.get_first('captive-portal', 'service', 'interface') || 'lan';
	uci.unload('captive-portal');

	const names = [cp_iface];
	const members = get_bridge_members(cp_iface);
	for (let i = 0; i < length(members); i++) {
		push(names, members[i]);
	}
	return names;
}

function sync_qos_config() {
	uci.load('captive-portal');
	const upload_bytes = uci.get_first('captive-portal', 'service', 'default_upload_limit') || '0';
	const download_bytes = uci.get_first('captive-portal', 'service', 'default_download_limit') || '0';
	uci.unload('captive-portal');

	const upload_mbit = bytes_to_mbit(upload_bytes);
	const download_mbit = bytes_to_mbit(download_bytes);
	const match_names = get_qos_interface_names();

	// Check for qosify
	const fp_qosify = popen('test -f /etc/config/qosify && echo yes || echo no');
	const has_qosify = trim(fp_qosify.read('all') || '') === 'yes';
	fp_qosify.close();

	if (has_qosify) {
		uci.load('qosify');
		let updated = false;
		uci.foreach('qosify', 'interface', function(s) {
			if (s.disabled === '1') return true;
			const iface_name = s.name || s['.name'];
			let matched = false;
			for (let i = 0; i < length(match_names); i++) {
				if (iface_name === match_names[i]) {
					matched = true;
					break;
				}
			}
			if (!matched) return true;
			uci.set('qosify', s['.name'], 'bandwidth_up', upload_mbit + 'mbit');
			uci.set('qosify', s['.name'], 'bandwidth_down', download_mbit + 'mbit');
			updated = true;
			return true;
		});
		if (updated) {
			uci.commit('qosify');
		}
		uci.unload('qosify');
		return { success: true, qos: 'qosify' };
	}

	// Check for sqm
	const fp_sqm = popen('test -f /etc/config/sqm && echo yes || echo no');
	const has_sqm = trim(fp_sqm.read('all') || '') === 'yes';
	fp_sqm.close();

	if (has_sqm) {
		uci.load('sqm');
		let updated = false;
		uci.foreach('sqm', 'queue', function(s) {
			if (s.enabled === '0') return true;
			const iface_name = s.interface || '';
			let matched = false;
			for (let i = 0; i < length(match_names); i++) {
				if (iface_name === match_names[i]) {
					matched = true;
					break;
				}
			}
			if (!matched) return true;
			// SQM uses kbit/s, convert from bytes: bytes * 8 / 1000
			const upload_kbit = '' + int((int(upload_bytes) || 0) * 8 / 1000);
			const download_kbit = '' + int((int(download_bytes) || 0) * 8 / 1000);
			uci.set('sqm', s['.name'], 'upload', upload_kbit);
			uci.set('sqm', s['.name'], 'download', download_kbit);
			updated = true;
			return true;
		});
		if (updated) {
			uci.commit('sqm');
		}
		uci.unload('sqm');
		return { success: true, qos: 'sqm' };
	}

	return { success: true, qos: 'none' };
}

const methods = {
	get_status: {
		call: function() {
			const daemon = get_daemon();
			const running = service_running();
			const uptime = running ? get_uptime() : '';
			const client_count = running ? get_client_count() : 0;
			const daemon_status = running ? get_daemon_status_text() : '';

			uci.load('captive-portal');
			const config = {
				daemon: uci.get_first('captive-portal', 'service', 'daemon') || 'nodogsplash',
				interface: uci.get_first('captive-portal', 'service', 'interface') || 'lan',
				gatewayname: uci.get_first('captive-portal', 'service', 'gatewayname') || 'CaptivePortal',
			};
			uci.unload('captive-portal');

			return {
				running: running,
				daemon: daemon,
				uptime: uptime,
				client_count: client_count,
				daemon_status: daemon_status,
				config: config,
			};
		}
	},

	get_daemon_status: {
		call: function() {
			if (!service_running()) {
				return { success: false, error: 'Service not running' };
			}
			const output = get_daemon_status_text();
			return { success: true, output: output };
		}
	},

	get_network_devices: {
		call: function() {
			return { success: true, devices: get_network_devices() };
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
			if (mac) {
				return drop_client(mac);
			}
			const ctl = get_ctl_binary();
			const fp = popen(ctl + ' deauth ' + ip + ' 2>&1');
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

			// Deauthenticate / drop the client first.
			const deauth = drop_client(mac);

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

			sync_blocked_json();

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

			// Drop an active session for this MAC, if any.
			const deauth = drop_client(mac);

			uci.load('captive-portal');
			const section = uci.add('captive-portal', 'blocked');
			uci.set('captive-portal', section, 'mac', norm_mac);
			uci.set('captive-portal', section, 'enabled', '1');
			uci.commit('captive-portal');
			uci.unload('captive-portal');

			sync_blocked_json();

			return { success: true, section: section, deauth: deauth };
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

			// Drop any active session when the entry is enabled.
			let deauth = { success: true, output: '' };
			if (uci.get('captive-portal', section, 'enabled') !== '0') {
				const mac = uci.get('captive-portal', section, 'mac');
				if (mac) deauth = drop_client(mac);
			}

			uci.commit('captive-portal');
			uci.unload('captive-portal');

			sync_blocked_json();

			return { success: true, deauth: deauth };
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

			sync_blocked_json();

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

			let qos = { success: true, qos: 'none' };
			try {
				qos = sync_qos_config();
			} catch (e) {
				qos = { success: false, error: 'QoS sync failed: ' + e };
			}

			return { success: true, output: output, qos: qos };
		}
	},
};

return { 'luci.captive-portal': methods };
