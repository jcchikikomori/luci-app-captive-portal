// Shared client-side security helpers for the captive portal splash/status
// pages. Kept in one file so a fix only ever needs to happen once — this
// exact logic used to be duplicated in splash.js and status.html and had
// drifted (one copy only stripped whitespace, not scheme-validated).
(function() {
	'use strict';

	// `redir` is attacker-influenced (FAS query string, or echoed back by
	// fas_auth) and gets assigned to window.location/href after login.
	//
	// Intentionally scheme-only, NOT same-origin-only: in a captive portal,
	// `redir` legitimately points to whatever external site the guest was
	// trying to reach before being captured (that's the entire point of the
	// parameter — log in, then continue on to the internet). Restricting
	// navigation to this page's own origin would break that core flow. What
	// actually needs blocking is a non-http(s) scheme (javascript:, data:,
	// vbscript:, etc.) that would execute script in this page's origin
	// instead of just navigating the browser.
	window.sanitizeRedirect = function sanitizeRedirect(url) {
		try {
			var parsed = new URL(url, window.location.origin);
			if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
				return '/';
			}
			return parsed.href;
		} catch (e) {
			return '/';
		}
	};
})();
