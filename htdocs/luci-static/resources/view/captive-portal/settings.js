'use strict';
'require view';
'require form';
'require rpc';
'require uci';

var callGetNetworkDevices = rpc.declare({
	object: 'luci.captive-portal',
	method: 'get_network_devices'
});

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callGetNetworkDevices(), { devices: [] }),
			uci.load('captive-portal')
		]).then(function(res) {
			return {
				devices: res[0].devices || [],
				currentInterface: uci.get_first('captive-portal', 'service', 'interface') || 'lan'
			};
		});
	},

	render: function(data) {
		var m, s, o;
		var devices = data.devices || [];
		var currentInterface = data.currentInterface || 'lan';

		m = new form.Map('captive-portal', _('Captive Portal Settings'),
			_('Configure the captive portal daemon and default settings.'));

		s = m.section(form.TypedSection, 'service', _('Service Configuration'));
		s.anonymous = true;

		o = s.option(form.DummyValue, 'daemon', _('Daemon'),
			_('The active captive portal daemon (cannot be changed)'));
		o.cfgvalue = function() {
			var val = this.map.data.get(this.map.config, this.section, 'daemon');
			return val === 'opennds' ? 'OpenNDS' : 'Nodogsplash';
		};
		o.rawhtml = true;

		o = s.option(form.ListValue, 'interface', _('Interface'),
			_('Network interface to bind to'));
		o.rmempty = false;

		var seenCurrent = false;

		for (var i = 0; i < devices.length; i++) {
			var name = devices[i];
			o.value(name, name);
			if (name === currentInterface) {
				seenCurrent = true;
			}
		}

		if (!seenCurrent && currentInterface) {
			o.value(currentInterface, currentInterface + ' ' + _('(current)'));
		}

		o = s.option(form.ListValue, 'auth_method', _('Authentication Method'),
			_('Default authentication method for guests'));
		o.value('password', _('Username and Password'));
		o.value('mac', _('MAC Address Only'));
		o.value('both', _('Both'));
		o.rmempty = false;

		o = s.option(form.Value, 'gatewayname', _('Gateway Name'),
			_('Gateway name used by the daemon'));
		o.placeholder = 'CaptivePortal';
		o.rmempty = false;

		o = s.option(form.Value, 'max_client_time', _('Max Client Time'),
			_('Maximum session time in minutes (0 = unlimited)'));
		o.placeholder = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Value, 'default_upload_limit', _('Default Upload Limit'),
			_('Default upload bandwidth limit in KB (0 = unlimited)'));
		o.placeholder = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;
		o.cfgvalue = function(section) {
			var bytes = this.map.data.get(this.map.config, section, 'default_upload_limit') || '0';
			return String(Math.round(parseInt(bytes) / 1024));
		};
		o.write = function(section, value) {
			var kb = parseInt(value) || 0;
			return this.map.data.set(this.map.config, section, 'default_upload_limit', String(kb * 1024));
		};

		o = s.option(form.Value, 'default_download_limit', _('Default Download Limit'),
			_('Default download bandwidth limit in KB (0 = unlimited)'));
		o.placeholder = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;
		o.cfgvalue = function(section) {
			var bytes = this.map.data.get(this.map.config, section, 'default_download_limit') || '0';
			return String(Math.round(parseInt(bytes) / 1024));
		};
		o.write = function(section, value) {
			var kb = parseInt(value) || 0;
			return this.map.data.set(this.map.config, section, 'default_download_limit', String(kb * 1024));
		};

		o = s.option(form.Value, 'default_timeout', _('Default Timeout'),
			_('Default session timeout in seconds'));
		o.placeholder = '1200';
		o.datatype = 'uinteger';
		o.rmempty = false;

		return m.render();
	},
});
