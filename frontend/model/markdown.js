sap.ui.define([], function () {
	"use strict";

	/**
	 * Small, dependency-free Markdown renderer for article bodies.
	 * All input is HTML-escaped first; only the generated tags are emitted, links are
	 * restricted to http(s), mailto, relative URLs and in-app anchors.
	 * Supported: headings, paragraphs, **bold**, *italic*, ~~strike~~, `code`, fenced code
	 * blocks, ordered / unordered lists, > quotes, tables, horizontal rules, links, images.
	 */
	function escape(s) {
		return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;").replace(/'/g, "&#39;");
	}

	function safeUrl(sUrl) {
		var u = sUrl.trim();
		if (/^(https?:|mailto:|\/|#|\.\/|\.\.\/)/i.test(u) || !/^[a-z][a-z0-9+.-]*:/i.test(u)) {
			return u;
		}
		return "#";
	}

	/** inline formatting on an already escaped string */
	function inline(s) {
		var aCode = [];
		s = s.replace(/`([^`]+)`/g, function (m, c) {
			aCode.push("<code>" + c + "</code>");
			return "\u0000" + (aCode.length - 1) + "\u0000";
		});
		s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, function (m, alt, src) {
			return "<img alt=\"" + alt + "\" src=\"" + safeUrl(src) + "\">";
		});
		s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (m, text, href) {
			var sHref = safeUrl(href);
			var bExternal = /^https?:/i.test(sHref);
			return "<a href=\"" + sHref + "\"" + (bExternal ? " target=\"_blank\" rel=\"noopener noreferrer\"" : "") + ">"
				+ text + "</a>";
		});
		s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
			.replace(/__([^_]+)__/g, "<strong>$1</strong>")
			.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>")
			.replace(/(^|\W)_([^_\s][^_]*)_(?=\W|$)/g, "$1<em>$2</em>")
			.replace(/~~([^~]+)~~/g, "<del>$1</del>");
		return s.replace(/\u0000(\d+)\u0000/g, function (m, i) { return aCode[Number(i)]; });
	}

	function splitRow(sLine) {
		var s = sLine.trim().replace(/^\|/, "").replace(/\|$/, "");
		return s.split("|").map(function (c) { return c.trim(); });
	}

	function render(sText) {
		var aLines = escape(String(sText || "")).replace(/\r\n?/g, "\n").split("\n");
		var aOut = [];
		var i = 0;
		var aPara = [];

		function flushPara() {
			if (aPara.length) {
				aOut.push("<p>" + inline(aPara.join(" ")) + "</p>");
				aPara = [];
			}
		}

		while (i < aLines.length) {
			var sLine = aLines[i];
			var m;
			if (/^```/.test(sLine)) {
				flushPara();
				var aCode = [];
				i++;
				while (i < aLines.length && !/^```/.test(aLines[i])) {
					aCode.push(aLines[i]);
					i++;
				}
				i++;
				aOut.push("<pre><code>" + aCode.join("\n") + "</code></pre>");
				continue;
			}
			if ((m = /^(#{1,6})\s+(.*)$/.exec(sLine))) {
				flushPara();
				aOut.push("<h" + m[1].length + ">" + inline(m[2]) + "</h" + m[1].length + ">");
				i++;
				continue;
			}
			if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(sLine)) {
				flushPara();
				aOut.push("<hr>");
				i++;
				continue;
			}
			if (/^&gt;\s?/.test(sLine)) {
				flushPara();
				var aQuote = [];
				while (i < aLines.length && /^&gt;\s?/.test(aLines[i])) {
					aQuote.push(aLines[i].replace(/^&gt;\s?/, ""));
					i++;
				}
				aOut.push("<blockquote>" + inline(aQuote.join(" ")) + "</blockquote>");
				continue;
			}
			if (/^\s*\|.*\|\s*$/.test(sLine) && i + 1 < aLines.length && /^\s*\|?\s*:?-{2,}/.test(aLines[i + 1])) {
				flushPara();
				var aHead = splitRow(sLine);
				i += 2;
				var sTable = "<table><thead><tr>" + aHead.map(function (c) { return "<th>" + inline(c) + "</th>"; }).join("")
					+ "</tr></thead><tbody>";
				while (i < aLines.length && /^\s*\|.*\|\s*$/.test(aLines[i])) {
					sTable += "<tr>" + splitRow(aLines[i]).map(function (c) { return "<td>" + inline(c) + "</td>"; }).join("") + "</tr>";
					i++;
				}
				aOut.push(sTable + "</tbody></table>");
				continue;
			}
			if (/^\s*([-*+]|\d+[.)])\s+/.test(sLine)) {
				flushPara();
				var bOrdered = /^\s*\d+[.)]/.test(sLine);
				var aItems = [];
				while (i < aLines.length && /^\s*([-*+]|\d+[.)])\s+/.test(aLines[i])) {
					aItems.push("<li>" + inline(aLines[i].replace(/^\s*([-*+]|\d+[.)])\s+/, "")) + "</li>");
					i++;
				}
				aOut.push((bOrdered ? "<ol>" : "<ul>") + aItems.join("") + (bOrdered ? "</ol>" : "</ul>"));
				continue;
			}
			if (sLine.trim() === "") {
				flushPara();
				i++;
				continue;
			}
			aPara.push(sLine.trim());
			i++;
		}
		flushPara();
		return aOut.join("\n");
	}

	return { render: render, escape: escape };
});
