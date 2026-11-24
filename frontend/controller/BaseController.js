sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/ui/core/routing/History",
	"sap/ui/core/Fragment",
	"sap/m/MessageBox",
	"sap/m/MessageToast",
	"sap/ui/model/json/JSONModel",
	"../model/formatter",
	"../model/api"
], function (Controller, History, Fragment, MessageBox, MessageToast, JSONModel, formatter, api) {
	"use strict";

	return Controller.extend("uim.myfiori.kms.controller.BaseController", {
		formatter: formatter,
		api: api,

		getRouter: function () {
			return this.getOwnerComponent().getRouter();
		},

		session: function (sPath) {
			return this.getOwnerComponent().getModel("session").getProperty(sPath);
		},

		text: function (sKey, aArgs) {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
		},

		navTo: function (sRoute, oParams, bReplace) {
			this.getRouter().navTo(sRoute, oParams || {}, bReplace);
		},

		onNavBack: function () {
			if (History.getInstance().getPreviousHash() !== undefined) {
				window.history.go(-1);
			} else {
				this.navTo("home", {}, true);
			}
		},

		/** runs fn only when the route matches and the session is established */
		onRoute: function (sRoute, fn) {
			this.getRouter().getRoute(sRoute).attachPatternMatched(function (oEvent) {
				this.getOwnerComponent().sessionReady.then(function () {
					if (this.session("/loggedIn")) {
						fn.call(this, oEvent);
					}
				}.bind(this));
			}, this);
		},

		toast: function (sKey, aArgs) {
			MessageToast.show(this.text(sKey, aArgs));
		},

		showError: function (oError) {
			if (oError && oError.status === 401) {
				return; // the component redirects to the login
			}
			MessageBox.error((oError && oError.message) || String(oError));
		},

		confirmDelete: function (sName, fnDelete) {
			MessageBox.confirm(this.text("common.confirmDelete", [sName]), {
				actions: [MessageBox.Action.DELETE, MessageBox.Action.CANCEL],
				emphasizedAction: MessageBox.Action.DELETE,
				onClose: function (sAction) {
					if (sAction === MessageBox.Action.DELETE) {
						fnDelete();
					}
				}
			});
		},

		/** lazily loads a fragment as dependent of the view (cached per name) */
		dialog: function (sName) {
			this._dialogs = this._dialogs || {};
			if (!this._dialogs[sName]) {
				this._dialogs[sName] = Fragment.load({
					id: this.getView().getId(),
					name: "uim.myfiori.kms.view." + sName,
					controller: this
				}).then(function (oDialog) {
					this.getView().addDependent(oDialog);
					return oDialog;
				}.bind(this));
			}
			return this._dialogs[sName];
		},

		/** "a, b" -> ["a","b"] */
		splitTags: function (s) {
			return (s || "").split(",").map(function (t) { return t.trim(); }).filter(Boolean);
		},

		setBusy: function (b) {
			this.getView().setBusy(!!b);
		},

		_viewModel: function (sName, oInitial) {
			var oModel = this.getView().getModel(sName);
			if (!oModel) {
				oModel = new JSONModel(oInitial || {});
				this.getView().setModel(oModel, sName);
			}
			return oModel;
		},

		// ------------------------------------------------------------------ user picker (directory)

		/** opens the user directory; resolves with the selected users (empty array on cancel) */
		pickUsers: function (sTitle, bMulti) {
			var oModel = this._viewModel("picker");
			oModel.setData({ title: sTitle, multi: !!bMulti, items: [] });
			return this.dialog("UserPicker").then(function (oDialog) {
				this._loadDirectory("");
				return new Promise(function (resolve) {
					this._pickerResolve = resolve;
					oDialog.attachEventOnce("cancel", function () { resolve([]); });
					oDialog.open();
				}.bind(this));
			}.bind(this));
		},

		_loadDirectory: function (sQuery) {
			this.api.get("users/directory", { q: sQuery }).then(function (o) {
				this.getView().getModel("picker").setProperty("/items", o.items);
			}.bind(this)).catch(this.showError.bind(this));
		},

		onUserPickerSearch: function (oEvent) {
			this._loadDirectory(oEvent.getParameter("value") || "");
		},

		onUserPickerConfirm: function (oEvent) {
			var aItems = oEvent.getParameter("selectedItems") || [];
			if (!aItems.length && oEvent.getParameter("selectedItem")) {
				aItems = [oEvent.getParameter("selectedItem")];
			}
			if (this._pickerResolve) {
				this._pickerResolve(aItems.map(function (i) { return i.getBindingContext("picker").getObject(); }));
				this._pickerResolve = null;
			}
		},

		// ------------------------------------------------------------------ area create / edit dialog

		/**
		 * Opens the area dialog. oArea: existing area DTO, or { parentId } for a new (sub-)area.
		 * Resolves with the saved area.
		 */
		editSpace: function (oArea) {
			var bNew = !oArea.id;
			var bAdmin = this.session("/isAdmin");
			var aAll = this.getOwnerComponent().getModel("spaces").getProperty("/items") || [];
			var sOwnPath = oArea.path ? oArea.path + " / " : null;
			var aParents;
			if ((bNew && !oArea.parentId) || (!bNew && bAdmin)) {
				aParents = [{ id: "", path: this.text("area.topLevel") }].concat(aAll.filter(function (s) {
					return s.id !== oArea.id && !(sOwnPath && s.path.indexOf(sOwnPath) === 0);
				}));
			} else {
				aParents = oArea.parentId
					? [{ id: oArea.parentId, path: oArea.parentPath || (aAll.filter(function (s) { return s.id === oArea.parentId; })[0] || {}).path || "…" }]
					: [{ id: "", path: this.text("area.topLevel") }];
			}
			this._viewModel("space").setData({
				id: oArea.id || "",
				version: oArea.version,
				parentId: oArea.parentId || "",
				originalParentId: oArea.parentId || "",
				parentPath: oArea.parentPath || "",
				parents: aParents,
				canMove: bAdmin && !(bNew && oArea.parentId),
				key: oArea.key || "",
				name: oArea.name || "",
				description: oArea.description || "",
				icon: oArea.icon || "sap-icon://course-book",
				managerId: oArea.managerId || this.session("/user/id"),
				originalManagerId: oArea.managerId || "",
				managerName: oArea.managerName || this.session("/user/displayName") || this.session("/user/username"),
				canAssignManager: bNew || !!oArea.canGovern
			});
			return this.dialog("SpaceDialog").then(function (oDialog) {
				return new Promise(function (resolve) {
					this._spaceResolve = resolve;
					oDialog.open();
				}.bind(this));
			}.bind(this));
		},

		onPickManager: function () {
			this.pickUsers(this.text("area.manager"), false).then(function (aUsers) {
				if (aUsers.length) {
					var oModel = this.getView().getModel("space");
					oModel.setProperty("/managerId", aUsers[0].id);
					oModel.setProperty("/managerName", aUsers[0].displayName);
				}
			}.bind(this));
		},

		onSaveSpace: function () {
			var o = this.getView().getModel("space").getData();
			var oBody = { key: o.key, name: o.name, description: o.description, icon: o.icon };
			var p;
			if (o.id) {
				if (o.canMove && o.parentId !== o.originalParentId) {
					oBody.parentId = o.parentId;
				}
				if (o.canAssignManager && o.managerId !== o.originalManagerId) {
					oBody.managerId = o.managerId;
				}
				p = this.api.patch("spaces/" + o.id, oBody);
			} else {
				oBody.parentId = o.parentId;
				oBody.managerId = o.managerId;
				p = this.api.post("spaces", oBody);
			}
			p.then(function (oSaved) {
				this.byId("spaceDialog").close();
				this.toast("common.saved");
				return this.getOwnerComponent().refreshSession().then(function () {
					if (this._spaceResolve) {
						this._spaceResolve(oSaved);
						this._spaceResolve = null;
					}
				}.bind(this));
			}.bind(this)).catch(this.showError.bind(this));
		},

		onCancelSpace: function () {
			this.byId("spaceDialog").close();
		}
	});
});
