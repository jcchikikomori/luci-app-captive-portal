(function() {
	'use strict';

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

	// Populate device info
	function populateDeviceInfo() {
		var info = detectDevice();
		var infoSection = document.getElementById('device-info');

		if (infoSection) {
			document.getElementById('manufacturer').textContent = info.manufacturer;
			document.getElementById('device').textContent = info.device;
			document.getElementById('browser').textContent = info.browser;
			infoSection.style.display = 'block';
		}
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

	// Form submission
	function setupForm() {
		var form = document.getElementById('login-form');
		var loadingModal = document.getElementById('loading-modal');

		if (form) {
			form.addEventListener('submit', function() {
				if (loadingModal) {
					loadingModal.style.display = 'flex';
				}
			});
		}
	}

	// Show blocked message for blacklisted devices, otherwise reveal the login form
	function checkBlocked() {
		var macInput = document.querySelector('input[name="clientmac"]');
		var mac = macInput ? macInput.value : '';
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
		checkBlocked();
		populateDeviceInfo();
		setupTermsModal();
		setupForm();
	});
})();
