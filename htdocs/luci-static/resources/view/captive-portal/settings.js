'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;

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

		o = s.option(form.Value, 'interface', _('Interface'),
			_('Network interface to bind to'));
		o.placeholder = 'lan';
		o.rmempty = false;

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
			_('Default upload bandwidth limit in bytes (0 = unlimited)'));
		o.placeholder = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Value, 'default_download_limit', _('Default Download Limit'),
			_('Default download bandwidth limit in bytes (0 = unlimited)'));
		o.placeholder = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Value, 'default_timeout', _('Default Timeout'),
			_('Default session timeout in seconds'));
		o.placeholder = '1200';
		o.datatype = 'uinteger';
		o.rmempty = false;

		return m.render();
	},
});
