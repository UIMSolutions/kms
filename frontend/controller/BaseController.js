sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/ui/core/routing/History",
	"sap/ui/core/Fragment",
	"sap/m/MessageBox",
	"sap/m/MessageToast",
	"../model/formatter",
	"../model/api"
], function (Controller, History, Fragment, MessageBox, MessageToast, formatter, api) {
	"use strict";

	return Controller.extend("uim.myfiori.kms.controller.BaseController", {
		formatter: formatter,
		api: api,

		getRouter: function () {
			return this.getOwnerComponent().getRouter();
		},

		session: function (sPath) {
			return this.getOwnerComponent().getModel("session").getProperty(sPath);
		},

		text: function (sKey, aArgs) {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
		},

		navTo: function (sRoute, oParams, bReplace) {
			this.getRouter().navTo(sRoute, oParams || {}, bReplace);
		},

		onNavBack: function () {
			if (History.getInstance().getPreviousHash() !== undefined) {
				window.history.go(-1);
			} else {
				this.navTo("home", {}, true);
			}
		},

		/** runs fn only when the route matches and the session is established */
		onRoute: function (sRoute, fn) {
			this.getRouter().getRoute(sRoute).attachPatternMatched(function (oEvent) {
				this.getOwnerComponent().sessionReady.then(function () {
					if (this.session("/loggedIn")) {
						fn.call(this, oEvent);
					}
				}.bind(this));
			}, this);
		},

		toast: function (sKey, aArgs) {
			MessageToast.show(this.text(sKey, aArgs));
		},

		showError: function (oError) {
			if (oError && oError.status === 401) {
				return; // the component redirects to the login
			}
			MessageBox.error((oError && oError.message) || String(oError));
		},

		confirmDelete: function (sName, fnDelete) {
			MessageBox.confirm(this.text("common.confirmDelete", [sName]), {
				actions: [MessageBox.Action.DELETE, MessageBox.Action.CANCEL],
				emphasizedAction: MessageBox.Action.DELETE,
				onClose: function (sAction) {
					if (sAction === MessageBox.Action.DELETE) {
						fnDelete();
					}
				}
			});
		},

		/** lazily loads a fragment as dependent of the view (cached per name) */
		dialog: function (sName) {
			this._dialogs = this._dialogs || {};
			if (!this._dialogs[sName]) {
				this._dialogs[sName] = Fragment.load({
					id: this.getView().getId(),
					name: "uim.myfiori.kms.view." + sName,
					controller: this
				}).then(function (oDialog) {
					this.getView().addDependent(oDialog);
					return oDialog;
				}.bind(this));
			}
			return this._dialogs[sName];
		},

		/** "a, b" -> ["a","b"] */
		splitTags: function (s) {
			return (s || "").split(",").map(function (t) { return t.trim(); }).filter(Boolean);
		},

		setBusy: function (b) {
			this.getView().setBusy(!!b);
		}
	});
});
