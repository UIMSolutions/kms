sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel",
	"sap/base/strings/formatMessage"
], function (BaseController, JSONModel, formatMessage) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.Home", {
		formatMessage: formatMessage,

		onInit: function () {
			this.getView().setModel(new JSONModel({}), "stats");
			this.onRoute("home", this._load);
		},

		_load: function () {
			this.getOwnerComponent().loadSpaces();
			this.api.get("stats").then(function (o) {
				this.getView().getModel("stats").setData(o);
			}.bind(this)).catch(this.showError.bind(this));
		},

		onSearch: function (oEvent) {
			var sQuery = oEvent.getParameter("query");
			if (sQuery) {
				this.navTo("search", { query: { q: sQuery } });
			}
		},

		onNewArticle: function () {
			this.navTo("articleNew");
		},

		onUpload: function () {
			this.navTo("documents", { query: { upload: "true" } });
		},

		onTile: function (oEvent) {
			this.navTo(oEvent.getSource().data("route"));
		},

		onRecent: function (oEvent) {
			var o = oEvent.getSource().getBindingContext("stats").getObject();
			if (o.kind === "article") {
				this.navTo("article", { id: o.id });
			} else {
				this.navTo("documents", { query: { open: o.id } });
			}
		},

		onTag: function (oEvent) {
			var sTag = oEvent.getSource().getBindingContext("stats").getProperty("key");
			this.navTo("search", { query: { tag: sTag } });
		},

		onSpace: function (oEvent) {
			var sId = oEvent.getSource().getBindingContext("spaces").getProperty("id");
			this.navTo("articles", { query: { space: sId } });
		}
	});
});
