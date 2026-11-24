sap.ui.define(function () {
	"use strict";
	return {
		name: "QUnit test suite for the KMS frontend",
		defaults: {
			page: "ui5://test-resources/uim/myfiori/kms/Test.qunit.html?testsuite={suite}&test={name}",
			qunit: { version: 2 },
			sinon: { version: 4 },
			ui5: { theme: "sap_fiori_3", resourceroots: { "uim.myfiori.kms": "../" } },
			loader: { paths: { "uim/myfiori/kms": "../" } }
		},
		tests: {
			"unit/markdown": { title: "Markdown renderer" },
			"unit/formatter": { title: "Formatters" }
		}
	};
});
