sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel",
	"sap/base/strings/formatMessage",
	"sap/m/Dialog",
	"sap/m/Button",
	"sap/ui/core/HTML",
	"../model/formatter"
], function (BaseController, JSONModel, formatMessage, Dialog, Button, HTML, formatter) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.ArticleDetail", {
		formatMessage: formatMessage,

		onInit: function () {
			this.getView().setModel(new JSONModel({}), "article");
			this.getView().setModel(new JSONModel({ items: [] }), "history");
			this.onRoute("article", function (oEvent) {
				this._id = oEvent.getParameter("arguments").id;
				this._load(true);
			});
		},

		_load: function (bCountView) {
			this.setBusy(true);
			this.api.get("articles/" + this._id, bCountView ? { view: "true" } : {}).then(function (o) {
				this.getView().getModel("article").setData(o);
			}.bind(this)).catch(function (e) {
				this.showError(e);
				if (e.status === 404) {
					this.navTo("articles", {}, true);
				}
			}.bind(this)).finally(function () {
				this.setBusy(false);
			}.bind(this));
		},

		_article: function () {
			return this.getView().getModel("article").getData();
		},

		onEdit: function () {
			this.navTo("articleEdit", { id: this._id });
		},

		onAction: function (oEvent) {
			var sAction = oEvent.getSource().data("action");
			this.api.post("articles/" + this._id + "/" + sAction).then(function (o) {
				this.getView().getModel("article").setData(o);
				this.toast("common.saved");
			}.bind(this)).catch(this.showError.bind(this));
		},

		onDelete: function () {
			this.confirmDelete(this._article().title, function () {
				this.api.del("articles/" + this._id).then(function () {
					this.toast("common.deleted");
					this.navTo("articles", {}, true);
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		},

		onSpace: function () {
			this.navTo("space", { id: this._article().spaceId });
		},

		onTag: function (oEvent) {
			this.navTo("search", { query: { tag: oEvent.getSource().getBindingContext("article").getObject() } });
		},

		onAttachment: function (oEvent) {
			var o = oEvent.getSource().getBindingContext("article").getObject();
			this.navTo("documents", { query: { open: o.id } });
		},

		// ---- history
		onHistory: function () {
			this.api.get("articles/" + this._id + "/versions").then(function (o) {
				this.getView().getModel("history").setData(o);
				return this.dialog("HistoryDialog");
			}.bind(this)).then(function (d) { d.open(); }).catch(this.showError.bind(this));
		},

		onPreviewVersion: function (oEvent) {
			var o = oEvent.getSource().getBindingContext("history").getObject();
			var oDialog = new Dialog({
				title: o.title,
				contentWidth: "50rem",
				resizable: true,
				content: [new HTML({ content: formatter.markdown(o.body), sanitizeContent: true })],
				endButton: new Button({ text: this.text("common.close"), press: function () { oDialog.close(); } }),
				afterClose: function () { oDialog.destroy(); }
			}).addStyleClass("sapUiContentPadding");
			this.getView().addDependent(oDialog);
			oDialog.open();
		},

		onRestoreVersion: function (oEvent) {
			var o = oEvent.getSource().getBindingContext("history").getObject();
			this.api.post("articles/" + this._id + "/versions/" + o.id + "/restore").then(function (oArticle) {
				this.getView().getModel("article").setData(oArticle);
				this.byId("historyDialog").close();
				this.toast("article.restored");
			}.bind(this)).catch(this.showError.bind(this));
		},

		onCloseHistory: function () {
			this.byId("historyDialog").close();
		}
	});
});
