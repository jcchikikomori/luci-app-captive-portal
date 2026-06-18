'use strict';
'require view';
'require rpc';
'require ui';

var callGetAccounts = rpc.declare({
	object: 'luci.captive-portal',
	method: 'get_accounts'
});

var callAddAccount = rpc.declare({
	object: 'luci.captive-portal',
	method: 'add_account',
	params: ['data']
});

var callUpdateAccount = rpc.declare({
	object: 'luci.captive-portal',
	method: 'update_account',
	params: ['data']
});

var callDeleteAccount = rpc.declare({
	object: 'luci.captive-portal',
	method: 'delete_account',
	params: ['data']
});

function formatBytes(bytes) {
	var b = parseInt(bytes) || 0;
	if (b === 0) return _('Unlimited');
	if (b < 1024) return b + ' B';
	if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
	if (b < 1073741824) return (b / 1048576).toFixed(1) + ' MB';
	return (b / 1073741824).toFixed(1) + ' GB';
}

function formatTimeout(seconds) {
	var s = parseInt(seconds) || 0;
	if (s === 0) return _('Unlimited');
	if (s < 60) return s + 's';
	if (s < 3600) return Math.floor(s / 60) + 'm';
	return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
}

function showAccountDialog(account) {
	var isEdit = !!account;
	var title = isEdit ? _('Edit Guest Account') : _('Add Guest Account');

	var fields = {
		username: { label: _('Username'), value: account ? account.username : '', type: 'text', required: true },
		password: { label: _('Password'), value: account ? account.password : '', type: 'text', required: true },
		mac: { label: _('MAC Address'), value: account ? account.mac : '', type: 'text', placeholder: _('Optional') },
		upload_limit: { label: _('Upload Limit (bytes)'), value: account ? account.upload_limit : '0', type: 'text' },
		download_limit: { label: _('Download Limit (bytes)'), value: account ? account.download_limit : '0', type: 'text' },
		timeout: { label: _('Timeout (seconds)'), value: account ? account.timeout : '1200', type: 'text' },
		auth_method: { label: _('Auth Method'), value: account ? account.auth_method : 'password', type: 'select', options: [
			{ value: 'password', label: _('Password') },
			{ value: 'mac', label: _('MAC Address') },
			{ value: 'both', label: _('Both') }
		]},
		enabled: { label: _('Enabled'), value: account ? account.enabled : '1', type: 'checkbox' }
	};

	var body = E('div', { 'class': 'cbi-section' });

	for (var key in fields) {
		var f = fields[key];
		var input;

		if (f.type === 'select') {
			input = E('select', { 'class': 'cbi-input-select', 'data-field': key });
			for (var i = 0; i < f.options.length; i++) {
				var opt = f.options[i];
				input.appendChild(E('option', { 'value': opt.value, 'selected': opt.value === f.value ? 'selected' : null }, opt.label));
			}
		} else if (f.type === 'checkbox') {
			input = E('input', { 'class': 'cbi-input-checkbox', 'type': 'checkbox', 'data-field': key, 'checked': f.value === '1' ? 'checked' : null });
		} else {
			input = E('input', { 'class': 'cbi-input-text', 'type': f.type, 'data-field': key, 'value': f.value, 'placeholder': f.placeholder || '' });
		}

		body.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, f.label + (f.required ? ' *' : '')),
			E('div', { 'class': 'cbi-value-field' }, [input])
		]));
	}

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
					var data = {};
					var inputs = body.querySelectorAll('[data-field]');
					for (var i = 0; i < inputs.length; i++) {
						var inp = inputs[i];
						var field = inp.getAttribute('data-field');
						if (inp.type === 'checkbox') {
							data[field] = inp.checked ? '1' : '0';
					} else if (field === 'mac') {
						data[field] = inp.value.trim().toUpperCase();
					} else {
						data[field] = inp.value;
					}
					}

					function handleResult(result, action) {
						if (result && result.success) {
							ui.hideModal();
							location.reload();
						} else {
							ui.addNotification(null, E('p', {}, _('Failed to ') + action + ': ' + (result && result.error ? result.error : _('Unknown error'))));
						}
					}

					if (isEdit) {
						data.section = account.section;
						callUpdateAccount(data).then(function(result) {
							handleResult(result, _('save account'));
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, _('Failed to save account: ') + (err ? String(err) : _('Unknown error'))));
						});
					} else {
						callAddAccount(data).then(function(result) {
							handleResult(result, _('create account'));
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, _('Failed to create account: ') + (err ? String(err) : _('Unknown error'))));
						});
					}
				}
			}, isEdit ? _('Save') : _('Add'))
		])
	]);
}

return view.extend({
	load: function() {
		return callGetAccounts();
	},

	render: function(data) {
		var accounts = data.accounts || [];

		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Username')),
				E('th', { 'class': 'th' }, _('Password')),
				E('th', { 'class': 'th' }, _('MAC Address')),
				E('th', { 'class': 'th' }, _('Upload Limit')),
				E('th', { 'class': 'th' }, _('Download Limit')),
				E('th', { 'class': 'th' }, _('Timeout')),
				E('th', { 'class': 'th' }, _('Auth Method')),
				E('th', { 'class': 'th' }, _('Enabled')),
				E('th', { 'class': 'th' }, _('Actions'))
			])
		]);

		if (accounts.length === 0) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '9' }, _('No guest accounts configured'))
			]));
		} else {
			for (var i = 0; i < accounts.length; i++) {
				var a = accounts[i];
				(function(account) {
					table.appendChild(E('tr', { 'class': 'tr cbi-section-table-row' }, [
						E('td', { 'class': 'td' }, account.username),
						E('td', { 'class': 'td' }, account.password),
						E('td', { 'class': 'td' }, account.mac || '-'),
						E('td', { 'class': 'td' }, formatBytes(account.upload_limit)),
						E('td', { 'class': 'td' }, formatBytes(account.download_limit)),
						E('td', { 'class': 'td' }, formatTimeout(account.timeout)),
						E('td', { 'class': 'td' }, account.auth_method),
						E('td', { 'class': 'td' }, account.enabled === '1' ? _('Yes') : _('No')),
						E('td', { 'class': 'td' }, [
							E('button', {
								'class': 'btn cbi-button cbi-button-edit',
								'click': function() { showAccountDialog(account); }
							}, _('Edit')),
							' ',
							E('button', {
								'class': 'btn cbi-button cbi-button-negative',
								'click': function() {
									ui.showModal(_('Confirm Delete'), [
										E('p', {}, _('Are you sure you want to delete this account?')),
										E('div', { 'class': 'right' }, [
											E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
											' ',
											E('button', {
												'class': 'btn cbi-button-negative',
												'click': function() {
												callDeleteAccount({ section: account.section }).then(function(result) {
													if (result && result.success) {
														ui.hideModal();
														location.reload();
													} else {
														ui.addNotification(null, E('p', {}, _('Failed to delete account: ') + (result && result.error ? result.error : _('Unknown error'))));
													}
												}).catch(function(err) {
													ui.addNotification(null, E('p', {}, _('Failed to delete account: ') + (err ? String(err) : _('Unknown error'))));
												});
												}
											}, _('Delete'))
										])
									]);
								}
							}, _('Delete'))
						])
					]));
				})(a);
			}
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Guest Accounts')),
			E('div', { 'class': 'cbi-section-descr' }, _('Manage guest accounts for captive portal authentication')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'right', 'style': 'margin-bottom: 1em' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-add',
						'click': function() { showAccountDialog(null); }
					}, _('Add Account'))
				]),
				table
			])
		]);
	}
});
