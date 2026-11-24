sap.ui.define([
	"./BaseController"
], function (BaseController) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.Spaces", {
		onInit: function () {
			this.onRoute("spaces", function () {
				this.getOwnerComponent().loadSpaces();
			});
		},

		_ctx: function (oEvent) {
			return oEvent.getSource().getBindingContext("spaces").getObject();
		},

		onOpen: function (oEvent) {
			this.navTo("space", { id: this._ctx(oEvent).id });
		},

		onOpenArticles: function (oEvent) {
			this.navTo("articles", { query: { space: this._ctx(oEvent).id } });
		},

		onOpenDocuments: function (oEvent) {
			this.navTo("documents", { query: { space: this._ctx(oEvent).id } });
		},

		onNew: function () {
			this.editSpace({});
		},

		onNewSub: function (oEvent) {
			var o = this._ctx(oEvent);
			this.editSpace({ parentId: o.id, parentPath: o.path });
		},

		onEdit: function (oEvent) {
			this.editSpace(Object.assign({}, this._ctx(oEvent)));
		},

		onDelete: function (oEvent) {
			var o = this._ctx(oEvent);
			this.confirmDelete(o.path, function () {
				this.api.del("spaces/" + o.id).then(function () {
					this.toast("common.deleted");
					this.getOwnerComponent().refreshSession();
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		}
	});
});
