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

	// Initialize
	document.addEventListener('DOMContentLoaded', function() {
		populateDeviceInfo();
		setupTermsModal();
		setupForm();
	});
})();
