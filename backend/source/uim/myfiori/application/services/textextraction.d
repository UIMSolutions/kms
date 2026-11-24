/// Extracts the full text of a stored document and updates the search index.
/// Called by the background TextExtractionWorker (or synchronously in tests / CLI).
module uim.myfiori.application.services.textextraction;

import vibe.core.log;
import uim.myfiori.application.services.searchindexer;
import uim.myfiori.domain;
import uim.myfiori.ports;

enum maxExtractedText = 1024 * 1024;

final class TextExtractionService {
    private DocumentRepository documents;
    private BlobStorage blobs;
    private TextExtractor extractor;
    private SearchIndexer indexer;

    this(DocumentRepository documents, BlobStorage blobs, TextExtractor extractor, SearchIndexer indexer) {
        this.documents = documents;
        this.blobs = blobs;
        this.extractor = extractor;
        this.indexer = indexer;
    }

    /// Returns true if text was extracted.
    bool process(string documentId) {
        auto d = documents.byId(documentId);
        if (d is null || !blobs.exists(d.blobKey))
            return false;
        string text;
        try
            text = extractor.extract(d.fileName, d.mimeType, blobs.get(d.blobKey));
        catch (Exception e) {
            logWarn("text extraction failed for %s (%s): %s", d.id, d.fileName, e.msg);
            text = "";
        }
        if (text.length > maxExtractedText)
            text = text[0 .. maxExtractedText];
        // re-read: the document may have changed while the extractor ran
        d = documents.byId(documentId);
        if (d is null)
            return false;
        d.text = text;
        d.textExtracted = text.length > 0;
        documents.save(d);
        indexer.index(d);
        logDiagnostic("extracted %s characters from %s", text.length, d.fileName);
        return d.textExtracted;
    }
}
