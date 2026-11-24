sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel"
], function (BaseController, JSONModel) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.AreaDetail", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ members: [], children: [] }), "area");
			this.getView().setModel(new JSONModel({ role: "reader", users: [] }), "add");
			this.onRoute("space", function (oEvent) {
				this._id = oEvent.getParameter("arguments").id;
				this._load();
			});
		},

		_load: function () {
			var oModel = this.getView().getModel("area");
			this.setBusy(true);
			Promise.all([
				this.api.get("spaces/" + this._id),
				this.api.get("spaces/" + this._id + "/members"),
				this.getOwnerComponent().loadSpaces()
			]).then(function (a) {
				var oArea = a[0];
				oArea.members = a[1].items;
				oArea.children = (this.getOwnerComponent().getModel("spaces").getProperty("/items") || [])
					.filter(function (s) { return s.parentId === oArea.id; });
				oModel.setData(oArea);
			}.bind(this)).catch(function (e) {
				this.showError(e);
				if (e.status === 404) {
					this.navTo("spaces", {}, true);
				}
			}.bind(this)).finally(function () {
				this.setBusy(false);
			}.bind(this));
		},

		_area: function () {
			return this.getView().getModel("area").getData();
		},

		onArticles: function () {
			this.navTo("articles", { query: { space: this._id } });
		},

		onDocuments: function () {
			this.navTo("documents", { query: { space: this._id } });
		},

		onOpenChild: function (oEvent) {
			this.navTo("space", { id: oEvent.getSource().getBindingContext("area").getProperty("id") });
		},

		onNewSub: function () {
			var o = this._area();
			this.editSpace({ parentId: o.id, parentPath: o.path }).then(function (oNew) {
				this.navTo("space", { id: oNew.id });
			}.bind(this));
		},

		onEdit: function () {
			this.editSpace(Object.assign({}, this._area())).then(this._load.bind(this));
		},

		onDelete: function () {
			var o = this._area();
			this.confirmDelete(o.path, function () {
				this.api.del("spaces/" + o.id).then(function () {
					this.toast("common.deleted");
					this.getOwnerComponent().refreshSession();
					this.navTo("spaces", {}, true);
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		},

		onChangeManager: function () {
			if (!this._area().canGovern) {
				return;
			}
			this.pickUsers(this.text("area.changeManager"), false).then(function (aUsers) {
				if (!aUsers.length) {
					return null;
				}
				return this.api.put("spaces/" + this._id + "/manager", { userId: aUsers[0].id }).then(function () {
					this.toast("area.managerChanged");
					return this.getOwnerComponent().refreshSession();
				}.bind(this)).then(this._load.bind(this));
			}.bind(this)).catch(this.showError.bind(this));
		},

		// ---- members
		onAddMembers: function () {
			this.getView().getModel("add").setData({ role: "reader", users: [] });
			this.dialog("AddMemberDialog").then(function (d) { d.open(); });
		},

		onPickMembers: function () {
			var oAdd = this.getView().getModel("add");
			this.pickUsers(this.text("area.selectUser"), true).then(function (aUsers) {
				var aCurrent = oAdd.getProperty("/users");
				aUsers.forEach(function (u) {
					if (!aCurrent.some(function (x) { return x.id === u.id; })) {
						aCurrent.push(u);
					}
				});
				oAdd.setProperty("/users", aCurrent.slice());
			});
		},

		onRemovePicked: function (oEvent) {
			var oAdd = this.getView().getModel("add");
			var aKeys = (oEvent.getParameter("tokens") || []).map(function (t) { return t.getKey(); });
			oAdd.setProperty("/users", oAdd.getProperty("/users").filter(function (u) { return aKeys.indexOf(u.id) < 0; }));
		},

		onSaveMembers: function () {
			var o = this.getView().getModel("add").getData();
			Promise.all(o.users.map(function (u) {
				return this.api.put("spaces/" + this._id + "/members/" + u.id, { role: o.role });
			}.bind(this))).then(function () {
				this.byId("addMemberDialog").close();
				this.toast("area.memberAdded", [o.users.length]);
				this._load();
			}.bind(this)).catch(this.showError.bind(this));
		},

		onCancelMembers: function () {
			this.byId("addMemberDialog").close();
		},

		onRoleChange: function (oEvent) {
			var oMember = oEvent.getSource().getBindingContext("area").getObject();
			this.api.put("spaces/" + this._id + "/members/" + oMember.userId, { role: oMember.role }).then(function () {
				this.toast("common.saved");
			}.bind(this)).catch(function (e) {
				this.showError(e);
				this._load();
			}.bind(this));
		},

		onRemoveMember: function (oEvent) {
			var oMember = oEvent.getSource().getBindingContext("area").getObject();
			this.confirmDelete(oMember.displayName, function () {
				this.api.del("spaces/" + this._id + "/members/" + oMember.userId).then(function () {
					this.toast("area.memberRemoved");
					this._load();
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		}
	});
});
