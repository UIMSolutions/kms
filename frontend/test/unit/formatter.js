sap.ui.define(["uim/myfiori/kms/model/formatter"], function (formatter) {
	"use strict";

	QUnit.module("formatter");

	QUnit.test("fileSize", function (assert) {
		assert.strictEqual(formatter.fileSize(512), "512 B");
		assert.strictEqual(formatter.fileSize(1536), "1.5 KB");
		assert.strictEqual(formatter.fileSize(20 * 1024 * 1024), "20 MB");
	});

	QUnit.test("status and icons", function (assert) {
		assert.strictEqual(formatter.statusState("published"), "Success");
		assert.strictEqual(formatter.statusState("draft"), "Warning");
		assert.strictEqual(formatter.kindIcon("document", "image"), "sap-icon://attachment-photo");
		assert.strictEqual(formatter.tagsText(["a", "b"]), "#a #b");
	});
});
