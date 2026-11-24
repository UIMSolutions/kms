sap.ui.define([], function () {
	"use strict";

	/**
	 * Thin client for the KMS REST API (/api/v1).
	 *  - local login: bearer token from /api/v1/auth/login, kept in sessionStorage
	 *  - approuter (XSUAA): session cookie, CSRF token fetched on demand
	 */
	var TOKEN_KEY = "uim.kms.token";
	var BASE = "/api/v1/";
	var sCsrf = null;
	var fnUnauthorized = function () {};

	function url(sPath) {
		return new URL(sPath.charAt(0) === "/" ? sPath : BASE + sPath, window.location.origin).toString();
	}

	function getToken() {
		try {
			return window.sessionStorage.getItem(TOKEN_KEY);
		} catch (e) {
			return null;
		}
	}

	function setToken(sToken) {
		try {
			if (sToken) {
				window.sessionStorage.setItem(TOKEN_KEY, sToken);
			} else {
				window.sessionStorage.removeItem(TOKEN_KEY);
			}
		} catch (e) { /* storage blocked */ }
	}

	function headers(oExtra) {
		var h = Object.assign({ "Accept": "application/json" }, oExtra || {});
		var t = getToken();
		if (t) {
			h.Authorization = "Bearer " + t;
		}
		return h;
	}

	function fetchCsrf() {
		return fetch(url("auth/config"), {
			method: "GET",
			credentials: "same-origin",
			headers: headers({ "X-CSRF-Token": "Fetch" })
		}).then(function (r) {
			sCsrf = r.headers.get("X-CSRF-Token") || "";
			return sCsrf;
		});
	}

	function parse(r) {
		if (r.status === 204) {
			return null;
		}
		var sType = r.headers.get("Content-Type") || "";
		return sType.indexOf("json") >= 0 ? r.json() : r.text();
	}

	function toError(r, sPath) {
		return parse(r).catch(function () { return null; }).then(function (oErr) {
			var e = new Error((oErr && oErr.error && oErr.error.message) || r.statusText || ("HTTP " + r.status));
			e.status = r.status;
			if (r.status === 401 && sPath.indexOf("auth/login") < 0) {
				fnUnauthorized();
			}
			throw e;
		});
	}

	/** core request; oBody is JSON-encoded unless it is a Blob/File/FormData */
	function request(sMethod, sPath, oBody, oExtraHeaders, bRetried) {
		var bModifying = sMethod !== "GET";
		var bRaw = oBody instanceof Blob || oBody instanceof FormData;
		var p = (bModifying && sCsrf === null) ? fetchCsrf().catch(function () { return ""; }) : Promise.resolve();
		return p.then(function () {
			var h = headers(oExtraHeaders);
			if (oBody !== undefined && !bRaw) {
				h["Content-Type"] = "application/json";
			}
			if (bModifying && sCsrf) {
				h["X-CSRF-Token"] = sCsrf;
			}
			return fetch(url(sPath), {
				method: sMethod,
				credentials: "same-origin",
				headers: h,
				body: oBody === undefined ? undefined : (bRaw ? oBody : JSON.stringify(oBody))
			});
		}).then(function (r) {
			if (r.status === 403 && (r.headers.get("X-CSRF-Token") || "").toLowerCase() === "required" && !bRetried) {
				sCsrf = null;
				return request(sMethod, sPath, oBody, oExtraHeaders, true);
			}
			return r.ok ? parse(r) : toError(r, sPath);
		});
	}

	function query(oParams) {
		var a = [];
		Object.keys(oParams || {}).forEach(function (k) {
			var v = oParams[k];
			if (v !== undefined && v !== null && v !== "") {
				a.push(encodeURIComponent(k) + "=" + encodeURIComponent(v));
			}
		});
		return a.length ? "?" + a.join("&") : "";
	}

	function enc(s) {
		return encodeURIComponent(s || "");
	}

	return {
		getToken: getToken,
		setToken: setToken,
		onUnauthorized: function (fn) { fnUnauthorized = fn; },
		query: query,

		get: function (sPath, oParams) { return request("GET", sPath + query(oParams)); },
		post: function (sPath, oBody) { return request("POST", sPath, oBody === undefined ? {} : oBody); },
		patch: function (sPath, oBody, sVersion) {
			return request("PATCH", sPath, oBody, sVersion ? { "If-Match": "W/\"" + sVersion + "\"" } : undefined);
		},
		del: function (sPath) { return request("DELETE", sPath); },

		// ---- auth
		config: function () { return request("GET", "auth/config"); },
		me: function () { return request("GET", "auth/me"); },
		login: function (sUser, sPassword) {
			return request("POST", "auth/login", { username: sUser, password: sPassword }).then(function (o) {
				setToken(o.token);
				return o.user;
			});
		},
		logout: function () {
			var t = getToken();
			setToken(null);
			sCsrf = null;
			if (t) {
				fetch(url("auth/logout"), { method: "POST", headers: { Authorization: "Bearer " + t } }).catch(function () {});
			}
		},
		changePassword: function (sOld, sNew) {
			return request("POST", "auth/password", { oldPassword: sOld, newPassword: sNew });
		},

		// ---- documents & media
		/** oOptions: { title, spaceId, tags (comma separated), description } */
		upload: function (oFile, oOptions) {
			var o = oOptions || {};
			var h = {
				"Content-Type": oFile.type || "application/octet-stream",
				"X-File-Name": enc(oFile.name)
			};
			if (o.title) { h["X-Title"] = enc(o.title); }
			if (o.spaceId) { h["X-Space"] = enc(o.spaceId); }
			if (o.tags) { h["X-Tags"] = enc(o.tags); }
			if (o.description) { h["X-Description"] = enc(o.description); }
			return request("POST", "documents", oFile, h);
		},
		replaceFile: function (sId, oFile) {
			return request("PUT", "documents/" + sId + "/content", oFile, {
				"Content-Type": oFile.type || "application/octet-stream",
				"X-File-Name": enc(oFile.name)
			});
		},
		/** authenticated download as Blob (for previews and "save as") */
		blob: function (sId) {
			return fetch(url("documents/" + sId + "/content"), {
				credentials: "same-origin", headers: headers()
			}).then(function (r) {
				return r.ok ? r.blob() : toError(r, "documents");
			});
		},
		download: function (sId, sFileName) {
			return this.blob(sId).then(function (oBlob) {
				var sUrl = URL.createObjectURL(oBlob);
				var a = document.createElement("a");
				a.href = sUrl;
				a.download = sFileName || "download";
				document.body.appendChild(a);
				a.click();
				a.remove();
				setTimeout(function () { URL.revokeObjectURL(sUrl); }, 10000);
			});
		}
	};
});
