sap.ui.define(["uim/myfiori/kms/model/markdown"], function (markdown) {
	"use strict";

	QUnit.module("markdown");

	QUnit.test("headings, emphasis, code", function (assert) {
		assert.strictEqual(markdown.render("# Title"), "<h1>Title</h1>");
		assert.strictEqual(markdown.render("a **b** *c* `d`"), "<p>a <strong>b</strong> <em>c</em> <code>d</code></p>");
	});

	QUnit.test("lists and tables", function (assert) {
		assert.strictEqual(markdown.render("- a\n- b"), "<ul><li>a</li><li>b</li></ul>");
		assert.strictEqual(markdown.render("1. a\n2. b"), "<ol><li>a</li><li>b</li></ol>");
		assert.ok(markdown.render("| a | b |\n|---|---|\n| 1 | 2 |").indexOf("<td>1</td><td>2</td>") > 0);
	});

	QUnit.test("escapes HTML and blocks script URLs", function (assert) {
		assert.strictEqual(markdown.render("<script>x</script>"), "<p>&lt;script&gt;x&lt;/script&gt;</p>");
		assert.ok(markdown.render("[x](javascript:alert(1))").indexOf("href=\"#\"") > 0);
		assert.ok(markdown.render("[x](https://example.org)").indexOf("href=\"https://example.org\"") > 0);
	});
});
