sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel"
], function (BaseController, JSONModel) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.Admin", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ metrics: {}, stats: {}, audit: [] }), "admin");
			this.onRoute("admin", function () {
				if (this.session("/isAdmin")) {
					this.onRefresh();
				}
			});
		},

		onRefresh: function () {
			var oModel = this.getView().getModel("admin");
			this.setBusy(true);
			Promise.all([
				this.api.get("admin/metrics"),
				this.api.get("stats"),
				this.api.get("admin/audit", { top: 300 }),
				this.api.get("users", { top: 1000 })
			]).then(function (a) {
				var mNames = {};
				(a[3].items || []).forEach(function (u) { mNames[u.id] = u.displayName || u.username; });
				var aAudit = (a[2].items || []).map(function (e) {
					e.actorName = mNames[e.actor] || e.actor || "";
					return e;
				});
				oModel.setData({ metrics: a[0], stats: a[1], audit: aAudit });
			}).catch(this.showError.bind(this)).finally(function () {
				this.setBusy(false);
			}.bind(this));
		},

		onReindex: function () {
			this.setBusy(true);
			this.api.post("admin/reindex").then(function (o) {
				this.toast("admin.reindexed", [o.indexed]);
				this.onRefresh();
			}.bind(this)).catch(this.showError.bind(this)).finally(function () {
				this.setBusy(false);
			}.bind(this));
		}
	});
});
