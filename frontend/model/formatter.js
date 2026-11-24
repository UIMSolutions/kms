sap.ui.define([
	"sap/ui/core/format/DateFormat",
	"./markdown"
], function (DateFormat, markdown) {
	"use strict";

	var oDateTime = DateFormat.getDateTimeInstance({ style: "medium" });
	var oRelative = DateFormat.getDateTimeInstance({ relative: true, relativeScale: "auto" });

	var KIND_ICONS = {
		article: "sap-icon://document-text",
		document: "sap-icon://attachment-text-file",
		spreadsheet: "sap-icon://excel-attachment",
		presentation: "sap-icon://ppt-attachment",
		image: "sap-icon://attachment-photo",
		video: "sap-icon://attachment-video",
		audio: "sap-icon://attachment-audio",
		archive: "sap-icon://attachment-zip-file",
		other: "sap-icon://document"
	};

	var formatter = {
		/** ISO timestamp -> localized date/time */
		dateTime: function (sIso) {
			return sIso ? oDateTime.format(new Date(sIso)) : "";
		},

		/** ISO timestamp -> "3 hours ago" */
		relative: function (sIso) {
			return sIso ? oRelative.format(new Date(sIso)) : "";
		},

		/** bytes -> "1.2 MB" */
		fileSize: function (iBytes) {
			if (iBytes === undefined || iBytes === null) {
				return "";
			}
			var a = ["B", "KB", "MB", "GB", "TB"];
			var i = 0;
			var n = Number(iBytes);
			while (n >= 1024 && i < a.length - 1) {
				n /= 1024;
				i++;
			}
			return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + " " + a[i];
		},

		kindIcon: function (sKind, sMediaKind) {
			return KIND_ICONS[sMediaKind] || KIND_ICONS[sKind] || KIND_ICONS.other;
		},

		statusState: function (sStatus) {
			switch (sStatus) {
				case "published": return "Success";
				case "draft": return "Warning";
				case "archived": return "None";
				default: return "None";
			}
		},

		roleState: function (sRole) {
			return sRole === "admin" ? "Error" : "None";
		},

		/** area roles: reader / editor / manager */
		spaceRoleState: function (sRole) {
			return sRole === "manager" ? "Success" : (sRole === "editor" ? "Information" : "None");
		},

		spaceRoleText: function (sRole) {
			return formatter.enumText.call(this, "spaceRole", sRole);
		},

		/** where a member's role comes from */
		memberSource: function (sSource, sPath) {
			var oBundle = this.getOwnerComponent().getModel("i18n").getResourceBundle();
			return oBundle.getText("area.source." + (sSource || "member"), [sPath || ""]);
		},

		/** indentation of sub-areas in tree-ordered lists */
		indent: function (iDepth) {
			return Math.max(0, (iDepth || 1) - 1) * 1.5 + "rem";
		},

		/** translates enumeration values via i18n keys like "status.draft" */
		enumText: function (sPrefix, sValue) {
			if (!sValue) {
				return "";
			}
			var oBundle = this.getOwnerComponent ? this.getOwnerComponent().getModel("i18n").getResourceBundle()
				: null;
			var sKey = sPrefix + "." + sValue;
			return oBundle && oBundle.hasText && oBundle.hasText(sKey) ? oBundle.getText(sKey) : sValue;
		},

		statusText: function (sStatus) {
			return formatter.enumText.call(this, "status", sStatus);
		},

		kindText: function (sKind) {
			return formatter.enumText.call(this, "kind", sKind);
		},

		roleText: function (sRole) {
			return formatter.enumText.call(this, "role", sRole);
		},

		/** Markdown -> sanitized HTML wrapped in a single root (for sap.ui.core.HTML) */
		markdown: function (sText) {
			return "<div class=\"kmsMarkdown\">" + markdown.render(sText || "") + "</div>";
		},

		/** search snippets are HTML-escaped by the backend; wrap for FormattedText */
		snippet: function (s) {
			return s ? "<span>" + s + "</span>" : "";
		},

		tagsText: function (aTags) {
			return (aTags || []).map(function (t) { return "#" + t; }).join(" ");
		},

		joinTags: function (aTags) {
			return (aTags || []).join(", ");
		}
	};
	return formatter;
});
