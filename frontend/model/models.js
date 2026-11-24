sap.ui.define([
	"sap/ui/model/json/JSONModel",
	"sap/ui/Device"
], function (JSONModel, Device) {
	"use strict";

	return {
		createDeviceModel: function () {
			var oModel = new JSONModel(Device);
			oModel.setDefaultBindingMode("OneWay");
			return oModel;
		},

		createSessionModel: function () {
			return new JSONModel({ loggedIn: false, mode: "local", user: {}, isAdmin: false, isEditor: false });
		},

		createSpacesModel: function () {
			return new JSONModel({ items: [], withAll: [] });
		},

		fillSession: function (oSession, oUser) {
			oSession.setProperty("/loggedIn", true);
			oSession.setProperty("/user", oUser);
			oSession.setProperty("/isAdmin", oUser.role === "admin");
			oSession.setProperty("/isEditor", oUser.role === "admin" || oUser.role === "editor");
		},

		clearSession: function (oSession) {
			oSession.setProperty("/loggedIn", false);
			oSession.setProperty("/user", {});
			oSession.setProperty("/isAdmin", false);
			oSession.setProperty("/isEditor", false);
		}
	};
});
