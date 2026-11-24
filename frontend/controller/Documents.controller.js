sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel"
], function (BaseController, JSONModel) {
	"use strict";

	var PAGE = 50;
	var TEXT_TYPES = ["text/plain", "text/markdown", "text/csv", "application/json", "application/xml", "application/yaml"];

	function escapeHtml(s) {
		return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
	}

	return BaseController.extend("uim.myfiori.kms.controller.Documents", {
		onInit: function () {
			this.getView().setModel(new JSONModel({ items: [], total: 0 }), "docs");
			this.getView().setModel(new JSONModel(this._emptyUpload()), "upload");
			this.getView().setModel(new JSONModel({}), "doc");
			this.onRoute("documents", function (oEvent) {
				var q = oEvent.getParameter("arguments")["?query"] || {};
				if (q.space !== undefined) {
					this.byId("docSpace").setSelectedKey(q.space);
				}
				this._load(false);
				if (q.open) {
					this._openDocument(q.open);
				} else if (q.upload === "true" && this.session("/canCreate")) {
					this.onUpload();
				}
			});
		},

		_load: function (bAppend) {
			var oModel = this.getView().getModel("docs");
			var aItems = bAppend ? oModel.getProperty("/items") : [];
			var oTable = this.byId("documentTable");
			oTable.setBusy(true);
			this.api.get("documents", {
				q: this.byId("docFilter").getValue(),
				space: this.byId("docSpace").getSelectedKey(),
				deep: "true",
				kind: this.byId("docKind").getSelectedKey(),
				orderBy: this.byId("docOrder").getSelectedKey(),
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

		// ------------------------------------------------------------------ upload
		_emptyUpload: function () {
			return { files: [], spaceId: "", title: "", titlePlaceholder: "", tags: "", description: "", busy: false, progress: 0, progressText: "" };
		},

		onUpload: function (aFiles) {
			var oModel = this.getView().getModel("upload");
			var oData = this._emptyUpload();
			var sSpace = this.byId("docSpace").getSelectedKey();
			var aWritable = this.getOwnerComponent().getModel("spaces").getProperty("/writable") || [];
			oData.spaceId = aWritable.some(function (s) { return s.id === sSpace; }) ? sSpace : ((aWritable[0] || {}).id || "");
			oModel.setData(oData);
			this._pending = [];
			if (Array.isArray(aFiles)) {
				this._addPending(aFiles);
			}
			this.dialog("UploadDialog").then(function (d) { d.open(); });
		},

		_addPending: function (aFiles) {
			this._pending = (this._pending || []).concat(aFiles);
			var oModel = this.getView().getModel("upload");
			oModel.setProperty("/files", this._pending.map(function (f) { return { name: f.name, size: f.size }; }));
			oModel.setProperty("/titlePlaceholder", this._pending.length === 1 ? this._pending[0].name : "");
		},

		onFilesChosen: function (oEvent) {
			this._addPending(Array.prototype.slice.call(oEvent.getParameter("files") || []));
			oEvent.getSource().clear();
		},

		_droppedFiles: function (oEvent) {
			var oBrowserEvent = oEvent.getParameter("browserEvent");
			var oTransfer = oBrowserEvent && oBrowserEvent.dataTransfer;
			return oTransfer ? Array.prototype.slice.call(oTransfer.files || []) : [];
		},

		onDropFiles: function (oEvent) {
			var aFiles = this._droppedFiles(oEvent);
			if (aFiles.length) {
				this.onUpload(aFiles);
			}
		},

		onDropIntoDialog: function (oEvent) {
			this._addPending(this._droppedFiles(oEvent));
		},

		onRemovePending: function (oEvent) {
			var iIndex = Number(oEvent.getParameter("listItem").getBindingContext("upload").getPath().split("/").pop());
			this._pending.splice(iIndex, 1);
			this._addPending([]);
		},

		onStartUpload: function () {
			var oModel = this.getView().getModel("upload");
			var o = oModel.getData();
			var aFiles = this._pending.slice();
			var iDone = 0;
			oModel.setProperty("/busy", true);
			var fnProgress = function () {
				oModel.setProperty("/progress", Math.round(iDone * 100 / aFiles.length));
				oModel.setProperty("/progressText", this.text("document.uploading", [Math.min(iDone + 1, aFiles.length), aFiles.length]));
			}.bind(this);
			fnProgress();
			aFiles.reduce(function (p, oFile) {
				return p.then(function () {
					return this.api.upload(oFile, {
						spaceId: o.spaceId,
						title: aFiles.length === 1 ? o.title : "",
						tags: o.tags,
						description: o.description
					}).then(function () {
						iDone++;
						fnProgress();
					});
				}.bind(this));
			}.bind(this), Promise.resolve()).then(function () {
				this.toast("document.uploaded", [iDone]);
				this.byId("uploadDialog").close();
			}.bind(this)).catch(this.showError.bind(this)).finally(function () {
				oModel.setProperty("/busy", false);
				this._load(false);
			}.bind(this));
		},

		onCloseUpload: function () {
			this.byId("uploadDialog").close();
		},

		onUploadClosed: function () {
			this._pending = [];
		},

		// ------------------------------------------------------------------ details & preview
		onOpen: function (oEvent) {
			this._openDocument(oEvent.getSource().getBindingContext("docs").getProperty("id"));
		},

		_openDocument: function (sId) {
			var oModel = this.getView().getModel("doc");
			this.api.get("documents/" + sId).then(function (d) {
				d.edit = { title: d.title, spaceId: d.spaceId, tags: (d.tags || []).join(", "), description: d.description };
				d.textInfo = this.text("document.textIndexed", [d.textLength]);
				d.previewHtml = "";
				d.previewBusy = true;
				oModel.setData(d);
				return this.dialog("DocumentDialog");
			}.bind(this)).then(function (oDialog) {
				this.byId("docTabs").setSelectedKey("preview");
				oDialog.open();
				this._preview(oModel.getData());
			}.bind(this)).catch(this.showError.bind(this));
		},

		_preview: function (d) {
			var oModel = this.getView().getModel("doc");
			var bPreviewable = ["image", "video", "audio"].indexOf(d.kind) >= 0 || d.mimeType === "application/pdf"
				|| TEXT_TYPES.indexOf(d.mimeType) >= 0;
			if (!bPreviewable || d.size > 50 * 1024 * 1024 && d.kind !== "video") {
				oModel.setProperty("/previewBusy", false);
				return;
			}
			this.api.blob(d.id).then(function (oBlob) {
				if (TEXT_TYPES.indexOf(d.mimeType) >= 0) {
					return oBlob.text().then(function (s) {
						return "<pre style=\"max-height:60vh;overflow:auto;white-space:pre-wrap;width:100%\">"
							+ escapeHtml(s.substring(0, 200000)) + "</pre>";
					});
				}
				this._revoke();
				this._blobUrl = URL.createObjectURL(oBlob);
				var u = this._blobUrl;
				if (d.kind === "image") {
					return "<img class=\"kmsPreview\" alt=\"\" src=\"" + u + "\">";
				}
				if (d.kind === "video") {
					return "<video class=\"kmsPreview\" controls src=\"" + u + "\"></video>";
				}
				if (d.kind === "audio") {
					return "<audio controls src=\"" + u + "\"></audio>";
				}
				return "<iframe class=\"kmsPreviewFrame\" title=\"preview\" src=\"" + u + "\"></iframe>";
			}.bind(this)).then(function (sHtml) {
				oModel.setProperty("/previewHtml", "<div style=\"width:100%;text-align:center\">" + sHtml + "</div>");
			}).catch(function () {
				oModel.setProperty("/previewHtml", "");
			}).finally(function () {
				oModel.setProperty("/previewBusy", false);
			});
		},

		_revoke: function () {
			if (this._blobUrl) {
				URL.revokeObjectURL(this._blobUrl);
				this._blobUrl = null;
			}
		},

		onDocumentClosed: function () {
			this._revoke();
			this.getView().getModel("doc").setProperty("/previewHtml", "");
		},

		onCloseDocument: function () {
			this.byId("documentDialog").close();
		},

		onSaveDocument: function () {
			var d = this.getView().getModel("doc").getData();
			this.api.patch("documents/" + d.id, {
				title: d.edit.title,
				spaceId: d.edit.spaceId,
				tags: this.splitTags(d.edit.tags),
				description: d.edit.description
			}).then(function () {
				this.toast("common.saved");
				this.byId("documentDialog").close();
				this._load(false);
			}.bind(this)).catch(this.showError.bind(this));
		},

		onDownload: function () {
			var d = this.getView().getModel("doc").getData();
			this.api.download(d.id, d.fileName).catch(this.showError.bind(this));
		},

		onDownloadRow: function (oEvent) {
			var d = oEvent.getSource().getBindingContext("docs").getObject();
			this.api.download(d.id, d.fileName).catch(this.showError.bind(this));
		},

		onReplaceFile: function (oEvent) {
			var oFile = (oEvent.getParameter("files") || [])[0];
			var oUploader = oEvent.getSource();
			if (!oFile) {
				return;
			}
			var d = this.getView().getModel("doc").getData();
			this.api.replaceFile(d.id, oFile).then(function () {
				this.toast("document.replaced");
				this.byId("documentDialog").close();
				this._load(false);
			}.bind(this)).catch(this.showError.bind(this)).finally(function () {
				oUploader.clear();
			});
		},

		onDeleteDocument: function () {
			var d = this.getView().getModel("doc").getData();
			this.confirmDelete(d.title, function () {
				this.api.del("documents/" + d.id).then(function () {
					this.toast("common.deleted");
					this.byId("documentDialog").close();
					this._load(false);
				}.bind(this)).catch(this.showError.bind(this));
			}.bind(this));
		}
	});
});
