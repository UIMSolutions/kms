sap.ui.define([
	"sap/ui/core/UIComponent",
	"./model/models",
	"./model/api"
], function (UIComponent, models, api) {
	"use strict";

	/** routes only administrators may open */
	var ADMIN_ROUTES = ["users", "admin"];
	/** routes that need the editor role */
	var EDITOR_ROUTES = ["articleNew", "articleEdit"];

	return UIComponent.extend("uim.myfiori.kms.Component", {
		metadata: {
			manifest: "json",
			interfaces: ["sap.ui.core.IAsyncContentCreation"]
		},

		init: function () {
			UIComponent.prototype.init.apply(this, arguments);
			this.setModel(models.createDeviceModel(), "device");
			this.setModel(models.createSessionModel(), "session");
			this.setModel(models.createSpacesModel(), "spaces");

			api.onUnauthorized(this.logout.bind(this));
			this.sessionReady = this.restoreSession().finally(function () {
				this.getRouter().attachBeforeRouteMatched(this._guard, this);
				this.getRouter().initialize();
			}.bind(this));
		},

		/** Restores a stored token (local login) or the approuter session (XSUAA). */
		restoreSession: function () {
			var oSession = this.getModel("session");
			return api.config().then(function (oCfg) {
				oSession.setProperty("/mode", oCfg.mode);
				return api.me();
			}).then(function (oUser) {
				this.applySession(oUser);
			}.bind(this)).catch(function () {
				api.setToken(null);
			});
		},

		applySession: function (oUser) {
			models.fillSession(this.getModel("session"), oUser);
			this.loadSpaces();
			this.getEventBus().publish("kms", "session", oUser);
		},

		/** spaces are needed by many views (filters, selects) - kept in a shared model */
		loadSpaces: function () {
			var oSpaces = this.getModel("spaces");
			return api.get("spaces").then(function (o) {
				oSpaces.setProperty("/items", o.items);
				oSpaces.setProperty("/withAll", [{ id: "", name: "" }].concat(o.items));
			}).catch(function () { /* handled by api */ });
		},

		logout: function () {
			var bWasLoggedIn = this.getModel("session").getProperty("/loggedIn");
			api.logout();
			models.clearSession(this.getModel("session"));
			if (this.getModel("session").getProperty("/mode") === "xsuaa" && bWasLoggedIn) {
				window.location.assign("/do/logout");
				return;
			}
			this.getRouter().navTo("login", {}, true);
		},

		/** Route guard: login required, role checks for admin / editor pages. */
		_guard: function (oEvent) {
			var sRoute = oEvent.getParameter("name");
			var oSession = this.getModel("session");
			var oRouter = this.getRouter();
			if (!oSession.getProperty("/loggedIn")) {
				if (sRoute !== "login") {
					setTimeout(function () { oRouter.navTo("login", {}, true); }, 0);
				}
				return;
			}
			var bDenied = sRoute === "login"
				|| (ADMIN_ROUTES.indexOf(sRoute) >= 0 && !oSession.getProperty("/isAdmin"))
				|| (EDITOR_ROUTES.indexOf(sRoute) >= 0 && !oSession.getProperty("/isEditor"));
			if (bDenied) {
				setTimeout(function () { oRouter.navTo("home", {}, true); }, 0);
			}
		}
	});
});
