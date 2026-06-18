'use strict';
'require view';
'require rpc';
'require ui';

var callGetClients = rpc.declare({
	object: 'luci.captive-portal',
	method: 'get_clients'
});

var callDisconnectClient = rpc.declare({
	object: 'luci.captive-portal',
	method: 'disconnect_client',
	params: ['data']
});

function formatBytes(bytes) {
	var b = parseInt(bytes) || 0;
	if (b === 0) return '0 B';
	if (b < 1024) return b + ' B';
	if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
	if (b < 1073741824) return (b / 1048576).toFixed(1) + ' MB';
	return (b / 1073741824).toFixed(1) + ' GB';
}

return view.extend({
	load: function() {
		return callGetClients();
	},

	render: function(data) {
		var clients = data.clients || [];
		var error = data.error || null;

		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('IP Address')),
				E('th', { 'class': 'th' }, _('MAC Address')),
				E('th', { 'class': 'th' }, _('Username')),
				E('th', { 'class': 'th' }, _('Uptime')),
				E('th', { 'class': 'th' }, _('Downloaded')),
				E('th', { 'class': 'th' }, _('Uploaded')),
				E('th', { 'class': 'th' }, _('Actions'))
			])
		]);

		if (error) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '7' }, error)
			]));
		} else if (clients.length === 0) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '7' }, _('No clients connected'))
			]));
		} else {
			for (var i = 0; i < clients.length; i++) {
				var c = clients[i];
				(function(client) {
					table.appendChild(E('tr', { 'class': 'tr cbi-section-table-row' }, [
						E('td', { 'class': 'td' }, client.ip || '-'),
						E('td', { 'class': 'td' }, client.mac || '-'),
						E('td', { 'class': 'td' }, client.username || '-'),
						E('td', { 'class': 'td' }, client.uptime || '-'),
						E('td', { 'class': 'td' }, formatBytes(client.downloaded)),
						E('td', { 'class': 'td' }, formatBytes(client.uploaded)),
						E('td', { 'class': 'td' }, [
							E('button', {
								'class': 'btn cbi-button cbi-button-negative',
								'click': function() {
									ui.showModal(_('Confirm Disconnect'), [
										E('p', {}, _('Disconnect client ') + (client.mac || client.ip) + '?'),
										E('div', { 'class': 'right' }, [
											E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
											' ',
											E('button', {
												'class': 'btn cbi-button-negative',
												'click': function() {
											callDisconnectClient({ mac: client.mac, ip: client.ip }).then(function(result) {
												if (result && result.success) {
													ui.hideModal();
													location.reload();
												} else {
													ui.addNotification(null, E('p', {}, _('Failed to disconnect client: ') + (result && result.error ? result.error : _('Unknown error'))));
												}
											}).catch(function(err) {
												ui.addNotification(null, E('p', {}, _('Failed to disconnect client: ') + (err ? String(err) : _('Unknown error'))));
											});
												}
											}, _('Disconnect'))
										])
									]);
								}
							}, _('Disconnect'))
						])
					]));
				})(c);
			}
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Connected Clients')),
			E('div', { 'class': 'cbi-section-descr' }, _('View and manage active client sessions')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'right', 'style': 'margin-bottom: 1em' }, [
					E('button', {
						'class': 'btn cbi-button',
						'click': function() { location.reload(); }
					}, _('Refresh'))
				]),
				table
			])
		]);
	}
});
