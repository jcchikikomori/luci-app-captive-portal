(function() {
	'use strict';

	// openNDS has no `$var` template-substitution mechanism for a static FAS
	// splash page (unlike nodogsplash) — it instead redirects the client's
	// browser to this page with client/session info appended as a query
	// string (fas_secure_enabled=1: plain, not encrypted). See
	// docs/plans/analysis/opennds-verification-findings.md, section 5.
	var fasParams = (function parseFasParams() {
		var params = new URLSearchParams(window.location.search);
		return {
			clientip: params.get('clientip') || '',
			clientmac: params.get('clientmac') || '',
			gatewayname: params.get('gatewayname') || '',
			gatewayaddress: params.get('gatewayaddress') || '',
			clientif: params.get('clientif') || '',
			authdir: params.get('authdir') || '',
			redir: params.get('redir') || '',
			// fas_secure_enabled level 1 sends a plain 'tok'; higher levels
			// (not used by this app) send a hashed 'hid' instead. fas_auth
			// does not currently verify either value (see captive-portal.uc).
			token: params.get('tok') || params.get('hid') || ''
		};
	})();

	// Well-known all-zero ubus session ID used for unauthenticated /ubus
	// JSON-RPC calls. This app's rpcd ACL grants the "unauthenticated" scope
	// access to fas_auth specifically so this splash page (which has no LuCI
	// login session) can call it.
	var ANONYMOUS_UBUS_SESSION = '00000000000000000000000000000000';

	// redir is attacker-influenced (FAS query string, or echoed back by
	// fas_auth). Reject javascript:/data: and other non-http(s) schemes
	// before ever assigning it to window.location, so a crafted redir value
	// can't execute script in this page's origin.
	function sanitizeRedirect(url) {
		try {
			var parsed = new URL(url, window.location.origin);
			if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
				return '/';
			}
			return parsed.href;
		} catch (e) {
			return '/';
		}
	}

	// Submits credentials to the fas_auth ubus method via the same listener
	// that served this page (task-04's FAS uhttpd instance exposes /ubus
	// alongside the static splash assets). Uses the standard ubus HTTP
	// JSON-RPC envelope (matching the shape this app's LuCI views send via
	// rpc.declare): {jsonrpc, id, method: "call", params: [session, object,
	// method, args]}.
	function callFasAuth(credentials) {
		var payload = {
			jsonrpc: '2.0',
			id: 1,
			method: 'call',
			params: [
				ANONYMOUS_UBUS_SESSION,
				'luci.captive-portal',
				'fas_auth',
				{
					data: {
						username: credentials.username,
						password: credentials.password,
						mac: fasParams.clientmac,
						redir: fasParams.redir
					}
				}
			]
		};

		return fetch('/ubus', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(payload)
		}).then(function(response) {
			return response.json();
		}).then(function(envelope) {
			if (!envelope || envelope.error || !Array.isArray(envelope.result)) {
				throw new Error('Invalid response from authentication service');
			}

			var ubusStatus = envelope.result[0];
			var result = envelope.result[1] || {};

			if (ubusStatus !== 0) {
				throw new Error('Authentication service unavailable');
			}

			return result;
		});
	}

	// Device detection
	function detectDevice() {
		var ua = navigator.userAgent;
		var manufacturer = 'Unknown';
		var device = 'Unknown';
		var browser = 'Unknown';

		// Browser detection
		if (ua.indexOf('Firefox') > -1) {
			browser = 'Firefox';
		} else if (ua.indexOf('SamsungBrowser') > -1) {
			browser = 'Samsung Internet';
		} else if (ua.indexOf('Opera') > -1 || ua.indexOf('OPR') > -1) {
			browser = 'Opera';
		} else if (ua.indexOf('Trident') > -1) {
			browser = 'Internet Explorer';
		} else if (ua.indexOf('Edge') > -1) {
			browser = 'Edge';
		} else if (ua.indexOf('Chrome') > -1) {
			browser = 'Chrome';
		} else if (ua.indexOf('Safari') > -1) {
			browser = 'Safari';
		}

		// OS/Device detection
		if (ua.indexOf('Android') > -1) {
			manufacturer = 'Android';
			device = 'Android Device';
			var match = ua.match(/Android[^;]*;\s*([^)]+)/);
			if (match) {
				device = match[1].trim();
			}
		} else if (ua.indexOf('iPhone') > -1) {
			manufacturer = 'Apple';
			device = 'iPhone';
		} else if (ua.indexOf('iPad') > -1) {
			manufacturer = 'Apple';
			device = 'iPad';
		} else if (ua.indexOf('Mac') > -1) {
			manufacturer = 'Apple';
			device = 'Mac';
		} else if (ua.indexOf('Windows') > -1) {
			manufacturer = 'Microsoft';
			device = 'Windows PC';
		} else if (ua.indexOf('Linux') > -1) {
			manufacturer = 'Linux';
			device = 'Linux Device';
		}

		return {
			manufacturer: manufacturer,
			device: device,
			browser: browser
		};
	}

	// Populate device info, including the client MAC address sourced from
	// the FAS query string (previously daemon-substituted via $clientmac).
	function populateDeviceInfo() {
		var info = detectDevice();
		var infoSection = document.getElementById('device-info');

		if (infoSection) {
			document.getElementById('manufacturer').textContent = info.manufacturer;
			document.getElementById('device').textContent = info.device;
			document.getElementById('browser').textContent = info.browser;
			var macDisplay = document.getElementById('mac-display');
			if (macDisplay) macDisplay.textContent = fasParams.clientmac || 'Unknown';
			infoSection.style.display = 'block';
		}
	}

	// Populate the gateway name (previously daemon-substituted via
	// $gatewayname) from the FAS query string.
	function populateGatewayInfo() {
		var name = fasParams.gatewayname || 'Captive Portal';
		document.title = 'Welcome to ' + name;
		var heading = document.getElementById('gateway-name');
		if (heading) heading.textContent = name;
	}

	// Terms modal
	function setupTermsModal() {
		var modal = document.getElementById('terms-modal');
		var showTermsLinks = [
			document.getElementById('show-terms'),
			document.getElementById('view-terms-btn')
		];
		var closeBtn = document.getElementById('close-terms');
		var acceptBtn = document.getElementById('accept-terms');

		function openModal() {
			if (modal) modal.style.display = 'flex';
		}

		function closeModal() {
			if (modal) modal.style.display = 'none';
		}

		showTermsLinks.forEach(function(link) {
			if (link) {
				link.addEventListener('click', function(e) {
					e.preventDefault();
					openModal();
				});
			}
		});

		if (closeBtn) closeBtn.addEventListener('click', closeModal);
		if (acceptBtn) acceptBtn.addEventListener('click', closeModal);

		// Close on overlay click
		if (modal) {
			modal.addEventListener('click', function(e) {
				if (e.target === modal) closeModal();
			});
		}

		// Close on Escape
		document.addEventListener('keydown', function(e) {
			if (e.key === 'Escape') closeModal();
		});
	}

	function showLoginError(message) {
		var errorEl = document.getElementById('login-error');
		if (errorEl) {
			errorEl.textContent = message;
			errorEl.style.display = 'block';
		}
	}

	function clearLoginError() {
		var errorEl = document.getElementById('login-error');
		if (errorEl) {
			errorEl.textContent = '';
			errorEl.style.display = 'none';
		}
	}

	// Form submission: POST credentials to fas_auth via /ubus instead of a
	// plain HTML form action="$authaction" submission, then navigate to the
	// redir target on success.
	function setupForm() {
		var form = document.getElementById('login-form');
		var loadingModal = document.getElementById('loading-modal');
		var loginBtn = document.getElementById('login-btn');

		if (!form) return;

		form.addEventListener('submit', function(e) {
			e.preventDefault();
			clearLoginError();

			var username = document.getElementById('username').value;
			var password = document.getElementById('password').value;

			if (loadingModal) loadingModal.style.display = 'flex';
			if (loginBtn) loginBtn.disabled = true;

			callFasAuth({ username: username, password: password })
				.then(function(result) {
					if (result && result.success) {
						window.location.href = sanitizeRedirect(result.redir || fasParams.redir || '/');
						return;
					}

					if (loadingModal) loadingModal.style.display = 'none';
					if (loginBtn) loginBtn.disabled = false;
					showLoginError((result && result.error) || 'Authentication failed');
				})
				.catch(function() {
					if (loadingModal) loadingModal.style.display = 'none';
					if (loginBtn) loginBtn.disabled = false;
					showLoginError('Unable to reach the authentication service. Please try again.');
				});
		});
	}

	// Show blocked message for blacklisted devices, otherwise reveal the login form
	function checkBlocked() {
		var mac = fasParams.clientmac;
		var blockedMessage = document.getElementById('blocked-message');
		var loginContent = document.getElementById('login-content');
		var loginFooter = document.getElementById('login-footer');

		function showLogin() {
			if (blockedMessage) blockedMessage.style.display = 'none';
			if (loginContent) loginContent.style.display = 'block';
			if (loginFooter) loginFooter.style.display = 'block';
		}

		function showBlocked() {
			if (blockedMessage) blockedMessage.style.display = 'block';
			if (loginContent) loginContent.style.display = 'none';
			if (loginFooter) loginFooter.style.display = 'none';
		}

		if (!mac) {
			showLogin();
			return;
		}

		fetch('blocked.json?_=' + Date.now())
			.then(function(response) { return response.json(); })
			.then(function(data) {
				var list = data.blocked || [];
				var upperMac = mac.toUpperCase();
				for (var i = 0; i < list.length; i++) {
					if (list[i].toUpperCase() === upperMac) {
						showBlocked();
						return;
					}
				}
				showLogin();
			})
			.catch(function() {
				showLogin();
			});
	}

	// Initialize
	document.addEventListener('DOMContentLoaded', function() {
		populateGatewayInfo();
		checkBlocked();
		populateDeviceInfo();
		setupTermsModal();
		setupForm();
	});
})();
