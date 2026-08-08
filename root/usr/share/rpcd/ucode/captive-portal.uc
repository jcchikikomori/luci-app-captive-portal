#!/usr/bin/env ucode

'use strict';

import { cursor } from 'uci';
import { popen, lsdir } from 'fs';

const uci = cursor();

// openNDS is the sole supported daemon (the OpenWrt captive-portal daemon
// packages mutually CONFLICT with each other, so there is no runtime toggle
// to preserve).
const CTL_BIN = 'ndsctl';
const DAEMON_SVC = 'opennds';

// Local FAS (Forwarding Authentication Service) listener wiring. These values
// must match task-04's `uhttpd.captive_portal_fas` listener (`listen_http`
// port) and task-10's `fas_auth` ubus method exactly — do not change one side
// without updating the others.
const FAS_PORT = '2080';
const FAS_PATH = '/splash.html';
// Level 1 implies openNDS sends a hashed `hid` token that the FAS is expected
// to verify before trusting client-supplied identifiers. fas_auth does not
// implement that verification (would require reverse-engineering openNDS's
// hid hashing scheme against a real device), so this is set to 0 (plain,
// unverified) rather than falsely advertising a security property that isn't
// implemented. fas_auth's `mac` argument is therefore trusted as given by the
// caller with no cryptographic proof of control over that MAC — see
// CLAUDE.md's Key Design Decision #5 for the accepted-risk writeup.
const FAS_SECURE_ENABLED = '0';

// Single generic failure message returned by fas_auth for every rejection
// path (blocked MAC, no matching account, wrong username/password, MAC
// mismatch, daemon call failure). fas_auth is reachable unauthenticated, so
// the response must never let a caller distinguish "unknown username" from
// "wrong password" from "blocked MAC" (account enumeration).
const AUTH_FAILURE_MESSAGE = 'Authentication failed';

function get_daemon() {
	return DAEMON_SVC;
}

function get_ctl_binary() {
	return CTL_BIN;
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

// Every mac/ip value below eventually flows into a shell command string via
// popen(). Reject anything that isn't a well-formed MAC/IPv4 address BEFORE
// it ever reaches a popen() call, so a crafted value (e.g. containing `;`,
// `|`, backticks) can never execute a second shell command. This is
// especially critical for fas_auth, which is reachable unauthenticated.
function is_valid_mac(mac) {
	return match(mac || '', /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/) != null;
}

function is_valid_ipv4(ip) {
	const m = match(ip || '', /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/);
	if (m == null) return false;
	for (let i = 1; i <= 4; i++) {
		if (int(m[i]) > 255) return false;
	}
	return true;
}

// The FAS splash page cannot obtain the client's own MAC from openNDS's
// redirect at all: confirmed on real hardware (via `logread | grep
// splashpageurl`) that at fas_secure_enabled=0 the query string only ever
// carries authaction/gatewayname/tok/redir — no clientmac, and clientip
// is only reachable embedded inside authaction's own value. ucode's rpcd
// `req` parameter carries no connection-level metadata either (confirmed
// empty on session/object/method) — there is no way to learn the caller's
// address from within the ubus call itself. fas_auth instead derives the
// MAC server-side from the client-reported IP via the router's own ARP/
// neighbor table. This is also more robust against MAC spoofing than
// trusting a client-supplied MAC would have been, since the client has no
// influence over what the router's own neighbor table records for that
// IP (unlike a MAC string in the request body, which is pure user input).
function lookup_mac_by_ip(ip) {
	if (!is_valid_ipv4(ip)) return '';
	const iface = uci.get_first('captive-portal', 'service', 'interface') || 'lan';
	const fp = popen('ip neigh show ' + ip + ' dev ' + iface + ' 2>/dev/null');
	const output = trim(fp.read('all') || '');
	fp.close();
	const m = match(output, /lladdr ([0-9A-Fa-f:]+)/);
	return m ? m[1] : '';
}

function sync_blocked_json() {
	const fp = popen('/usr/lib/captive-portal/sync-blocked-json.sh 2>&1');
	fp.read('all');
	fp.close();
}

function drop_client(mac) {
	if (!is_valid_mac(mac)) {
		return { success: false, error: 'Invalid MAC address' };
	}
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
	return parse_clients_json();
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

// openNDS's `sessiontimeout` is in minutes; our UCI schema's `default_timeout`
// is in seconds. A source value of 0 means "unlimited" in both systems and is
// passed through unconverted; any other value is rounded up to at least 1
// minute so a small nonzero second count never collapses to 0 (which would
// mean "unlimited" instead of "very short").
function timeout_seconds_to_minutes(default_timeout) {
	const seconds = int(default_timeout) || 0;
	if (seconds == 0) {
		return '0';
	}
	const minutes = int(seconds / 60);
	return '' + (minutes > 0 ? minutes : 1);
}

function sync_opennds_config() {
	uci.load('captive-portal');
	uci.load('opennds');

	const service = {
		interface: uci.get_first('captive-portal', 'service', 'interface') || 'lan',
		gatewayname: uci.get_first('captive-portal', 'service', 'gatewayname') || 'CaptivePortal',
		default_timeout: uci.get_first('captive-portal', 'service', 'default_timeout') || '1200',
	};

	let section_name = '';
	uci.foreach('opennds', 'opennds', function(s) {
		section_name = s['.name'];
		return false;
	});

	if (section_name == '') {
		uci.unload('captive-portal');
		uci.unload('opennds');
		return { success: false, error: 'No opennds section found' };
	}

	uci.set('opennds', section_name, 'enabled', '1');
	uci.set('opennds', section_name, 'gatewayname', service.gatewayname);
	uci.set('opennds', section_name, 'gatewayinterface', service.interface);
	uci.set('opennds', section_name, 'sessiontimeout', timeout_seconds_to_minutes(service.default_timeout));
	// binauth.sh is now logging-only (task-07); authentication itself is
	// gated by the fas_auth ubus method (task-10), not this script.
	uci.set('opennds', section_name, 'binauth', '/usr/lib/captive-portal/binauth.sh');
	uci.set('opennds', section_name, 'fasport', FAS_PORT);
	uci.set('opennds', section_name, 'faspath', FAS_PATH);
	uci.set('opennds', section_name, 'fas_secure_enabled', FAS_SECURE_ENABLED);

	uci.commit('opennds');
	uci.unload('captive-portal');
	uci.unload('opennds');

	return { success: true };
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

// -- fas_auth support --------------------------------------------------
//
// openNDS's BinAuth hook cannot gate authentication (it only runs after the
// daemon has already decided) — the local FAS flow calls the fas_auth ubus
// method directly, and it is now the sole place guest credentials/blocked
// MACs are validated. The precedence rules below are ported from this
// package's original binauth.sh `auth_client` case (see git history), which
// performed the same checks synchronously inside nodogsplash's BinAuth call.

function is_mac_blocked(norm_mac) {
	let blocked = false;
	uci.foreach('captive-portal', 'blocked', function(s) {
		if (s.enabled !== '1') return true;
		if (normalize_mac(s.mac || '') === norm_mac) {
			blocked = true;
			return false;
		}
		return true;
	});
	return blocked;
}

function get_default_auth_method() {
	return uci.get_first('captive-portal', 'service', 'auth_method') || 'both';
}

// Returns the matching guest account's session limits, or null if no
// enabled `guest` section matches per its own (or the service-wide default)
// `auth_method`: `password` matches on username+password only, `mac`
// matches on MAC only, `both` requires username+password plus either no MAC
// bound to the account or a MAC that matches the requesting client.
function find_matching_guest(username, password, norm_mac, default_auth_method) {
	let matched = null;

	uci.foreach('captive-portal', 'guest', function(s) {
		if (s.enabled !== '1') return true;

		const stored_user = s.username || '';
		const stored_pass = s.password || '';
		const stored_mac = s.mac || '';
		const stored_mac_norm = normalize_mac(stored_mac);
		const auth_method = s.auth_method || default_auth_method;

		const cred_match = (username === stored_user) && (password === stored_pass);
		const mac_match = (stored_mac != '') && (norm_mac === stored_mac_norm);

		let account_match = false;
		if (auth_method == 'password') {
			account_match = cred_match;
		} else if (auth_method == 'mac') {
			account_match = mac_match;
		} else if (auth_method == 'both') {
			account_match = cred_match && (stored_mac == '' || mac_match);
		}

		if (account_match) {
			matched = { timeout: s.timeout || '1200' };
			return false;
		}
		return true;
	});

	return matched;
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
				daemon: uci.get_first('captive-portal', 'service', 'daemon') || 'opennds',
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
			if (!is_valid_ipv4(ip)) {
				return { success: false, error: 'Invalid IP address' };
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
			if (!is_valid_mac(mac)) {
				return { success: false, error: 'Invalid MAC address' };
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
			if (!is_valid_mac(mac)) {
				return { success: false, error: 'Invalid MAC address' };
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
			if (has_mac && !is_valid_mac(data.mac)) {
				return { success: false, error: 'Invalid MAC address' };
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

	// Unauthenticated entry point called by the local FAS splash page
	// (task-08's splash.js) after the guest submits credentials. This is
	// the actual authentication decision point — the role binauth.sh's
	// `auth_client` case used to play under nodogsplash.
	fas_auth: {
		args: {
			data: {}
		},
		call: function(req) {
			const data = (req.args && req.args.data) || {};
			const username = data.username || '';
			const password = data.password || '';
			const client_ip = data.ip || '';
			const redir = data.redir || '';

			if (!client_ip || !is_valid_ipv4(client_ip)) {
				return { success: false, error: 'No IP provided', redir: redir };
			}

			if (!service_running()) {
				return { success: false, error: 'Service not running', redir: redir };
			}

			uci.load('captive-portal');

			// The client cannot report its own MAC (openNDS never sends
			// clientmac to the FAS at fas_secure_enabled=0 — see splash.js)
			// so it is derived here from the ARP/neighbor table entry for
			// its reported IP. This is also the reason a client-supplied MAC
			// is never trusted: this lookup uses only what the router's own
			// network stack already knows.
			const mac = lookup_mac_by_ip(client_ip);
			if (!mac || !is_valid_mac(mac)) {
				uci.unload('captive-portal');
				return { success: false, error: AUTH_FAILURE_MESSAGE, redir: redir };
			}

			const norm_mac = normalize_mac(mac);

			if (is_mac_blocked(norm_mac)) {
				uci.unload('captive-portal');
				return { success: false, error: AUTH_FAILURE_MESSAGE, redir: redir };
			}

			const default_auth_method = get_default_auth_method();
			const account = find_matching_guest(username, password, norm_mac, default_auth_method);

			uci.unload('captive-portal');

			if (!account) {
				return { success: false, error: AUTH_FAILURE_MESSAGE, redir: redir };
			}

			// Confirmed upstream syntax (ndsctl.c usage text): `ndsctl auth
			// mac|ip|token sessiontimeout(minutes) uploadrate(kb/s)
			// downloadrate(kb/s) uploadquota(kB) downloadquota(kB)
			// customstring`. Only sessiontimeout is passed here, reusing the
			// same seconds->minutes conversion already used for the global
			// default_timeout in sync_opennds_config(). uploadrate/
			// downloadrate/uploadquota/downloadquota are intentionally left
			// unset (the daemon falls back to its own global settings):
			// our per-account upload_limit/download_limit fields have no
			// confirmed unit mapping onto ndsctl's kb/s rate model, and that
			// mapping can't be verified without a real device. Do not guess
			// at it — follow up separately before relying on per-client
			// rate/quota enforcement via `ndsctl auth`.
			const ctl = get_ctl_binary();
			const target = lower_mac(mac);
			const sessiontimeout = timeout_seconds_to_minutes(account.timeout);
			const fp = popen(ctl + ' auth ' + target + ' ' + sessiontimeout + ' 2>&1');
			fp.read('all');
			const rc = fp.close();

			if (rc != 0) {
				return { success: false, error: AUTH_FAILURE_MESSAGE, redir: redir };
			}

			return { success: true, redir: redir };
		}
	},

	sync_daemon_config: {
		call: function() {
			return sync_opennds_config();
		}
	},

	restart_service: {
		call: function() {
			const sync = sync_opennds_config();
			if (!sync.success) {
				return sync;
			}

			const fp = popen('/etc/init.d/' + DAEMON_SVC + ' restart 2>&1');
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
