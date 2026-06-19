'use strict';
'require view';
'require rpc';
'require ui';

var callGetStatus = rpc.declare({
	object: 'luci.captive-portal',
	method: 'get_status'
});

var callRestartService = rpc.declare({
	object: 'luci.captive-portal',
	method: 'restart_service'
});

return view.extend({
	load: function() {
		return callGetStatus();
	},

	render: function(data) {
		var running = data.running || false;
		var daemon = data.daemon || 'nodogsplash';
		var uptime = data.uptime || '-';
		var clientCount = data.client_count || 0;
		var daemonStatus = data.daemon_status || '';
		var config = data.config || {};

		var statusText = running ? _('Running') : _('Stopped');
		var statusClass = running ? 'label-success' : 'label-danger';

		var daemonDisplay = daemon === 'opennds' ? 'OpenNDS' : 'Nodogsplash';

		return E('div', { 'class': 'cbi-map' }, [
			E('style', {}, '.cbi-page-actions { display: none !important; }'),
			E('h2', {}, _('Captive Portal Status')),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Service Information')),
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, _('Status')),
						E('td', { 'class': 'td left' }, [
							E('span', { 'class': 'label ' + statusClass }, statusText)
						])
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Daemon')),
						E('td', { 'class': 'td left' }, daemonDisplay)
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Interface')),
						E('td', { 'class': 'td left' }, config.interface || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Gateway Name')),
						E('td', { 'class': 'td left' }, config.gatewayname || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Uptime')),
						E('td', { 'class': 'td left' }, uptime)
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Connected Clients')),
						E('td', { 'class': 'td left' }, '' + clientCount)
					])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Daemon Status')),
				E('div', { 'class': 'cbi-section-descr' }, _('Raw status output from the active daemon')),
				running
					? E('div', { 'class': 'cbi-value-field', 'style': 'font-family: monospace; white-space: pre-wrap; word-wrap: break-word; padding: 0.5em;' }, daemonStatus || _('No status output available'))
					: E('p', { 'class': 'cbi-section-descr' }, _('Service is not running'))
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Service Controls')),
				E('div', { 'class': 'cbi-section-descr' }, _('Manage the captive portal daemon')),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							callRestartService().then(function(result) {
								if (result.success) {
									ui.addNotification(null, E('p', {}, _('Service restarted successfully')));
									setTimeout(function() { location.reload(); }, 1500);
								} else {
									ui.addNotification(null, E('p', {}, _('Failed to restart service: ') + (result.error || '')));
								}
							});
						}
					}, _('Restart Service'))
				])
			])
		]);
	}
});
