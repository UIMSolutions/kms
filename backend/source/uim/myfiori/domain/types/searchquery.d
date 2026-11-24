/// Parsed full-text query and search result value types.
module uim.myfiori.domain.types.searchquery;

import std.array : appender;
import std.string : strip;
import uim.myfiori.domain.enumerations.itemkind;

/// User query: free terms, "quoted phrases", -excluded terms, prefix* terms
/// plus structured filters.
struct SearchQuery {
    string text;          /// raw query text
    string kind;          /// "", "article", "document"
    string spaceId;       /// "" = all spaces
    string tag;           /// "" = any tag
    string mediaKind;     /// "" = any (documents only)
    size_t skip;
    size_t top = 20;
}

struct ParsedQuery {
    string[] terms;       /// must match (OR-scored, AND-filtered when `matchAll`)
    string[] prefixes;    /// "data*" -> "data"
    string[][] phrases;   /// token sequences that must appear in order
    string[] excluded;
}

struct SearchHit {
    string id;
    ItemKind kind;
    string title;
    string snippet;       /// HTML-escaped, matches wrapped in <strong>
    double score;
    string spaceId;
    string[] tags;
    string status;
    string mediaKind;
    string updatedAt;
}

struct FacetValue {
    string value;
    size_t count;
}

struct SearchResult {
    size_t total;
    SearchHit[] hits;
    FacetValue[] kinds;
    FacetValue[] spaces;
    FacetValue[] tags;
    FacetValue[] mediaKinds;
    string[] suggestions; /// "did you mean" corrections for unknown terms
    long tookMicros;
}
