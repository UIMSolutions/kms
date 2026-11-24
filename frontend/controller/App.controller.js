sap.ui.define([
	"./BaseController",
	"sap/m/SuggestionItem"
], function (BaseController, SuggestionItem) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.App", {
		onInit: function () {
			this.getView().addStyleClass(this.getOwnerComponent().getContentDensityClass
				? this.getOwnerComponent().getContentDensityClass() : "sapUiSizeCompact");
			this.getRouter().attachRouteMatched(function (oEvent) {
				var sName = oEvent.getParameter("name");
				var mKeys = { article: "articles", articleEdit: "articles", articleNew: "articles", space: "spaces" };
				this.byId("sideNav").setSelectedKey(mKeys[sName] || sName);
			}, this);
			// after login: force a password change when required
			// sap.m.routing.Router closes dialogs on navigation, so open it after the next route match
			var fnCheck = function () {
				if (!this.session("/loggedIn") || !this.session("/user/mustChangePassword")) {
					return;
				}
				var bOpened = false;
				var fnOpen = function () {
					if (!bOpened && this.session("/user/mustChangePassword")) {
						bOpened = true;
						this.onChangePassword(true);
					}
				}.bind(this);
				this.getRouter().attachEventOnce("routeMatched", function () { setTimeout(fnOpen, 300); });
				setTimeout(fnOpen, 2000);
			}.bind(this);
			this.getOwnerComponent().getEventBus().subscribe("kms", "session", fnCheck);
			this.getOwnerComponent().sessionReady.then(fnCheck);
		},

		onToggleSide: function () {
			var oPage = this.byId("toolPage");
			oPage.setSideExpanded(!oPage.getSideExpanded());
		},

		onNavSelect: function (oEvent) {
			this.navTo(oEvent.getParameter("item").getKey());
		},

		onNewArticle: function () {
			this.navTo("articleNew");
		},

		onHeaderSearch: function (oEvent) {
			if (oEvent.getParameter("clearButtonPressed")) {
				return;
			}
			var sQuery = oEvent.getParameter("query") || "";
			var oItem = oEvent.getParameter("suggestionItem");
			if (oItem) {
				sQuery = oItem.getText();
			}
			this.navTo("search", { query: { q: sQuery } });
		},

		onSuggest: function (oEvent) {
			var oField = oEvent.getSource();
			var sValue = oEvent.getParameter("suggestValue");
			if (!sValue || sValue.length < 2) {
				oField.destroySuggestionItems();
				return;
			}
			this.api.get("search/suggest", { q: sValue }).then(function (o) {
				oField.destroySuggestionItems();
				(o.items || []).forEach(function (s) {
					oField.addSuggestionItem(new SuggestionItem({ text: s }));
				});
				oField.suggest();
			}).catch(function () {});
		},

		onUserMenu: function (oEvent) {
			var oSource = oEvent.getSource();
			this.dialog("UserMenu").then(function (o) { o.openBy(oSource); });
		},

		onLogout: function () {
			this.byId("userMenu").close();
			this.getOwnerComponent().logout();
		},

		// ---- profile
		onProfile: function () {
			this.byId("userMenu").close();
			this.dialog("ProfileDialog").then(function (o) {
				this.byId("profileDisplayName").setValue(this.session("/user/displayName"));
				this.byId("profileEmail").setValue(this.session("/user/email"));
				o.open();
			}.bind(this));
		},

		onSaveProfile: function () {
			this.api.patch("auth/profile", {
				displayName: this.byId("profileDisplayName").getValue(),
				email: this.byId("profileEmail").getValue()
			}).then(function (oUser) {
				this.getOwnerComponent().getModel("session").setProperty("/user", oUser);
				this.byId("profileDialog").close();
				this.toast("common.saved");
			}.bind(this)).catch(this.showError.bind(this));
		},

		onCloseProfile: function () {
			this.byId("profileDialog").close();
		},

		// ---- password
		onChangePassword: function (bForced) {
			var oMenu = this.byId("userMenu");
			if (oMenu) {
				oMenu.close();
			}
			this.dialog("PasswordDialog").then(function (o) {
				["pwOld", "pwNew", "pwRepeat"].forEach(function (s) {
					this.byId(s).setValue("").setValueState("None");
				}.bind(this));
				this.byId("pwMustChange").setVisible(bForced === true);
				o.open();
			}.bind(this));
		},

		onSavePassword: function () {
			var sNew = this.byId("pwNew").getValue();
			if (sNew !== this.byId("pwRepeat").getValue()) {
				this.byId("pwRepeat").setValueState("Error").setValueStateText(this.text("user.passwordMismatch"));
				return;
			}
			this.api.changePassword(this.byId("pwOld").getValue(), sNew).then(function () {
				this.getOwnerComponent().getModel("session").setProperty("/user/mustChangePassword", false);
				this.byId("passwordDialog").close();
				this.toast("user.passwordChanged");
			}.bind(this)).catch(this.showError.bind(this));
		},

		onClosePassword: function () {
			this.byId("passwordDialog").close();
		}
	});
});
