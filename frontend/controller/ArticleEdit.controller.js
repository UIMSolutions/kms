sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel",
	"sap/m/MessageBox"
], function (BaseController, JSONModel, MessageBox) {
	"use strict";

	return BaseController.extend("uim.myfiori.kms.controller.ArticleEdit", {
		onInit: function () {
			this.getView().setModel(new JSONModel({}), "edit");
			this.getView().setModel(new JSONModel({ items: [] }), "picker");
			this.onRoute("articleEdit", function (oEvent) {
				this._open(oEvent.getParameter("arguments").id);
			});
			this.onRoute("articleNew", function (oEvent) {
				var q = oEvent.getParameter("arguments")["?query"] || {};
				var aSpaces = this.getOwnerComponent().getModel("spaces").getProperty("/writable") || [];
				this._setData({
					id: "", title: "", summary: "", body: "", tags: [], attachments: [], status: "draft",
					spaceId: q.space || (aSpaces[0] && aSpaces[0].id) || ""
				});
			});
		},

		_setData: function (o) {
			o.tagsText = (o.tags || []).join(", ");
			this.getView().getModel("edit").setData(o);
			this.byId("bodyTabs").setSelectedKey("write");
		},

		_open: function (sId) {
			this.setBusy(true);
			this.api.get("articles/" + sId).then(this._setData.bind(this)).catch(this.showError.bind(this))
				.finally(function () { this.setBusy(false); }.bind(this));
		},

		_payload: function () {
			var o = this.getView().getModel("edit").getData();
			return {
				title: o.title,
				spaceId: o.spaceId,
				summary: o.summary,
				body: o.body,
				tags: this.splitTags(o.tagsText),
				attachmentIds: (o.attachments || []).map(function (a) { return a.id; })
			};
		},

		/** creates or updates; resolves with the saved article */
		_save: function () {
			var o = this.getView().getModel("edit").getData();
			if (!o.title || !o.spaceId) {
				MessageBox.warning(this.text("article.titleRequired"));
				return Promise.reject(null);
			}
			this.setBusy(true);
			var p = o.id ? this.api.patch("articles/" + o.id, this._payload(), String(o.version))
				: this.api.post("articles", this._payload());
			return p.catch(function (e) {
				if (e.status === 409) {
					e.message = this.text("article.conflict");
				}
				throw e;
			}.bind(this)).finally(function () { this.setBusy(false); }.bind(this));
		},

		onSave: function () {
			this._save().then(function (a) {
				this.toast("common.saved");
				this.navTo("article", { id: a.id }, true);
			}.bind(this)).catch(function (e) { if (e) { this.showError(e); } }.bind(this));
		},

		onSaveAndPublish: function () {
			this._save().then(function (a) {
				return this.api.post("articles/" + a.id + "/publish");
			}.bind(this)).then(function (a) {
				this.toast("common.saved");
				this.navTo("article", { id: a.id }, true);
			}.bind(this)).catch(function (e) { if (e) { this.showError(e); } }.bind(this));
		},

		onCancel: function () {
			var sId = this.getView().getModel("edit").getProperty("/id");
			if (sId) {
				this.navTo("article", { id: sId }, true);
			} else {
				this.onNavBack();
			}
		},

		// ---- attachments
		onRemoveAttachment: function (oEvent) {
			var oModel = this.getView().getModel("edit");
			var sId = oEvent.getParameter("listItem").getBindingContext("edit").getProperty("id");
			oModel.setProperty("/attachments", oModel.getProperty("/attachments").filter(function (a) { return a.id !== sId; }));
		},

		_addAttachments: function (aDocs) {
			var oModel = this.getView().getModel("edit");
			var a = oModel.getProperty("/attachments") || [];
			aDocs.forEach(function (d) {
				if (!a.some(function (x) { return x.id === d.id; })) {
					a.push({ id: d.id, title: d.title, fileName: d.fileName, mimeType: d.mimeType, kind: d.kind, size: d.size });
				}
			});
			oModel.setProperty("/attachments", a.slice());
		},

		onAddAttachment: function () {
			this.dialog("DocumentPicker").then(function (d) {
				this.onPickerSearch({ getParameter: function () { return ""; } });
				d.open();
			}.bind(this));
		},

		onPickerSearch: function (oEvent) {
			var sValue = oEvent.getParameter("value") || "";
			this.api.get("documents", { q: sValue, top: 100 }).then(function (o) {
				this.getView().getModel("picker").setData(o);
			}.bind(this)).catch(this.showError.bind(this));
		},

		onPickerConfirm: function (oEvent) {
			var aDocs = (oEvent.getParameter("selectedItems") || []).map(function (i) {
				return i.getBindingContext("picker").getObject();
			});
			this._addAttachments(aDocs);
		},

		onUploadAttachment: function (oEvent) {
			var aFiles = Array.prototype.slice.call(oEvent.getParameter("files") || []);
			var oUploader = oEvent.getSource();
			var sSpace = this.getView().getModel("edit").getProperty("/spaceId");
			this.setBusy(true);
			aFiles.reduce(function (p, oFile) {
				return p.then(function (aDone) {
					return this.api.upload(oFile, { spaceId: sSpace }).then(function (d) { return aDone.concat([d]); });
				}.bind(this));
			}.bind(this), Promise.resolve([])).then(function (aDocs) {
				this._addAttachments(aDocs);
				this.toast("document.uploaded", [aDocs.length]);
			}.bind(this)).catch(this.showError.bind(this)).finally(function () {
				oUploader.clear();
				this.setBusy(false);
			}.bind(this));
		}
	});
});
