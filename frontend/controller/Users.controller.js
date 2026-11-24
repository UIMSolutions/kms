sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/Button",
	"sap/m/VBox"
], function (BaseController, JSONModel, Dialog, Input, Label, Button, VBox) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.Users", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ items: [], total: 0 }), "users");
			this.getView().setModel(new JSONModel({}), "user");
			this.onRoute("users", function () {
				if (this.session("/isAdmin")) {
					this._load();
				}
			});
		},

		_load: function () {
			var oTable = this.byId("userTable");
			oTable.setBusy(true);
			this.api.get("users", { q: this.byId("userFilter").getValue() }).then(function (o) {
				this.getView().getModel("users").setData(o);
			}.bind(this)).catch(this.showError.bind(this)).finally(function () {
				oTable.setBusy(false);
			});
		},

		_ctx: function (oEvent) {
			return oEvent.getSource().getBindingContext("users").getObject();
		},

		onFilter: function () {
			this._load();
		},

		onNew: function () {
			this._edit({ id: "", username: "", displayName: "", email: "", role: "reader", active: true, password: "", mustChangePassword: true });
		},

		onEdit: function (oEvent) {
			this._edit(Object.assign({}, this._ctx(oEvent)));
		},

		_edit: function (o) {
			this.getView().getModel("user").setData(o);
			this.dialog("UserDialog").then(function (d) { d.open(); });
		},

		onSave: function () {
			var o = this.getView().getModel("user").getData();
			var oBody = {
				username: o.username, displayName: o.displayName, email: o.email, role: o.role,
				active: o.active, mustChangePassword: o.mustChangePassword
			};
			var p;
			if (o.id) {
				p = this.api.patch("users/" + o.id, oBody);
			} else {
				oBody.password = o.password;
				p = this.api.post("users", oBody);
			}
			p.then(function () {
				this.byId("userDialog").close();
				this.toast("common.saved");
				this._load();
			}.bind(this)).catch(this.showError.bind(this));
		},

		onCancel: function () {
			this.byId("userDialog").close();
		},

		onUnlock: function (oEvent) {
			this.api.post("users/" + this._ctx(oEvent).id + "/unlock").then(function () {
				this.toast("user.unlocked");
				this._load();
			}.bind(this)).catch(this.showError.bind(this));
		},

		onResetPassword: function (oEvent) {
			var o = this._ctx(oEvent);
			var oInput = new Input({ type: "Password", placeholder: this.text("user.passwordPolicy") });
			var oDialog = new Dialog({
				title: this.text("user.resetPassword") + ": " + o.username,
				contentWidth: "24rem",
				content: [new VBox({ items: [new Label({ text: this.text("user.newPassword"), labelFor: oInput }), oInput] })
					.addStyleClass("sapUiSmallMargin")],
				beginButton: new Button({
					type: "Emphasized",
					text: this.text("common.save"),
					press: function () {
						this.api.post("users/" + o.id + "/password", { password: oInput.getValue() }).then(function () {
							oDialog.close();
							this.toast("user.passwordReset");
							this._load();
						}.bind(this)).catch(this.showError.bind(this));
					}.bind(this)
				}),
				endButton: new Button({ text: this.text("common.cancel"), press: function () { oDialog.close(); } }),
				afterClose: function () { oDialog.destroy(); }
			});
			this.getView().addDependent(oDialog);
			oDialog.open();
		},

		onDelete: function (oEvent) {
			var o = this._ctx(oEvent);
			this.confirmDelete(o.username, function () {
				this.api.del("users/" + o.id).then(function () {
					this.toast("common.deleted");
					this._load();
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		}
	});
});
