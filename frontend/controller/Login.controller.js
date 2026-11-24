sap.ui.define([
	"./BaseController"
], function (BaseController) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.Login", {
		onInit: function () {
			this.getRouter().getRoute("login").attachPatternMatched(function () {
				this.byId("loginError").setVisible(false);
				this.byId("loginPassword").setValue("");
				setTimeout(function () { this.byId("loginUser").focus(); }.bind(this), 300);
			}, this);
		},

		onLogin: function () {
			var sUser = this.byId("loginUser").getValue().trim();
			var sPassword = this.byId("loginPassword").getValue();
			if (!sUser || !sPassword) {
				return;
			}
			this.setBusy(true);
			this.api.login(sUser, sPassword).then(function (oUser) {
				this.getOwnerComponent().applySession(oUser);
				this.navTo("home", {}, true);
			}.bind(this)).catch(function (e) {
				var oStrip = this.byId("loginError");
				oStrip.setText(e.message || this.text("login.failed"));
				oStrip.setVisible(true);
			}.bind(this)).finally(function () {
				this.setBusy(false);
			}.bind(this));
		},

		/** XSUAA: the approuter performs the login when a protected route is opened */
		onSso: function () {
			window.location.assign("/app/index.html");
		}
	});
});
