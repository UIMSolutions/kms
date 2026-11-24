sap.ui.define([
	"./BaseController",
	"sap/ui/model/json/JSONModel",
	"sap/base/strings/formatMessage",
	"../model/formatter"
], function (BaseController, JSONModel, formatMessage, formatter) {
	"use strict";

	var PAGE = 20;
	var FILTERS = ["kind", "space", "tag", "media"];

	return BaseController.extend("uim.myfiori.kms.controller.Search", {
		formatMessage: formatMessage,

		onInit: function () {
			this.getView().setModel(new JSONModel(this._empty()), "search");
			this.onRoute("search", function (oEvent) {
				var q = oEvent.getParameter("arguments")["?query"] || {};
				this._params = { q: q.q || "", kind: q.kind || "", space: q.space || "", tag: q.tag || "", media: q.media || "" };
				this.getView().getModel("search").setProperty("/q", this._params.q);
				this._run(false);
			});
		},

		_empty: function () {
			return { q: "", total: 0, hits: [], kinds: [], spaces: [], tags: [], mediaKinds: [], suggestions: [], active: [], tookMs: 0 };
		},

		_navigate: function (oParams) {
			var o = {};
			Object.keys(oParams).forEach(function (k) {
				if (oParams[k]) {
					o[k] = oParams[k];
				}
			});
			this.navTo("search", { query: o }, true);
		},

		_run: function (bAppend) {
			var oModel = this.getView().getModel("search");
			var iSkip = bAppend ? oModel.getProperty("/hits").length : 0;
			var p = Object.assign({ skip: iSkip, top: PAGE }, this._params);
			this.byId("results").setBusy(true);
			this.api.get("search", p).then(function (r) {
				if (bAppend) {
					r.hits = oModel.getProperty("/hits").concat(r.hits);
				}
				r.q = this._params.q;
				r.active = this._activeFilters(r);
				oModel.setData(r);
			}.bind(this)).catch(this.showError.bind(this)).finally(function () {
				this.byId("results").setBusy(false);
			}.bind(this));
		},

		/** human readable chips for the active filters */
		_activeFilters: function (r) {
			var a = [];
			var p = this._params;
			var fnSpace = function (sId) {
				var o = (this.getOwnerComponent().getModel("spaces").getProperty("/items") || [])
					.filter(function (s) { return s.id === sId; })[0];
				return o ? o.path : sId;
			}.bind(this);
			if (p.kind) { a.push({ key: "kind", label: this.text("search.facet.kind") + ": " + formatter.kindText.call(this, p.kind) }); }
			if (p.space) { a.push({ key: "space", label: this.text("search.facet.space") + ": " + fnSpace(p.space) }); }
			if (p.media) { a.push({ key: "media", label: this.text("search.facet.media") + ": " + formatter.kindText.call(this, p.media) }); }
			if (p.tag) { a.push({ key: "tag", label: "#" + p.tag }); }
			return a;
		},

		onSearch: function (oEvent) {
			this._navigate(Object.assign({}, this._params, { q: oEvent.getParameter("query") }));
		},

		onFacet: function (oEvent) {
			var oItem = oEvent.getSource();
			var sFacet = oItem.data("facet");
			var sValue = oItem.getBindingContext("search").getProperty("value");
			var o = Object.assign({}, this._params);
			o[sFacet] = o[sFacet] === sValue ? "" : sValue;
			this._navigate(o);
		},

		onRemoveFilter: function (oEvent) {
			var sKey = oEvent.getSource().getBindingContext("search").getProperty("key");
			var o = Object.assign({}, this._params);
			o[sKey] = "";
			this._navigate(o);
		},

		onClearFilters: function () {
			var o = Object.assign({}, this._params);
			FILTERS.forEach(function (k) { o[k] = ""; });
			this._navigate(o);
		},

		onSuggestion: function (oEvent) {
			var sWord = oEvent.getSource().getText();
			var aWords = (this._params.q || "").split(/\s+/);
			// replace the first unknown word; good enough for single-word typos
			var sQuery = aWords.length <= 1 ? sWord : aWords.map(function (w, i) { return i === 0 ? sWord : w; }).join(" ");
			this._navigate(Object.assign({}, this._params, { q: sQuery }));
		},

		onMore: function () {
			this._run(true);
		},

		onOpen: function (oEvent) {
			var oSource = oEvent.getSource();
			var oCtx = oSource.getBindingContext("search");
			var o = oCtx.getObject();
			if (o.kind === "article") {
				this.navTo("article", { id: o.id });
			} else {
				this.navTo("documents", { query: { open: o.id } });
			}
		}
	});
});
