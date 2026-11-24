sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel"
], function (BaseController, JSONModel) {
	"use strict";

	var PAGE = 50;

	return BaseController.extend("uim.myfiori.kms.controller.Articles", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ items: [], total: 0 }), "list");
			this.onRoute("articles", function (oEvent) {
				var q = oEvent.getParameter("arguments")["?query"] || {};
				if (q.space !== undefined) {
					this.byId("articleSpace").setSelectedKey(q.space);
				}
				if (q.tag !== undefined) {
					this.byId("articleFilter").setValue("");
				}
				this._tag = q.tag || "";
				this._load(false);
			});
		},

		_load: function (bAppend) {
			var oModel = this.getView().getModel("list");
			var aItems = bAppend ? oModel.getProperty("/items") : [];
			var oTable = this.byId("articleTable");
			oTable.setBusy(true);
			this.api.get("articles", {
				q: this.byId("articleFilter").getValue(),
				space: this.byId("articleSpace").getSelectedKey(),
				deep: "true",
				status: this.byId("articleStatus").getSelectedKey(),
				orderBy: this.byId("articleOrder").getSelectedKey(),
				tag: this._tag,
				skip: aItems.length,
				top: PAGE
			}).then(function (o) {
				oModel.setData({ items: aItems.concat(o.items), total: o.total });
			}).catch(this.showError.bind(this)).finally(function () {
				oTable.setBusy(false);
			});
		},

		onFilter: function () {
			this._load(false);
		},

		onMore: function () {
			this._load(true);
		},

		onNew: function () {
			var sSpace = this.byId("articleSpace").getSelectedKey();
			var bWritable = (this.getOwnerComponent().getModel("session").getProperty("/roles") || {})[sSpace];
			this.navTo("articleNew", { query: sSpace && bWritable && bWritable !== "reader" ? { space: sSpace } : {} });
		},

		onOpen: function (oEvent) {
			this.navTo("article", { id: oEvent.getSource().getBindingContext("list").getProperty("id") });
		}
	});
});
