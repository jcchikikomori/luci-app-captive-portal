'use strict';
'require view';
'require rpc';
'require ui';

var callGetBlocked = rpc.declare({
	object: 'luci.captive-portal',
	method: 'get_blocked'
});

var callAddBlocked = rpc.declare({
	object: 'luci.captive-portal',
	method: 'add_blocked',
	params: ['data']
});

var callUpdateBlocked = rpc.declare({
	object: 'luci.captive-portal',
	method: 'update_blocked',
	params: ['data']
});

var callDeleteBlocked = rpc.declare({
	object: 'luci.captive-portal',
	method: 'delete_blocked',
	params: ['data']
});

function isValidMac(mac) {
	return /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(mac);
}

function formatMacInput(value) {
	var raw = value.replace(/[^0-9a-fA-F]/g, '').toUpperCase();
	var parts = [];
	for (var i = 0; i < raw.length && i < 12; i += 2) {
		parts.push(raw.substr(i, 2));
	}
	return parts.join(':');
}

function showBlockedDialog(entry) {
	var isEdit = !!entry;
	var title = isEdit ? _('Edit Blacklist Entry') : _('Add to Blacklist');

	var body = E('div', { 'class': 'cbi-section' });

	var macInput = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'id': 'blacklist-mac',
		'value': entry ? entry.mac : '',
		'placeholder': 'AA:BB:CC:DD:EE:FF',
		'autocomplete': 'off',
		'aria-label': _('MAC Address')
	});

	macInput.addEventListener('input', function() {
		macInput.value = formatMacInput(macInput.value);
	});

	var enabledInput = E('input', {
		'class': 'cbi-input-checkbox',
		'type': 'checkbox',
		'id': 'blacklist-enabled',
		'checked': (!entry || entry.enabled === '1') ? 'checked' : null
	});

	body.appendChild(E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title', 'for': 'blacklist-mac' }, _('MAC Address') + ' *'),
		E('div', { 'class': 'cbi-value-field' }, [macInput])
	]));

	body.appendChild(E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title', 'for': 'blacklist-enabled' }, _('Enabled')),
		E('div', { 'class': 'cbi-value-field' }, [enabledInput])
	]));

	ui.showModal(title, [
		body,
		E('div', { 'class': 'right' }, [
			E('button', {
				'class': 'btn',
				'click': ui.hideModal
			}, _('Cancel')),
			' ',
			E('button', {
				'class': 'btn cbi-button-positive',
				'click': function() {
					var mac = macInput.value.trim().toUpperCase();
					if (!isValidMac(mac)) {
						ui.addNotification(null, E('p', {}, _('MAC address must be a valid address like AA:BB:CC:DD:EE:FF.')));
						return;
					}

					var data = {
						mac: mac,
						enabled: enabledInput.checked ? '1' : '0'
					};

					function handleResult(result, action) {
						if (result && result.success) {
							ui.hideModal();
							location.reload();
						} else {
							ui.addNotification(null, E('p', {}, _('Failed to ') + action + ': ' + (result && result.error ? result.error : _('Unknown error'))));
						}
					}

					if (isEdit) {
						data.section = entry.section;
						callUpdateBlocked(data).then(function(result) {
							handleResult(result, _('update blacklist entry'));
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, _('Failed to update blacklist entry: ') + (err ? String(err) : _('Unknown error'))));
						});
					} else {
						callAddBlocked(data).then(function(result) {
							handleResult(result, _('add to blacklist'));
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, _('Failed to add to blacklist: ') + (err ? String(err) : _('Unknown error'))));
						});
					}
				}
			}, isEdit ? _('Save') : _('Add'))
		])
	]);
}

return view.extend({
	load: function() {
		return callGetBlocked();
	},

	render: function(data) {
		var blocked = data.blocked || [];

		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('MAC Address')),
				E('th', { 'class': 'th' }, _('Enabled')),
				E('th', { 'class': 'th' }, _('Actions'))
			])
		]);

		if (blocked.length === 0) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '3' }, _('No devices are blacklisted'))
			]));
		} else {
			for (var i = 0; i < blocked.length; i++) {
				var b = blocked[i];
				(function(entry) {
					table.appendChild(E('tr', { 'class': 'tr cbi-section-table-row' }, [
						E('td', { 'class': 'td' }, entry.mac),
						E('td', { 'class': 'td' }, entry.enabled === '1' ? _('Yes') : _('No')),
						E('td', { 'class': 'td' }, [
							E('button', {
								'class': 'btn cbi-button cbi-button-edit',
								'click': function() { showBlockedDialog(entry); }
							}, _('Edit')),
							' ',
							E('button', {
								'class': 'btn cbi-button cbi-button-negative',
								'click': function() {
									ui.showModal(_('Confirm Delete'), [
										E('p', {}, _('Remove this device from the blacklist?')),
										E('div', { 'class': 'right' }, [
											E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
											' ',
											E('button', {
												'class': 'btn cbi-button-negative',
												'click': function() {
												callDeleteBlocked({ section: entry.section }).then(function(result) {
													if (result && result.success) {
														ui.hideModal();
														location.reload();
													} else {
														ui.addNotification(null, E('p', {}, _('Failed to delete blacklist entry: ') + (result && result.error ? result.error : _('Unknown error'))));
													}
												}).catch(function(err) {
													ui.addNotification(null, E('p', {}, _('Failed to delete blacklist entry: ') + (err ? String(err) : _('Unknown error'))));
												});
											}
										}, _('Delete'))
										])
									]);
								}
							}, _('Delete'))
						])
					]));
				})(b);
			}
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Blacklist')),
			E('div', { 'class': 'cbi-section-descr' }, _('Manage blocked MAC addresses that are prevented from authenticating')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'right', 'style': 'margin-bottom: 1em' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-add',
						'click': function() { showBlockedDialog(null); }
					}, _('Add to Blacklist'))
				]),
				table
			])
		]);
	}
});
