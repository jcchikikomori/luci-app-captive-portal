#!/usr/bin/env ucode

'use strict';

import { cursor } from 'uci';
import { popen } from 'fs';

const uci = cursor();

function get_daemon() {
	uci.load('captive-portal');
	const sections = uci.sections('captive-portal', 'service');
	if (length(sections) > 0) {
		return uci.get('captive-portal', sections[0]['.name'], 'daemon') || 'nodogsplash';
	}
	return 'nodogsplash';
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
	const fp = popen(`ps | grep -c '[${substr(daemon, 0, 1)}]${substr(daemon, 1)}'`);
	const count = trim(fp.read('all') || '0');
	fp.close();
	return int(count) > 0;
}

function get_uptime() {
	const daemon = get_daemon();
	const fp = popen(`ps -o etime= -C ${daemon} 2>/dev/null`);
	const etime = trim(fp.read('all') || '');
	fp.close();
	return etime;
}

function parse_clients_output() {
	const ctl = get_ctl_binary();
	const fp = popen(`${ctl} status 2>/dev/null`);
	const output = fp.read('all') || '';
	fp.close();

	const clients = [];
	const lines = split(output, '\n');
	let in_client_section = false;
	let current_client = {};

	for (let line of lines) {
		line = trim(line);
		if (line === '') {
			if (current_client.mac) {
				push(clients, current_client);
			}
			current_client = {};
			in_client_section = false;
			continue;
		}

		if (match(line, /^Client MAC:/)) {
			in_client_section = true;
			current_client.mac = trim(replace(line, /^Client MAC:\s*/, ''));
		} else if (in_client_section) {
			if (match(line, /^IP:/)) {
				current_client.ip = trim(replace(line, /^IP:\s*/, ''));
			} else if (match(line, /^Name:/)) {
				current_client.username = trim(replace(line, /^Name:\s*/, ''));
			} else if (match(line, /^Uptime:/)) {
				current_client.uptime = trim(replace(line, /^Uptime:\s*/, ''));
			} else if (match(line, /^Downloaded:/)) {
				current_client.downloaded = trim(replace(line, /^Downloaded:\s*/, ''));
			} else if (match(line, /^Uploaded:/)) {
				current_client.uploaded = trim(replace(line, /^Uploaded:\s*/, ''));
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
			const sections = uci.sections('captive-portal', 'service');
			let config = {};
			if (length(sections) > 0) {
				const s = sections[0];
				config = {
					daemon: uci.get('captive-portal', s['.name'], 'daemon') || 'nodogsplash',
					interface: uci.get('captive-portal', s['.name'], 'interface') || 'lan',
					portal_name: uci.get('captive-portal', s['.name'], 'portal_name') || 'Guest WiFi',
					gatewayname: uci.get('captive-portal', s['.name'], 'gatewayname') || 'CaptivePortal',
				};
			}
			uci.unload();

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
		call: function(args) {
			const mac = args?.mac || '';
			const ip = args?.ip || '';
			if (!mac && !ip) {
				return { success: false, error: 'No MAC or IP provided' };
			}
			const ctl = get_ctl_binary();
			let target = mac || ip;
			const fp = popen(`${ctl} deauth ${target} 2>&1`);
			const output = trim(fp.read('all') || '');
			fp.close();
			return { success: true, output: output };
		}
	},

	get_accounts: {
		call: function() {
			uci.load('captive-portal');
			const sections = uci.sections('captive-portal', 'guest');
			const accounts = [];

			for (let s of sections) {
				const name = s['.name'];
				push(accounts, {
					section: name,
					username: uci.get('captive-portal', name, 'username') || '',
					password: uci.get('captive-portal', name, 'password') || '',
					mac: uci.get('captive-portal', name, 'mac') || '',
					upload_limit: uci.get('captive-portal', name, 'upload_limit') || '0',
					download_limit: uci.get('captive-portal', name, 'download_limit') || '0',
					timeout: uci.get('captive-portal', name, 'timeout') || '1200',
					auth_method: uci.get('captive-portal', name, 'auth_method') || 'password',
					enabled: uci.get('captive-portal', name, 'enabled') || '1',
				});
			}
			uci.unload();

			return { accounts: accounts };
		}
	},

	add_account: {
		call: function(args) {
			if (!args) {
				return { success: false, error: 'No arguments provided' };
			}
			uci.load('captive-portal');
			uci.add('captive-portal', 'guest');
			const name = '@guest[-1]';

			uci.set('captive-portal', name, 'username', args.username || '');
			uci.set('captive-portal', name, 'password', args.password || '');
			uci.set('captive-portal', name, 'mac', args.mac || '');
			uci.set('captive-portal', name, 'upload_limit', args.upload_limit || '0');
			uci.set('captive-portal', name, 'download_limit', args.download_limit || '0');
			uci.set('captive-portal', name, 'timeout', args.timeout || '1200');
			uci.set('captive-portal', name, 'auth_method', args.auth_method || 'password');
			uci.set('captive-portal', name, 'enabled', args.enabled || '1');
			uci.commit('captive-portal');
			uci.unload();

			return { success: true };
		}
	},

	update_account: {
		call: function(args) {
			if (!args || !args.section) {
				return { success: false, error: 'No section provided' };
			}
			uci.load('captive-portal');
			const section = args.section;

			if (args.username !== undefined) uci.set('captive-portal', section, 'username', args.username);
			if (args.password !== undefined) uci.set('captive-portal', section, 'password', args.password);
			if (args.mac !== undefined) uci.set('captive-portal', section, 'mac', args.mac);
			if (args.upload_limit !== undefined) uci.set('captive-portal', section, 'upload_limit', args.upload_limit);
			if (args.download_limit !== undefined) uci.set('captive-portal', section, 'download_limit', args.download_limit);
			if (args.timeout !== undefined) uci.set('captive-portal', section, 'timeout', args.timeout);
			if (args.auth_method !== undefined) uci.set('captive-portal', section, 'auth_method', args.auth_method);
			if (args.enabled !== undefined) uci.set('captive-portal', section, 'enabled', args.enabled);

			uci.commit('captive-portal');
			uci.unload();

			return { success: true };
		}
	},

	delete_account: {
		call: function(args) {
			if (!args || !args.section) {
				return { success: false, error: 'No section provided' };
			}
			uci.load('captive-portal');
			uci.delete('captive-portal', args.section);
			uci.commit('captive-portal');
			uci.unload();

			return { success: true };
		}
	},

	restart_service: {
		call: function() {
			const daemon = get_daemon();
			const fp = popen(`/etc/init.d/${daemon} restart 2>&1`);
			const output = trim(fp.read('all') || '');
			fp.close();
			return { success: true, output: output };
		}
	},
};

return { 'luci.captive-portal': methods };
