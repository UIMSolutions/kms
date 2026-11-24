sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel"
], function (BaseController, JSONModel) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.Spaces", {
		onInit: function () {
			this.getView().setModel(new JSONModel({}), "space");
			this.onRoute("spaces", function () {
				this.getOwnerComponent().loadSpaces();
			});
		},

		_ctx: function (oEvent) {
			return oEvent.getSource().getBindingContext("spaces").getObject();
		},

		onOpen: function (oEvent) {
			this.navTo("articles", { query: { space: this._ctx(oEvent).id } });
		},

		onOpenDocuments: function (oEvent) {
			this.navTo("documents", { query: { space: this._ctx(oEvent).id } });
		},

		onNew: function () {
			this._edit({ id: "", key: "", name: "", description: "", icon: "sap-icon://course-book" });
		},

		onEdit: function (oEvent) {
			this._edit(Object.assign({}, this._ctx(oEvent)));
		},

		_edit: function (o) {
			this.getView().getModel("space").setData(o);
			this.dialog("SpaceDialog").then(function (d) { d.open(); });
		},

		onSave: function () {
			var o = this.getView().getModel("space").getData();
			var oBody = { key: o.key, name: o.name, description: o.description, icon: o.icon };
			var p = o.id ? this.api.patch("spaces/" + o.id, oBody) : this.api.post("spaces", oBody);
			p.then(function () {
				this.byId("spaceDialog").close();
				this.toast("common.saved");
				this.getOwnerComponent().loadSpaces();
			}.bind(this)).catch(this.showError.bind(this));
		},

		onCancel: function () {
			this.byId("spaceDialog").close();
		},

		onDelete: function (oEvent) {
			var o = this._ctx(oEvent);
			this.confirmDelete(o.name, function () {
				this.api.del("spaces/" + o.id).then(function () {
					this.toast("common.deleted");
					this.getOwnerComponent().loadSpaces();
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		}
	});
});
