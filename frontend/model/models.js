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
			return new JSONModel({ loggedIn: false, mode: "local", user: {}, isAdmin: false, canCreate: false, managesAreas: false, roles: {} });
		},

		createSpacesModel: function () {
			return new JSONModel({ items: [], withAll: [], writable: [] });
		},

		fillSession: function (oSession, oUser) {
			oSession.setProperty("/loggedIn", true);
			oSession.setProperty("/user", oUser);
			oSession.setProperty("/isAdmin", oUser.role === "admin");
			// content rights come from area roles: spaceId -> reader | editor | manager
			var mRoles = {};
			(oUser.spaceRoles || []).forEach(function (r) { mRoles[r.spaceId] = r.role; });
			oSession.setProperty("/roles", mRoles);
			oSession.setProperty("/canCreate", !!oUser.canCreateContent);
			oSession.setProperty("/managesAreas", !!oUser.managesAreas || oUser.role === "admin");
		},

		clearSession: function (oSession) {
			oSession.setProperty("/loggedIn", false);
			oSession.setProperty("/user", {});
			oSession.setProperty("/isAdmin", false);
			oSession.setProperty("/canCreate", false);
			oSession.setProperty("/managesAreas", false);
			oSession.setProperty("/roles", {});
		}
	};
});
