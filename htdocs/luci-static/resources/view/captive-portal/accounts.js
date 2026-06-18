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

function isValidMac(mac) {
	return mac === '' || /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(mac);
}

function isValidPassword(password) {
	if (password.length < 12) return false;
	if (!/[A-Z]/.test(password)) return false;
	if (!/[a-z]/.test(password)) return false;
	if (!/[0-9]/.test(password)) return false;
	return true;
}

function formatMacInput(value) {
	var raw = value.replace(/[^0-9a-fA-F]/g, '').toUpperCase();
	var parts = [];
	for (var i = 0; i < raw.length && i < 12; i += 2) {
		parts.push(raw.substr(i, 2));
	}
	return parts.join(':');
}

function showAccountDialog(account) {
	var isEdit = !!account;
	var title = isEdit ? _('Edit Guest Account') : _('Add Guest Account');
	var hasMac = account && account.mac && account.mac !== '';

	var body = E('div', { 'class': 'cbi-section' });

	var fields = {
		username: { label: _('Username'), value: account ? account.username : '', type: 'text', required: true },
		password: { label: _('Password'), value: account ? account.password : '', type: 'password', required: true, id: 'account-password', autocomplete: 'new-password' },
		mac: { label: _('MAC Address'), value: account ? account.mac : '', type: 'text', placeholder: _('Optional') },
		timeout: { label: _('Timeout (seconds)'), value: account ? account.timeout : '1200', type: 'text' },
		enabled: { label: _('Enabled'), value: account ? account.enabled : '1', type: 'checkbox' }
	};

	var macInput = null;
	var authSelect = null;
	var passwordInput = null;

	for (var key in fields) {
		var f = fields[key];
		var input;
		var attrs = { 'class': 'cbi-input-text', 'type': f.type, 'data-field': key, 'value': f.value, 'placeholder': f.placeholder || '' };

		if (f.type === 'checkbox') {
			input = E('input', { 'class': 'cbi-input-checkbox', 'type': 'checkbox', 'data-field': key, 'checked': f.value === '1' ? 'checked' : null });
		} else {
			if (f.id) attrs.id = f.id;
			if (f.autocomplete) attrs.autocomplete = f.autocomplete;
			if (f['aria-label']) attrs['aria-label'] = f['aria-label'];
			input = E('input', attrs);
		}

		if (key === 'mac') {
			macInput = input;
			macInput.addEventListener('input', function() {
				var formatted = formatMacInput(macInput.value);
				macInput.value = formatted;
				var enabled = formatted !== '';
				if (!enabled) {
					authSelect.value = 'password';
				}
				authSelect.disabled = !enabled;
			});
		}

		if (key === 'password') {
			passwordInput = input;
		}

		var labelAttrs = { 'class': 'cbi-value-title' };
		if (f.id) labelAttrs.for = f.id;
		var fieldDiv = E('div', { 'class': 'cbi-value-field' }, [input]);

		if (key === 'password') {
			var toggleBtn = E('button', {
				'class': 'btn cbi-button',
				'style': 'margin-left: 0.5em',
				'type': 'button',
				'aria-pressed': 'false',
				'aria-label': _('Show password'),
				'click': function() {
					var showing = passwordInput.type === 'text';
					passwordInput.type = showing ? 'password' : 'text';
					toggleBtn.setAttribute('aria-pressed', showing ? 'false' : 'true');
					toggleBtn.setAttribute('aria-label', showing ? _('Show password') : _('Hide password'));
					toggleBtn.textContent = showing ? _('Show') : _('Hide');
				}
			}, _('Show'));
			fieldDiv.appendChild(toggleBtn);
		}

		body.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', labelAttrs, f.label + (f.required ? ' *' : '')),
			fieldDiv
		]));
	}

	authSelect = E('select', { 'class': 'cbi-input-select', 'data-field': 'auth_method', 'disabled': hasMac ? null : 'disabled' });
	var authOptions = [
		{ value: 'password', label: _('Password') },
		{ value: 'mac', label: _('MAC Address') },
		{ value: 'both', label: _('Both') }
	];
	var currentAuth = account ? account.auth_method : 'password';
	if (!hasMac) {
		currentAuth = 'password';
	}
	for (var i = 0; i < authOptions.length; i++) {
		var opt = authOptions[i];
		authSelect.appendChild(E('option', { 'value': opt.value, 'selected': opt.value === currentAuth ? 'selected' : null }, opt.label));
	}

	body.appendChild(E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, _('Auth Method')),
		E('div', { 'class': 'cbi-value-field' }, [authSelect])
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

					if (data.username === '') {
						ui.addNotification(null, E('p', {}, _('Username is required.')));
						return;
					}

					if (!isValidPassword(data.password)) {
						ui.addNotification(null, E('p', {}, _('Password must be at least 12 characters and include uppercase, lowercase, and a number.')));
						return;
					}

					if (!isValidMac(data.mac)) {
						ui.addNotification(null, E('p', {}, _('MAC address must be empty or a valid address like AA:BB:CC:DD:EE:FF.')));
						return;
					}

					if (data.mac === '') {
						data.auth_method = 'password';
					} else {
						data.auth_method = authSelect.value;
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
				E('th', { 'class': 'th' }, _('Timeout')),
				E('th', { 'class': 'th' }, _('Auth Method')),
				E('th', { 'class': 'th' }, _('Enabled')),
				E('th', { 'class': 'th' }, _('Actions'))
			])
		]);

		if (accounts.length === 0) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '7' }, _('No guest accounts configured'))
			]));
		} else {
			for (var i = 0; i < accounts.length; i++) {
				var a = accounts[i];
				(function(account) {
						var passCell = E('td', { 'class': 'td' });
						var passSpan = E('span', {}, '••••••••');
						var revealBtn = E('button', {
							'class': 'btn cbi-button',
							'style': 'margin-left: 0.5em',
							'aria-label': _('Reveal password'),
							'aria-pressed': 'false',
							'type': 'button',
							'click': function() {
								var showing = passSpan.textContent !== '••••••••';
								passSpan.textContent = showing ? '••••••••' : account.password;
								revealBtn.setAttribute('aria-pressed', showing ? 'false' : 'true');
								revealBtn.textContent = showing ? _('Show') : _('Hide');
							}
						}, _('Show'));
						passCell.appendChild(passSpan);
						passCell.appendChild(revealBtn);

						table.appendChild(E('tr', { 'class': 'tr cbi-section-table-row' }, [
							E('td', { 'class': 'td' }, account.username),
							passCell,
							E('td', { 'class': 'td' }, account.mac || '-'),
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
