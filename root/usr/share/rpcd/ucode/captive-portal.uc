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

function parse_clients_output() {
	const ctl = get_ctl_binary();
	const fp = popen(ctl + ' status 2>/dev/null');
	const output = fp.read('all') || '';
	fp.close();

	const clients = [];
	const lines = split(output, '\n');
	let in_client_section = false;
	let current_client = {};

	for (let i = 0; i < length(lines); i++) {
		let line = trim(lines[i]);
		if (line === '') {
			if (current_client.mac) {
				push(clients, current_client);
			}
			current_client = {};
			in_client_section = false;
			continue;
		}

		if (index(line, 'Client MAC:') == 0) {
			in_client_section = true;
			current_client.mac = trim(replace(line, 'Client MAC:', ''));
		} else if (in_client_section) {
			if (index(line, 'IP:') == 0) {
				current_client.ip = trim(replace(line, 'IP:', ''));
			} else if (index(line, 'Name:') == 0) {
				current_client.username = trim(replace(line, 'Name:', ''));
			} else if (index(line, 'Uptime:') == 0) {
				current_client.uptime = trim(replace(line, 'Uptime:', ''));
			} else if (index(line, 'Downloaded:') == 0) {
				current_client.downloaded = trim(replace(line, 'Downloaded:', ''));
			} else if (index(line, 'Uploaded:') == 0) {
				current_client.uploaded = trim(replace(line, 'Uploaded:', ''));
			}
		}
	}

	if (current_client.mac) {
		push(clients, current_client);
	}

	return clients;
}

function get_client_count() {
	const clients = parse_clients_output();
	return length(clients);
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
			return { clients: parse_clients_output() };
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
			const target = mac || ip;
			const fp = popen(ctl + ' deauth ' + target + ' 2>&1');
			const output = trim(fp.read('all') || '');
			fp.close();
			return { success: true, output: output };
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

	restart_service: {
		call: function() {
			const daemon = get_daemon();
			const fp = popen('/etc/init.d/' + daemon + ' restart 2>&1');
			const output = trim(fp.read('all') || '');
			fp.close();
			return { success: true, output: output };
		}
	},
};

return { 'luci.captive-portal': methods };
